# Runbook

Short checklist for people who already know the story.  
**New here?** Use [Getting started](getting-started.md) → [Guided demo](guided-demo.md) instead.

---

## Track A — Guided demo

1. Cursor → type **`start`** → choose **1** (or **`edw-demo-guide`** + kickoff phrase)  
2. If preflight asks: `az login` / `databricks auth login --host <workspace>` / create serverless warehouse — then say continue  
3. Open Control Plane + Genie + Catalog URLs (Notebooks after Land; Job after deploy)  
4. Teardown: `make teardown-databricks` (Databricks assets; keeps Azure SQL) and/or `make teardown` (Azure RG)  

Scripted infra: `make materialize-demo && make demo`  

Details: [guided-demo.md](guided-demo.md)

---

## Track B — Azure MySQL

```bash
cp infra/azure/.env.example .env   # SOURCE_TYPE=mysql + SOURCE_* + DATABRICKS_*
make setup
# edw-coordinator: Migrate my Azure MySQL into catalog <name>.
```

Firewall note: [firewall.md](firewall.md) · Full page: [your-database.md](your-database.md)

---

## Track B — Existing Azure SQL

```bash
cp infra/azure/.env.example .env   # SOURCE_TYPE=sqlserver + SOURCE_* or AZ_SQL_*
make setup
# edw-coordinator: Start an EDW migration run against my Azure SQL.
```

SqlPackage **not** required for `make setup`.

---

## Makefile (common)

| Target | Purpose |
|---|---|
| `make materialize-demo` | Build `.env` from logins (A) |
| `make bootstrap` | Free Azure SQL + WWI |
| `make setup` | Secrets + federation + deploy + genie + URLs |
| `make observe-setup` | Create `.venv` + install MLflow observe deps |
| `make print-urls` | Control Plane + Genie + Catalog + Job + Notebooks + MLflow `observe_url` |
| `make reset-sink` | Wipe Databricks managed sink + `agents/out` (**keeps Azure**) |
| `make teardown-databricks` | Destroy job, dashboard, Genie, MLflow experiment, catalog, connection, secret scope, `edwmigration_*` notebooks (**keeps Azure SQL**) |
| `make deploy` / `make run` | Bundle deploy / job |
| `make teardown` | Delete demo Azure RG |
| `make sync-prompts` | Regenerate Cursor + Copilot agents |

Also: `./agents/tools/observe_status.sh` (stage checkpoint), `./agents/tools/check_mlflow_observe.sh` (add `--strict` in Track A preflight). Full write-up: **[MLflow observability](mlflow.md)**.

**Re-demo without rebuilding Azure:** `make reset-sink` then mint a new run (Discover → Gate). To wipe Databricks assets entirely (orphaned MLflow runs, Genie, jobs) but keep Azure SQL: `make teardown-databricks` then `make setup`.
---

## Trust checklist

1. `agents/out/<run_id>/inventory.json`  
2. Convert artifacts (`convert/*.json` + `convert_summary.json`) when procs were in scope  
3. Bronze reconcile pass  
4. Gate blockers empty → `make print-urls`
