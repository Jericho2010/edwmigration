#!/usr/bin/env python3
"""record_subagent_hook.sh writes the same events.buf shape as log_event.sh."""
from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "agents" / "tools" / "record_subagent_hook.sh"


def _run(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT), "--root", str(root), "--skip-flush", *args],
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        check=False,
    )


def _rows(run: Path) -> list[dict]:
    buf = run / "events.buf.jsonl"
    if not buf.is_file():
        return []
    return [json.loads(line) for line in buf.read_text().splitlines() if line.strip()]


def _spans(run: Path) -> list[dict]:
    buf = run / "spans.buf.jsonl"
    if not buf.is_file():
        return []
    return [json.loads(line) for line in buf.read_text().splitlines() if line.strip()]


class RecordSubagentHookTests(unittest.TestCase):
    def test_assess_start_is_watchable(self):
        import sys

        sys.path.insert(0, str(ROOT / "agents" / "tools"))
        import assert_watchable as aw  # noqa: E402

        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "hook-assess"
            proc = _run(
                root,
                "--run-id",
                run_id,
                "--agent",
                "assess",
                "--event",
                "start",
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            run = root / "agents" / "out" / run_id
            rows = _rows(run)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["event"], "subagentStart")
            self.assertEqual(rows[0]["agent"], "assess")
            self.assertEqual(rows[0]["run_id"], run_id)
            self.assertIn("edw-assess", rows[0]["detail"])
            spans = _spans(run)
            self.assertTrue(any(s.get("op") == "span-start" for s in spans))
            self.assertTrue(any(s.get("name") == "agent.assess" for s in spans))
            errors = aw.check_stage(run_id, "Assess", root=root, require_mlflow=False)
            self.assertEqual(errors, [])

    def test_convert_requires_item_id_and_matches_wave(self):
        import sys

        sys.path.insert(0, str(ROOT / "agents" / "tools"))
        import assert_watchable as aw  # noqa: E402

        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "hook-convert"
            missing = _run(root, "--run-id", run_id, "--agent", "convert", "--event", "start")
            self.assertNotEqual(missing.returncode, 0)
            proc = _run(
                root,
                "--run-id",
                run_id,
                "--agent",
                "convert",
                "--event",
                "start",
                "--item-id",
                "item-010",
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            run = root / "agents" / "out" / run_id
            run.mkdir(parents=True, exist_ok=True)
            (run / "convert_wave.json").write_text(
                json.dumps({"item_ids": ["item-010"]})
            )
            (run / "migration_backlog.json").write_text(
                json.dumps(
                    [
                        {
                            "item_id": "item-010",
                            "target_layer": "silver",
                            "status": "pending",
                        }
                    ]
                )
            )
            rows = _rows(run)
            self.assertEqual(rows[0]["event"], "subagentStart")
            self.assertEqual(rows[0]["agent"], "convert")
            self.assertIn("item-010", rows[0]["detail"])
            errors = aw.check_stage(run_id, "Convert", root=root, require_mlflow=False)
            self.assertEqual(errors, [])

    def test_stop_enqueues_span_end(self):
        with TemporaryDirectory() as td:
            root = Path(td)
            run_id = "hook-stop"
            start = _run(root, "--run-id", run_id, "--agent", "test", "--event", "start")
            self.assertEqual(start.returncode, 0, start.stderr)
            stop = _run(root, "--run-id", run_id, "--agent", "test", "--event", "stop")
            self.assertEqual(stop.returncode, 0, stop.stderr)
            rows = _rows(root / "agents" / "out" / run_id)
            events = [r["event"] for r in rows]
            self.assertEqual(events, ["subagentStart", "subagentStop"])
            spans = _spans(root / "agents" / "out" / run_id)
            self.assertTrue(any(s.get("op") == "span-end" for s in spans))


if __name__ == "__main__":
    unittest.main()
