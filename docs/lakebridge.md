# Lakebridge vs this repo

Lakebridge is Databricks’ migration toolkit (profile / analyze / transpile / reconcile). This repo is a **guided operating model** for Azure SQL → Unity Catalog: connect, discover, land, convert with agents, reconcile, **Gate**, and observe in Dashboard + Genie.

## Honest comparison

| Capability | Lakebridge | This repo |
|---|---|---|
| Dialect breadth | Many sources / ETL tools | Azure SQL (SQL Server) path, designed to stay simple |
| Profiler / TCO | Yes | No |
| Transpile engines | BladeBridge / Morpheus / Switch | LLM Convert with project style + Gate verification |
| Live value reconcile | Strong | Inventory row-count reconcile + optional fixtures |
| Ship/no-ship | Human judgment | Deterministic Gate + retry hooks |
| Observability | Reports | `ops.*` → Control Plane dashboard + Genie |
| Demo on Free Edition | Not the product focus | First-class guided demo |

## Punchline

For **Azure SQL EDW → Databricks UC**, this path is simpler: permissions in, agents discover and migrate, you watch the Control Plane. Lakebridge wins on heterogeneous estate breadth. We do **not** shell out to Lakebridge — we compete on the job-to-be-done and the operating model.
