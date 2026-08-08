# What you get

Plain-English picture of the outcome — before you run anything.

← [Getting started](getting-started.md) · [Glossary](glossary.md) · Next: [Guided demo](guided-demo.md)

---

## One catalog, five schemas

You choose a name (`DATABRICKS_CATALOG`, for example `edw_migration`). Inside it:

| Schema | Role |
|---|---|
| `source_fed` | Stable views over the live federated source |
| `bronze` | 1:1 landed base tables (+ audit columns) |
| `silver` / `gold` | Converted procedure logic (when routines/procs were converted) |
| `ops` | Inventory, backlog, reconcile, Gate summary, agent events |

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart TB
  subgraph Source["Your source DB"]
    T[Base tables]
    P[Procs / routines]
  end
  subgraph UC["Unity Catalog: your catalog"]
    SF[source_fed]
    BR[bronze]
    SV[silver]
    GD[gold]
    OPS[ops]
  end
  T -->|Federation + land| SF --> BR
  P -->|Convert when available| SV --> GD
  BR --> OPS
  GD --> OPS
  classDef azureC fill:#0078D4,stroke:#005A9E,color:#fff
  classDef bronze fill:#C47B2D,stroke:#8F5A1F,color:#fff
  classDef silver fill:#6B7C8F,stroke:#4A5663,color:#fff
  classDef gold fill:#B8860B,stroke:#8A6508,color:#fff
  classDef ops fill:#5B4B8A,stroke:#3F3460,color:#fff
  classDef muted fill:#E8F1F8,stroke:#5B7A8C,color:#0B3D5C
  class T,P azureC
  class SF muted
  class BR bronze
  class SV silver
  class GD gold
  class OPS ops
```

**Landed objects are base tables only** (not views). Discovery finds everything visible after connect — you do not paste a table list.

---

## The migration sequence

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart LR
  D[Discover] --> L[Land bronze]
  L --> C[Convert]
  C --> J[Job run]
  J --> T[Test]
  T --> G[Gate]
  G --> O[Dashboard + Genie]
  classDef work fill:#C47B2D,stroke:#8F5A1F,color:#fff
  classDef agent fill:#1B7A6E,stroke:#145A51,color:#fff
  classDef ops fill:#5B4B8A,stroke:#3F3460,color:#fff
  class D,L,J work
  class C,T agent
  class G,O ops
```

| Stage | What it means |
|---|---|
| **Discover** | List base tables (+ export procs/routines if tools allow) |
| **Land** | Copy each table into `bronze.*` and record counts |
| **Convert** | Turn T-SQL / MySQL routines into Spark SQL notebooks in **parallel waves (≤5)** via `edw-convert` *(skipped cleanly if none)* |
| **Test** | Bronze row counts vs source |
| **Gate** | Ship / no-ship from inventory + reconcile + conversions |
| **Observe** | Control Plane dashboard + Genie Q&A |

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart TB
  Start[edw-start]
  Guide[edw-demo-guide]
  Coord[edw-coordinator]
  Start --> Guide
  Start --> Coord
  Guide --> Coord
  Coord --> Assess[edw-assess]
  Coord --> C1[edw-convert]
  Coord --> C2[edw-convert]
  Coord --> Test[edw-test]
  Coord --> Gate[edw-gate]
  classDef agent fill:#1B7A6E,stroke:#145A51,color:#fff
  classDef readonly fill:#6B7C8F,stroke:#4A5663,color:#fff
  class Start,Guide,Coord,C1,C2 agent
  class Assess,Test,Gate readonly
```

Also: [`img/agent_squad_roles.png`](img/agent_squad_roles.png) (README roles) · [`img/agent_delegation.mmd`](img/agent_delegation.mmd) · [`img/architecture.mmd`](img/architecture.mmd)

---

## What you will see while it works

You are not expected to stare at terminals the whole time. Typical pauses:

1. **Inventory** — table (and proc) counts after Discover  
2. **Convert wave** — up to five `edw-convert` agents writing notebooks in parallel  
3. **Merge** — `convert_summary.json` with converted / blocked counts  
4. **Job → Test → Gate** — medallion run, bronze reconcile, ship / no-ship  
5. **URLs** — Control Plane + Genie (`make print-urls`)

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
sequenceDiagram
  participant You
  participant Coord as edw-coordinator
  participant Wave as Convert_wave_max_5
  participant DBX as Databricks
  You->>Coord: Kickoff
  Coord->>DBX: Discover and land bronze
  Coord->>Wave: Fan-out edw-convert
  Wave-->>Coord: convert result JSON files
  Coord->>DBX: Job then Test then Gate
  Coord-->>You: Dashboard and Genie URLs
```

---

## Run artifacts map

Everything for one run lives under `agents/out/<run_id>/` (also pointed at by `agents/out/CURRENT_RUN`):

| Artifact | Meaning |
|---|---|
| `context.json` | Catalogs, host, retries, `SOURCE_TYPE` |
| `inventory.json` | Discovered tables + procs/routines |
| `migration_backlog.json` | Assess output (empty OK if routines skipped) |
| `assess_summary.md` | Optional Assess narrative (if persisted) |
| `convert/<item_id>.json` | One Convert worker result (fan-out handoff) |
| `convert_summary.json` | Merged converted / blocked counts |
| `merge_failed.json` | Present only if ops merge failed (fix before continuing) |
| `reconcile_report.json` | Test pass/fail checks |
| `migration_manifest.json` | Gate ship / no-ship + blockers |

---

## Control Plane + Genie

After setup: `make print-urls`

- **Control Plane** — Gate, timeline, backlog, reconcile  
- **Genie** — *Did the last run ship?* / *Why did the gate fail?*  

Trust checklist: inventory → convert artifacts (when procs in scope) → bronze reconcile pass → Gate blockers empty.

---

## Track A vs Track B (same destination)

| | Track A — Guided demo | Track B — Your DB |
|---|---|---|
| Source | Sample WideWorldImporters on free Azure SQL | Your Azure SQL or Azure MySQL |
| Entry | `start` → **1** (or `edw-demo-guide`) | `start` → **2** / **3** (or `edw-coordinator`) |
| Agent | `edw-demo-guide` → coordinator | `edw-coordinator` |
| Cost (typical) | $0 with Free Edition + teardown | Your existing DB + Free Edition sink |
| Outcome | Same catalog shape + dashboard + Genie | Same |

Production-shaped controls: **[Enterprise](enterprise.md)**.

---

## Next

→ **[Guided demo](guided-demo.md)** · **[Your database](your-database.md)** · **[Enterprise](enterprise.md)** · **[Architecture](architecture.md)**
