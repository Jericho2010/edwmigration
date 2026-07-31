# Contributing

Contributions are welcome. This demo is meant to be extended.

## Ways to contribute

- **Add a new proc pattern.** If you convert a WWI proc that uses a T-SQL
  pattern not covered by `agents/prompts/convert_style.md`, add the mapping
  to the style guide and a corresponding gold notebook.
- **Add a new stage agent.** If you want a stage between Assess and Convert
  (e.g. a "Plan" agent that orders the backlog by dependency), add a prompt
  in `agents/prompts/`, a subagent in `.cursor/agents/`, and update the
  coordinator prompt to delegate to it.
- **Add a reconcile check.** Add a new INSERT into `ops.reconcile_results`
  in `databricks/tests/reconcile.sql`. The Test agent will pick it up
  automatically.
- **Port to another runtime.** The prompts in `agents/prompts/` are
  tool-agnostic. If you wire them into Claude Code, Codex, or another agent
  runtime, add a note in the README and a porting guide in `docs/`.
- **Improve the dashboard.** Add widgets to
  `databricks/dashboards/agent_events.lvdash.json`.

## Development workflow

1. Fork and clone.
2. Make your changes.
3. If you edited any prompt in `agents/prompts/`, re-sync the Cursor
   subagents:
   ```bash
   ./agents/tools/sync_prompts.sh
   ```
4. Test end-to-end on a fresh Azure SQL free-offer DB:
   ```bash
   ./infra/azure/teardown.sh
   ./infra/azure/bootstrap.sh
   databricks bundle deploy && databricks bundle run edw_migration_medallion
   ```
5. Run the agent workflow in Cursor and confirm the gate passes.
6. Open a PR.

## Style

- Shell scripts: `set -euo pipefail`, `bash` shebang, no `cd` inside
  scripts (use absolute paths or `SCRIPT_DIR`).
- SQL: snake_case for new objects; backtick-quote WWI's PascalCase-with-spaces
  columns when selecting from the foreign catalog.
- Prompts: markdown, self-contained (subagents do not inherit User Rules).
- Hooks: `failClosed: false` for logging, `failClosed: true` for control
  flow (retry). Never let a logging hook break the agent run.

## Commit messages

Conventional Commits style:

```
feat: add SCD2 reconcile check for dim_customer
fix: warm up Azure SQL before federation smoke
docs: clarify firewall 0.0.0.0/0 risk
```

## Issues

Open an issue for bugs, gaps, or feature requests. Tag with `demo`,
`agents`, or `medallion` as appropriate.
