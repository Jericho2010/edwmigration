#!/usr/bin/env python3
"""assert_watchable: hook subagentStart required; dual_write is not evidence."""
from __future__ import annotations

import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
import sys

sys.path.insert(0, str(ROOT / "agents" / "tools"))
import assert_watchable as aw  # noqa: E402
import merge_convert_results as merge  # noqa: E402


def _write_buf(run: Path, rows: list[dict]) -> None:
    buf = run / "events.buf.jsonl"
    buf.write_text("".join(json.dumps(r) + "\n" for r in rows))


def _hook(agent: str, event: str = "subagentStart", detail: str = "") -> dict:
    return {"agent": agent, "event": event, "detail": detail, "tool": ""}


class WatchableHookTests(unittest.TestCase):
    def test_dual_write_only_fails_convert(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "r1"
            run = root / "agents" / "out" / run_id
            run.mkdir(parents=True)
            (run / "migration_backlog.json").write_text(
                json.dumps(
                    [
                        {
                            "item_id": "item-001",
                            "target_layer": "silver",
                            "status": "pending",
                            "target_path": "databricks/silver/20_x.sql",
                        }
                    ]
                )
            )
            _write_buf(
                run,
                [
                    _hook("convert", "start", "dual_write start"),
                    _hook("convert", "completed", "dual_write stop"),
                    _hook("convert", "skipped", "ensure_run_events"),
                ],
            )
            errors = aw.check_stage(run_id, "Convert", root=root, require_mlflow=False)
            self.assertTrue(any("subagentStart" in e for e in errors))

    def test_subagent_start_ok(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "r2"
            run = root / "agents" / "out" / run_id
            run.mkdir(parents=True)
            _write_buf(run, [_hook("convert", "subagentStart", "item-001")])
            (run / "migration_backlog.json").write_text(
                json.dumps(
                    [
                        {
                            "item_id": "item-001",
                            "target_layer": "silver",
                            "status": "pending",
                        }
                    ]
                )
            )
            errors = aw.check_stage(run_id, "Convert", root=root, require_mlflow=False)
            self.assertEqual(errors, [])

    def test_table_only_skips_convert_agent(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "r3"
            run = root / "agents" / "out" / run_id
            run.mkdir(parents=True)
            (run / "inventory.json").write_text(
                json.dumps({"routines_skipped_reason": "no mysql cli", "procs_total": 0})
            )
            (run / "migration_backlog.json").write_text("[]")
            errors = aw.check_stage(run_id, "Convert", root=root, require_mlflow=False)
            self.assertEqual(errors, [])

    def test_wave_item_id_required_when_mentioned(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "r4"
            run = root / "agents" / "out" / run_id
            run.mkdir(parents=True)
            (run / "convert_wave.json").write_text(
                json.dumps({"item_ids": ["item-a", "item-b"]})
            )
            (run / "migration_backlog.json").write_text(
                json.dumps(
                    [
                        {"item_id": "item-a", "target_layer": "silver", "status": "pending"},
                        {"item_id": "item-b", "target_layer": "silver", "status": "pending"},
                    ]
                )
            )
            _write_buf(run, [_hook("convert", "subagentStart", "item-a")])
            errors = aw.check_stage(run_id, "Convert", root=root, require_mlflow=False)
            self.assertTrue(any("item-b" in e for e in errors))

    def test_strict_from_track_a_context(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "r5"
            run = root / "agents" / "out" / run_id
            run.mkdir(parents=True)
            (run / "context.json").write_text(json.dumps({"run_id": run_id, "track_a": True}))
            self.assertTrue(aw.is_strict(run_id, root, env={}))
            self.assertFalse(
                aw.is_strict(run_id, root, env={"EDW_OBSERVE_STRICT": "0"})
            )


class WatchableMergeTests(unittest.TestCase):
    def test_strict_merge_writes_merge_failed_without_hooks(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "wave-silent"
            run = root / "agents" / "out" / run_id
            (run / "convert").mkdir(parents=True)
            (run / "context.json").write_text(json.dumps({"track_a": True, "run_id": run_id}))
            backlog = [
                {
                    "item_id": "item-wave",
                    "legacy_proc": "dbo.A",
                    "target_path": "databricks/gold/40_x.sql",
                    "target_layer": "gold",
                    "status": "pending",
                }
            ]
            (run / "migration_backlog.json").write_text(json.dumps(backlog))
            (run / "convert_wave.json").write_text(
                json.dumps({"item_ids": ["item-wave"], "target_paths": [backlog[0]["target_path"]]})
            )
            (run / "convert" / "item-wave.json").write_text(
                json.dumps(
                    {
                        "item_id": "item-wave",
                        "legacy_proc": "dbo.A",
                        "target_path": backlog[0]["target_path"],
                        "status": "blocked",
                        "notes": "x",
                        "patterns_used": [],
                    }
                )
            )
            _write_buf(run, [_hook("convert", "completed", "dual_write only")])
            orig = merge.ROOT
            merge.ROOT = root
            try:
                with self.assertRaises(SystemExit) as ctx:
                    merge.merge(run_id, skip_ops=True)
                self.assertEqual(ctx.exception.code, 1)
            finally:
                merge.ROOT = orig
            self.assertTrue((run / "merge_failed.json").is_file())
            marker = json.loads((run / "merge_failed.json").read_text())
            self.assertIn("watchable", marker.get("error", "").lower() + marker.get("note", "").lower())


if __name__ == "__main__":
    unittest.main()
