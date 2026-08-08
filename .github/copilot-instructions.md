# EDW migration — Copilot instructions

This repo migrates Azure SQL or Azure MySQL → a user-named Databricks Unity Catalog catalog.

## Agent setup

Open the repo root so instructions under `agents/github-copilot/` apply. See `docs/agent-setup.md`.

## Track A — Guided demo

Follow `agents/github-copilot/edw-demo-guide.md`. Kickoff first; the guide runs `./agents/tools/preflight_track_a.sh` and asks for login/install only if needed.

Kickoff: *Set up the EDW demo and walk me through the migration.*

## Track B — Migration run

Follow `agents/github-copilot/edw-coordinator.md`. Stages: assess, convert, test, gate under `agents/github-copilot/`.

- MySQL: `SOURCE_TYPE=mysql` + `SOURCE_*` in `.env` — *Migrate my Azure MySQL into catalog `<name>`.*
- Azure SQL: `SOURCE_TYPE=sqlserver` — *Start an EDW migration run against my Azure SQL.*

**Parallel Convert:** after Assess, validate paths → launch up to 5 `edw-convert` workers per wave → each writes `agents/out/<run_id>/convert/<item_id>.json` → `merge_convert_results.py`.

## Rules

- Discover **all base tables** (not views) and procs/routines when export tools exist — no hard-coded WWI object lists in engine logic.
- Convert writes only `databricks/silver/` or `databricks/gold/` plus its convert result JSON — not `ops.*` or the backlog.
- Never invoke Lakebridge.
- Secrets stay in `.env` (gitignored); Federation password secret key is `source-password`.
- PAT auth now; OAuth is the documented enterprise target.
