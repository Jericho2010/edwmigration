# Runbook

Short checklist for people who already know the story.  
**New here?** Use [Getting started](getting-started.md) → [Guided demo](guided-demo.md) instead.

---

## Track A — Guided demo

1. Cursor → **`edw-demo-guide`** → *Set up the EDW demo and walk me through the migration.*  
2. If preflight asks: `az login` / `databricks auth login --host <workspace>` / create serverless warehouse — then say continue  
3. Open Control Plane + Genie URLs  
4. Teardown: ask the guide, or `make teardown`  

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
| `make print-urls` | Dashboard + Genie links |
| `make deploy` / `make run` | Bundle deploy / job |
| `make teardown` | Delete demo Azure RG |
| `make sync-prompts` | Regenerate Cursor + Copilot agents |

---

## Trust checklist

1. `agents/out/<run_id>/inventory.json`  
2. Convert artifacts (`convert/*.json` + `convert_summary.json`) when procs were in scope  
3. Bronze reconcile pass  
4. Gate blockers empty → `make print-urls`
