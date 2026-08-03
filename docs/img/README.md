# Diagrams and demo media

## Architecture diagrams

Mermaid sources and rendered PNGs for enablement docs. Narrative docs also embed live Mermaid (GitHub renders them).

| File | Used in | Description |
|---|---|---|
| `architecture.mmd` / `.png` | [architecture.md](../architecture.md), [what-you-get.md](../what-you-get.md) | Source → Federation → medallion → agents |
| `agent_delegation.mmd` / `.png` | [architecture.md](../architecture.md), [agents/README](../../agents/README.md) | Demo guide / Coordinator → stages |

```bash
# Re-render PNGs (requires Node / @mermaid-js/mermaid-cli)
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/architecture.mmd -o docs/img/architecture.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/agent_delegation.mmd -o docs/img/agent_delegation.png
```

## Demo recordings (GIF)

Optional asciinema → GIF scenes. Sources and re-record script:
[docs/media/](../media/README.md).

**Re-record against the Azure-backed guided demo path** (offline seed was removed).
Until refreshed, treat existing `demo_*.gif` files as historical.

| File | Intended scene (after re-record) |
|---|---|
| `demo_bootstrap.gif` | `materialize_demo_env` + `make bootstrap` |
| `demo_setup.gif` | `make setup` (federation, Control Plane, Genie) |
| `demo_job.gif` | Medallion job run via bundle |
| `demo_fault.gif` | Fault injection → gate blocks → Genie → revert |
| `demo_genie.gif` | Control-plane Genie questions |
| `demo_manifest.gif` | Gate manifest render |
