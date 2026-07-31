# Sample agent run artifacts

Offline fixtures for Gate/Test demos without Azure or a live Cursor run.

```bash
RUN_ID=00000000-0000-4000-8000-000000000001
mkdir -p "agents/out/${RUN_ID}"
cp agents/samples/run/* "agents/out/${RUN_ID}/"
echo "$RUN_ID" > agents/out/CURRENT_RUN
./agents/tools/render_manifest_table.py "agents/out/${RUN_ID}/migration_manifest.json"
```

Contents of `run/`:

| File | Stage |
|---|---|
| `context.json` | Coordinator kickoff |
| `migration_backlog.json` | Assess |
| `reconcile_report.json` | Test |
| `migration_manifest.json` | Gate |

Converted path convention: agent notebooks under `databricks/converted/` so
job baselines in `databricks/gold|silver/` are not overwritten.
