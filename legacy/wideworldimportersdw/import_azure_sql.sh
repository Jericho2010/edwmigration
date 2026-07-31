#!/usr/bin/env bash
# Download and verify the WideWorldImportersDW-Standard.bacpac from Microsoft's
# official SQL Server samples release. Idempotent: skips download if a verified
# copy already exists.
#
# Reference: https://github.com/Microsoft/sql-server-samples/tree/master/samples/databases/wide-world-importers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACPAC_URL="https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImportersDW-Standard.bacpac"
BACPAC_PATH="${SCRIPT_DIR}/WideWorldImportersDW-Standard.bacpac"
# Replace EXPECTED_SHA256 with the actual hash from the upstream release the
# first time you run this script. The placeholder below is illustrative only.
EXPECTED_SHA256="0000000000000000000000000000000000000000000000000000000000000000"

if [ -s "$BACPAC_PATH" ]; then
  ACTUAL_SHA256="$(sha256sum "$BACPAC_PATH" | awk '{print $1}')"
  if [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] && [ "$EXPECTED_SHA256" != "0000000000000000000000000000000000000000000000000000000000000000" ]; then
    echo "[import_azure_sql] bacpac already present and verified; skipping download."
    exit 0
  fi
  echo "[import_azure_sql] existing bacpac missing or hash not pinned; re-downloading."
fi

echo "[import_azure_sql] downloading WideWorldImportersDW-Standard.bacpac ..."
echo "[import_azure_sql]   from: $BACPAC_URL"
echo "[import_azure_sql]   to:   $BACPAC_PATH"

if command -v curl >/dev/null 2>&1; then
  curl -L --fail --output "$BACPAC_PATH" "$BACPAC_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$BACPAC_PATH" "$BACPAC_URL"
else
  echo "[import_azure_sql] ERROR: neither curl nor wget is installed." >&2
  exit 1
fi

ACTUAL_SHA256="$(sha256sum "$BACPAC_PATH" | awk '{print $1}')"
echo "[import_azure_sql] downloaded. sha256=$ACTUAL_SHA256"

if [ "$EXPECTED_SHA256" != "0000000000000000000000000000000000000000000000000000000000000000" ] \
   && [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "[import_azure_sql] WARNING: sha256 mismatch (expected $EXPECTED_SHA256)." >&2
  echo "[import_azure_sql] If this is a known-good upstream change, update EXPECTED_SHA256." >&2
fi

echo "[import_azure_sql] done."
