#!/usr/bin/env bash
# ensure_federation_login.sh — Track A / default-admin SQL Server only.
# Create a least-privilege login (edwfed) so Lakehouse Federation does not
# register sys.* (Free Edition: 100 tables per schema).
#
# No-op for MySQL and for a custom SOURCE_USER (Track B).
# Updates .env SOURCE_USER / SOURCE_PASSWORD (does not change AZ_SQL_ADMIN).
# Drops a stale FOREIGN CATALOG + CONNECTION so the next make setup recreates them.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi
# shellcheck disable=SC1091
. "${REPO_ROOT}/agents/tools/resolve_source_env.sh"

if [ "${SOURCE_TYPE}" != "sqlserver" ]; then
  echo "[federation_login] skip SOURCE_TYPE=${SOURCE_TYPE}"
  exit 0
fi

ADMIN="${AZ_SQL_ADMIN:-}"
FED_USER="${FEDERATION_SQL_USER:-edwfed}"
CUR_USER="${SOURCE_USER:-}"

# Track B: caller already set a non-admin federation user.
if [ -n "$CUR_USER" ] && [ "$CUR_USER" != "$FED_USER" ] && [ -n "$ADMIN" ] && [ "$CUR_USER" != "$ADMIN" ]; then
  echo "[federation_login] skip custom SOURCE_USER=${CUR_USER}"
  exit 0
fi
if [ -n "$CUR_USER" ] && [ -z "$ADMIN" ] && [ "$CUR_USER" != "$FED_USER" ]; then
  echo "[federation_login] skip custom SOURCE_USER=${CUR_USER} (no AZ_SQL_ADMIN)"
  exit 0
fi

: "${AZ_SQL_PASSWORD:?AZ_SQL_PASSWORD required to create the federation login}"
SERVER="${AZ_SQL_HOST:-${SOURCE_HOST:-${AZ_SQL_SERVER:-}.database.windows.net}}"
DB="${AZ_SQL_DB:-${SOURCE_DATABASE:-}}"
: "${SERVER:?SOURCE_HOST / AZ_SQL_SERVER required}"
: "${DB:?SOURCE_DATABASE / AZ_SQL_DB required}"

if ! command -v sqlcmd >/dev/null 2>&1; then
  echo "[federation_login] FAIL sqlcmd missing — see docs/prerequisites.md" >&2
  exit 1
fi

# Reuse existing edwfed password; otherwise mint one (never reuse admin as the only user).
if [ "$CUR_USER" = "$FED_USER" ] && [ -n "${SOURCE_PASSWORD:-}" ] && [ "${SOURCE_PASSWORD}" != "${AZ_SQL_PASSWORD}" ]; then
  FED_PASS="$SOURCE_PASSWORD"
else
  # Must not contain the login name (SQL policy) and must include upper/lower/digit/symbol.
  FED_PASS="Mig$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)Aa1!"
fi

SQL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/edw-fed-login.XXXXXX")"
chmod 700 "$SQL_DIR"
cleanup() { rm -rf "$SQL_DIR"; }
trap cleanup EXIT

python3 - "$SQL_DIR" "$FED_USER" "$FED_PASS" <<'PY'
import sys
from pathlib import Path

out, user, password = Path(sys.argv[1]), sys.argv[2], sys.argv[3]

def lit(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"

u, p = lit(user), lit(password)
# Login lives in master; user + grants in the app database.
(out / "master.sql").write_text(
    f"""SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = {u})
  CREATE LOGIN [{user}] WITH PASSWORD = {p};
ELSE
  ALTER LOGIN [{user}] WITH PASSWORD = {p};
"""
)
(out / "db.sql").write_text(
    f"""SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = {u})
  CREATE USER [{user}] FROM LOGIN [{user}];
GRANT CONNECT TO [{user}];
GRANT SELECT ON SCHEMA::Dimension TO [{user}];
GRANT SELECT ON SCHEMA::Fact TO [{user}];
GRANT SELECT ON SCHEMA::Integration TO [{user}];
GRANT SELECT ON SCHEMA::INFORMATION_SCHEMA TO [{user}];
GRANT VIEW DEFINITION ON SCHEMA::Dimension TO [{user}];
GRANT VIEW DEFINITION ON SCHEMA::Fact TO [{user}];
GRANT VIEW DEFINITION ON SCHEMA::Integration TO [{user}];
-- Schema-level DENY on sys breaks JDBC LIST NAMESPACES. Deny sys objects
-- except the metadata views Federation needs to list schemas/columns.
REVOKE SELECT ON SCHEMA::sys FROM [{user}];
DECLARE @sql nvarchar(max) = N'';
SELECT @sql = @sql + N'BEGIN TRY DENY SELECT ON OBJECT::sys.' + QUOTENAME(o.name) + N' TO [{user}]; END TRY BEGIN CATCH END CATCH;'
FROM sys.objects AS o
WHERE o.schema_id = SCHEMA_ID(N'sys')
  AND o.type = N'V'
  AND o.name NOT IN (
    N'schemas', N'tables', N'columns', N'types', N'indexes',
    N'foreign_keys', N'key_constraints', N'check_constraints',
    N'default_constraints', N'computed_columns', N'identity_columns',
    N'extended_properties', N'sql_modules', N'parameters', N'index_columns',
    N'databases', N'database_principals'
  );
IF @sql <> N'' EXEC sp_executesql @sql;
GRANT SELECT ON OBJECT::sys.schemas TO [{user}];
GRANT SELECT ON OBJECT::sys.tables TO [{user}];
GRANT SELECT ON OBJECT::sys.columns TO [{user}];
GRANT SELECT ON OBJECT::sys.types TO [{user}];
"""
)
(out / "probe.sql").write_text(
    """SET NOCOUNT ON;
SELECT TABLE_SCHEMA, COUNT(*) AS n
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
GROUP BY TABLE_SCHEMA
ORDER BY TABLE_SCHEMA;
"""
)
PY

echo "[federation_login] waking ${SERVER}/${DB} as admin ..."
AWAKE=0
for i in $(seq 1 12); do
  if sqlcmd -S "$SERVER" -U "$ADMIN" -P "$AZ_SQL_PASSWORD" -d "$DB" -C -l 60 -Q "SELECT 1" >/dev/null 2>/dev/null; then
    echo "[federation_login] Azure SQL awake (attempt ${i})"
    AWAKE=1
    break
  fi
  echo "[federation_login] wake attempt ${i}/12 failed; retrying in 15s"
  sleep 15
done
if [ "$AWAKE" -ne 1 ]; then
  echo "[federation_login] FAIL Azure SQL not reachable (AutoPause / firewall). See docs/firewall.md" >&2
  exit 1
fi

echo "[federation_login] creating login ${FED_USER} (SELECT on Dimension/Fact/Integration only) ..."
# -b: sqlcmd otherwise exits 0 when the batch has T-SQL errors.
sqlcmd -b -S "$SERVER" -U "$ADMIN" -P "$AZ_SQL_PASSWORD" -d master -C -l 60 -i "${SQL_DIR}/master.sql"
sqlcmd -b -S "$SERVER" -U "$ADMIN" -P "$AZ_SQL_PASSWORD" -d "$DB" -C -l 60 -i "${SQL_DIR}/db.sql"

PROBE="$(sqlcmd -b -S "$SERVER" -U "$FED_USER" -P "$FED_PASS" -d "$DB" -C -l 60 -h -1 -W -s $'\t' -i "${SQL_DIR}/probe.sql")"
echo "[federation_login] tables visible to ${FED_USER}:"
echo "$PROBE" | sed '/^$/d' | sed 's/^/  /'

python3 - "$PROBE" <<'PY'
import sys
raw = sys.argv[1]
bad = []
total = 0
for line in raw.splitlines():
    parts = [p.strip() for p in line.split("\t") if p.strip() != ""]
    if len(parts) != 2 or not parts[1].isdigit():
        continue
    schema, n = parts[0], int(parts[1])
    total += n
    if schema.lower() in {"sys", "information_schema"} or n > 80:
        bad.append(f"{schema}={n}")
if bad:
    raise SystemExit(f"[federation_login] FAIL still over-visible: {', '.join(bad)}")
if total < 1:
    raise SystemExit("[federation_login] FAIL edwfed sees 0 tables — grants or wake failed")
print(f"[federation_login] ok visible_base_tables={total}")
PY

python3 - "$REPO_ROOT/.env" "$FED_USER" "$FED_PASS" <<'PY'
from pathlib import Path
import sys

path, user, password = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
lines = path.read_text().splitlines() if path.is_file() else []
keys = {"SOURCE_USER": user, "SOURCE_PASSWORD": password}
seen: set[str] = set()
out: list[str] = []
for line in lines:
    if line and not line.startswith("#") and "=" in line:
        k = line.split("=", 1)[0].strip()
        if k in keys:
            out.append(f"{k}={keys[k]}")
            seen.add(k)
            continue
    out.append(line)
for k, v in keys.items():
    if k not in seen:
        out.append(f"{k}={v}")
path.write_text("\n".join(out) + "\n")
print("[federation_login] wrote SOURCE_USER / SOURCE_PASSWORD in .env")
PY

# Recreate only when the foreign catalog is missing user tables (or forced).
FOREIGN_CATALOG="${FOREIGN_CATALOG:-sqlserver_fed}"
CONNECTION_NAME="${CONNECTION_NAME:-azure_sql_edw}"
NEED_DROP=1
if [ "${FEDERATION_RECREATE:-}" = "1" ]; then
  echo "[federation_login] FEDERATION_RECREATE=1 — dropping ${FOREIGN_CATALOG} + ${CONNECTION_NAME}"
else
  DROP_PROBE="$("${REPO_ROOT}/agents/tools/run_sql.sh" --sql \
    "SELECT COUNT(*) AS n FROM ${FOREIGN_CATALOG}.information_schema.tables WHERE table_schema = 'Dimension' AND table_type = 'BASE TABLE';" \
    2>/dev/null || true)"
  if printf '%s\n' "$DROP_PROBE" | awk 'BEGIN{f=0} $1=="n"{next} $1+0>=1{f=1} END{exit !f}'; then
    echo "[federation_login] ${FOREIGN_CATALOG} already has Dimension tables — keeping catalog/connection"
    NEED_DROP=0
  fi
fi
if [ "$NEED_DROP" -eq 1 ]; then
  echo "[federation_login] dropping stale ${FOREIGN_CATALOG} + ${CONNECTION_NAME} (recreated by setup) ..."
  "${REPO_ROOT}/agents/tools/run_sql.sh" --sql "
DROP CATALOG IF EXISTS ${FOREIGN_CATALOG} CASCADE;
DROP CONNECTION IF EXISTS ${CONNECTION_NAME};
SELECT 'federation_login_dropped' AS check_name;
" || echo "[federation_login] WARN drop skipped (catalog/connection missing or warehouse cold)"
fi

echo "[federation_login] done user=${FED_USER} — next: make setup"
