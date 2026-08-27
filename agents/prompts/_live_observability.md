# Live observability contract (during the run)

Shared by `edw-demo-guide`, `edw-coordinator`, and stage agents. Observability is **live while migration runs**, not only after Gate. Provision banners are **automatic** via scripts — do not wait until Gate.

## Planes

| Plane | Updates live |
|---|---|
| **Cursor chat** | `announce_observability` / `observe_status` after each stage |
| **MLflow** | AGENT/TOOL spans from hooks + milestones (`observe_url` at mint) |
| **Control Plane** | `ops.*` widgets as inventory/events/backlog land |
| **Genie** | Same `ops.*` as rows appear |
| **Workspace notebooks** | `edwmigration_YYYYMMDD` gallery after Land (`publish_run_notebooks.py`) |
| **Catalog / Job** | Explorer + medallion job URLs in the same banner |

## Provision (before mint) — mandatory

**First action after menu 1 + catalog** (and before any long `make`):

```bash
./agents/tools/announce_observability.sh --stage Provision
```

Paste that output into chat immediately (*Keep these open during the run.*). Prefer the full Track A path:

```bash
./agents/tools/track_a_provision.sh
# or: make provision-track-a
```

That wrapper announces **Provision → Bootstrap → Setup**, runs materialize/bootstrap/setup, and prints `[edw]` heartbeats. **Paste each announce block** into the user-visible chat.

**Forbidden:** one opaque Cursor `Task` that owns materialize→bootstrap→setup with no intermediate paste. Mute Task handoffs look like “nothing is happening” and users interrupt. Run provision in the **parent/visible session**; use `edw-*` Tasks only from Assess onward (hooks).

Stages for announce / observe_status: `Provision`, `Bootstrap`, `Setup`, `PreMint`, `Mint`, `Discover`, `Land`, `Assess`, `Convert`, `Job`, `Test`, `Gate`, `Done`.

**URLs:** paste Control Plane + Genie + **Catalog** at **Provision** (best-effort if a prior deploy exists) and again at **Setup**; add `observe_url` at **Mint**; add **Notebooks** at **Land** (`publish_run_notebooks.py`); add **Job** after `make deploy`. Do not re-paste long URL essays every later stage — use:

```bash
./agents/tools/observe_status.sh --stage <Name>
```

Gate Hero (gate counters on `migration_manifest_current`) stays empty until Gate — expected. Inventory / Events / Backlog should move as stages complete. **Tables-landed** (`ops.load_control`) should move at Land. Latest-run widgets prefer `ops.agent_events` then the manifest, so mid-demo screens follow the live run rather than a prior Gate row.

## Subagent policy (mandatory)

| Stage | Cursor subagent | Writes files? |
|---|---|---|
| Assess | `edw-assess` | No (readonly) — JSON in reply; coordinator writes `assess_raw.json` |
| Convert | `edw-convert` (≤5 parallel) | Yes — `.sql` + `convert/<item_id>.json` |
| Test | `edw-test` | No (readonly) — JSON in reply; coordinator writes `reconcile_raw.json` |
| Gate | `edw-gate` | No (readonly) — JSON in reply; coordinator writes `manifest_raw.json` |

Parent/coordinator may own Discover, Land, job wiring, `make deploy`/`make run`, and **all Track A provision**.

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

`init` starts a **single-writer `serve` daemon** for this `run_id`. Hooks append span records to `agents/out/<run_id>/spans.buf.jsonl` (flock); only the daemon talks to MLflow. The daemon always `start_trace`s in its own process (InMemoryTraceManager is per-process). Do **not** pass `--force` to "fix" empty traces from a hook.

**Gate does not end MLflow.** `stage(gate, completed)` logs `gate_pass` and leaves the serve daemon running so retries stay on the same trace. Coordinator calls `end-run` at **Done**:

```bash
"$(./agents/tools/resolve_python.sh)" agents/tools/mlflow_observe.py end-run --run-id <run_id>
```

Paste `observe_url` **immediately** (part of the URL banner). Soft no-op if observe is not ready — still paste Control Plane + Genie + Catalog. Notebooks join at Land; Job after deploy.

Gate Hero stays empty until Gate — expected. Inventory / Events / Backlog should move as stages complete; tables-landed from `load_control` should move at Land.

## Dirty catalog (one chat choice)

Before mint, if ops look dirty (`reconcile_results` / `migration_backlog` non-zero) and this is not a resume: ask once to run `make reset-sink` (keeps Azure). Never auto-reset. After a demo, offer `make teardown-databricks` (job, dashboard, Genie, MLflow experiment, catalog, connection, secret scope — Azure SQL stays) or `make teardown` (Azure RG). Do not invent a migration outside `start` → menu **1/2/3**.
