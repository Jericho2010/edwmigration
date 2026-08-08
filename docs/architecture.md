# Architecture

Deep dive for after your first successful run.  
Start with [What you get](what-you-get.md) for plain English; [Enterprise](enterprise.md) for SoD / prod.

---

## Engine vs demo pack

- **Engine:** `SOURCE_TYPE` (`sqlserver`|`mysql`) → Lakehouse Federation → discover base tables (+ procs/routines) → generate bronze land/reconcile → **parallel Convert fan-out** → job → Test → Gate → Dashboard/Genie.  
- **Demo pack** (`demo/wwi`, `infra/azure`, `legacy/*`): optional WideWorldImporters sample for [Track A](guided-demo.md). Gate never requires WWI object names.

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart LR
  subgraph engine [Engine]
    ST[SOURCE_TYPE] --> Fed[Federation]
    Fed --> Disc[Discover]
    Disc --> Land[Land bronze]
    Land --> Conv[Convert fan-out]
    Conv --> Job[Job run]
    Job --> Test[Test]
    Test --> Gate[Gate]
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
  class ST,Fed,Disc,Conv,Test agent
  class WWI azureC
  class Land,Job bronze
  class Gate,Obs ops
```

**Convert fan-out:** after Assess, `validate_backlog_paths.py` → waves of ≤5 `edw-convert` agents → `merge_convert_results.py` → then deploy/run. Shared memory is disk artifacts under `agents/out/<run_id>/` (orchestrator-worker; land-first Federation — convert reads bronze Delta). See [artifacts map](what-you-get.md#run-artifacts-map).

**Convert vs job tasks:** Gate checks notebooks on disk + `ops.proc_conversion_map`. The medallion DAB job runs the **checked-in** silver/gold task set in `databricks/jobs/edw_migration_medallion.yml` — new convert paths are not auto-wired into job tasks until that YAML is extended. See [limits.md](limits.md).

Full colored system diagram: [`img/architecture.mmd`](img/architecture.mmd) · Delegation: [`img/agent_delegation.mmd`](img/agent_delegation.mmd)

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
