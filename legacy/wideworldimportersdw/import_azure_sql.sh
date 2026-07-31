#!/usr/bin/env bash
# Compatibility wrapper — use download_bacpac.sh (download only).
# SqlPackage import is performed by infra/azure/bootstrap.sh.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/download_bacpac.sh" "$@"
