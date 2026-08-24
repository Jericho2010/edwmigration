# docs/img — diagram theme

All Mermaid diagrams in this repo share one palette (navy / teal / Azure blue / bronze–silver–gold / ops purple / danger red).

## Theme tokens

| Token | Hex | Use |
|---|---|---|
| User | `#0B3D5C` | You / human |
| Agent | `#1B7A6E` | Cursor agents |
| Azure | `#0078D4` | Source systems |
| Bronze | `#C47B2D` | bronze layer |
| Silver | `#6B7C8F` | silver / readonly stages |
| Gold | `#B8860B` | gold layer |
| Ops | `#5B4B8A` | ops / Gate / CI |
| Danger | `#B33A3A` | public FW / SoD breaks / demo anti-patterns |

## Init snippet (paste at top of fenced `mermaid` blocks)

```text
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
```

## Source files

| File | Description |
|---|---|
| [architecture.mmd](architecture.mmd) | Source → Federation → medallion → agents (convert fan-out) |
| [agent_squad_roles.html](agent_squad_roles.html) · [agent_squad_roles.png](agent_squad_roles.png) | README hero poster — comparison panels (agents + table/view/proc fate); HTML is the source, PNG is the render |
| [agent_delegation.mmd](agent_delegation.mmd) | Guide / Coordinator with parallel Convert wave |
| [enterprise_sod.mmd](enterprise_sod.mmd) | Segregation of duties swimlanes |
| [demo_vs_enterprise.mmd](demo_vs_enterprise.mmd) | Demo anti-pattern vs enterprise controls |
| [cursor_open_repo.png](cursor_open_repo.png) | Cursor: open repo root |
| [cursor_pick_agent.png](cursor_pick_agent.png) | Cursor: prefer `edw-start` (reshoot if still demo-guide only) |
| [cursor_kickoff.png](cursor_kickoff.png) | Cursor: after `start` — menu + choose `1` (reshoot if kickoff-only) |

## Demo GIFs (captures)

| File | Note |
|---|---|
| [demo_job.gif](demo_job.gif) | Job run capture |
| [demo_genie.gif](demo_genie.gif) | Genie Q&A capture |
| [demo_manifest.gif](demo_manifest.gif) | Gate / manifest capture |
| [demo_fault.gif](demo_fault.gif) | Fault-injection capture |
| [demo_seed.gif](demo_seed.gif) | **Legacy filename** — offline seed mode was removed; keep the name so storyboard/media paths stay stable |

```bash
# Optional PNG export (Node)
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/architecture.mmd -o docs/img/architecture.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/agent_delegation.mmd -o docs/img/agent_delegation.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/enterprise_sod.mmd -o docs/img/enterprise_sod.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/demo_vs_enterprise.mmd -o docs/img/demo_vs_enterprise.png

# README hero poster (HTML → PNG via Chrome headless)
timeout 30 google-chrome --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
  --user-data-dir=/tmp/edw-poster-chrome \
  --window-size=1600,1680 \
  --screenshot=docs/img/agent_squad_roles.png \
  "file://$PWD/docs/img/agent_squad_roles.html"
```

Narrative pages embed Mermaid directly (GitHub renders them). PNGs are for slides/PDF. The README hero is a hand-authored comparison poster (`agent_squad_roles.html`), not Mermaid — each agent and object fate gets its own architecture drawing.
