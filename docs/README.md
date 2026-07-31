# Documentation index

Enablement docs for the EDW → Databricks AI-assisted migration demo.

## Start here

| If you are… | Read this |
|---|---|
| Running the demo for the first time | [prerequisites.md](prerequisites.md) → [runbook.md](runbook.md) |
| Presenting as a Databricks SE | [demo-script.md](demo-script.md) |
| Explaining the design | [architecture.md](architecture.md) |
| Stuck on an error | [troubleshooting.md](troubleshooting.md) |

## Operator docs

| Doc | Contents |
|---|---|
| [prerequisites.md](prerequisites.md) | Tool install, versions, verify checklist |
| [runbook.md](runbook.md) | Configure → Azure → Federation → bundle → agents → teardown |
| [troubleshooting.md](troubleshooting.md) | Cold DB, firewall, bundle, hooks, gate failures |

## Design docs

| Doc | Contents |
|---|---|
| [architecture.md](architecture.md) | Catalogs, medallion contracts, agent write model, hooks |
| [limits.md](limits.md) | Free Edition + Azure SQL free offer constraints |
| [firewall.md](firewall.md) | `0.0.0.0/0` demo rule risk and teardown |
| [lakeflow_connect.md](lakeflow_connect.md) | Why Lakehouse Federation on Free Edition |

## Field enablement

| Doc | Contents |
|---|---|
| [demo-script.md](demo-script.md) | Timed talk tracks + screen cues + prospect takeaways |
| [img/](img/) | Architecture and agent-delegation diagrams (Mermaid + PNG) |

## Code-adjacent READMEs

| Path | Contents |
|---|---|
| [../agents/README.md](../agents/README.md) | Prompts, contracts, subagent roles |
| [../agents/samples/README.md](../agents/samples/README.md) | Offline Gate sample artifacts |
| [../databricks/README.md](../databricks/README.md) | Medallion + DAB deploy |
| [../databricks/uc/README.md](../databricks/uc/README.md) | Federation SQL order |
| [../.cursor/README.md](../.cursor/README.md) | Cursor hooks wiring |
| [../infra/azure/README.md](../infra/azure/README.md) | Azure bootstrap |
| [../legacy/README.md](../legacy/README.md) | Bacpac, procs, fixtures |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Extending the demo |
