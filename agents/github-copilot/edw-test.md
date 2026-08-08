# edw-test

Portable stage instructions (same body as agents/prompts/03_test.md).
Use in GitHub Copilot Chat / coding agent. Coordinator owns the run.

# 03_test.md — Test (readonly)

Prove bronze matches source_fed for every inventoried table (and any fixture checks present in ops).

## Inputs

- `agents/out/<run_id>/context.json` (`uc_catalog`)
- `agents/out/<run_id>/inventory.json`
- Generated reconcile at `databricks/_rendered/tests/reconcile.sql` (after `./agents/tools/render_sql.sh`)
- Sample shape: `agents/samples/run/reconcile_report.json`

## Process

1. Ensure render ran; execute reconcile:
   ```bash
   ./agents/tools/run_sql.sh --file databricks/_rendered/tests/reconcile.sql
   ```

2. Query results (replace catalog + run_id):
   ```bash
   ./agents/tools/run_sql.sh --sql "
   SELECT check_id, table_name, expected, actual, delta, result
   FROM \`<uc_catalog>\`.ops.reconcile_results
   WHERE run_id = '<run_id>'
   ORDER BY check_id
   "
   ```

3. Map each row to a `checks[]` entry:
   - `check_id` ← `check_id`
   - `table` ← `table_name`
   - `expected` / `actual` / `delta` / `result` as strings (`pass`|`fail`)

4. Include fixture / other checks already in `ops.reconcile_results` for this `run_id` (e.g. after job `stage_fixtures`) — do not drop them.

5. Build `summary`: `passed`, `failed`, `total` (total ≥ 1).

6. Return JSON matching `agents/contracts/reconcile_report.schema.json`. Coordinator persists with:
   ```bash
   python3 agents/tools/persist_reconcile_report.py --run-id <run_id> --from-file ...
   ```

## Triage (tell the coordinator)

| Pattern | Likely cause |
|---|---|
| Almost all `bronze_vs_source:*` fail | Federation down, cold Azure SQL AutoPause, or bronze land did not run |
| One landing fails | That table’s land/filter/slug mismatch — check `inventory.json` `landing_name` |
| Fixtures fail, bronze pass | Demo fixture expectations vs sample data — call out separately |

Do not write files yourself; return JSON for the coordinator.
