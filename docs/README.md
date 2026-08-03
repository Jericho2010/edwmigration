# Documentation

Start here: [runbook.md](runbook.md) (guided demo) or the root [README](../README.md).

## Operator docs

| Doc | Purpose |
|---|---|
| [prerequisites.md](prerequisites.md) | Tools, privileges, Azure + Databricks logins |
| [runbook.md](runbook.md) | Guided demo + self-serve Azure SQL path |
| [troubleshooting.md](troubleshooting.md) | Common failures and fixes |

## Design docs

| Doc | Purpose |
|---|---|
| [architecture.md](architecture.md) | Engine vs demo pack, discovery, observability |
| [limits.md](limits.md) | Free Edition + Azure free SQL + engine scope |
| [firewall.md](firewall.md) | Why `0.0.0.0/0` on the demo SQL server |
| [lakeflow_connect.md](lakeflow_connect.md) | Why Federation on Free Edition |
| [lakebridge.md](lakebridge.md) | Compete on Azure SQL → UC (do not compose) |

## Field enablement

| Doc | Purpose |
|---|---|
| [demo-script.md](demo-script.md) | SE talk track (15 / 30 / 45 min) |
| [img/](img/) | Architecture diagrams + GIF notes |
| [media/](media/) | Asciinema re-record script (Azure-backed) |

## Code-adjacent READMEs

| Path | Purpose |
|---|---|
| [../agents/README.md](../agents/README.md) | Prompts, tools, Copilot adapter |
| [../databricks/README.md](../databricks/README.md) | Medallion + DAB + Control Plane |
| [../demo/wwi/README.md](../demo/wwi/README.md) | Sample DW demo pack |
| [../infra/azure/README.md](../infra/azure/README.md) | Free Azure SQL bootstrap |
| [../legacy/README.md](../legacy/README.md) | Bacpac, procs, fixtures |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | How to extend engine vs demo pack |
