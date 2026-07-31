# Diagrams

Mermaid sources for the architecture and agent delegation graphs.

```bash
# Optional: render PNGs (requires Node / @mermaid-js/mermaid-cli)
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/architecture.mmd -o docs/img/architecture.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/agent_delegation.mmd -o docs/img/agent_delegation.png
```

| File | Description |
|---|---|
| `architecture.mmd` | Azure SQL → Federation → medallion → Cursor |
| `agent_delegation.mmd` | Coordinator → Assess → Convert → Test → Gate |
