# Agent setup

How this repo’s Cursor (and Copilot) agents work — including **how to launch one** if you’ve never done that before.

← [Getting started](getting-started.md) · **[Using Cursor (pictures)](cursor-ui.md)** · Kickoffs also in [guided-demo](guided-demo.md) / [your-database](your-database.md)

---

## One-time checklist

1. Open the **repository root** in Cursor (folder with `README.md` + `.cursor/`).  
2. Confirm these agents exist:  
   `edw-start`, `edw-demo-guide`, `edw-coordinator`, `edw-assess`, `edw-convert`, `edw-test`, `edw-gate`  
3. If missing or you edited prompts: `make sync-prompts`, then reload Cursor.  
4. Type **`start`** (or launch **`edw-start`**) for status + phrase menu — or paste a kickoff below.

---

## How to launch an agent in Cursor

Prefer the illustrated guide: **[cursor-ui.md](cursor-ui.md)**.

Exact UI labels move between Cursor versions; the idea is stable:

1. Open **Chat** or **Agent** mode.  
2. Type **`start`**, or select **`edw-start`** / a specialized agent.  
3. From the menu, reply with a number — or paste a kickoff for your track.  
4. Allow tool / terminal use when prompted.  
5. When it pauses (preflight remediation, counts, >200 tables, teardown), answer in plain language — then say **continue**.

**You are not expected to run SqlPackage or write SQL by hand** on the guided path — the agent orchestrates that. Soft status is `./agents/tools/start_status.sh`; Track A tool/auth smoke is `./agents/tools/preflight_track_a.sh` (after menu **1**).

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart LR
  Open[Open repo root] --> Start[Type start]
  Start --> Menu[Status + menu]
  Menu --> Choose[Pick 1-6]
  Choose --> Work[Guide or coordinator]
  classDef user fill:#0B3D5C,stroke:#082C43,color:#fff
  classDef agent fill:#1B7A6E,stroke:#145A51,color:#fff
  class Open,Choose user
  class Start,Menu,Work agent
```

---

## Front door + kickoff sentences

| Path | Agent | Say |
|---|---|---|
| **Menu** | `edw-start` | `start` |
| **A — Guided demo** | `edw-demo-guide` | Set up the EDW demo and walk me through the migration. |
| **B — MySQL** | `edw-coordinator` | Migrate my Azure MySQL into catalog `<name>`. Host/user/db are in `.env` (or I’ll paste them). |
| **B — Azure SQL** | `edw-coordinator` | Start an EDW migration run against my Azure SQL. |

---

## Who does what

| You | Agent / Makefile |
|---|---|
| Open repo + type `start` | Soft status + phrase menu |
| Pick 1–6 (or paste kickoff) | Preflight (Track A on 1) → write `.env` → migrate |
| Fix only what preflight/auth asks | Continue after you say continue |
| Watch Control Plane + Genie | Federation → discover → land → **Convert fan-out** → job → Gate; print URLs |

Shared memory across Convert workers is **disk only** under `agents/out/<run_id>/` (see [What you get — run artifacts](what-you-get.md#run-artifacts-map)).

---

## Agent roles (optional detail)

| Agent | Role |
|---|---|
| `edw-start` | Front door: soft status + phrase menu; routes to the agents below |
| `edw-demo-guide` | Track A walkthrough; runs `preflight_track_a.sh` then provision + checkpoints |
| `edw-coordinator` | Full migration run owner; validate → parallel Convert waves (≤5) → merge |
| `edw-assess` | Backlog from inventory (unique silver/gold `target_path`s) |
| `edw-convert` | One proc/routine → silver/gold SQL + `convert/<item_id>.json` |
| `edw-test` | Reconcile report |
| `edw-gate` | Ship / no-ship manifest |

Convert protocol: `validate_backlog_paths.py` → launch up to **5** `edw-convert` agents per wave → `merge_convert_results.py`. Persist helpers: `persist_backlog.py` / `persist_reconcile_report.py` / `persist_manifest.py`. Job wiring: `check_job_wiring.py` (WARN). What you will see: [during the run](what-you-get.md#what-you-will-see-while-it-works).

Regenerate Cursor + Copilot files anytime:

```bash
make sync-prompts
```

---

## GitHub Copilot

Same stage bodies: [`agents/github-copilot/`](../agents/github-copilot/)  
Workspace hints: [`.github/copilot-instructions.md`](../.github/copilot-instructions.md)

**Terminal?** Cursor CLI (`agent`) and Copilot CLI (`copilot`) — setup + what’s different: **[cli-setup.md](cli-setup.md)**.

---

## Track logins (when asked)

- **Track A:** preflight asks for `az login` + Databricks auth if needed  
- **Track B MySQL:** Databricks auth; optional `az` for firewall; optional `mysql` CLI for routines  
- **Track B Azure SQL:** Databricks auth + `SOURCE_*` in `.env`  

Full tool matrix (reference): [prerequisites.md](prerequisites.md)
