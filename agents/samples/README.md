# Sample agent run artifacts

Offline fixtures for Gate/Test demos without a live Cursor run.

```bash
# Copy into a live run folder to exercise Gate:
RUN_ID=00000000-0000-4000-8000-000000000001
mkdir -p "agents/out/${RUN_ID}"
cp agents/samples/run/* "agents/out/${RUN_ID}/"
echo "$RUN_ID" > agents/out/CURRENT_RUN
./agents/tools/render_manifest_table.py "agents/out/${RUN_ID}/migration_manifest.json"
```

Converted path convention: agent output under `databricks/converted/` so the
job DAG baselines in `databricks/gold|silver/` are not overwritten.
