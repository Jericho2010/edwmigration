# EDW → Databricks Migration

Migrate an Azure SQL warehouse into a **user-named Unity Catalog** catalog with an agent pipeline (Assess → Convert → Test → Gate), full discovery of base tables + stored procedures, and a Control Plane dashboard + Genie copilot.

**Awesome demo, not a toy:** optional WideWorldImporters sample DW on Azure SQL free offer + Databricks Free Edition. **Not tightly coupled:** the engine discovers whatever is in *your* Azure SQL database.

## Guided demo (easiest)

Your effort:

1. `az login`
2. `databricks auth login --host <your-workspace-url>` (or set a PAT)
3. Open this repo in Cursor and launch **`edw-demo-guide`**:

   > Set up the EDW demo and walk me through the migration.

The guide materializes `.env`, provisions the sample DW, wires Federation into your catalog, deploys the **EDW Migration Control Plane** dashboard + Genie, then steps Assess → Convert → Test → Gate with you.

Scripted twin (CI/SE): `make materialize-demo && make demo`

## Self-serve (your Azure SQL)

Fill source + sink in `.env` (see [`infra/azure/.env.example`](infra/azure/.env.example)), then:

```bash
make setup          # federation + ops + dashboard + genie
# launch edw-coordinator — discovers ALL base tables + user procs
```

No object list required. If inventory exceeds 200 tables, the coordinator asks you to confirm before landing.

## What you get

| Piece | Role |
|---|---|
| Lakehouse Federation (`TYPE SQLSERVER`) | Live read of Azure SQL |
| Generated bronze land | Every discovered **base table** → `${catalog}.bronze.*` |
| Agent Convert | T-SQL procs → `databricks/silver|gold` notebooks the job runs |
| Gate | Ship/no-ship from inventory + reconcile + conversions |
| Control Plane dashboard | Gate, timeline, backlog, reconcile |
| Genie copilot | “Did the last run ship?” / “Why did the gate fail?” |

Demo acceptance (WWI path): **≥10 tables** and **≥5 procs** migrated — **counts only**, no hard-coded table names in Gate.

## Docs

| Doc | Purpose |
|---|---|
| [docs/runbook.md](docs/runbook.md) | Operator guide |
| [docs/architecture.md](docs/architecture.md) | Engine vs demo pack |
| [docs/prerequisites.md](docs/prerequisites.md) | Tools + privileges |
| [docs/demo-script.md](docs/demo-script.md) | SE talk track |
| [docs/lakebridge.md](docs/lakebridge.md) | Why this path vs Lakebridge |
| [agents/README.md](agents/README.md) | Agent playbook |
| [demo/wwi/README.md](demo/wwi/README.md) | Sample DW pack |

## Layout

```text
infra/azure/     bootstrap / teardown (demo pack)
demo/wwi/        sample DW notes
legacy/          bacpac helpers, procs, fixtures
databricks/      uc/, bronze/, silver/, gold/, jobs/, dashboards/, genie/
agents/          prompts/, contracts/, tools/, github-copilot/
.cursor/agents/  generated Cursor subagents
```

## Cost

Azure SQL free offer + Databricks Free Edition → **$0** when you `make teardown` after the demo.

## License

MIT — see [LICENSE](LICENSE). WideWorldImporters sample is MIT (Microsoft).
