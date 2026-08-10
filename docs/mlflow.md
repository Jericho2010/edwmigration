# MLflow observability

MLflow is the **live execution trace** plane for a migration run. It does not replace the Control Plane dashboard or Genie: those answer *what shipped / why Gate failed* from Unity Catalog `ops.*` tables. MLflow answers *what the agents and tools are doing right now* while Convert (and the rest of the pipeline) runs.

← [Architecture](architecture.md) · [What you get](what-you-get.md) · [Using Cursor](cursor-ui.md) · [Troubleshooting](troubleshooting.md)

---

## Role

| Plane | Source of truth | Best for |
|---|---|---|
| **UC events** (`ops.agent_events`) | Hooks + `record_agent_event.sh` | Gate rule 4, Control Plane timeline, Genie Q&A |
| **MLflow traces** | Same lifecycle dual-written via `mlflow_observe.py` | Live parent/child span tree in Databricks Experiments |

MLflow is **additive and soft**: missing `.venv` / `mlflow`, tracking errors, or `EDW_MLFLOW_BACKEND=off` → no-op (exit 0). Migration continues; traces simply do not record.

Traces land in Databricks experiment **`/Shared/edw-migration`** (fallback name `edw-migration` if Shared create fails). Per-run state is `agents/out/<run_id>/mlflow_context.json` (experiment id, trace id, open spans, `observe_url`).

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart LR
  subgraph uc [UC plane]
    Ev[ops.agent_events] --> CP[Control Plane]
    Ev --> G[Genie]
  end
  subgraph ml [MLflow plane]
    Ctx[mlflow_context.json] --> Tr[Experiment traces]
    Tr --> URL[observe_url]
  end
  Life[Agent + tool lifecycle] --> Ev
  Life --> Ctx
  classDef ops fill:#5B4B8A,stroke:#3F3460,color:#fff
  classDef agent fill:#1B7A6E,stroke:#145A51,color:#fff
  class CP,G,URL ops
  class Life,Ev,Ctx,Tr agent
```

---

## How it is wired

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart TD
  Mint[Coordinator mints run_id] --> Init["mlflow_observe.py init"]
  Init --> Ctx[mlflow_context.json + observe_url]
  Init --> Root[Root span edw.run]
  CursorHooks[Cursor hooks · log_event.sh] --> Spans
  Record[record_agent_event.sh] --> Stage[Stage spans]
  Ensure[ensure_run_events.py] --> Init
  Spans[AGENT / TOOL spans] --> Tree[One shared trace tree]
  Stage --> Tree
  Root --> Tree
  Tree --> DBX[Databricks Experiments · observe_url]
  classDef agent fill:#1B7A6E,stroke:#145A51,color:#fff
  classDef ops fill:#5B4B8A,stroke:#3F3460,color:#fff
  classDef azureC fill:#0078D4,stroke:#005A9E,color:#fff
  class Mint,Init,Ensure,CursorHooks,Record agent
  class Ctx,Root,Spans,Stage,Tree ops
  class DBX azureC
```

### 1. Run mint (coordinator)

After `run_id` is created, the coordinator runs:

```bash
python3 agents/tools/mlflow_observe.py init --run-id <run_id>
```

It must paste `observe_url:` / `Observed by MLflow:` to the user **immediately** so they can open live traces while Convert continues. `ensure_run_events.py` re-inits idempotently (same URL if already enabled).

### 2. Cursor hooks (automatic)

With the **repository root** open in **Cursor** (not VS Code alone), [`.cursor/hooks.json`](../.cursor/hooks.json) fires [`.cursor/hooks/log_event.sh`](../.cursor/hooks/log_event.sh) on:

| Hook event | MLflow span | Notes |
|---|---|---|
| `subagentStart` / `subagentStop` | AGENT (`agent.<name>`) | Keyed `subagent:<id>`; status OK/ERROR on stop |
| `afterShellExecution` | TOOL (`tool.shell`) | Plus `shell_success` / `shell_failure` metrics |
| `afterMCPExecution` | TOOL (`tool.mcp`) | MCP tool name in attributes |
| `afterFileEdit` | TOOL (`tool.file_edit`) | Path/detail truncated |

Hooks resolve `run_id` via `CURRENT_RUN` / `_resolve_run_id.sh`, then dual-write to MLflow using shared `mlflow_context.json` so separate hook processes attach to **one** tree (`parent_id` via open spans). Tool spans prefer an open subagent span as parent when present.

### 3. Milestone dual-write

`record_agent_event.sh` inserts into `ops.agent_events` **and** calls `mlflow_observe.py stage` for stage/chain spans (Discover → Assess → Convert → Test → Gate milestones).

### 4. Subagents

Every Cursor subagent is observed the same way — hooks map the payload to an agent name and open/close AGENT spans:

| Subagent | Typical role on the tree |
|---|---|
| `edw-start` | Front door / menu (short-lived) |
| `edw-demo-guide` | Track A orchestration |
| `edw-coordinator` | Discover → land → fan-out → Test → Gate |
| `edw-assess` | Readonly backlog (when routines in scope) |
| `edw-convert` | Parallel Convert workers (fan-out waves) |
| `edw-test` | Reconcile report |
| `edw-gate` | Ship / no-ship manifest |

Convert fan-out appears as **parallel child AGENT spans** under the run root. Shared memory between agents remains disk artifacts under `agents/out/<run_id>/`; MLflow only observes lifecycle, it does not pass chat context.

### 5. Announce URLs

`make print-urls` / `print_observability_urls.sh` prints Control Plane + Genie + MLflow `observe_url` when context exists. Setup-time print-urls often lack `observe_url` until the coordinator mints a run.

---

## Setup and health

| Step | Command |
|---|---|
| One-time deps | `make observe-setup` (repo `.venv` + `mlflow>=3.8`) |
| Health | `./agents/tools/check_mlflow_observe.sh` (also from soft status / Track A preflight) |
| Auth | Same Databricks session as the CLI (`DATABRICKS_HOST` + profile/PAT) |

Soft status / preflight **WARN** if observe is not ready; they do **not** block the menu or migration. See [prerequisites.md](prerequisites.md) and [troubleshooting.md](troubleshooting.md).

---

## Operator checklist

1. Open the **repo root** in Cursor so hooks load ([cursor-ui.md](cursor-ui.md)).  
2. Run `make observe-setup` once per machine.  
3. Start a run (`start` → Track A/B); when `observe_url` appears, open it while Convert runs.  
4. Use Control Plane / Genie for ship/fail narrative; use MLflow for the live agent/tool hierarchy.

---

## Key files

| Path | Role |
|---|---|
| `agents/tools/mlflow_observe.py` | init / span-start / span-end / stage / metric / end-run / trace-url |
| `agents/tools/mlflow_context.py` | Locked read/write of `mlflow_context.json` |
| `.cursor/hooks.json` + `.cursor/hooks/log_event.sh` | Cursor lifecycle → UC buffer + MLflow spans |
| `agents/tools/record_agent_event.sh` | UC row + MLflow stage span |
| `agents/tools/ensure_run_events.py` | Milestone rows + idempotent MLflow init |
| `agents/tools/check_mlflow_observe.sh` | venv + `mlflow≥3.8` + host readiness |
| `agents/tools/print_observability_urls.sh` | Control Plane + Genie + `observe_url` |

---

## Related

- [Architecture — Observability](architecture.md#observability) · [What you get](what-you-get.md#control-plane--genie--mlflow) · [Agents README](../agents/README.md) · [Glossary](glossary.md)
