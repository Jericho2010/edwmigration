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

## Land-first (Federation)

Foreign catalogs are **read-only**. Window functions and many complex joins are **not** reliably pushed to the source via Federation.

1. Bronze land already copied base tables into `__UC_CATALOG__.bronze.<landing_name>`.
2. Convert **reads bronze Delta**, not the federated source, for windows/joins/MERGE.
3. Prefer inventory `landing_name` when mapping source tables → bronze.

## Patterns

| Pattern | SQL |
|---|---|
| Full refresh / snapshot | `CREATE OR REPLACE TABLE ... AS SELECT ...` |
| SCD2 | `MERGE` / versioning on silver |
| Avoid | `INSERT INTO` for full-refresh tables |

## T-SQL → Spark SQL (SOURCE_TYPE=sqlserver)

| T-SQL | Spark SQL |
|---|---|
| `ISNULL(a,b)` | `COALESCE(a,b)` |
| `GETDATE()` / `SYSDATETIME()` | `current_timestamp()` |
| `CONVERT(DATE,x)` / `CAST(x AS DATE)` | `CAST(x AS DATE)` |
| `CONVERT(VARCHAR,…)` | `CAST(... AS STRING)` |
| `#tmp` / table vars | CTEs or temp views in-notebook |
| `WHILE` / cursor | set-based SQL (or `blocked` if redesign too large) |
| `TOP (n)` | `LIMIT n` |
| `OUTER APPLY` | `LEFT JOIN` / lateral redesign |
| `STRING_AGG` | `array_join(collect_list(...), …)` |
| `TRY_CAST` | `try_cast` |
| `MERGE` + `OUTPUT` | `MERGE` without OUTPUT; follow-up `SELECT` if needed |
| `SCOPE_IDENTITY()` | not applicable — use natural/business keys from bronze |

## MySQL → Spark SQL (SOURCE_TYPE=mysql)

| MySQL | Spark SQL |
|---|---|
| `` `ident` `` | `` `ident` `` or unquoted snake_case after land |
| `IFNULL(a,b)` | `COALESCE(a,b)` |
| `NOW()` / `CURRENT_TIMESTAMP` | `current_timestamp()` |
| `DATE_FORMAT(x, …)` | `date_format(x, …)` (check Spark format tokens) |
| `STR_TO_DATE` | `to_timestamp` / `to_date` |
| `LIMIT n` | `LIMIT n` |
| `AUTO_INCREMENT` keys | not recreated; use bronze landed values |
| Variables / cursors in routines | set-based SQL or document `blocked` |
| `DELIMITER` / procedure wrappers | strip; keep the inner SQL logic |
| `ON DUPLICATE KEY UPDATE` | `MERGE` |

Prefer reading `__UC_CATALOG__.bronze.<landing_name>` over federated MySQL for convert outputs.

## Blocked criteria (status: blocked + stub `-- TODO`)

Mark **blocked** (do not invent half-working SQL) when the source relies on:

- Cursors / row-by-row loops that cannot be rewritten set-based in scope
- Linked servers / remote four-part names outside Federation
- `xp_*` / CLR / OLE automation / file system procs
- Heavy dynamic SQL (`EXEC(@sql)` / `PREPARE` of arbitrary strings) without a clear static equivalent
- Multi-statement transactions that require true multi-table atomicity (single-statement Delta semantics differ)
- Writes back to the federated source (Federation is read-only)

## Out of scope for this engine

Databricks SQL scripting / `CREATE PROCEDURE` (Runtime 17+) is a valid enterprise migration path, but **this engine** emits set-based notebooks under `databricks/silver|gold/` for the medallion DAB job. Do **not** emit `CREATE PROCEDURE` here.

## Smoke

```sql
SELECT '<table>_ok' AS check_name, COUNT(*) AS rows FROM __UC_CATALOG__.<layer>.<table>;
```

## Forbidden

- Creating catalogs/schemas (those live in `databricks/uc/`)
- Writing under `databricks/converted/`
- Dropping tables outside your target
- Writing to foreign catalogs
