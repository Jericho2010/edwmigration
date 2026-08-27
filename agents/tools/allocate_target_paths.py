#!/usr/bin/env python3
"""Assign unique target_paths under databricks/silver|gold.

Next free NN starts at 20 (10 is bronze land). Slug from legacy_proc.
Coordinator runs this after persist_backlog before validate_backlog_paths / Convert.

Usage:
  python3 agents/tools/allocate_target_paths.py --run-id UUID
  python3 agents/tools/allocate_target_paths.py --backlog path.json --write
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ALLOC_MIN = 20
SKIP_STATUSES = {"done", "n/a", "blocked"}
PREFIX_RE = re.compile(r"^(\d+)_")
PATH_RE = re.compile(r"^databricks/(silver|gold)/[^/]+\.sql$")


def _stem_slug(legacy_proc: str, item_id: str) -> str:
    name = (legacy_proc or item_id or "item").split(".")[-1]
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return (slug or "item")[:80]


def _prefix(path: str) -> int | None:
    m = re.search(r"/(?:silver|gold)/(\d+)_", path)
    if not m:
        return None
    return int(m.group(1))


def _needs_alloc(item: dict, used_paths: set[str]) -> bool:
    status = (item.get("status") or "").lower()
    layer = (item.get("target_layer") or "").lower()
    if status in SKIP_STATUSES or layer == "n/a":
        return False
    path = item.get("target_path") or ""
    if not path or not PATH_RE.match(path):
        return True
    pref = _prefix(path)
    if pref is None or pref < ALLOC_MIN:
        return True
    if path in used_paths:
        return True
    return False


def existing_numbers(root: Path) -> set[int]:
    used: set[int] = set()
    for layer in ("silver", "gold"):
        d = root / "databricks" / layer
        if not d.is_dir():
            continue
        for f in d.glob("*.sql"):
            m = PREFIX_RE.match(f.name)
            if m:
                used.add(int(m.group(1)))
    return used


def allocate(backlog: list[dict], root: Path | None = None) -> list[dict]:
    root = root or ROOT
    used_nums = existing_numbers(root)
    used_paths: set[str] = set()
    next_n = ALLOC_MIN

    def take_path(layer: str, slug: str) -> str:
        nonlocal next_n
        while next_n in used_nums:
            next_n += 1
        path = f"databricks/{layer}/{next_n}_{slug}.sql"
        while path in used_paths:
            next_n += 1
            while next_n in used_nums:
                next_n += 1
            path = f"databricks/{layer}/{next_n}_{slug}.sql"
        used_paths.add(path)
        used_nums.add(next_n)
        next_n += 1
        return path

    out: list[dict] = []
    for item in backlog:
        row = dict(item)
        status = (row.get("status") or "").lower()
        layer = (row.get("target_layer") or "").lower()
        if status in SKIP_STATUSES or layer == "n/a":
            out.append(row)
            continue
        if not _needs_alloc(row, used_paths):
            path = str(row.get("target_path") or "")
            used_paths.add(path)
            n = _prefix(path)
            if n is not None:
                used_nums.add(n)
            out.append(row)
            continue
        layer = layer if layer in {"silver", "gold"} else "gold"
        slug = _stem_slug(str(row.get("legacy_proc") or ""), str(row.get("item_id") or ""))
        row["target_path"] = take_path(layer, slug)
        out.append(row)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id")
    ap.add_argument("--backlog")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    if bool(args.run_id) == bool(args.backlog) and not args.run_id:
        print("Provide --run-id or --backlog", file=sys.stderr)
        return 2
    if args.run_id:
        path = ROOT / "agents" / "out" / args.run_id / "migration_backlog.json"
    else:
        path = Path(args.backlog)
        if not path.is_absolute():
            path = ROOT / path
    if not path.is_file():
        print(f"[allocate_target_paths] missing {path}", file=sys.stderr)
        return 1
    backlog = json.loads(path.read_text())
    if not isinstance(backlog, list):
        print("[allocate_target_paths] backlog must be an array", file=sys.stderr)
        return 1
    allocated = allocate(backlog)
    if args.write or args.run_id:
        path.write_text(json.dumps(allocated, indent=2) + "\n")
    print(f"[allocate_target_paths] items={len(allocated)} path={path}")
    seen: set[str] = set()
    for item in allocated:
        if (item.get("target_layer") or "").lower() == "n/a":
            continue
        if (item.get("status") or "").lower() in SKIP_STATUSES:
            continue
        tp = item.get("target_path") or ""
        print(f"  {item.get('item_id')} -> {tp}")
        if tp in seen:
            print(f"[allocate_target_paths] ERROR duplicate {tp}", file=sys.stderr)
            return 1
        seen.add(tp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
