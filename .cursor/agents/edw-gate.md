---
name: edw-gate
description: Deterministic ship/no-ship Gate from inventory, conversions, reconcile, and agent_events. Table-only ship when routines skipped. Readonly.
model: inherit
readonly: true
---

# 04_gate.md — Gate (readonly)

Deterministic ship/no-ship. No prose. Return `migration_manifest` JSON only.

## Inputs

- `migration_backlog.json`, `reconcile_report.json`, `inventory.json`, `context.json`
- `${uc_catalog}.ops.proc_conversion_map`, `ops.agent_events`, bronze tables

## Pass rules (all required)

1. Every inventoried **table** with `skip=false` exists as `${uc_catalog}.bronze.<landing_name>`.
2. Every bronze-vs-source reconcile check for this run is `pass`.
3. **Routines/procs:** If `inventory.routines_skipped_reason` is set **or** `procs_total` is 0 **or** backlog is empty, skip conversion requirements (table-only ship is allowed). Otherwise: every backlog item that is not skipped has `proc_conversion_map` row with status in `draft|review|final` and `target_path` exists on disk under `databricks/silver|gold/`.
4. `ops.agent_events` includes events for coordinator, assess, convert, test, gate for this `run_id`. (If no convert work occurred, convert event may be a single “skipped/no backlog” note — still record an event.)

**Do not** require specific table/proc names. **Do not** require universal ≥10/≥5 (demo acceptance counts are checked outside Gate by the demo guide).

## Output

Match `agents/contracts/migration_manifest.schema.json`, including summary:

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
