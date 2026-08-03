# Glossary

Short definitions for terms used in this repo. ← [Getting started](getting-started.md)

| Term | Plain meaning |
|---|---|
| **Unity Catalog (UC)** | Databricks governance layer: catalogs, schemas, tables, permissions. |
| **Catalog** | Top-level container you name (`DATABRICKS_CATALOG`) holding `bronze` / `silver` / `gold` / `ops`. |
| **Lakehouse Federation** | Live *read* of an external database (Azure SQL or MySQL) into Databricks without copying first. |
| **Foreign catalog** | UC catalog that mirrors the source DB via a Federation **connection**. |
| **Connection** | UC object with host/user/password (secret) for SQL Server or MySQL. |
| **Bronze / silver / gold** | Medallion layers: raw land → conformed → marts. |
| **`source_fed`** | Views in your catalog that point at federated source tables. |
| **`ops`** | Control tables: inventory, backlog, reconcile, Gate, agent events. |
| **Discover** | Auto-list base tables (+ procs/routines when tools allow). |
| **Land** | `CREATE OR REPLACE` bronze tables from the federated source. |
| **Convert** | Turn a stored procedure / routine into Spark SQL under `databricks/silver\|gold`. |
| **Reconcile / Test** | Compare bronze row counts to source; write pass/fail. |
| **Gate** | Deterministic ship / no-ship decision from inventory + reconcile + conversions. |
| **Control Plane** | AI/BI dashboard over `ops.*` for the migration run. |
| **Genie** | Natural-language room over ops (and later silver/gold) tables. |
| **Track A** | Guided demo with sample WideWorldImporters on free Azure SQL. |
| **Track B** | Your existing Azure SQL or Azure MySQL. |
| **Kickoff sentence** | The one line you paste to start `edw-demo-guide` or `edw-coordinator`. |
| **SoD** | Segregation of duties — split create / convert / approve / deploy. See [enterprise.md](enterprise.md). |
| **Service principal (SP)** | Non-human identity for jobs and CI (enterprise), instead of a person’s PAT. |
| **PAT** | Personal access token — fine for demos; not the enterprise prod pattern. |
| **SqlPackage** | Tool that imports `.bacpac` files — used in Track A bootstrap, not everyday Track B setup. |

## Next

→ [What you get](what-you-get.md) · [Enterprise](enterprise.md) · [Architecture](architecture.md)
