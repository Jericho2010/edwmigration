#!/usr/bin/env python3
"""Warn when backlog target_paths are not wired into the medallion job YAML.

Exit 0 always (WARN-only). Does not edit the job.

Usage:
  python3 agents/tools/check_job_wiring.py --run-id UUID
  python3 agents/tools/check_job_wiring.py --backlog path/to/migration_backlog.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
JOB_YAML = ROOT / "databricks" / "jobs" / "edw_migration_medallion.yml"
PATH_RE = re.compile(
    r"(?:databricks|_rendered)/(?:silver|gold)/[A-Za-z0-9_.-]+\.sql"
)


def normalize_repo_path(raw: str) -> str:
    """Map job ../_rendered/silver/X.sql → databricks/silver/X.sql."""
    s = raw.strip().strip('"').strip("'")
    s = s.replace("../_rendered/", "databricks/")
    if s.startswith("_rendered/"):
        s = "databricks/" + s[len("_rendered/") :]
    if "/silver/" in s or "/gold/" in s:
        # collapse to databricks/<layer>/<file>
        m = re.search(r"(silver|gold)/([^/]+\.sql)$", s)
        if m:
            return f"databricks/{m.group(1)}/{m.group(2)}"
    return s


def job_wired_paths(job_path: Path) -> set[str]:
    text = job_path.read_text()
    found: set[str] = set()
    for match in PATH_RE.findall(text):
        found.add(normalize_repo_path(match))
    # Also catch path: ../_rendered/silver/...
    for m in re.finditer(r"path:\s*(\S+\.sql)", text):
        found.add(normalize_repo_path(m.group(1)))
    return found


def backlog_targets(backlog: list[dict]) -> list[str]:
    paths: list[str] = []
    for item in backlog:
        status = (item.get("status") or "").lower()
        layer = (item.get("target_layer") or "").lower()
        if status == "blocked" or layer == "n/a":
            continue
        tp = item.get("target_path") or ""
        if tp:
            paths.append(str(tp))
    return paths


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", help="Load agents/out/<run_id>/migration_backlog.json")
    ap.add_argument("--backlog", help="Path to migration_backlog.json")
    ap.add_argument(
        "--job",
        default=str(JOB_YAML.relative_to(ROOT)),
        help="Job YAML path (default: medallion job)",
    )
    args = ap.parse_args()

    if args.backlog:
        backlog_path = Path(args.backlog)
        if not backlog_path.is_absolute():
            backlog_path = ROOT / backlog_path
    elif args.run_id:
        backlog_path = ROOT / "agents" / "out" / args.run_id / "migration_backlog.json"
    else:
        print(
            "[check_job_wiring] provide --run-id or --backlog",
            file=sys.stderr,
        )
        return 1

    if not backlog_path.is_file():
        print(f"[check_job_wiring] backlog not found: {backlog_path}", file=sys.stderr)
        return 1

    job_path = Path(args.job)
    if not job_path.is_absolute():
        job_path = ROOT / job_path
    if not job_path.is_file():
        print(f"[check_job_wiring] job YAML not found: {job_path}", file=sys.stderr)
        return 1

    backlog = json.loads(backlog_path.read_text())
    if not isinstance(backlog, list):
        print("[check_job_wiring] backlog must be a JSON array", file=sys.stderr)
        return 1

    wired = job_wired_paths(job_path)
    targets = backlog_targets(backlog)
    missing = sorted({t for t in targets if t not in wired})

    if not targets:
        print("[check_job_wiring] OK no convertible backlog paths to check")
        return 0

    if not missing:
        print(
            f"[check_job_wiring] OK all {len(targets)} backlog path(s) "
            f"appear in {job_path.relative_to(ROOT)}"
        )
        return 0

    print(
        f"[check_job_wiring] WARN {len(missing)} backlog path(s) not wired "
        f"into {job_path.relative_to(ROOT)} — Gate may pass notebooks the job "
        f"does not run (see docs/limits.md):"
    )
    for path in missing:
        print(f"  WARN not in job: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
