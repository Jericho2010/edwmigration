# Prerequisites

Install these before running `bootstrap.sh` or the agent workflow.

## Checklist

| # | Tool | Min version | Verify |
|---|---|---|---|
| 1 | Azure CLI (`az`) | 2.63.0+ | `az account show` |
| 2 | SqlPackage | 162.0.198+ | `SqlPackage /version` |
| 3 | sqlcmd (Go-based preferred) | 1.2.0+ | `sqlcmd -?` |
| 4 | Databricks CLI | 0.230.0+ (0.281.0+ for dashboard `dataset_catalog`) | `databricks --version` |
| 5 | python3 | 3.10+ | `python3 --version` |
| 6 | Cursor | current | Repo opens; `.cursor/agents/` visible |
| 7 | Databricks Free Edition | — | Host + PAT + serverless warehouse ID |
| 8 | Azure subscription | — | Free SQL offer available in chosen region |

Optional: `jq` for ad-hoc JSON pretty-printing (hooks use `python3`).

---

## 1. Azure CLI (`az`)

- Install: https://learn.microsoft.com/cli/azure/install-azure-cli
- Login: `az login`
- Verify: `az account show`
- Needed for `--use-free-limit` / `--free-limit-exhaustion-behavior` (2.63.0+).

## 2. SqlPackage

Imports the `.bacpac` into Azure SQL.

- Install: https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-download
- Verify: `SqlPackage /version`

### Linux install (one-liner)

```bash
curl -L -o sqlpackage.zip https://aka.ms/sqlpackage-linux
unzip sqlpackage.zip -d ~/sqlpackage
chmod +x ~/sqlpackage/sqlpackage
export PATH="$HOME/sqlpackage:$PATH"
```

## 3. sqlcmd

Exports proc source and fixtures from Azure SQL.

- Install: https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility
- Verify: `sqlcmd -?`
- Go-based **1.2.0+** preferred; legacy ODBC `sqlcmd` also works.

### Linux install (one-liner)

```bash
curl -L -o sqlcmd.zip https://aka.ms/sqlcmd-linux
unzip sqlcmd.zip -d ~/sqlcmd
chmod +x ~/sqlcmd/sqlcmd
export PATH="$HOME/sqlcmd:$PATH"
```

## 4. Databricks CLI (`databricks`)

Deploys the bundle, runs the job, manages secrets, and calls the Statement
Execution API via `agents/tools/run_sql.sh`.

- Install: https://docs.databricks.com/cli/install.html
- Login: `databricks auth login --host <your-workspace-url>`
- Verify: `databricks auth profiles`

There is **no** `databricks sql execute` command:

```bash
./agents/tools/run_sql.sh --sql "SELECT 1"
./agents/tools/run_sql.sh --file path/to/file.sql
```

## 5. python3

Used by hooks (payload parsing), `run_sql.sh` helpers, fixture builders, and
`agents/tools/render_manifest_table.py`.

## 6. jq (optional)

```bash
sudo apt-get install -y jq   # Debian/Ubuntu
brew install jq              # macOS
```

## 7. Cursor

Agent workflow (subagents + hooks).

- Install: https://cursor.com
- Open this repo at the git root so `.cursor/agents/` and `.cursor/hooks.json`
  load automatically.

## 8. Databricks Free Edition workspace

- Sign up: https://www.databricks.com/learn/free-edition
- Note workspace URL (e.g. `https://dbc-XXXXXX.cloud.databricks.com`).
- Create a personal access token (PAT).
- Find or create a **serverless** SQL warehouse (2X-Small is fine):
  `databricks warehouses list`.

## 9. Azure subscription

- Any subscription works; free offer is per-subscription.
- First free DB locks the region for all free DBs on that subscription.
- 100,000 vCore-seconds + 32 GB data + 32 GB backup per DB per month.
- Details: [limits.md](limits.md).

---

## Verify everything

```bash
az --version
SqlPackage /version
sqlcmd -?
databricks --version
python3 --version
# optional: jq --version
```

All required commands should print a version without error. Then continue to
the [runbook](runbook.md).
