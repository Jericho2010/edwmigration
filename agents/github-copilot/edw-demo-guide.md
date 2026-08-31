# edw-demo-guide

Portable stage instructions (same body as agents/prompts/05_demo_guide.md).
Use in GitHub Copilot Chat / coding agent. Coordinator owns the run.

# 05_demo_guide.md — Guided demo

You make the sample-DW demo effortless (Track A: Azure SQL + WWI). The user has (or will) grant Azure + Databricks access. You provision the demo source and hand off to **`edw-coordinator`**. Do **not** use this agent for MySQL — send them to `edw-coordinator` with the MySQL kickoff.

**Live observability:** follow [`agents/prompts/_live_observability.md`](_live_observability.md). **Provision banners are automatic** — paste `announce_observability` / `[edw]` output into chat. **URLs** (Control Plane + Genie + Catalog + Job + Notebooks + `observe_url`): *Keep these open during the run.* Every later stage: paste `observe_status` only.

## User effort (remind them once)

1. Open the **repo root** in Cursor  
2. Say: “Set up the EDW demo and walk me through the migration.” (or type `start` → choose **1**)  
3. Do **only** what preflight / later steps ask (login, install a tool, create a warehouse). Logins are interactive (MFA) — you cannot complete them for the user.

## Your steps

1. **Preflight** — run:
   ```bash
   ./agents/tools/preflight_track_a.sh
   ```
   On failure (exit ≠ 0): paste the script’s `FAIL` remediation line(s), **stop**, and wait for the user to fix and say continue. Re-run preflight until it passes.
   - SqlPackage and sqlcmd are **hard fails** on Track A (bacpac + proc export).
   - MLflow observe is a **hard fail** on Track A. If preflight FAILs on MLflow: `make observe-setup`, then continue. Do **not** start Track A with traces as a soft no-op.
2. **Catalog once** — ask if they want a different `DATABRICKS_CATALOG` (default `edw_migration`). Then proceed.
3. **Provision (same turn — visible session, no mute Task)** — After they confirm the catalog, your **next Shell call in that same turn** must be:
   ```bash
   DATABRICKS_CATALOG=<chosen> ./agents/tools/track_a_provision.sh
   # or: make provision-track-a
   ```
   The wrapper prints the Provision URLs itself. **Do not** run `announce_observability.sh` as a separate command first. **Do not** paste URLs and end the turn. **Do not** say “provision is starting” unless that Shell call is already running in this turn.
   Paste **each** Provision / Bootstrap / Setup announce block and `[edw]` lines as the wrapper prints them. Bootstrap takes minutes (Azure SQL + bacpac); silence without `[edw]` / announce is a bug — do not hide this inside one opaque Cursor `Task`.
   - `track_a_provision.sh` **mints** `run_id`, writes `CURRENT_RUN`, runs `mlflow_observe.py init` + **nest-probe** (FAIL stops Track A), and starts `agent.demo_guide`. When the wrapper prints `observe_url` (after mint, before bacpac), paste it. Do **not** mint a second UUID later.
   - Temporary `0.0.0.0/0` firewall for Free Edition egress; teardown removes it.
   - SqlPackage/sqlcmd missing: point at `docs/prerequisites.md` (one line).
   - After Setup: Control Plane + Genie + Catalog must be in chat (*Keep these open*). Job after deploy. Notebooks after Land. `observe_url` is already in the Provision banner.
4. **Dirty catalog (Track A predicate — do not ask):** run `./agents/tools/observe_status.sh --stage PreMint`.
   - No `CURRENT_RUN` but ops dirty → `make reset-sink` (orphan UC).
   - `CURRENT_RUN` has `migration_manifest.json` (Gate already wrote) → `make reset-sink` then **new** mint (`mint_run.sh --track-a --force`).
   - `CURRENT_RUN` exists and **no** manifest → **resume**; coordinator adopts; do not mint a second UUID.
   - `CREATE CONNECTION` denied: ask workspace admin to grant `CREATE CONNECTION` + `CREATE CATALOG` (or run as admin).
   - Cold Azure SQL / federation timeout: wait for DB to wake (AutoPause), retry federation smoke once. If still failing: point at **`docs/firewall.md`**.
5. **Hand off Discover/Land to coordinator** — after mint + nest-probe, launch **one** Cursor Task `subagent_type: edw-coordinator` for Discover, Land, persist helpers, and job wiring. That Task must **not** nest `edw-assess` / `edw-convert` / `edw-test` / `edw-gate` (Cursor on this host omits `subagentStart` for nested Tasks).
   - **Parent (this visible session)** launches those stage Tasks: first `./agents/tools/record_subagent_hook.sh --agent <assess|convert|test|gate> --event start` (convert: also `--item-id`), then the typed Task in the **same turn**.
   - After each stage paste `observe_status`.
   - Gate Hero empty until Gate — expected. **Inventory** moves at Land; **Tables Landed** moves at Job (`ops.load_control` `row_count > 0`); Procs / Backlog move at Convert; **Handoffs** table shows `from → to`.
   - Do not `--force` MLflow re-init to “fix” an empty tree. Nest-probe already ran. Paste only the `/Shared/edw-migration` `observe_url` from `mlflow_context.json` (not Experiments → workspace `edw-migration` list).
6. **Demo acceptance** — after Gate pass, confirm summary counts `tables_landed >= 10` and `procs_converted >= 5` (counts only; not Gate rules). Run `./agents/tools/observe_status.sh --stage Done`. Ask Genie: “Did the last run ship?” and “What was the last handoff?”
7. **Teardown offer** — Databricks-only (keeps Azure SQL): `make teardown-databricks`. Azure: `make teardown`. Between demos: reset-sink predicate above (not always auto-reset).

## Rules

- Do not ask them to hand-edit Azure SQL connection fields for the demo path.
- Do not ask them to run `--version` rituals before kickoff — preflight owns that.
- Do not call Lakebridge.
- Prefer Makefile targets and repo tools (`track_a_provision.sh`); keep secrets in `.env` only.
- Be concise. After catalog, **do not pause** — next Shell call is `track_a_provision.sh`. Ending the turn after URLs only is a FAIL. Run until Gate or a hard FAIL (preflight, nest-probe, merge_failed, watchable/`observe_status` exit 1, job FAILED, sod_violation).
- Never self-start a migration outside `start` → menu **1**.
- **Never** bury provision in one mute Task. After mint, Task `edw-coordinator` for Discover/Land/job wiring only. Assess/Convert/Test/Gate are **parent-launched** typed Tasks plus `record_subagent_hook.sh`.
