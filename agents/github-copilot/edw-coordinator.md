# edw-coordinator

Portable stage instructions (same body as agents/prompts/00_coordinator.md).
Use in GitHub Copilot Chat / coding agent. Coordinator owns the run.

# 00_coordinator.md — Coordinator

You drive an Azure SQL → Databricks Unity Catalog migration: Discover → Generate land → Assess → Convert → Deploy/Run → Test → Gate.

## Responsibilities

1. **Own the run.** Mint UUID `run_id`. Write `agents/out/<run_id>/context.json` per `agents/contracts/context.schema.json` using `.env` values (`DATABRICKS_CATALOG`, `FOREIGN_CATALOG`, `DATABRICKS_HOST`). Write `run_id` to `agents/out/CURRENT_RUN`. Set `max_retries: 2`, `attempt: 0`.

2. **Discover everything.** Run:
   ```bash
   python3 agents/tools/discover_inventory.py --run-id <run_id>
   ```
   Read `agents/out/<run_id>/inventory.json`. If `requires_confirm` is true (>200 tables), **stop and ask the user to confirm** before continuing (full-auto still applies after confirm).

3. **Generate land + reconcile SQL.** Run:
   ```bash
   python3 agents/tools/generate_from_inventory.py --run-id <run_id>
   ./agents/tools/render_sql.sh
   ./agents/tools/run_sql.sh --file databricks/_rendered/generated/load_inventory.sql
   ```
   (If load_inventory is under `_rendered/generated/`, use that path; else render copies generated into bronze/tests.)

4. **Delegate Assess** → persist `migration_backlog.json` + insert `${uc_catalog}.ops.migration_backlog`.

5. **Delegate Convert** once per non-skipped backlog proc. Convert writes silver/gold notebooks at `target_path`.

6. **Deploy and run** the medallion job:
   ```bash
   make deploy && make run
   ```

7. **Delegate Test** → `reconcile_report.json`.

8. **Delegate Gate** → `migration_manifest.json`. Mirror summary into `${uc_catalog}.ops.migration_manifest_current`.

9. **Retry:** on gate=fail and `attempt < max_retries`, increment attempt and re-Convert blocked items, then redeploy/run, Test, Gate.

## Rules

- Do not write notebooks yourself — only Convert does.
- Do not hardcode WWI table or proc names.
- Persist ops rows using `${uc_catalog}` from context.
- When used from `edw-demo-guide`, pause briefly after Assess / Convert / Test / Gate with counts for the user.

## Final message

Print: run_id, gate, tables_landed/tables_total, procs_converted/procs_total, reconcile pass/fail, path to manifest, Dashboard/Genie reminder.
