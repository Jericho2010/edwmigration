# Contributing

## Extend the engine (preferred)

- Improve discovery (`discover_inventory.py`), land generation, Gate rules, Dashboard/Genie.
- Parallel Convert handoff: `agents/contracts/convert_result.schema.json`, `validate_backlog_paths.py`, `merge_convert_results.py`.
- Keep **WWI object names out of** `databricks/uc/`, stage prompts `00`–`04`, and `slugify.py`.
- Demo-only content belongs under `demo/wwi/`, `infra/azure/`, or `legacy/`.

## Extend the demo pack

- Bacpac, fixtures, talk track, known-good silver/gold patterns.

## Prompts

Edit `agents/prompts/`, then:

```bash
./agents/tools/sync_prompts.sh
```

## Validate

```bash
# local
./agents/tools/sync_prompts.sh
SOURCE_TYPE=sqlserver DATABRICKS_CATALOG=edw_migration AZ_SQL_SERVER=example ./agents/tools/render_sql.sh
SOURCE_TYPE=mysql SOURCE_HOST=h SOURCE_DATABASE=d SOURCE_USER=u SOURCE_PASSWORD=x DATABRICKS_CATALOG=c ./agents/tools/render_sql.sh
```

CI runs contract validation, render, and guardrails (no offline mode, no Lakebridge compose).
