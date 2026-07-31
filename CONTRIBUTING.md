# Contributing

Contributions welcome — this demo is meant to be extended.

## Ways to contribute

- **Add a proc pattern.** If you convert a WWI proc that uses a T-SQL pattern
  not covered by `agents/prompts/convert_style.md`, update the style guide and
  add a gold (or `converted/`) notebook.
- **Add a stage agent.** New prompt in `agents/prompts/`, regenerate Cursor
  subagents with `sync_prompts.sh`, update the coordinator prompt to delegate.
- **Add a reconcile check.** Insert into `ops.reconcile_results` in
  `databricks/tests/reconcile.sql` (and expectations if fixture-backed).
- **Port to another runtime.** Prompts in `agents/prompts/` are tool-agnostic;
  document the port under `docs/`.
- **Improve the dashboard.** Extend
  `databricks/dashboards/agent_events.lvdash.json`.
- **Docs.** Prefer accuracy over length; update [docs/README.md](docs/README.md)
  when adding a new top-level doc.

## Development workflow

1. Fork and clone.
2. Make your changes.
3. If you edited `agents/prompts/*`, re-sync:
   ```bash
   ./agents/tools/sync_prompts.sh
   ```
4. Test end-to-end on a fresh Azure SQL free-offer DB:
   ```bash
   set -a; . ./.env; set +a
   ./infra/azure/teardown.sh
   ./infra/azure/bootstrap.sh
   export BUNDLE_VAR_warehouse_id="$DATABRICKS_WAREHOUSE_ID"
   databricks bundle validate -t dev
   databricks bundle deploy -t dev
   databricks bundle run edw_migration_medallion -t dev
   ```
5. Run the agent workflow in Cursor and confirm Gate can pass (or document
   expected blockers).
6. Open a PR.

Offline agent/Gate checks: [agents/samples/README.md](agents/samples/README.md).

## Style

- Shell: `set -euo pipefail`, bash shebang; prefer `SCRIPT_DIR` over `cd`.
- SQL: snake_case for new objects; backtick-quote WWI PascalCase-with-spaces
  columns when selecting from the foreign catalog.
- Prompts: markdown, self-contained (subagents do not inherit User Rules).
- Hooks: `failClosed: false` for logging, `failClosed: true` for control flow
  (retry). Never let a logging hook break the agent run.
- Docs: keep the [runbook](docs/runbook.md) and [architecture](docs/architecture.md)
  aligned with code; avoid claiming the job is fully sequential or that `jq`
  is required.

## Commit messages

Conventional Commits:

```
feat: add SCD2 reconcile check for dim_customer
fix: warm up Azure SQL before federation smoke
docs: clarify firewall 0.0.0.0/0 risk
```

## Issues

Open an issue for bugs, gaps, or feature requests. Tags: `demo`, `agents`,
`medallion`, `docs`.
