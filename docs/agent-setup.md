# Agent setup (once)

Open this repo at the **git root** in Cursor so agents and hooks load.

## Checklist

1. Clone / open the repo root (not a subfolder).
2. Confirm these agents appear: `edw-demo-guide`, `edw-coordinator`, `edw-assess`, `edw-convert`, `edw-test`, `edw-gate`.
3. If missing: `make sync-prompts`.
4. Log in for the track you want (below), then paste the kickoff sentence.

GitHub Copilot: same instructions under [`agents/github-copilot/`](../agents/github-copilot/) and [`.github/copilot-instructions.md`](../.github/copilot-instructions.md).

## Kickoff sentences

| Track | Agent | Say |
|---|---|---|
| **A — Guided demo** (WWI on Azure SQL) | `edw-demo-guide` | Set up the EDW demo and walk me through the migration. |
| **B — MySQL** (your Azure MySQL) | `edw-coordinator` | Migrate my Azure MySQL into catalog `<name>`. Host/user/db are in `.env` (or I’ll paste them). |
| **B — Azure SQL** (existing DB) | `edw-coordinator` | Start an EDW migration run against my Azure SQL. |

## You do vs agent does

| You | Agent / Makefile |
|---|---|
| Open repo + pick agent | Load prompts/hooks |
| Logins | Verify auth; write `.env` |
| One kickoff sentence | Federation → discover → land → convert → job → Gate |
| Watch Control Plane + Genie | Print Dashboard + Genie URLs |

## Track logins / tools

**Track A (demo):** `az login` + Databricks auth. Agent installs path uses SqlPackage/sqlcmd via bootstrap — you do not run them by hand.

**Track B MySQL:** Databricks auth. Optional `az login` if you want the agent to open a firewall rule. Optional `mysql` CLI for routine export (tables still migrate without it).

**Track B Azure SQL:** Databricks auth + source connection fields in `.env`.
