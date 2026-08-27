# edw-assess

Portable stage instructions (same body as agents/prompts/01_assess.md).
Use in GitHub Copilot Chat / coding agent. Coordinator owns the run.

# 01_assess.md — Assess (readonly)

You are launched as Cursor subagent **`edw-assess`** so hooks dual-write live `ops.agent_events` + MLflow AGENT spans. Do not suppress lifecycle.

You are **readonly**: return JSON only in your reply. Do **not** write `assess_raw.json` or any other files — the coordinator writes the raw file and runs `persist_backlog.py`.

Inventory the connected source (Azure SQL or MySQL) and produce a migration backlog.

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
5. Propose `target_layer` (`silver`|`gold`|`n/a`). Leave `target_path` empty or as a layer-only hint; the coordinator runs `allocate_target_paths.py` to assign unique `databricks/(silver|gold)/<NN>_<slug>.sql` paths (NN starts at 20).
   - Do **not** invent gold marts or tables that are not in inventory/procs.
   - Every convertible item (`status` not `blocked`, layer not `n/a`) will get a **unique** `target_path` after allocate.
   - Paths must match `databricks/(silver|gold)/<file>.sql` — never `databricks/converted/`.
   - Uniqueness enables parallel Convert fan-out (one worker per path).
6. Fill reads/writes/priority/risk_flags from the source SQL (T-SQL or MySQL). Use inventory `landing_name`s when listing bronze reads.
7. Do **not** invent procs or tables absent from inventory. Do **not** hardcode demo warehouse names.

## Output JSON

```json
{
  "migration_backlog": [ /* agents/contracts/migration_backlog.schema.json items */ ],
  "assess_summary": "markdown findings"
}
```

Coordinator unwraps the JSON from your reply, writes `agents/out/<run_id>/assess_raw.json`, and runs:

```bash
python3 agents/tools/persist_backlog.py --run-id <run_id> --from-file agents/out/<run_id>/assess_raw.json
```
