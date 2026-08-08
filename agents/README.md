# agents/

Portable prompts + contracts. Cursor and GitHub Copilot adapters are generated.

**Human onboarding:** [docs/getting-started.md](../docs/getting-started.md) · [docs/cursor-ui.md](../docs/cursor-ui.md) · [docs/agent-setup.md](../docs/agent-setup.md) · [docs/enterprise.md](../docs/enterprise.md)

```bash
./agents/tools/sync_prompts.sh
```

## Stages

| Agent | Role |
|---|---|
| `edw-start` | Front door: `start` → soft status + phrase menu → route |
| `edw-demo-guide` | Guided demo; runs Track A preflight then bootstrap + migration |
| `edw-coordinator` | Track B: Azure SQL or MySQL → discover → parallel convert fan-out → gate |
| `edw-assess` | Backlog from inventory (empty OK if routines skipped); unique `target_path`s |
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
| `render_sql.sh` | Catalog/federation render (`SOURCE_TYPE`) → `_rendered/` |
| `resolve_source_env.sh` | Map `SOURCE_*` / `AZ_SQL_*` |
| `print_observability_urls.sh` | Control Plane + Genie URLs |
| `record_agent_event.sh` | Insert ops.agent_events row |
| `ensure_run_events.py` | `coordinator/started` + table-only `convert/skipped` (not assess) |
| `discover_inventory.py` | Base tables + procs/routines (`SOURCE_TYPE`) |
| `generate_from_inventory.py` | Land + reconcile SQL |
| `validate_artifact.py` | JSON Schema check against `agents/contracts/` |
| `validate_backlog_paths.py` | Unique silver/gold `target_path`s before Convert fan-out |
| `persist_backlog.py` | Assess → `migration_backlog.json` + `ops.migration_backlog` |
| `persist_reconcile_report.py` | Test → `reconcile_report.json` |
| `persist_manifest.py` | Gate → `migration_manifest.json` + `ops.migration_manifest_current` |
| `merge_convert_results.py` | Merge `convert/*.json` → backlog + `ops.proc_conversion_map` |
| `check_job_wiring.py` | WARN if backlog paths missing from medallion job YAML |
| `run_sql.sh` | Statement Execution API |
| `sync_prompts.sh` | Cursor + Copilot |

Copilot copies: [`github-copilot/`](github-copilot/).
