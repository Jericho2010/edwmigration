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

## Demo recordings (GIF)

Live terminal scenes embedded in the [root README](../../README.md#watch-it-run)
"Watch it run" section. Sources (asciinema casts) and the re-record script
live in [docs/media/](../media/README.md).

| File | Scene |
|---|---|
| `demo_seed.gif` | Offline seed → `source_fed` (no Azure) |
| `demo_job.gif` | Medallion job run via bundle |
| `demo_fault.gif` | Fault injection → gate blocks → Genie explains → revert → green |
| `demo_genie.gif` | Natural-language questions over gold marts |
| `demo_manifest.gif` | Gate manifest render (`make offline-gate`) |
