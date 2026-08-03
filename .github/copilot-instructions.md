# EDW migration — Copilot instructions

This repo migrates Azure SQL → a user-named Databricks Unity Catalog catalog.

## Guided demo

After `az login` and Databricks auth, follow `agents/github-copilot/edw-demo-guide.md`.

## Migration run

Follow `agents/github-copilot/edw-coordinator.md`. Stages: assess, convert, test, gate under `agents/github-copilot/`.

## Rules

- Discover **all base tables** (not views) and user procs — no hard-coded WWI object lists in engine logic.
- Convert writes only `databricks/silver/` or `databricks/gold/`.
- Never invoke Lakebridge.
- Secrets stay in `.env` (gitignored).
- PAT auth now; OAuth is the documented enterprise target.
