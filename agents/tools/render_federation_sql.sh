#!/usr/bin/env bash
# Back-compat wrapper: render all SQL, then print federation setup to stdout.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"${REPO_ROOT}/agents/tools/render_sql.sh" >/dev/null
cat "${REPO_ROOT}/databricks/_rendered/uc/01_federation_setup.sql"
