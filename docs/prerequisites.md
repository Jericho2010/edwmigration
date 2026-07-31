# Prerequisites

Install these before running `bootstrap.sh` or the agent workflow.

## 1. Azure CLI (`az`)

- Install: https://learn.microsoft.com/cli/azure/install-azure-cli
- Login: `az login`
- Verify: `az account show`
- Pinned version: **2.63.0 or newer** (for `--use-free-limit` and
  `--free-limit-exhaustion-behavior` support).

## 2. SqlPackage

Used to import the `.bacpac` into Azure SQL.

- Install: https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage-download
- Verify: `SqlPackage /version`
- Pinned version: **162.0.198 (Nov 2023) or newer**.

### Linux install (one-liner)

```bash
curl -L -o sqlpackage.zip https://aka.ms/sqlpackage-linux
unzip sqlpackage.zip -d ~/sqlpackage
chmod +x ~/sqlpackage/sqlpackage
export PATH="$HOME/sqlpackage:$PATH"
```

## 3. sqlcmd

Used to export proc source and fixtures from Azure SQL.

- Install: https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility
- Verify: `sqlcmd -?`
- Pinned version: **1.2.0 (Go-based) or newer**. The legacy `sqlcmd` (ODBC)
  also works but the Go-based one is easier to install on Linux/macOS.

### Linux install (one-liner)

```bash
curl -L -o sqlcmd.zip https://aka.ms/sqlcmd-linux
unzip sqlcmd.zip -d ~/sqlcmd
chmod +x ~/sqlcmd/sqlcmd
export PATH="$HOME/sqlcmd:$PATH"
```

## 4. Databricks CLI (`databricks`)

Used to deploy the bundle, run the job, manage secrets, and call the
Statement Execution API (via `agents/tools/run_sql.sh`).

- Install: https://docs.databricks.com/cli/install.html
- Login: `databricks auth login --host <your-workspace-url>`
- Verify: `databricks auth profiles`
- Pinned version: **0.230.0 or newer** (for `bundle`; **0.281.0+** for
  dashboard `dataset_catalog` / `dataset_schema`).

There is **no** `databricks sql execute` command. Use:

```bash
./agents/tools/run_sql.sh --sql "SELECT 1"
./agents/tools/run_sql.sh --file path/to/file.sql
```

## 5. jq

Used by the hook scripts to parse JSON payloads.

- Verify: `jq --version`
- Pinned version: **1.7 or newer**.

```bash
# Debian/Ubuntu
sudo apt-get install -y jq
# macOS
brew install jq
```

## 6. python3

Used by `agents/tools/render_manifest_table.py`.

- Verify: `python3 --version`
- Pinned version: **3.10 or newer**.

## 7. Cursor

The agent workflow runs in Cursor (subagents + hooks).

- Install: https://cursor.com
- Verify: open this repo in Cursor; the `.cursor/agents/` and
  `.cursor/hooks.json` should be picked up automatically.

## 8. Databricks Free Edition workspace

- Sign up: https://www.databricks.com/learn/free-edition
- Note your workspace URL (e.g.
  `https://dbc-XXXXXX.cloud.databricks.com`).
- Generate a personal access token (PAT) in the workspace settings.
- Find your serverless SQL warehouse ID (or create a 2X-Small one):
  `databricks warehouses list`.

## 9. Azure subscription

- Any Azure subscription works. The free offer is per-subscription.
- First free DB locks the region for all free DBs on that subscription.
- 100,000 vCore-seconds + 32 GB data + 32 GB backup per DB per month.
- See [docs/limits.md](limits.md) for full constraints.

## Verify everything

```bash
az --version
SqlPackage /version
sqlcmd -?
databricks --version
jq --version
python3 --version
```

All should print a version without error.
