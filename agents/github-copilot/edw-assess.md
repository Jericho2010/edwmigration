# edw-assess

Portable stage instructions (same body as agents/prompts/01_assess.md).
Use in GitHub Copilot Chat / coding agent. Coordinator owns the run.

# 01_assess.md — Assess (readonly)

Inventory the connected source (Azure SQL or MySQL) and produce a migration backlog. Return JSON only; coordinator persists via `persist_backlog.py`.

## Inputs

- `agents/out/<run_id>/context.json`
- `agents/out/<run_id>/inventory.json` (base tables + procs/routines already discovered)
- Proc/routine sources: prefer `inventory.procs[].source_path` (usually under `agents/out/<run_id>/procs/*.sql`); fallback `legacy/procs/*.sql`
- Samples: `agents/samples/run/migration_backlog.json`, `agents/samples/run/migration_backlog.empty.json`

## Inventory field map

| Field | Use |
|---|---|
| `tables[].landing_name` | Bronze table name Convert must read (`__UC_CATALOG__.bronze.<landing_name>`) |
| `tables[].skip` | Ignore when true |
| `procs[].legacy_proc` / name | Fully-qualified proc/routine |
| `procs[].source_path` | SQL file to classify |
| `procs[].skip` | Ignore when true (do not invent replacements) |
| `routines_skipped_reason` | If set → empty backlog (table-only) |

## Process

1. Read inventory. **Tables only** are in scope for land (views already excluded).
2. If `routines_skipped_reason` is set or `procs` is empty: return an empty `migration_backlog` and note in `assess_summary` that table land proceeds without routine conversion. Do not invent routines.
3. For each proc/routine in inventory with `skip=false`, read its SQL source and classify:
   - `get` — returns a result set
   - `migrate` — mutates/loads dimension or fact tables
   - `other` — helper
4. **Helpers / not worth converting:** either **omit** from the backlog, **or** include with `status: "blocked"`, `target_layer: "n/a"`, and reason in `risk_flags` (e.g. `helper,cursor`). There is **no** `skip` field on backlog items — the schema forbids it.
5. Propose `target_layer` (`silver`|`gold`|`n/a`) and `target_path` under `databricks/silver/` or `databricks/gold/` using numeric prefixes (20–29 silver, 30–39 gold).
   - Every convertible item (`status` not `blocked`, layer not `n/a`) **must** have a **unique** `target_path`.
   - Paths must match `databricks/(silver|gold)/<file>.sql` — never `databricks/converted/`.
   - Do not collide with **existing** files under `databricks/silver/` or `databricks/gold/` unless intentionally overwriting that conversion.
   - Uniqueness enables parallel Convert fan-out (one worker per path).
6. Fill reads/writes/priority/risk_flags from the source SQL (T-SQL or MySQL). Use inventory `landing_name`s when listing bronze reads.
7. Do **not** invent procs or tables absent from inventory. Do **not** hardcode WWI names.

## Output JSON

```json
{
  "migration_backlog": [ /* agents/contracts/migration_backlog.schema.json items */ ],
  "assess_summary": "markdown findings"
}
```

Coordinator unwraps and runs:

```bash
python3 agents/tools/persist_backlog.py --run-id <run_id> --from-file <assess.json>
```
