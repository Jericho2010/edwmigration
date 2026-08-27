# Source after .env (or Makefile export). Overlays DATABRICKS_TOKEN from a
# CLI profile whose host matches DATABRICKS_HOST when .env has HOST without PAT.
# Safe to source more than once. Never fails the caller.
_edw_auth_tools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_edw_auth_root="$(cd "${_edw_auth_tools}/../.." && pwd)"
if command -v python3 >/dev/null 2>&1 && [ -f "${_edw_auth_root}/agents/tools/databricks_cli_env.py" ]; then
  eval "$(python3 "${_edw_auth_root}/agents/tools/databricks_cli_env.py" --export 2>/dev/null || true)"
fi
unset _edw_auth_tools _edw_auth_root
