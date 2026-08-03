# 02_convert.md — Convert

Convert one legacy stored procedure (T-SQL) or MySQL routine into Databricks Spark SQL under `databricks/silver/` or `databricks/gold/`.

## Inputs

- One backlog item (`legacy_proc`, `target_path`, …)
- Proc/routine source file
- `SOURCE_TYPE` from context / `.env` (`sqlserver`|`mysql`)
- `agents/prompts/convert_style.md`
- Existing silver/gold files for patterns (do not assume WWI names)

## Process

1. Read source SQL; map to Spark SQL per convert_style for the dialect (`tsql` or `mysql`). Window logic runs on **landed Delta**, not pushed to the federated source.
2. Write/overwrite `target_path` with a complete notebook (header including `Source dialect`, SQL, smoke `SELECT`).
3. Use `${uc_catalog}` / `__UC_CATALOG__` three-part names consistent with repo templates (`__UC_CATALOG__.silver|gold.*`).
4. Return mapping notes JSON:

```json
{
  "legacy_proc": "Schema.ProcName",
  "target_path": "databricks/gold/3x_....sql",
  "status": "draft|review|final|blocked",
  "notes": "...",
  "patterns_used": ["snapshot", "scd2"]
}
```

## Constraints

- Write only under `databricks/silver/` or `databricks/gold/`. **Never** `databricks/converted/`, bronze, uc, or tests.
- Do not insert into `ops.*` — coordinator does.
- If blocked, write a stub with `-- TODO` and `status: "blocked"`.
