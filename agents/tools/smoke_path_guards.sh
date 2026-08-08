#!/usr/bin/env bash
# Local/CI smoke: repo root resolution, run_id fallback, placeholder land guard,
# empty backlog schema, merge --skip-ops happy path.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "[smoke] repo_root.sh"
ROOT_OUT="$(./agents/tools/repo_root.sh)"
test "$ROOT_OUT" = "$REPO_ROOT"

echo "[smoke] hooks _repo_root.sh"
HOOK_ROOT="$(./.cursor/hooks/_repo_root.sh)"
test "$HOOK_ROOT" = "$REPO_ROOT"

echo "[smoke] resolve_run_id with CURRENT_RUN"
RID="00000000-0000-4000-8000-000000000099"
OUT="agents/out/${RID}"
mkdir -p "$OUT"
echo "$RID" > agents/out/CURRENT_RUN
echo '{"run_id":"'"$RID"'","foreign_catalog":"f","uc_catalog":"c","databricks_host":"https://example.cloud.databricks.com","max_retries":2}' > "$OUT/context.json"
GOT="$(./.cursor/hooks/_resolve_run_id.sh "$REPO_ROOT")"
test "$GOT" = "$RID"

echo "[smoke] resolve_run_id portable newest (no CURRENT_RUN)"
rm -f agents/out/CURRENT_RUN
GOT2="$(./.cursor/hooks/_resolve_run_id.sh "$REPO_ROOT")"
test "$GOT2" = "$RID"

echo "[smoke] check_land_ready rejects placeholder"
if ./agents/tools/check_land_ready.sh 2>/dev/null; then
  # May pass if a prior generate left real land in generated/ — force placeholder check
  TMP_LAND="databricks/generated/10_land_all.sql"
  mkdir -p databricks/generated
  SAVED=""
  if [ -f "$TMP_LAND" ]; then
    SAVED="$(mktemp)"
    cp "$TMP_LAND" "$SAVED"
  fi
  printf '%s\n' "-- Placeholder" "SELECT 'bronze_land_placeholder' AS check_name;" > "$TMP_LAND"
  # Prefer generated when _rendered missing or also placeholder
  rm -rf databricks/_rendered/bronze 2>/dev/null || true
  if ./agents/tools/check_land_ready.sh 2>/dev/null; then
    echo "[smoke] FAIL: expected placeholder rejection" >&2
    [ -n "$SAVED" ] && mv "$SAVED" "$TMP_LAND"
    exit 1
  fi
  echo "[smoke] placeholder correctly rejected"
  if [ -n "$SAVED" ]; then
    mv "$SAVED" "$TMP_LAND"
  else
    rm -f "$TMP_LAND"
  fi
else
  echo "[smoke] placeholder/missing land correctly rejected"
fi

echo "[smoke] empty backlog schema"
python3 - <<'PY'
import json
from pathlib import Path
try:
    from jsonschema import Draft7Validator
except ImportError:
    print("jsonschema not installed — skip schema assert")
    raise SystemExit(0)
schema = json.loads(Path("agents/contracts/migration_backlog.schema.json").read_text())
doc = json.loads(Path("agents/samples/run/migration_backlog.empty.json").read_text())
errs = list(Draft7Validator(schema).iter_errors(doc))
assert not errs, errs
print("empty backlog OK")
PY

echo "[smoke] merge --skip-ops"
python3 - <<'PY'
import json, shutil, subprocess, uuid
from pathlib import Path
run_id = str(uuid.uuid4())
run = Path(f"agents/out/{run_id}")
(run / "convert").mkdir(parents=True)
backlog = json.loads(Path("agents/samples/run/migration_backlog.json").read_text())
for item in backlog:
    item["status"] = "pending"
(run / "migration_backlog.json").write_text(json.dumps(backlog, indent=2))
shutil.copy("agents/samples/run/convert/item-001.json", run / "convert" / "item-001.json")
shutil.copy("agents/samples/run/convert/item-002.json", run / "convert" / "item-002.json")
r = subprocess.run(
    ["python3", "agents/tools/merge_convert_results.py", "--run-id", run_id, "--skip-ops"],
    capture_output=True, text=True,
)
assert r.returncode == 0, r.stderr + r.stdout
assert not (run / "merge_failed.json").exists()
summary = json.loads((run / "convert_summary.json").read_text())
assert summary["converted"] == 2
shutil.rmtree(run)
print("merge skip-ops OK")
PY

echo "[smoke] validate_artifact samples"
python3 agents/tools/validate_artifact.py \
  --schema agents/contracts/migration_backlog.schema.json \
  --file agents/samples/run/migration_backlog.json
python3 agents/tools/validate_artifact.py \
  --schema agents/contracts/migration_manifest.schema.json \
  --file agents/samples/run/migration_manifest.json
python3 agents/tools/validate_artifact.py \
  --schema agents/contracts/reconcile_report.schema.json \
  --file agents/samples/run/reconcile_report.json

echo "[smoke] persist helpers --skip-ops"
SMOKE_RID="00000000-0000-4000-8000-000000000098"
rm -rf "agents/out/${SMOKE_RID}"
python3 agents/tools/persist_backlog.py --run-id "$SMOKE_RID" \
  --from-file agents/samples/run/migration_backlog.json --skip-ops
python3 agents/tools/persist_manifest.py --run-id "$SMOKE_RID" \
  --from-file agents/samples/run/migration_manifest.json --skip-ops
python3 agents/tools/persist_reconcile_report.py --run-id "$SMOKE_RID" \
  --from-file agents/samples/run/reconcile_report.json
test -f "agents/out/${SMOKE_RID}/migration_backlog.json"
test -f "agents/out/${SMOKE_RID}/migration_manifest.json"
test -f "agents/out/${SMOKE_RID}/reconcile_report.json"
rm -rf "agents/out/${SMOKE_RID}"

echo "[smoke] check_job_wiring sample backlog"
python3 agents/tools/check_job_wiring.py --backlog agents/samples/run/migration_backlog.json

# cleanup smoke run dir
rm -rf "agents/out/${RID}"

echo "[smoke] path guards OK"
