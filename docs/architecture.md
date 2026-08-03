# Architecture

Deep dive for after your first successful run.  
Start with [What you get](what-you-get.md) if you want the plain-English version first.

---

## Engine vs demo pack

- **Engine:** `SOURCE_TYPE` (`sqlserver`|`mysql`) → Lakehouse Federation → discover base tables (+ procs/routines) → generate bronze land/reconcile → agent Convert → job → Gate → Dashboard/Genie.  
- **Demo pack** (`demo/wwi`, `infra/azure`, `legacy/*`): optional WideWorldImporters sample for [Track A](guided-demo.md). Gate never requires WWI object names.

```mermaid
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
```

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

PAT supported now. OAuth (`databricks auth login`) is the enterprise target state.

---

## Free Edition

Serverless warehouse only; Federation not Lakeflow Connect; job concurrency ≤5. Source must be reachable from Free Edition egress — [firewall.md](firewall.md), [limits.md](limits.md), [lakeflow_connect.md](lakeflow_connect.md).

---

## Related

- [Guided demo](guided-demo.md) · [Your database](your-database.md) · [Agents](../agents/README.md) · [Diagrams](img/README.md)
