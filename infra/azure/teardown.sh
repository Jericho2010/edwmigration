#!/usr/bin/env bash
# Tear down the Azure SQL EDW created by bootstrap.sh.
#
# Deletes the entire resource group (server, DB, firewall rules, all).
# Idempotent: exits 0 if the RG does not exist.
#
# Usage:
#   ./teardown.sh
# Requires env vars from .env (see .env.example).
set -euo pipefail

: "${AZ_RG:=rg-edw-migration-demo}"

echo "[teardown] deleting resource group '${AZ_RG}' ..."
echo "[teardown] this also removes the AllowDatabricksDemo 0.0.0.0/0 firewall rule."

if ! az group exists --name "$AZ_RG" 2>/dev/null | grep -q true; then
  echo "[teardown] resource group does not exist; nothing to do."
  exit 0
fi

az group delete --name "$AZ_RG" --yes --no-wait
echo "[teardown] deletion initiated (async). Monitor with:"
echo "  az group exists --name '${AZ_RG}'   # returns false when fully deleted"

echo
echo "[teardown] NOTE: the Databricks secrets scope '${DATABRICKS_SECRET_SCOPE:-edw-migration}'"
echo "[teardown] was NOT deleted (it is outside Azure). To remove it:"
echo "  databricks secrets delete-scope ${DATABRICKS_SECRET_SCOPE:-edw-migration}"
