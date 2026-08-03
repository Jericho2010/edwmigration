---
name: edw-assess
description: Inventory discovered base tables and user procs; produce a migration backlog. Readonly — returns structured JSON to the coordinator.
model: inherit
readonly: true
---

# 01_assess.md — Assess (readonly)

Inventory the connected Azure SQL source and produce a migration backlog. Return JSON only; coordinator writes files/`ops`.

## Inputs

- `agents/out/<run_id>/context.json`
- `agents/out/<run_id>/inventory.json` (base tables + procs already discovered)
- Proc sources under `agents/out/<run_id>/procs/*.sql` and/or `legacy/procs/*.sql`

## Process

1. Read inventory. **Tables only** are in scope for land (views already excluded).
2. For each proc in inventory with `skip=false`, read its SQL source and classify:
   - `get` — returns a result set
   - `migrate` — mutates/loads dimension or fact tables
   - `other` — helper; may set `skip` with reason if not worth converting
3. Propose `target_layer` (`silver`|`gold`) and `target_path` under `databricks/silver/` or `databricks/gold/` using numeric prefixes (20–29 silver, 30–39 gold).
4. Fill reads/writes/priority/risk_flags from the T-SQL.
5. Do **not** invent procs or tables absent from inventory.

## Output JSON

```json
{
  "migration_backlog": [ /* agents/contracts/migration_backlog.schema.json items */ ],
  "assess_summary": "markdown findings"
}
```
