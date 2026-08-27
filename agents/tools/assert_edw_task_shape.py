#!/usr/bin/env python3
"""Prompt SoD: demo-guide must not launch convert; coordinator Convert has no unless.

Usage:
  python3 agents/tools/assert_edw_task_shape.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GUIDE = ROOT / "agents" / "prompts" / "05_demo_guide.md"
COORD = ROOT / "agents" / "prompts" / "00_coordinator.md"
LIVE = ROOT / "agents" / "prompts" / "_live_observability.md"


def main() -> int:
    errors: list[str] = []
    guide = GUIDE.read_text()
    if re.search(r"subagent_type:\s*edw-convert", guide):
        errors.append("05_demo_guide.md must not Task edw-convert (coordinator only)")
    if re.search(r"subagent_type:\s*edw-assess", guide):
        errors.append("05_demo_guide.md must not Task edw-assess")
    coord = COORD.read_text()
    convert_sec = coord
    if "Parallel Convert" in coord:
        convert_sec = coord.split("Parallel Convert", 1)[1].split("## ", 1)[0]
    if re.search(r"unless", convert_sec, re.I):
        errors.append("00_coordinator.md Convert section must not contain 'unless' (no dual_write loophole)")
    if "subagent_type" not in coord and "edw-convert" not in coord:
        errors.append("00_coordinator.md must require edw-convert")
    live = LIVE.read_text()
    if re.search(r"unless.*dual.write|unless dual-write", live, re.I):
        errors.append("_live_observability.md still has unless dual-write loophole")
    if errors:
        print("[assert_edw_task_shape] FAIL:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print("[assert_edw_task_shape] OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
