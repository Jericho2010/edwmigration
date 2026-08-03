# convert_style.md — Databricks notebook style for converted procs

## File header

```sql
-- Converted from: <legacy_proc>
-- Classification: <get|migrate|other>
-- Target layer:   <silver|gold>
-- Patterns:       <windowed|scd2|aggregation|...>
-- Notes:          <one-paragraph summary>
```

## Naming

- Files: `<NN>_<snake_case>.sql` (`20`-`29` silver, `30`-`39` gold).
- Tables: `__UC_CATALOG__.<layer>.<snake_case>` (rendered to the user catalog).
- Columns: snake_case. Quote source columns with spaces when reading bronze.

## Patterns

| Pattern | SQL |
|---|---|
| Full refresh / snapshot | `CREATE OR REPLACE TABLE ... AS SELECT ...` |
| SCD2 | `MERGE` / versioning on silver |
| Avoid | `INSERT INTO` for full-refresh tables |

## Federation limits

Window functions are **not** pushed to SQL Server Federation. Land to bronze first; run windows/joins on Delta in Databricks.

## T-SQL → Spark SQL

| T-SQL | Spark SQL |
|---|---|
| `ISNULL(a,b)` | `COALESCE(a,b)` |
| `GETDATE()` | `current_timestamp()` |
| `CONVERT(DATE,x)` | `CAST(x AS DATE)` |
| `#tmp` | CTEs |
| `WHILE`/cursor | set-based SQL |

## Smoke

```sql
SELECT '<table>_ok' AS check_name, COUNT(*) AS rows FROM __UC_CATALOG__.<layer>.<table>;
```

## Forbidden

- Creating catalogs/schemas (those live in `databricks/uc/`)
- Writing under `databricks/converted/`
- Dropping tables outside your target
