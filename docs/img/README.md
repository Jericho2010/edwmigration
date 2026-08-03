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
| [architecture.mmd](architecture.mmd) | Source → Federation → medallion → agents |
| [agent_delegation.mmd](agent_delegation.mmd) | Guide / Coordinator stage flow |
| [enterprise_sod.mmd](enterprise_sod.mmd) | Segregation of duties swimlanes |
| [demo_vs_enterprise.mmd](demo_vs_enterprise.mmd) | Demo anti-pattern vs enterprise controls |
| [cursor_open_repo.png](cursor_open_repo.png) | Cursor: open repo root (replace via [storyboard](../media/storyboard.md)) |
| [cursor_pick_agent.png](cursor_pick_agent.png) | Cursor: pick agent |
| [cursor_kickoff.png](cursor_kickoff.png) | Cursor: paste kickoff |
| `hero.gif` | README hero (create after recording — see storyboard) |

```bash
# Optional PNG export (Node)
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/architecture.mmd -o docs/img/architecture.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/agent_delegation.mmd -o docs/img/agent_delegation.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/enterprise_sod.mmd -o docs/img/enterprise_sod.png
npx -y @mermaid-js/mermaid-cli@11 -i docs/img/demo_vs_enterprise.mmd -o docs/img/demo_vs_enterprise.png
```

Narrative pages embed Mermaid directly (GitHub renders them). PNGs are for slides/PDF.
