# Contributing

## Extend the engine (preferred)

- Improve discovery (`discover_inventory.py`), land generation, Gate rules, Dashboard/Genie, Convert quality.
- Parallel Convert handoff: `agents/contracts/convert_result.schema.json`, `validate_backlog_paths.py`, `merge_convert_results.py`.
- Job DAG: `check_job_wiring.py` from Assess `reads`/`writes` (peak ≤ 5). Do not hardcode a peak-wave task list.
- Path allocation: `allocate_target_paths.py` next `NN` from 20 + slug from `legacy_proc`. No canned dims/marts namespace.
- Keep **WWI object names out of** the committed job YAML (+ skeleton), `databricks/uc/`, `databricks/tests/13_stage_fixture_expectations.sql`, `ensure_source_alias_views.sh`, `allocate_target_paths.py`, stage prompts `00`–`04`, and `slugify.py`.
- Do **not** copy `demo/wwi/reference/` into `databricks/silver|gold` or into the job. Do **not** keep `20_dims_scd1` / `22_fact_sale` / `30_mart_*` as default job tasks.
- Demo-only content belongs under `demo/wwi/` (including `reference/`), `infra/azure/`, or `legacy/`.

## Extend the demo pack

- Bacpac, fixtures, talk track. Teaching silver/gold stays under `demo/wwi/reference/` (not executed).

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
