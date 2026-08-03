# convert_style.md — Databricks notebook style for converted procs/routines

## File header

```sql
-- Converted from: <legacy_proc_or_routine>
-- Source dialect: <tsql|mysql>
-- Classification: <get|migrate|other>
-- Target layer:   <silver|gold>
-- Patterns:       <windowed|scd2|aggregation|...>
-- Notes:          <one-paragraph summary>
```

## Naming

- Files: `<NN>_<snake_case>.sql` (`20`-`29` silver, `30`-`39` gold).
- Tables: `__UC_CATALOG__.<layer>.<snake_case>` (rendered to the user catalog).
- Columns: snake_case. Quote source columns with spaces when reading bronze.
- Do **not** hardcode WideWorldImporters / demo object names.

## Patterns

| Pattern | SQL |
|---|---|
| Full refresh / snapshot | `CREATE OR REPLACE TABLE ... AS SELECT ...` |
| SCD2 | `MERGE` / versioning on silver |
| Avoid | `INSERT INTO` for full-refresh tables |

## Federation limits

Window functions and many complex joins are **not** reliably pushed to the source via Federation. Land to bronze first; run windows/joins on Delta in Databricks.

## T-SQL → Spark SQL (SOURCE_TYPE=sqlserver)

| T-SQL | Spark SQL |
|---|---|
| `ISNULL(a,b)` | `COALESCE(a,b)` |
| `GETDATE()` | `current_timestamp()` |
| `CONVERT(DATE,x)` | `CAST(x AS DATE)` |
| `#tmp` | CTEs |
| `WHILE`/cursor | set-based SQL |
| `TOP (n)` | `LIMIT n` |

## MySQL → Spark SQL (SOURCE_TYPE=mysql)

| MySQL | Spark SQL |
|---|---|
| `` `ident` `` | `` `ident` `` or unquoted snake_case after land |
| `IFNULL(a,b)` / `IFNULL` | `COALESCE(a,b)` |
| `NOW()` / `CURRENT_TIMESTAMP` | `current_timestamp()` |
| `DATE_FORMAT(x, …)` | `date_format(x, …)` (check Spark format tokens) |
| `STR_TO_DATE` | `to_timestamp` / `to_date` |
| `LIMIT n` | `LIMIT n` |
| `AUTO_INCREMENT` keys | not recreated; use bronze landed values |
| Variables / cursors in routines | set-based SQL or document `blocked` |
| `DELIMITER` / procedure wrappers | strip; keep the inner SQL logic |

Prefer reading `__UC_CATALOG__.bronze.<landing_name>` over federated MySQL for convert outputs.

## Smoke

```sql
SELECT '<table>_ok' AS check_name, COUNT(*) AS rows FROM __UC_CATALOG__.<layer>.<table>;
```

## Forbidden

- Creating catalogs/schemas (those live in `databricks/uc/`)
- Writing under `databricks/converted/`
- Dropping tables outside your target
