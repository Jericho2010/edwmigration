#!/usr/bin/env python3
"""Validate migration_backlog target_path uniqueness and silver/gold prefix.

Usage:
  python3 agents/tools/validate_backlog_paths.py --run-id UUID
  python3 agents/tools/validate_backlog_paths.py --backlog path/to/migration_backlog.json

Exit 0 when all convertible items have unique paths under databricks/silver|gold/.
Exit 1 with a clear error list otherwise.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH_RE = re.compile(r"^databricks/(silver|gold)/[^/]+\.sql$")
SKIP_STATUSES = {"done", "n/a"}


def load_backlog(path: Path) -> list[dict]:
    if not path.is_file():
        raise FileNotFoundError(f"backlog not found: {path}")
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise ValueError("migration_backlog.json must be a JSON array")
    return data


def convertible_items(backlog: list[dict]) -> list[dict]:
    items = []
    for item in backlog:
        status = (item.get("status") or "").lower()
        layer = (item.get("target_layer") or "").lower()
        if status in SKIP_STATUSES or layer == "n/a":
            continue
        items.append(item)
    return items


def validate(backlog: list[dict]) -> list[str]:
    errors: list[str] = []
    items = convertible_items(backlog)
    by_path: dict[str, list[str]] = defaultdict(list)

    for item in items:
        item_id = item.get("item_id") or "<missing-item_id>"
        path = item.get("target_path") or ""
        if not path:
            errors.append(f"{item_id}: missing target_path")
            continue
        if "converted/" in path:
            errors.append(
                f"{item_id}: target_path must not use databricks/converted/ "
                f"(got {path!r})"
            )
        if not PATH_RE.match(path):
            errors.append(
                f"{item_id}: target_path must match "
                f"^databricks/(silver|gold)/[^/]+\\.sql$ (got {path!r})"
            )
        by_path[path].append(item_id)

    for path, ids in sorted(by_path.items()):
        if len(ids) > 1:
            errors.append(f"duplicate target_path {path!r}: {', '.join(ids)}")

    return errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", help="Load agents/out/<run_id>/migration_backlog.json")
    ap.add_argument("--backlog", help="Explicit backlog JSON path")
    args = ap.parse_args()

    if bool(args.run_id) == bool(args.backlog):
        print("Provide exactly one of --run-id or --backlog", file=sys.stderr)
        return 2

    if args.run_id:
        backlog_path = ROOT / "agents" / "out" / args.run_id / "migration_backlog.json"
    else:
        backlog_path = Path(args.backlog)

    try:
        backlog = load_backlog(backlog_path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[validate_backlog_paths] ERROR: {exc}", file=sys.stderr)
        return 1

    errors = validate(backlog)
    if errors:
        print("[validate_backlog_paths] FAIL:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    n = len(convertible_items(backlog))
    print(f"[validate_backlog_paths] OK items={n} path={backlog_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
