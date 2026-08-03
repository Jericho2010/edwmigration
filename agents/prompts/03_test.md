# 03_test.md — Test (readonly)

Prove bronze matches source_fed for every inventoried table (and any fixture checks).

## Inputs

- `agents/out/<run_id>/context.json` (`uc_catalog`)
- `agents/out/<run_id>/inventory.json`
- Generated reconcile at `databricks/_rendered/tests/reconcile.sql` (or `databricks/generated/reconcile.sql` after render)

## Process

1. Ensure render ran; execute:
   ```bash
   ./agents/tools/run_sql.sh --file databricks/_rendered/tests/reconcile.sql
   ```
2. Query `${uc_catalog}.ops.reconcile_results` for this `run_id`.
3. Return `reconcile_report.json` per `agents/contracts/reconcile_report.schema.json` with every check pass/fail.

Do not write files; return JSON for the coordinator.
