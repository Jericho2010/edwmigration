#!/usr/bin/env bash
# Bootstrap the free Azure SQL EDW for the migration demo.
#
# Provisions:
#   - Resource group
#   - Azure SQL logical server (public network)
#   - Free-offer General Purpose serverless database (AutoPause on limit)
#   - Firewall rules (client + Databricks egress demo rule)
# Then loads:
#   - WideWorldImportersDW bacpac (via SqlPackage)
#   - Proc source export (legacy/procs/)
#   - Reconcile fixtures (legacy/fixtures/)
# Finally creates the Databricks secrets scope and stores the SQL password.
#
# Usage:
#   ./bootstrap.sh            # full run
#   ./bootstrap.sh --dry-run  # print all commands without executing
#
# Requires env vars from .env (see .env.example). Source .env first:
#   set -a; . ./.env; set +a
set -euo pipefail

# ---------------------------------------------------------------------------
# Config & arg parsing
# ---------------------------------------------------------------------------
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

run() {
  # Echo then execute (or just echo if dry-run).
  echo "+ $*"
  if [ "$DRY_RUN" -eq 0 ]; then
    eval "$@"
  fi
}

# ---------------------------------------------------------------------------
# Required env
# ---------------------------------------------------------------------------
: "${AZ_SUBSCRIPTION_ID:?AZ_SUBSCRIPTION_ID must be set (see .env.example)}"
: "${AZ_LOCATION:=eastus}"
: "${AZ_RG:=rg-edw-migration-demo}"
: "${AZ_SQL_SERVER:?AZ_SQL_SERVER must be set (globally unique)}"
: "${AZ_SQL_ADMIN:=edwadmin}"
: "${AZ_SQL_PASSWORD:?AZ_SQL_PASSWORD must be set}"
: "${AZ_SQL_DB:=WideWorldImportersDW}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST must be set}"
: "${DATABRICKS_TOKEN:?DATABRICKS_TOKEN must be set}"
: "${DATABRICKS_SECRET_SCOPE:=edw-migration}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACPAC_PATH="${REPO_ROOT}/legacy/wideworldimportersdw/WideWorldImportersDW-Standard.bacpac"

echo "============================================================"
echo " EDW Migration Demo — Azure SQL bootstrap"
echo "   subscription : ${AZ_SUBSCRIPTION_ID}"
echo "   location      : ${AZ_LOCATION}"
echo "   resource grp  : ${AZ_RG}"
echo "   sql server    : ${AZ_SQL_SERVER}.database.windows.net"
echo "   database      : ${AZ_SQL_DB}"
echo "   dry-run       : ${DRY_RUN}"
echo "============================================================"

# ---------------------------------------------------------------------------
# 0. Tool checks
# ---------------------------------------------------------------------------
echo
echo "[0/9] checking tools ..."
for tool in az sqlcmd SqlPackage databricks jq curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool not found on PATH: $tool" >&2
    echo "See docs/prerequisites.md for install instructions." >&2
    exit 1
  fi
done
echo "  all tools present."

# ---------------------------------------------------------------------------
# 1. Azure login + subscription
# ---------------------------------------------------------------------------
echo
echo "[1/9] setting Azure subscription ..."
run "az account set --subscription '${AZ_SUBSCRIPTION_ID}'"

# ---------------------------------------------------------------------------
# 2. Resource group
# ---------------------------------------------------------------------------
echo
echo "[2/9] creating resource group '${AZ_RG}' ..."
run "az group create --name '${AZ_RG}' --location '${AZ_LOCATION}'"

# ---------------------------------------------------------------------------
# 3. SQL logical server
# ---------------------------------------------------------------------------
echo
echo "[3/9] creating SQL logical server '${AZ_SQL_SERVER}' ..."
run "az sql server create --name '${AZ_SQL_SERVER}' --resource-group '${AZ_RG}' --location '${AZ_LOCATION}' --admin-user '${AZ_SQL_ADMIN}' --admin-password '${AZ_SQL_PASSWORD}' --enable-public-network true"

# ---------------------------------------------------------------------------
# 4. Free-offer database
# ---------------------------------------------------------------------------
echo
echo "[4/9] creating free-offer database '${AZ_SQL_DB}' (AutoPause on limit) ..."
run "az sql db create --resource-group '${AZ_RG}' --server '${AZ_SQL_SERVER}' --name '${AZ_SQL_DB}' --edition GeneralPurpose --compute-model Serverless --family Gen5 --capacity 1 --auto-pause-delay 15 --min-capacity 0.5 --max-size 32GB --use-free-limit true --free-limit-exhaustion-behavior AutoPause"

# ---------------------------------------------------------------------------
# 5. Firewall rules
# ---------------------------------------------------------------------------
echo
echo "[5/9] creating firewall rules ..."
CLIENT_IP="$(curl -s https://api.ipify.org || true)"
if [ -n "$CLIENT_IP" ]; then
  echo "  your client IP: ${CLIENT_IP}"
  run "az sql server firewall-rule create --resource-group '${AZ_RG}' --server '${AZ_SQL_SERVER}' --name AllowClientLoad --start-ip-address '${CLIENT_IP}' --end-ip-address '${CLIENT_IP}'"
else
  echo "  WARNING: could not detect client IP; skipping AllowClientLoad rule." >&2
fi

echo
echo "  WARNING: creating AllowDatabricksDemo rule with 0.0.0.0/0."
echo "  This opens the SQL server to the public internet so Databricks Free"
echo "  Edition (AWS-hosted) can reach it. Run teardown.sh to remove it."
echo "  See docs/firewall.md for the risk and the optional 2h auto-delete."
run "az sql server firewall-rule create --resource-group '${AZ_RG}' --server '${AZ_SQL_SERVER}' --name AllowDatabricksDemo --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255"

# ---------------------------------------------------------------------------
# 6. Import bacpac
# ---------------------------------------------------------------------------
echo
echo "[6/9] importing WideWorldImportersDW bacpac via SqlPackage ..."
if [ ! -s "$BACPAC_PATH" ]; then
  echo "  bacpac not found at ${BACPAC_PATH}; downloading ..."
  run "${REPO_ROOT}/legacy/wideworldimportersdw/download_bacpac.sh"
fi
CONN_STR="Server=tcp:${AZ_SQL_SERVER}.database.windows.net,1433;Database=${AZ_SQL_DB};User ID=${AZ_SQL_ADMIN};Password=${AZ_SQL_PASSWORD};Encrypt=true;TrustServerCertificate=false;"
run "SqlPackage /a:Import /tf:'${BACPAC_PATH}' /tcs:'${CONN_STR}'"

# ---------------------------------------------------------------------------
# 7. Warmup the (now-cold) serverless DB
# ---------------------------------------------------------------------------
echo
echo "[7/9] warming up the serverless DB (auto-paused after import) ..."
SERVER_ARG="tcp:${AZ_SQL_SERVER}.database.windows.net,1433"
if [ "$DRY_RUN" -eq 0 ]; then
  echo "  polling DB status until Online ..."
  for i in $(seq 1 30); do
    STATUS="$(az sql db show --resource-group "$AZ_RG" --server "$AZ_SQL_SERVER" --name "$AZ_SQL_DB" --query "status" -o tsv 2>/dev/null || echo "Unknown")"
    echo "  attempt ${i}: status=${STATUS}"
    if [ "$STATUS" = "Online" ]; then break; fi
    sleep 10
  done
  echo "  issuing SELECT 1 to wake the compute ..."
  sqlcmd -S "$SERVER_ARG" -U "$AZ_SQL_ADMIN" -P "$AZ_SQL_PASSWORD" -d "$AZ_SQL_DB" -C -l 60 -Q "SELECT 1" >/dev/null
else
  echo "  (dry-run) sqlcmd -S ${SERVER_ARG} ... -Q 'SELECT 1'"
fi

# ---------------------------------------------------------------------------
# 8. Export proc source + fixtures
# ---------------------------------------------------------------------------
echo
echo "[8/9] exporting proc source and reconcile fixtures ..."
run "${REPO_ROOT}/legacy/procs/export_proc_source.sh"
run "${REPO_ROOT}/legacy/fixtures/export_fixtures.sh"

# ---------------------------------------------------------------------------
# 9. Smoke test + Databricks secrets scope
# ---------------------------------------------------------------------------
echo
echo "[9/9] smoke test + Databricks secrets scope ..."
if [ "$DRY_RUN" -eq 0 ]; then
  echo "  smoke: row count + proc list ..."
  sqlcmd -S "$SERVER_ARG" -U "$AZ_SQL_ADMIN" -P "$AZ_SQL_PASSWORD" -d "$AZ_SQL_DB" -C -l 60 -Q "SELECT COUNT(*) AS fact_sale_count FROM Fact.Sale; SELECT name FROM sys.procedures WHERE schema_id = SCHEMA_ID('Integration') ORDER BY name;" -s "," -W
else
  echo "  (dry-run) sqlcmd smoke test"
fi

echo
echo "  creating Databricks secrets scope '${DATABRICKS_SECRET_SCOPE}' ..."
if [ "$DRY_RUN" -eq 0 ]; then
  # Idempotent: try create, ignore "already exists"
  databricks secrets create-scope "$DATABRICKS_SECRET_SCOPE" 2>/dev/null \
    || echo "  scope already exists; continuing."
  # Store the SQL password for the federation connection
  printf '%s' "$AZ_SQL_PASSWORD" | databricks secrets put-secret "$DATABRICKS_SECRET_SCOPE" azure-sql-password --string-from-stdin
  echo "  stored secret 'azure-sql-password' in scope '${DATABRICKS_SECRET_SCOPE}'."
else
  echo "  (dry-run) databricks secrets create-scope + put-secret"
fi

echo
echo "============================================================"
echo " Bootstrap complete."
echo " Next: databricks bundle deploy && databricks bundle run edw_migration_medallion"
echo " Teardown: ./infra/azure/teardown.sh"
echo "============================================================"
