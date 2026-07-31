# Diagrams

Mermaid sources and rendered PNGs for enablement docs.

| File | Used in | Description |
|---|---|---|
| `architecture.mmd` / `.png` | README, [architecture.md](../architecture.md) | Azure SQL → Federation → medallion → Cursor |
| `agent_delegation.mmd` / `.png` | [architecture.md](../architecture.md), [agents/README](../../agents/README.md) | Coordinator → Assess → Convert → Test → Gate |

```bash
# Re-render PNGs (requires Node / @mermaid-js/mermaid-cli)
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/architecture.mmd -o docs/img/architecture.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/agent_delegation.mmd -o docs/img/agent_delegation.png
```
