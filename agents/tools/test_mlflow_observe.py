#!/usr/bin/env python3
"""Unit tests for mlflow_context + mlflow_observe (memory backend, no real MLflow)."""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import mlflow_context as mctx
import mlflow_observe as mobs


class TruncateTests(unittest.TestCase):
    def test_truncate_short(self) -> None:
        self.assertEqual(mobs.truncate_io("hi"), "hi")

    def test_truncate_long(self) -> None:
        text = "a" * 5000
        out = mobs.truncate_io(text, limit=100)
        self.assertTrue(out.startswith("a" * 100))
        self.assertIn("truncated", out)


class ContextTests(unittest.TestCase):
    def test_save_load_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "run-abc"
            data = mctx.empty_context(run_id)
            data["enabled"] = True
            data["trace_id"] = "tr-1"
            mctx.save_context(run_id, data, root=root)
            loaded = mctx.load_context(run_id, root=root)
            assert loaded is not None
            self.assertEqual(loaded["trace_id"], "tr-1")
            self.assertTrue(loaded["enabled"])

    def test_update_context_open_spans(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "run-xyz"
            mctx.save_context(run_id, mctx.empty_context(run_id), root=root)

            def mut(d: dict) -> None:
                d["open_spans"] = {"subagent:1": "span-1"}

            out = mctx.update_context(run_id, mut, root=root)
            self.assertEqual(out["open_spans"]["subagent:1"], "span-1")

    def test_build_observe_url(self) -> None:
        url = mctx.build_observe_url(
            "https://dbc.example.com", "42", "tr-abc"
        )
        self.assertEqual(
            url,
            "https://dbc.example.com/ml/experiments/42/traces?selectedTraceId=tr-abc",
        )


class ObserveMemoryTests(unittest.TestCase):
    def setUp(self) -> None:
        mobs.reset_memory_backend()
        self._env = mock.patch.dict(
            os.environ,
            {"EDW_MLFLOW_BACKEND": "memory", "DATABRICKS_HOST": "https://dbc.example.com"},
            clear=False,
        )
        self._env.start()

    def tearDown(self) -> None:
        self._env.stop()
        mobs.reset_memory_backend()

    def test_init_span_end(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            data = mobs.init_run(run_id, root=root)
            self.assertTrue(data["enabled"])
            self.assertTrue(data["trace_id"])
            self.assertTrue(data["root_span_id"])
            self.assertIn("ml/experiments", data["observe_url"])

            c2 = mobs.span_start(
                run_id,
                key="subagent:convert-1",
                name="agent.convert",
                kind="agent",
                inputs="convert item",
                root=root,
            )
            self.assertIn("subagent:convert-1", c2["open_spans"])

            c3 = mobs.span_end(
                run_id,
                key="subagent:convert-1",
                outputs="done",
                root=root,
            )
            self.assertNotIn("subagent:convert-1", c3["open_spans"])

            mobs.stage(run_id, "assess", "completed", detail="ok", root=root)
            backend = mobs.get_backend()
            assert isinstance(backend, mobs.MemoryBackend)
            self.assertTrue(any(k.startswith("events_by_assess") for k, _, _ in backend.metrics))

            c4 = mobs.end_run(run_id, outputs={"gate": "pass"}, gate_pass=1.0, root=root)
            self.assertTrue(c4.get("ended"))
            self.assertEqual(c4["open_spans"], {})

    def test_gate_stage_ends_run(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "gate-run-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            mobs.init_run(run_id, root=root)
            c = mobs.stage(run_id, "gate", "completed", detail="pass", root=root)
            self.assertTrue(c.get("ended"))
            backend = mobs.get_backend()
            assert isinstance(backend, mobs.MemoryBackend)
            self.assertTrue(any(k == "gate_pass" and v == 1.0 for k, v, _ in backend.metrics))

    def test_init_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "idem-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            a = mobs.init_run(run_id, root=root)
            b = mobs.init_run(run_id, root=root)
            self.assertEqual(a["trace_id"], b["trace_id"])
            self.assertEqual(a["mlflow_run_id"], b["mlflow_run_id"])

    def test_cli_trace_url(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "cli-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            # Patch ROOT used by CLI helpers via init with root + monkeypatch module ROOT
            with mock.patch.object(mobs, "ROOT", root), mock.patch.object(mctx, "ROOT", root):
                mobs.init_run(run_id, root=root)
                rc = mobs.main(["trace-url", "--run-id", run_id])
                self.assertEqual(rc, 0)

    def test_announce_observe_url(self) -> None:
        import io

        buf = io.StringIO()
        mobs.announce_observe_url("https://dbc.example.com/ml/experiments/1", stream=buf)
        text = buf.getvalue()
        self.assertIn("observe_url: https://dbc.example.com/ml/experiments/1", text)
        self.assertIn("Observed by MLflow: https://dbc.example.com/ml/experiments/1", text)

    def test_announce_empty_noop(self) -> None:
        import io

        buf = io.StringIO()
        mobs.announce_observe_url("", stream=buf)
        self.assertEqual(buf.getvalue(), "")

    def test_cli_init_prints_announce(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "cli-init-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            with mock.patch.object(mobs, "ROOT", root), mock.patch.object(mctx, "ROOT", root):
                with mock.patch("sys.stdout", new_callable=lambda: __import__("io").StringIO()) as out:
                    rc = mobs.main(["init", "--run-id", run_id])
                    self.assertEqual(rc, 0)
                    text = out.getvalue()
                    self.assertIn("observe_url:", text)
                    self.assertIn("Observed by MLflow:", text)


class EnsureRunEventsAnnounceTests(unittest.TestCase):
    def setUp(self) -> None:
        mobs.reset_memory_backend()
        self._env = mock.patch.dict(
            os.environ,
            {"EDW_MLFLOW_BACKEND": "memory", "DATABRICKS_HOST": "https://dbc.example.com"},
            clear=False,
        )
        self._env.start()

    def tearDown(self) -> None:
        self._env.stop()
        mobs.reset_memory_backend()

    def test_init_mlflow_prints_url(self) -> None:
        import ensure_run_events as ere
        import io

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "ensure-announce-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            with mock.patch.object(ere, "ROOT", root), mock.patch.object(mobs, "ROOT", root), mock.patch.object(
                mctx, "ROOT", root
            ):
                buf = io.StringIO()
                with mock.patch("sys.stdout", buf):
                    ere.init_mlflow(run_id)
                text = buf.getvalue()
                self.assertIn("observe_url:", text)
                self.assertIn("Observed by MLflow:", text)
                self.assertIn("ml/experiments", text)


class ObserveNoopTests(unittest.TestCase):
    def test_backend_off(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "noop-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            with mock.patch.dict(os.environ, {"EDW_MLFLOW_BACKEND": "off"}, clear=False):
                mobs.reset_memory_backend()
                data = mobs.init_run(run_id, root=root)
                self.assertFalse(data["enabled"])
                c = mobs.span_start(run_id, "k", "n", root=root)
                self.assertFalse(c.get("enabled"))


if __name__ == "__main__":
    unittest.main()
