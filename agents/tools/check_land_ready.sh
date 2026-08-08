#!/usr/bin/env bash
# Fail if medallion land SQL is missing or still the bronze placeholder.
# Usage: ./agents/tools/check_land_ready.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CANDIDATES=(
  "${REPO_ROOT}/databricks/_rendered/bronze/10_land_all.sql"
  "${REPO_ROOT}/databricks/generated/10_land_all.sql"
)

LAND=""
for f in "${CANDIDATES[@]}"; do
  if [ -f "$f" ]; then
    LAND="$f"
    break
  fi
done

if [ -z "$LAND" ]; then
  echo "[check_land_ready] FAIL: no land SQL found." >&2
  echo "[check_land_ready]      -> run discover_inventory.py + generate_from_inventory.py + make render" >&2
  exit 1
fi

if grep -qE 'bronze_land_placeholder|Run discover_inventory' "$LAND"; then
  echo "[check_land_ready] FAIL: land SQL is still the placeholder (${LAND})." >&2
  echo "[check_land_ready]      -> run discover_inventory.py + generate_from_inventory.py + make render before make run" >&2
  exit 1
fi

echo "[check_land_ready] OK ${LAND}"
exit 0
