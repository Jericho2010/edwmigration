# Contract fixtures

Sample JSON under `run/` validates against `agents/contracts/*.schema.json` in CI.
Per-item convert results live under `run/convert/` (`convert_result.schema.json`).
`migration_backlog.empty.json` is `[]` (table-only / routines skipped).

These are **not** an offline migration mode — use them only for schema checks and unit demos of `render_manifest_table.py`.
