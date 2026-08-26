#!/usr/bin/env python3
"""Append JSON records to a JSONL span queue with flock. No mlflow import.

Usage:
  python3 enqueue_span.py PATH <<'EOF'
  {"op":"span-start","key":"k","name":"n","kind":"agent"}
  EOF
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

try:
    import fcntl
except ImportError:  # pragma: no cover
    fcntl = None  # type: ignore[assignment]


def enqueue_lines(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = Path(str(path) + ".lock")
    payload = ""
    now = time.time()
    for rec in records:
        rec.setdefault("ts", now)
        payload += json.dumps(rec, separators=(",", ":")) + "\n"
    if not payload:
        return

    def _write() -> None:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(payload)

    if fcntl is None:
        _write()
        return
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with open(lock_path, "a+", encoding="utf-8") as lockf:
        fcntl.flock(lockf.fileno(), fcntl.LOCK_EX)
        try:
            _write()
        finally:
            fcntl.flock(lockf.fileno(), fcntl.LOCK_UN)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        print("usage: enqueue_span.py PATH [json]", file=sys.stderr)
        return 2
    path = Path(args[0])
    records: list[dict] = []
    if len(args) > 1:
        rec = json.loads(args[1])
        if isinstance(rec, dict):
            records.append(rec)
    else:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if isinstance(rec, dict):
                records.append(rec)
    enqueue_lines(path, records)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
