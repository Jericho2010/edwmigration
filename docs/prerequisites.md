# Prerequisites

Install **only what your path needs**. If something is missing, the agent or Makefile names the one tool.

← [Getting started](getting-started.md)

---

## By path

### Always

| Tool | Verify |
|---|---|
| [Cursor](https://cursor.com) (or GitHub Copilot) | Repo opens; agents visible |
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

---

## Logins

**Track A**

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
