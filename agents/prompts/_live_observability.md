# Live observability contract (during the run)

Shared by `edw-demo-guide`, `edw-coordinator`, and stage agents. Observability is **live while migration runs**, not only after Gate.

## Four planes

| Plane | Updates live |
|---|---|
| **Cursor chat** | `observe_status` after each stage |
| **MLflow** | AGENT/TOOL spans from hooks + milestones (`observe_url` at mint) |
| **Control Plane** | `ops.*` widgets as inventory/events/backlog land |
| **Genie** | Same `ops.*` as rows appear |

**URLs once:** at setup and/or mint, paste Control Plane + Genie + `observe_url` with: *Keep these open during the run.* Do not re-paste long URL essays every stage.

**Every stage:** paste only:

```bash
./agents/tools/observe_status.sh --stage <Name>
```

Stages: `PreMint`, `Mint`, `Discover`, `Land`, `Assess`, `Convert`, `Job`, `Test`, `Gate`, `Done`.

Gate Hero stays empty until Gate — expected. Inventory / Events / Backlog should move as stages complete.

## Subagent policy (mandatory)

| Stage | Cursor subagent | Writes files? |
|---|---|---|
| Assess | `edw-assess` | No (readonly) — JSON in reply; coordinator writes `assess_raw.json` |
| Convert | `edw-convert` (≤5 parallel) | Yes — notebook + `convert/<item_id>.json` |
| Test | `edw-test` | No (readonly) — JSON in reply; coordinator writes `reconcile_raw.json` |
| Gate | `edw-gate` | No (readonly) — JSON in reply; coordinator writes `manifest_raw.json` |

Parent/coordinator may own Discover, Land, job wiring, `make deploy`/`make run`.

**Forbidden:** opaque Task / `generalPurpose` for Assess/Convert/Test/Gate **unless** dual-write (Convert: **per item**):

```bash
./agents/tools/dual_write_agent_lifecycle.sh --run-id <id> --agent convert --phase start --item-id <item_id>
./agents/tools/dual_write_agent_lifecycle.sh --run-id <id> --agent convert --phase stop --item-id <item_id>
```

Prefer Task only with `subagent_type` in `{edw-assess,edw-convert,edw-test,edw-gate}` so hooks fire.

## MLflow mint

```bash
"$(./agents/tools/resolve_python.sh)" agents/tools/mlflow_observe.py init --run-id <run_id>
```

Paste `observe_url` **immediately** (part of the one-time URL banner). Soft no-op if observe is not ready — still paste Control Plane + Genie.

## Dirty catalog (one chat choice)

Before mint, if ops look dirty (`reconcile_results` / `migration_backlog` non-zero) and this is not a resume: ask once to run `make reset-sink` (keeps Azure). Never auto-reset. Do not invent a migration outside `start` → menu **1/2/3**.
