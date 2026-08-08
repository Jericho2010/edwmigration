---
name: edw-gate
description: Deterministic ship/no-ship from inventory, conversions, reconcile, agent_events; proof SQL; table-only when routines skipped. Readonly.
model: inherit
readonly: true
---

# 04_gate.md — Gate (readonly)

Deterministic ship/no-ship. No prose. Return `migration_manifest` JSON only.

## Inputs

- `agents/out/<run_id>/migration_backlog.json`, `reconcile_report.json`, `inventory.json`, `context.json`
- `${uc_catalog}.ops.proc_conversion_map`, `ops.agent_events`, bronze tables
- Sample: `agents/samples/run/migration_manifest.json`
- `attempt` from `context.json` (default 0)

## Proof queries (via `run_sql.sh --sql`)

Bronze exists for a landing (repeat / use information_schema):

```sql
SELECT table_name FROM `<uc_catalog>`.information_schema.tables
WHERE table_schema = 'bronze' AND table_name = '<landing_name>';
```

Conversion map:

```sql
SELECT legacy_proc, target_path, status
FROM `<uc_catalog>`.ops.proc_conversion_map;
```

Agent events for this run:

```sql
SELECT agent, event, detail, ts
FROM `<uc_catalog>`.ops.agent_events
WHERE run_id = '<run_id>'
ORDER BY ts;
```

Also verify each non-blocked backlog `target_path` exists on disk under the repo.

## Pass rules (all required)

1. Every inventoried **table** with `skip=false` exists as `${uc_catalog}.bronze.<landing_name>`.
2. Every bronze-vs-source reconcile check for this run is `pass` (from `reconcile_report.json` / ops).
3. **Routines/procs:** If `inventory.routines_skipped_reason` is set **or** `procs_total` is 0 **or** backlog is empty, skip conversion requirements (table-only ship is allowed). Otherwise: every backlog item with `status != "blocked"` and `target_layer != "n/a"` has a `proc_conversion_map` row with status in `draft|review|final` and `target_path` exists on disk under `databricks/silver|gold/`.
4. `ops.agent_events` includes events for this `run_id` covering coordinator, assess, convert, test, gate. For table-only runs, `convert` with `event=skipped` (from `ensure_run_events.py`) satisfies the convert requirement; `assess/completed` comes from the coordinator after `persist_backlog.py`.

**Do not** require specific table/proc names. **Do not** require universal ≥10/≥5 (demo acceptance counts are checked outside Gate by the demo guide).

## Blocker id conventions

| id prefix | When |
|---|---|
| `bronze_missing:<landing>` | Table not in bronze |
| `reconcile_fail:<check_id>` | Reconcile result fail |
| `convert_missing:<item_id>` | No map row / file for convertible item |
| `convert_blocked:<item_id>` | Still blocked after retries (optional detail) |
| `events_missing:<agent>` | Required agent event absent |

## Output

Match `agents/contracts/migration_manifest.schema.json`, including `attempt` and summary:

```json
{
  "tables_total": N,
  "tables_landed": N,
  "procs_total": N,
  "procs_converted": N,
  "reconcile_passed": N,
  "reconcile_failed": N,
  "agent_events_recorded": N
}
```

`gate` is `pass` iff `blockers` is empty.

Coordinator persists with:

```bash
python3 agents/tools/persist_manifest.py --run-id <run_id> --from-file ...
```
