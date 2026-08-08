# edw-convert

Portable stage instructions (same body as agents/prompts/02_convert.md).
Use in GitHub Copilot Chat / coding agent. Coordinator owns the run.

# 02_convert.md — Convert

Convert **one** legacy stored procedure (T-SQL) or MySQL routine into Databricks Spark SQL under `databricks/silver/` or `databricks/gold/`.

You may run in parallel with other Convert workers for the same `run_id`. Shared memory is disk-only under `agents/out/<run_id>/`.

## Inputs

- `run_id` and one backlog item (`item_id`, `legacy_proc`, `target_path`, …)
- Proc/routine source file
- `agents/out/<run_id>/context.json` (`uc_catalog`, `source_type`)
- `SOURCE_TYPE` from context / `.env` (`sqlserver`|`mysql`)
- `agents/prompts/convert_style.md`
- Existing silver/gold files for patterns (do not assume WWI names)

## Process

1. Read `context.json` and source SQL; map to Spark SQL per convert_style for the dialect (`tsql` or `mysql`). Window logic runs on **landed Delta**, not pushed to the federated source.
2. Write/overwrite **only** this item's `target_path` with a complete notebook (header including `Source dialect`, SQL, smoke `SELECT`).
3. Use `${uc_catalog}` / `__UC_CATALOG__` three-part names consistent with repo templates (`__UC_CATALOG__.silver|gold.*`).
4. **Must** write result JSON to `agents/out/<run_id>/convert/<item_id>.json` per `agents/contracts/convert_result.schema.json`:

```json
{
  "item_id": "item-001",
  "legacy_proc": "Schema.ProcName",
  "target_path": "databricks/gold/3x_....sql",
  "status": "draft|review|final|blocked",
  "notes": "...",
  "patterns_used": ["snapshot", "scd2"]
}
```

You may also echo the same JSON in chat; the disk file is the handoff the coordinator merges.

## Constraints

- Write only under `databricks/silver/` or `databricks/gold/`. **Never** `databricks/converted/`, bronze, uc, or tests.
- Do **not** edit `migration_backlog.json`, other items' `target_path`s, other `convert/*.json` files, or `ops.*` — coordinator / merge helper owns those.
- If blocked, write a stub notebook with `-- TODO` and `status: "blocked"` in the result JSON.
