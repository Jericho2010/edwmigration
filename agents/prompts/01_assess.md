# 01_assess.md — Assess (readonly)

Inventory the connected source (Azure SQL or MySQL) and produce a migration backlog. Return JSON only; coordinator writes files/`ops`.

## Inputs

- `agents/out/<run_id>/context.json`
- `agents/out/<run_id>/inventory.json` (base tables + procs/routines already discovered)
- Proc/routine sources under `agents/out/<run_id>/procs/*.sql` and/or `legacy/procs/*.sql`

## Process

1. Read inventory. **Tables only** are in scope for land (views already excluded).
2. If `routines_skipped_reason` is set or `procs` is empty: return an empty `migration_backlog` and note in `assess_summary` that table land proceeds without routine conversion. Do not invent routines.
3. For each proc/routine in inventory with `skip=false`, read its SQL source and classify:
   - `get` — returns a result set
   - `migrate` — mutates/loads dimension or fact tables
   - `other` — helper; may set `skip` with reason if not worth converting
4. Propose `target_layer` (`silver`|`gold`) and `target_path` under `databricks/silver/` or `databricks/gold/` using numeric prefixes (20–29 silver, 30–39 gold).
   - Every convertible item **must** have a **unique** `target_path`.
   - Paths must match `databricks/(silver|gold)/<file>.sql` — never `databricks/converted/`.
   - Uniqueness enables parallel Convert fan-out (one worker per path).
5. Fill reads/writes/priority/risk_flags from the source SQL (T-SQL or MySQL).
6. Do **not** invent procs or tables absent from inventory. Do **not** hardcode WWI names.

## Output JSON

```json
{
  "migration_backlog": [ /* agents/contracts/migration_backlog.schema.json items */ ],
  "assess_summary": "markdown findings"
}
```
