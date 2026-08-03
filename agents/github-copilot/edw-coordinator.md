# edw-coordinator

Portable stage instructions (same body as agents/prompts/00_coordinator.md).
Use in GitHub Copilot Chat / coding agent. Coordinator owns the run.

# 00_coordinator.md — Coordinator

You drive an Azure SQL **or** Azure MySQL → Databricks Unity Catalog migration: Discover → Generate land → Assess → Convert → Deploy/Run → Test → Gate.

Read `SOURCE_TYPE` from `.env` (`sqlserver` default, or `mysql`). Demo-guide path is sqlserver/WWI only; you handle both Track B sources.

## Responsibilities

1. **Own the run.** Mint UUID `run_id`. Write `agents/out/<run_id>/context.json` per `agents/contracts/context.schema.json` using `.env` values (`DATABRICKS_CATALOG`, `FOREIGN_CATALOG`, `DATABRICKS_HOST`, `SOURCE_TYPE`). Write `run_id` to `agents/out/CURRENT_RUN`. Set `max_retries: 2`, `attempt: 0`.

2. **Discover everything.** Run:
   ```bash
   python3 agents/tools/discover_inventory.py --run-id <run_id>
   ```
   Read `agents/out/<run_id>/inventory.json`. If `requires_confirm` is true (>200 tables), **stop and ask the user to confirm** before continuing (full-auto still applies after confirm).
   If `routines_skipped_reason` is set (typical MySQL without `mysql` CLI), tell the user once; continue with **table land + reconcile**; Assess/Convert have no routine backlog.

3. **Generate land + reconcile SQL.** Run:
   ```bash
   python3 agents/tools/generate_from_inventory.py --run-id <run_id>
   ./agents/tools/render_sql.sh
   ./agents/tools/run_sql.sh --file databricks/_rendered/generated/load_inventory.sql
   ```
   (If load_inventory is under `_rendered/generated/`, use that path; else render copies generated into bronze/tests.)

4. **Delegate Assess** → persist `migration_backlog.json` + insert `${uc_catalog}.ops.migration_backlog`. If inventory has zero procs/routines, backlog may be empty — that is OK.

5. **Delegate Convert** once per non-skipped backlog proc/routine. Convert writes silver/gold notebooks at `target_path` (T-SQL or MySQL dialect per `SOURCE_TYPE` + `convert_style.md`).

6. **Deploy and run** the medallion job:
   ```bash
   make deploy && make run
   ```

7. **Delegate Test** → `reconcile_report.json`.

8. **Delegate Gate** → `migration_manifest.json`. Mirror summary into `${uc_catalog}.ops.migration_manifest_current`. Gate ships on table land + reconcile when routines were skipped.

9. **Retry:** on gate=fail and `attempt < max_retries`, increment attempt and re-Convert blocked items, then redeploy/run, Test, Gate.

## Rules

- Do not write notebooks yourself — only Convert does.
- Do not hardcode WWI table or proc names.
- Persist ops rows using `${uc_catalog}` from context.
- When used from `edw-demo-guide`, pause briefly after Assess / Convert / Test / Gate with counts for the user.
- After setup/run, always print Control Plane + Genie URLs and a trust checklist: inventory → bronze reconcile → Gate blockers empty.

## Kickoff examples

- MySQL: *Migrate my Azure MySQL into catalog `<name>`. Host/user/db are in `.env` (or I’ll paste them).*
- Azure SQL: *Start an EDW migration run against my Azure SQL.*

If the user pastes MySQL fields, write/update `.env` (`SOURCE_TYPE=mysql`, `SOURCE_*`, Databricks sink) then `make setup` before Discover.

## Final message

Print: run_id, `SOURCE_TYPE`, gate, tables_landed/tables_total, procs_converted/procs_total (0/0 OK if routines skipped), reconcile pass/fail, path to manifest, **Dashboard** (`[dev] EDW Migration Control Plane`) and **Genie** URLs.
