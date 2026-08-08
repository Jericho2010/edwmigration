# 02_convert.md — Convert

Convert **one** legacy stored procedure (T-SQL) or MySQL routine into Databricks Spark SQL under `databricks/silver/` or `databricks/gold/`.

You may run in parallel with other Convert workers for the same `run_id`. Shared memory is disk-only under `agents/out/<run_id>/` (orchestrator-worker artifact pattern: write the notebook + result JSON; return a short path summary in chat).

## Inputs

- `run_id` and one backlog item (`item_id`, `legacy_proc`, `target_path`, …)
- Proc/routine source file
- `agents/out/<run_id>/context.json` (`uc_catalog`, `source_type`)
- `agents/out/<run_id>/inventory.json` — map source tables → `landing_name` for bronze reads
- `SOURCE_TYPE` from context / `.env` (`sqlserver`|`mysql`)
- `agents/prompts/convert_style.md`
- Existing silver/gold files for patterns (do not assume WWI names)

## Process

1. Read `context.json`, inventory `landing_name`s, and source SQL; map to Spark SQL per convert_style for the dialect (`tsql` or `mysql`). **Land-first:** windows/joins/MERGE run on `__UC_CATALOG__.bronze.<landing_name>`, not the federated source.
2. If blocked criteria in convert_style apply: write a stub notebook with `-- TODO` and result `status: "blocked"`.
3. Otherwise write/overwrite **only** this item's `target_path` with a complete notebook (header including `Source dialect`, SQL, smoke `SELECT`). Prefer set-based `CREATE OR REPLACE` / `MERGE`. Do **not** emit `CREATE PROCEDURE`.
4. Use `${uc_catalog}` / `__UC_CATALOG__` three-part names consistent with repo templates (`__UC_CATALOG__.silver|gold.*`).
5. **Must** write result JSON to `agents/out/<run_id>/convert/<item_id>.json` per `agents/contracts/convert_result.schema.json`, then validate:

```bash
python3 agents/tools/validate_artifact.py \
  --schema agents/contracts/convert_result.schema.json \
  --file agents/out/<run_id>/convert/<item_id>.json
```

If validation fails, fix the JSON (or mark blocked) before finishing.

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

You may also echo a one-line path summary in chat; the disk file is the handoff the coordinator merges.

## Constraints

- Write only under `databricks/silver/` or `databricks/gold/`. **Never** `databricks/converted/`, bronze, uc, or tests.
- Own **only** this item's `target_path` and `convert/<item_id>.json`. Do not edit other workers' files, `migration_backlog.json`, or `ops.*`.
- Writing a notebook does **not** auto-add it to `databricks/jobs/edw_migration_medallion.yml` — coordinator runs `check_job_wiring.py` (WARN). Gate checks disk + `proc_conversion_map`, not job execution of every new path.
