#!/usr/bin/env python3
"""Render a migration_manifest.json as a human-readable table for the README
and the runbook. Reads the manifest from stdin or a path argument and prints
a markdown table to stdout.

Usage:
    ./agents/tools/render_manifest_table.py agents/out/<run_id>/migration_manifest.json
    cat agents/out/<run_id>/migration_manifest.json | ./agents/tools/render_manifest_table.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def render(manifest: dict) -> str:
    run_id = manifest.get("run_id", "?")
    gate = manifest.get("gate", "?")
    blockers = manifest.get("blockers", [])
    artifacts = manifest.get("converted_artifacts", [])
    summary = manifest.get("summary", {})

    lines = []
    lines.append(f"## Migration manifest — run `{run_id}`")
    lines.append("")
    lines.append(f"**Gate:** `{gate}`  ")
    lines.append(f"**Attempt:** {manifest.get('attempt', 0)}  ")
    lines.append(f"**Blockers:** {len(blockers)}  ")
    lines.append("")

    lines.append("### Summary")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("|---|---|")
    for k, v in summary.items():
        lines.append(f"| {k} | {v} |")
    lines.append("")

    lines.append("### Converted artifacts")
    lines.append("")
    if artifacts:
        lines.append("| Legacy proc | Target path | Status |")
        lines.append("|---|---|---|")
        for a in artifacts:
            lines.append(
                f"| `{a.get('legacy_proc', '?')}` | "
                f"`{a.get('target_path', '?')}` | "
                f"`{a.get('status', '?')}` |"
            )
    else:
        lines.append("_None._")
    lines.append("")

    lines.append("### Blockers")
    lines.append("")
    if blockers:
        lines.append("| ID | Message | Backlog item |")
        lines.append("|---|---|---|")
        for b in blockers:
            lines.append(
                f"| `{b.get('id', '?')}` | {b.get('message', '?')} | "
                f"`{b.get('backlog_item_id', '')}` |"
            )
    else:
        lines.append("_None._")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
        manifest = json.loads(path.read_text())
    else:
        manifest = json.loads(sys.stdin.read())
    print(render(manifest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
