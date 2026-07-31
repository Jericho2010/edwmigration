# convert_style.md — Databricks notebook style guide for converted procs

This guide keeps converted notebooks consistent and reviewable. The Convert
agent must follow it.

## File header

Every converted notebook starts with a header comment:

```sql
-- Converted from: <legacy_proc>
-- Classification: <get|migrate|other>
-- Target layer:   <silver|gold>
-- Patterns:       <windowed|scd2|aggregation|...>
-- Notes:          <one-paragraph summary of the conversion>
```

## Naming

- Files: `<NN>_<snake_case_name>.sql` where `NN` is the layer order
  (`10`-`19` bronze, `20`-`29` silver, `30`-`39` gold).
- Tables: `edw_migration.<layer>.<snake_case_name>`.
- Columns: snake_case. WWI source columns are PascalCase with spaces
  (e.g. `WWI Stock Item ID`); alias them to snake_case in the first SELECT
  that touches them.

## Table write patterns

| Pattern | When | SQL |
|---|---|---|
| Full refresh | `get` procs, daily marts | `CREATE OR REPLACE TABLE ... AS SELECT ...` |
| Snapshot | `migrate` procs (current-state) | `CREATE OR REPLACE TABLE ... AS SELECT ...` |
| Append | incremental facts (rare in this demo) | `INSERT INTO ...` (not used by default) |

Never use `INSERT INTO` for a full-refresh table — it will duplicate rows on
re-runs. Use `CREATE OR REPLACE TABLE AS SELECT` or `INSERT OVERWRITE`.

## T-SQL → Spark SQL mapping

| T-SQL | Spark SQL |
|---|---|
| `@LastCutoff` / `@NewCutoff` | `WHERE col BETWEEN ${last_cutoff} AND ${new_cutoff}` (use a DECLARE VARIABLE at the top) |
| `MERGE` | `MERGE INTO` |
| `#tmp` temp tables | CTEs (`WITH tmp AS (...)`) |
| `WHILE` / cursor | set-based SQL; if unavoidable, document why |
| `ISNULL(a, b)` | `COALESCE(a, b)` |
| `GETDATE()` | `current_timestamp()` |
| `CONVERT(DATE, x)` | `CAST(x AS DATE)` |
| `ROW_NUMBER() OVER (...)` | same (window functions are supported) |
| `TRY_CAST` | `TRY_CAST` (supported) |
| `STRING_AGG` | `STRING_AGG` (supported) |
| `JSON_*` | `from_json` / `get_json_object` |

## Smoke test

Every notebook ends with a one-line smoke:

```sql
SELECT '<table_name>_ok' AS check_name, COUNT(*) AS rows;
```

This makes failures visible in the job task output without a separate test step.

## Comments

- Comment the **why**, not the **what**. The SQL is the what.
- Mark any deviation from a 1:1 conversion with `-- CONVERSION NOTE: ...`
  so the Test agent and human reviewers can spot semantic drift.

## Forbidden

- Do not create databases, catalogs, or schemas from a converted notebook
  (those live in `databricks/uc/`).
- Do not drop tables outside your target layer.
- Do not use `SELECT *` in the final `CREATE OR REPLACE TABLE AS SELECT` —
  list columns explicitly so schema drift is visible.
