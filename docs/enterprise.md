# Enterprise

**After the guided demo:** what must change before this pattern is acceptable in a real organization with segregation of duties (SoD).

← [Guided demo](guided-demo.md) · [Architecture](architecture.md) · [Glossary](glossary.md)

The learning path (one person + agent + Free Edition) is intentional. **It is not an enterprise operating model.** This page is the bridge.

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart LR
  subgraph demo ["Demo / learning"]
    D1["One person + agent"]
    D2["PAT or personal login"]
    D3["Public firewall"]
    D4["Laptop make setup"]
    D5["Agent self-Gates"]
    D1 --> D2 --> D3 --> D4 --> D5
  end
  subgraph ent ["Enterprise"]
    E1["Split roles SoD"]
    E2["OAuth + job SP"]
    E3["Private Link / allowlist"]
    E4["CI deploy + envs"]
    E5["Human + policy Gate"]
    E1 --> E2 --> E3 --> E4 --> E5
  end
  classDef danger fill:#B33A3A,stroke:#8A2A2A,color:#fff
  classDef ok fill:#1B7A6E,stroke:#145A51,color:#fff
  class D1,D2,D3,D4,D5 danger
  class E1,E2,E3,E4,E5 ok
```

---

## What must change (demo → enterprise)

| Area | Demo today | Enterprise need |
|---|---|---|
| **Auth** | PAT / personal CLI profile | User OAuth + **service principal** for jobs; no long-lived PATs in laptop `.env` for prod |
| **Network** | Temporary `0.0.0.0/0` for Free Edition | Private Link / VNet / allowlisted egress — see [firewall.md](firewall.md) |
| **Secrets** | Local `.env` + secret scope | Vault-backed secrets; rotate; never paste passwords into chat for prod |
| **Privileges** | One admin creates CONNECTION + CATALOG | Split: metastore admin grants; project SP owns catalog; analysts get SELECT |
| **Discovery** | Full-auto all visible tables | Scoped schemas / allowlists; mandatory confirm; classify PII before land |
| **Convert** | Agent writes silver/gold in-repo | Pull request review; Convert ≠ Deploy |
| **Gate** | Agent interprets ship / no-ship | Gate as **policy** (CI + required reviewers); no self-approve prod |
| **Environments** | Single `dev` catalog | `dev` → `test` → `prod` catalogs + promotion |
| **Compute** | Free Edition serverless | Governed warehouses; job runs as SP |
| **Observability** | Dashboard + Genie for one user | Audit retention; who may query prod `ops.*` |
| **Change control** | `make setup` from laptop | Bundle deploy via CI; no prod deploy from a Cursor session |

---

## Segregation of duties

Roles that **must not** collapse into one Cursor user with admin + PAT:

| Role | May | Must not |
|---|---|---|
| **Requester / analyst** | Ask for migration; review Genie in non-prod | Create CONNECTION; declare Gate pass |
| **Platform / UC admin** | Grant privileges; network; create catalogs | Alone approve business Gate or edit conversions |
| **Migration engineer** | Discover / Convert in **dev**; open PRs | Deploy to prod; hold metastore admin |
| **Data owner / approver** | Sign off backlog scope + Gate criteria | Hold deploy credentials |
| **Ops / SRE** | Run prod job as SP; monitor | Change conversion SQL without PR |
| **Security** | Secrets, firewall, audit | Own the business ship decision |

**Demo anti-pattern (call this out in reviews):** one human + `edw-coordinator` + admin + PAT + public firewall = **no SoD**. Fine for learning; non-compliant for enterprise.

### SoD sequence

```mermaid
%%{init: {"theme":"base","themeVariables":{"primaryColor":"#E8F1F8","primaryTextColor":"#0B3D5C","primaryBorderColor":"#0B3D5C","lineColor":"#5B7A8C","secondaryColor":"#E6F4F1","tertiaryColor":"#F7F3EA","background":"#FFFFFF","mainBkg":"#E8F1F8","clusterBkg":"#F7FAFC","clusterBorder":"#5B7A8C","titleColor":"#0B3D5C","edgeLabelBackground":"#FFFFFF"}}}%%
flowchart TB
  subgraph platform ["1 · Platform / UC admin"]
    P1["Provision CONNECTION + catalog"]
    P2["Network + secret scopes"]
    P3["Grants: least privilege"]
  end
  subgraph engineer ["2 · Migration engineer"]
    E1["Discover + Convert in DEV"]
    E2["Open PR for silver/gold"]
  end
  subgraph owner ["3 · Data owner / approver"]
    O1["Approve backlog scope"]
    O2["Sign Gate criteria"]
  end
  subgraph ci ["4 · CI / Ops SP"]
    C1["Deploy to test / prod"]
    C2["Run job + Gate as SP"]
  end
  subgraph security ["5 · Security"]
    S1["Audit agent_events + CI"]
    S2["No laptop PAT in prod"]
  end
  P1 --> P2 --> P3 --> E1
  E1 --> E2 --> O1 --> O2 --> C1 --> C2 --> S1
  S2 -.-> C2
  classDef platform fill:#0078D4,stroke:#005A9E,color:#fff
  classDef engineer fill:#1B7A6E,stroke:#145A51,color:#fff
  classDef owner fill:#C47B2D,stroke:#8F5A1F,color:#fff
  classDef ci fill:#5B4B8A,stroke:#3F3460,color:#fff
  classDef security fill:#B33A3A,stroke:#8A2A2A,color:#fff
  class P1,P2,P3 platform
  class E1,E2 engineer
  class O1,O2 owner
  class C1,C2 ci
  class S1,S2 security
```

Sources also live in [`img/enterprise_sod.mmd`](img/enterprise_sod.mmd) and [`img/demo_vs_enterprise.mmd`](img/demo_vs_enterprise.mmd).

---

## Recommended enterprise run order

1. **Platform** provisions connection, catalog, network, and grants (often **without** the agent).  
2. **Engineer** runs Assess / Convert in **dev** (agent OK).  
3. **PR review** of silver/gold SQL.  
4. **Data owner** approves backlog scope and Gate criteria.  
5. **CI** deploys and runs Test in **test**.  
6. **Separate promotion** to **prod** as a service principal; Gate re-run.  
7. **Security** audits `ops.agent_events`, CI logs, and UC history.

---

## What we still promise

| Keep | Drop for enterprise |
|---|---|
| Discovery → land → convert → reconcile → Gate model | Free Edition + public firewall as the path |
| Control Plane + Genie as the explainer | Laptop PAT as prod identity |
| Inventory-driven (no hard-coded WWI names) | One person who creates, converts, deploys, and Gates |

Auth note in-engine today: PAT works for demos; **OAuth + SP is the enterprise target** ([architecture.md](architecture.md), [limits.md](limits.md)).

---

## RACI (summary)

| Activity | Platform | Engineer | Owner | CI/Ops | Security |
|---|---|---|---|---|---|
| Create CONNECTION / catalog | **A/R** | C | I | I | C |
| Discover / Convert (dev) | I | **R** | C | I | I |
| Approve backlog / Gate policy | I | C | **A** | I | C |
| Deploy prod job | I | C | I | **R** | C |
| Audit | I | I | I | C | **A/R** |

*(R = responsible, A = accountable, C = consulted, I = informed)*

---

## Next

- Still learning? → [Guided demo](guided-demo.md)  
- Point at a real DB in a sandbox → [Your database](your-database.md) (use non-prod + locked firewall)  
- Terms → [Glossary](glossary.md)  
- Engine depth → [Architecture](architecture.md)
