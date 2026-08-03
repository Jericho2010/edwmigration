# Agent setup

How this repo’s Cursor (and Copilot) agents work — including **how to launch one** if you’ve never done that before.

← [Getting started](getting-started.md) · **[Using Cursor (pictures)](cursor-ui.md)** · Kickoffs also in [guided-demo](guided-demo.md) / [your-database](your-database.md)

---

## One-time checklist

1. Open the **repository root** in Cursor (folder with `README.md` + `.cursor/`).  
2. Confirm these agents exist:  
   `edw-demo-guide`, `edw-coordinator`, `edw-assess`, `edw-convert`, `edw-test`, `edw-gate`  
3. If missing or you edited prompts: `make sync-prompts`, then reload Cursor.  
4. Log in for your path ([getting-started](getting-started.md)), then paste a kickoff sentence below.

---

## How to launch an agent in Cursor

Prefer the illustrated guide: **[cursor-ui.md](cursor-ui.md)**.

Exact UI labels move between Cursor versions; the idea is stable:

1. Open **Chat** or **Agent** mode.  
2. Select / mention the agent by name (example: `edw-demo-guide`).  
3. Paste the kickoff sentence for your track.  
4. Allow tool / terminal use when prompted.  
5. When it pauses (counts, >200 tables, teardown), answer in plain language.

**You are not expected to run SqlPackage or write SQL by hand** on the guided path — the agent orchestrates that.

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart LR
  Open[Open repo root] --> Pick[Pick agent]
  Pick --> Paste[Paste kickoff]
  Paste --> Watch[Watch tools + URLs]
  classDef user fill:#0B3D5C,stroke:#082C43,color:#fff
  classDef agent fill:#1B7A6E,stroke:#145A51,color:#fff
  class Open,Paste user
  class Pick,Watch agent
```

---

## Kickoff sentences (copy / paste)

| Track | Agent | Say |
|---|---|---|
| **A — Guided demo** | `edw-demo-guide` | Set up the EDW demo and walk me through the migration. |
| **B — MySQL** | `edw-coordinator` | Migrate my Azure MySQL into catalog `<name>`. Host/user/db are in `.env` (or I’ll paste them). |
| **B — Azure SQL** | `edw-coordinator` | Start an EDW migration run against my Azure SQL. |

---

## Who does what

| You | Agent / Makefile |
|---|---|
| Open repo + pick agent | Load prompts / hooks |
| Logins | Verify auth; write / update `.env` |
| One kickoff sentence | Federation → discover → land → convert → job → Gate |
| Watch Control Plane + Genie | Print Dashboard + Genie URLs (`make print-urls`) |

---

## Agent roles (optional detail)

| Agent | Role |
|---|---|
| `edw-demo-guide` | Track A walkthrough (provision sample + checkpoints) |
| `edw-coordinator` | Full migration run owner |
| `edw-assess` | Backlog from inventory |
| `edw-convert` | One proc/routine → silver/gold SQL |
| `edw-test` | Reconcile report |
| `edw-gate` | Ship / no-ship manifest |

Regenerate Cursor + Copilot files anytime:

```bash
make sync-prompts
```

---

## GitHub Copilot

Same stage bodies: [`agents/github-copilot/`](../agents/github-copilot/)  
Workspace hints: [`.github/copilot-instructions.md`](../.github/copilot-instructions.md)

---

## Track logins (short)

- **Track A:** `az login` + Databricks auth  
- **Track B MySQL:** Databricks auth; optional `az` for firewall; optional `mysql` CLI for routines  
- **Track B Azure SQL:** Databricks auth + `SOURCE_*` in `.env`  

Full tool matrix: [prerequisites.md](prerequisites.md)
