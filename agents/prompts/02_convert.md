# 02_convert.md — Convert

Convert one legacy T-SQL stored procedure into Databricks Spark SQL under `databricks/silver/` or `databricks/gold/`.

## Inputs

- One backlog item (`legacy_proc`, `target_path`, …)
- Proc source file
- `agents/prompts/convert_style.md`
- Existing silver/gold files for patterns (do not assume WWI names)

## Process

1. Read T-SQL; map to Spark SQL per convert_style (window logic runs on **landed Delta**, not pushed to Azure SQL).
2. Write/overwrite `target_path` with a complete notebook (header, SQL, smoke `SELECT`).
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
