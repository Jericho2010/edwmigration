# agents/

Portable prompts + contracts. Cursor and GitHub Copilot adapters are generated.

**Human onboarding:** [docs/getting-started.md](../docs/getting-started.md) · [docs/cursor-ui.md](../docs/cursor-ui.md) · [docs/agent-setup.md](../docs/agent-setup.md) · [docs/mlflow.md](../docs/mlflow.md) · [docs/enterprise.md](../docs/enterprise.md)

```bash
./agents/tools/sync_prompts.sh
```

## Stages

| Agent | Role |
|---|---|
| `edw-start` | Front door: `start` → soft status + phrase menu → route |
| `edw-demo-guide` | Guided demo; runs Track A preflight then bootstrap + migration |
| `edw-coordinator` | Track B: Azure SQL or MySQL → discover → parallel convert fan-out → gate |
| `edw-assess` | Readonly backlog JSON from inventory (empty OK if routines skipped); coordinator persists; unique `target_path`s |
| `edw-convert` | One T-SQL / MySQL routine → silver/gold SQL + `convert/<item_id>.json` |
| `edw-test` | Generated reconcile |
| `edw-gate` | Ship/no-ship |

## Tools

| Tool | Purpose |
|---|---|
| `repo_root.sh` | Resolve checkout root (Makefile + `.cursor` + `agents/tools`) |
| `start_status.sh` | Soft status for `edw-start` menu (no hard fails) |
| `preflight_track_a.sh` | Track A smoke: tools, auth, warehouse, SqlPackage/sqlcmd |
| `check_land_ready.sh` | Fail if bronze land SQL is missing/placeholder (`make run`) |
| `smoke_path_guards.sh` | CI/local path-coupling + merge smoke |
| `materialize_demo_env.sh` | Build `.env` from logins |
| `announce_observability.sh` | Paste-ready Control Plane + Genie + Catalog + Job + Notebooks + observe_url banner (`--stage`) |
| `track_a_provision.sh` | Track A materialize→bootstrap→setup with announce heartbeats |
| `render_sql.sh` | Catalog/federation render (`SOURCE_TYPE`) → `_rendered/` |
| `resolve_source_env.sh` | Map `SOURCE_*` / `AZ_SQL_*` |
| `print_observability_urls.sh` | Control Plane + Genie + Catalog + Job + Notebooks + MLflow `observe_url` |
| `publish_run_notebooks.py` | Import SQL as Workspace notebooks under `edwmigration_YYYYMMDD` |
| `databricks_cli_env.py` | Overlay CLI PAT from a profile whose host matches `DATABRICKS_HOST` |
| `apply_databricks_cli_auth.sh` | Source after `.env` to apply that overlay (used by `run_sql`, setup, teardown, print-urls) |
| `databricks_cli.sh` | `databricks` CLI wrapper with the same overlay (`make deploy` / `make run`) |
| `observe_status.sh` | Ops counts + URLs snapshot for stage checkpoints |
| `dual_write_agent_lifecycle.sh` | UC + MLflow start/stop when hooks cannot fire (fallback; Convert: `--item-id` per item) |
| `reset_databricks_sink.sh` | Wipe managed UC + views + `agents/out` (keeps Azure); `make reset-sink` |
| `teardown_databricks.sh` | Destroy job/dashboard/Genie/MLflow/catalog/connection/scope/notebooks; `make teardown-databricks` |
| `record_agent_event.sh` | Insert ops.agent_events row (+ MLflow stage enqueue + force flush) |
| `ensure_run_events.py` | `coordinator/started` + table-only `convert/skipped` (not assess); inits MLflow serve daemon |
| `mlflow_observe.py` | Soft MLflow init / serve daemon / span queue / end-run / experiment-purge |
| `mlflow_context.py` | `agents/out/<run_id>/mlflow_context.json` helpers |
| `resolve_python.sh` | Prefer `.venv/bin/python` for observe tools/hooks |
| `check_mlflow_observe.sh` | Health: venv + mlflow≥3.8 + DATABRICKS_HOST (`--strict` for preflight WARN) |
| `discover_inventory.py` | Base tables + procs/routines (`SOURCE_TYPE`) |
| `generate_from_inventory.py` | Land + reconcile SQL |
| `validate_artifact.py` | JSON Schema check against `agents/contracts/` |
| `validate_backlog_paths.py` | Unique silver/gold `target_path`s before Convert fan-out |
| `persist_backlog.py` | Assess → `migration_backlog.json` + `ops.migration_backlog` |
| `persist_reconcile_report.py` | Test → `reconcile_report.json` + `ops.reconcile_results` |
| `persist_manifest.py` | Gate → `migration_manifest.json` + `ops.migration_manifest_current` |
| `merge_convert_results.py` | Merge `convert/*.json` → backlog + `ops.proc_conversion_map` |
| `allocate_target_paths.py` | Next `NN` from 20 + slug from `legacy_proc` (no canned WWI stems) |
| `ensure_source_alias_views.sh` | SQL Server spaced-name views from `INFORMATION_SCHEMA` (one `sqlcmd` per view) |
| `validate_converted_sql.py` | Convert SQL must read bronze, not the federated catalog |
| `assert_watchable.py` | Fail closed: hook `subagentStart` required (not dual_write); Track A / `EDW_OBSERVE_STRICT` |
| `record_subagent_hook.sh` | Parent launch-time `subagentStart`/`Stop` (same JSONL as Cursor hooks) when the host omits the hook |
| `check_job_wiring.py` | DAG from Assess `reads`/`writes`; WARN + `--apply` (peak ≤ 5); restore via skeleton YAML |
| `run_sql.sh` | Statement Execution API |
| `sync_prompts.sh` | Cursor + Copilot |

Copilot copies: [`github-copilot/`](github-copilot/).
