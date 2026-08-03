# Architecture

Deep dive for after your first successful run.  
Start with [What you get](what-you-get.md) for plain English; [Enterprise](enterprise.md) for SoD / prod.

---

## Engine vs demo pack

- **Engine:** `SOURCE_TYPE` (`sqlserver`|`mysql`) → Lakehouse Federation → discover base tables (+ procs/routines) → generate bronze land/reconcile → agent Convert → job → Gate → Dashboard/Genie.  
- **Demo pack** (`demo/wwi`, `infra/azure`, `legacy/*`): optional WideWorldImporters sample for [Track A](guided-demo.md). Gate never requires WWI object names.

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart LR
  subgraph engine [Engine]
    ST[SOURCE_TYPE] --> Fed[Federation]
    Fed --> Disc[Discover]
    Disc --> Land[Land bronze]
    Land --> Conv[Convert]
    Conv --> Gate[Gate]
  end
  subgraph demo [Demo pack optional]
    WWI[WWI bacpac]
  end
  WWI -.-> Fed
  Gate --> Obs[Dashboard + Genie]
  classDef agent fill:#1B7A6E,stroke:#145A51,color:#fff
  classDef azureC fill:#0078D4,stroke:#005A9E,color:#fff
  classDef bronze fill:#C47B2D,stroke:#8F5A1F,color:#fff
  classDef ops fill:#5B4B8A,stroke:#3F3460,color:#fff
  class ST,Fed,Disc,Conv agent
  class WWI azureC
  class Land bronze
  class Gate,Obs ops
```

Full colored system diagram: [`img/architecture.mmd`](img/architecture.mmd)

---

## Catalog model

User supplies `DATABRICKS_CATALOG`. Schemas: `source_fed`, `bronze`, `silver`, `gold`, `ops`.

Foreign catalog mirrors the source via `CONNECTION` `TYPE SQLSERVER` or `TYPE MYSQL`. Password secret: `source-password` (sqlserver also keeps `azure-sql-password` alias).

---

## Discovery

- Tables: `information_schema` on the foreign catalog, `BASE TABLE` only.  
- SQL Server procs: sqlcmd / `export_proc_source.sh`.  
- MySQL routines: `mysql` CLI when present; otherwise `routines_skipped_reason` and table-only Gate.  
- Landing names: `Dimension.X`→`dim_*`, `Fact.X`→`fact_*`, else `schema_table`.

---

## Observability

Hooks → `ops.agent_events`. Control Plane dashboard (`dataset_catalog` / `ops`). Genie with dynamic `table_identifiers`. Print links with `make print-urls`.

---

## Auth

PAT supported now for demos. OAuth (`databricks auth login`) + service principal for jobs is the **enterprise** target — [enterprise.md](enterprise.md).

---

## Free Edition

Serverless warehouse only; Federation not Lakeflow Connect; job concurrency ≤5. Source must be reachable from Free Edition egress — [firewall.md](firewall.md), [limits.md](limits.md), [lakeflow_connect.md](lakeflow_connect.md).

---

## Related

- [Guided demo](guided-demo.md) · [Your database](your-database.md) · [Enterprise](enterprise.md) · [Glossary](glossary.md) · [Agents](../agents/README.md) · [Diagrams](img/README.md)
