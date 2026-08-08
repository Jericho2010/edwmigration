# Prerequisites

**Reference matrix** — install what the agent (or Makefile) names when something is missing. You do **not** need to run a version checklist before typing `start`. Soft status is informational; Track A preflight (`./agents/tools/preflight_track_a.sh`) runs after you choose menu **1** (or paste the demo kickoff).

← [Getting started](getting-started.md) · [Guided demo](guided-demo.md)

---

## By path

### Always

| Tool | Verify (when asked) |
|---|---|
| [Cursor](https://cursor.com) IDE, [Cursor CLI](cli-setup.md), or [Copilot CLI](cli-setup.md) | Repo root open; agents / instructions visible |
| Databricks CLI 0.281+ | `databricks --version` |
| python3 3.10+ | `python3 --version` |
| jq, curl | `jq --version` |

### Track A — Guided demo

| Tool | Why |
|---|---|
| Azure CLI | Bootstrap free SQL |
| SqlPackage + sqlcmd | Bacpac + proc export — **agent runs these**, you don’t memorize them |

### Track B — Your database

| Tool | Why |
|---|---|
| *(core tools only for `make setup`)* | SqlPackage **not** required |
| Azure CLI | Optional — MySQL/SQL firewall help |
| mysql client | Optional — MySQL **routine** export (tables still migrate without it) |

---

## Databricks privileges

- `CREATE CONNECTION` on the metastore (or admin)  
- `CREATE CATALOG` on the metastore  
- Secret scopes + Statement Execution on a **serverless** SQL warehouse  

The guide detects a missing warehouse in preflight; UC privilege denials usually appear at `make setup`.

---

## Logins (when the agent asks)

**Track A** (interactive — MFA is yours):

```bash
az login
databricks auth login --host https://<your-workspace>.cloud.databricks.com
```

**Track B**

```bash
databricks auth login --host https://<your-workspace>.cloud.databricks.com
# optional: az login
```

Env template: [`infra/azure/.env.example`](../infra/azure/.env.example)

---

## Next

→ [Guided demo](guided-demo.md) · [Your database](your-database.md) · [Troubleshooting](troubleshooting.md)
