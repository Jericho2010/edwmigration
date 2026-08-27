#!/usr/bin/env python3
"""Unit tests for mlflow_context + mlflow_observe (memory backend, no real MLflow)."""
from __future__ import annotations

import json
import os
import tempfile
import time
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

    def test_gate_stage_does_not_end_run(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "gate-run-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            mobs.init_run(run_id, root=root)
            c = mobs.stage(run_id, "gate", "completed", detail="pass", root=root)
            self.assertFalse(c.get("ended"))
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

    def test_parent_missing_does_not_create_run(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "no-recover-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            mobs.init_run(run_id, root=root)
            backend = mobs.get_backend()
            assert isinstance(backend, mobs.MemoryBackend)
            n_before = len(backend.runs)

            def boom(*_a: object, **_k: object) -> str:
                raise RuntimeError("Parent span with ID 'dead' not found.")

            backend.start_span = boom  # type: ignore[method-assign]
            c = mobs.span_start(run_id, key="subagent:x", name="agent.x", root=root)
            self.assertEqual(len(backend.runs), n_before)
            self.assertIn("Parent span", str(c.get("last_error") or ""))

    def test_drain_queue_does_not_consume_on_start_span_fail(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "drain-block-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            with mock.patch.object(mobs, "ROOT", root), mock.patch.object(mctx, "ROOT", root):
                mobs.init_run(run_id, root=root)
                backend = mobs.get_backend()
                assert isinstance(backend, mobs.MemoryBackend)

                def boom(*_a: object, **_k: object) -> str:
                    raise RuntimeError("Parent span with ID 'dead' not found.")

                backend.start_span = boom  # type: ignore[method-assign]
                mobs.enqueue(
                    run_id,
                    {
                        "op": "span-start",
                        "key": "subagent:x",
                        "name": "agent.x",
                        "kind": "agent",
                    },
                    root=root,
                )
                result = mobs.drain_queue(run_id, root=root)
                self.assertEqual(result, "blocked")
                consumed = root / "agents" / "out" / run_id / "spans.consumed.jsonl"
                self.assertFalse(consumed.is_file() and consumed.read_text().strip())
                buf = root / "agents" / "out" / run_id / "spans.buf.jsonl"
                self.assertIn("span-start", buf.read_text())

    def test_nest_probe_ok_on_memory(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "nest-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            mobs.init_run(run_id, root=root)
            result = mobs.nest_probe(run_id, root=root)
            self.assertTrue(result.get("ok"), result)

    def test_nest_probe_via_serve_queue(self) -> None:
        """When serve is alive, nest-probe must enqueue — not touch empty _live."""
        import threading

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "nest-queue-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            with mock.patch.object(mobs, "ROOT", root), mock.patch.object(mctx, "ROOT", root):
                mobs.init_run(run_id, root=root)
                stop = threading.Event()

                def _serve() -> None:
                    while not stop.is_set():
                        mobs.drain_queue(run_id, root=root)
                        time.sleep(0.05)

                # Fake a live serve PID file so nest_probe takes the queue path.
                pid_path = mobs.serve_pid_path(run_id, root)
                pid_path.write_text(str(os.getpid()) + "\n", encoding="utf-8")
                t = threading.Thread(target=_serve, daemon=True)
                t.start()
                try:
                    with mock.patch.object(mobs, "_inline_cli", return_value=False):
                        result = mobs.nest_probe(run_id, root=root, timeout=5.0)
                    self.assertTrue(result.get("ok"), result)
                finally:
                    stop.set()
                    t.join(timeout=2)

    def test_blocked_outcome_span_status_ok(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "blocked-ok-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            mobs.init_run(run_id, root=root)
            c = mobs.span_start(
                run_id,
                key="subagent:convert:item-9",
                name="agent.convert.item-9",
                kind="agent",
                root=root,
            )
            sid = c["open_spans"]["subagent:convert:item-9"]
            mobs.span_end(
                run_id,
                key="subagent:convert:item-9",
                outputs='{"from":"convert","to":"coordinator","outcome":"blocked"}',
                status="ERROR",
                root=root,
            )
            backend = mobs.get_backend()
            assert isinstance(backend, mobs.MemoryBackend)
            self.assertEqual(backend._spans[sid].get("status"), "OK")

    def test_enqueue_and_serve_once(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "serve-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            with mock.patch.object(mobs, "ROOT", root), mock.patch.object(mctx, "ROOT", root):
                first = mobs.init_run(run_id, root=root)
                first_id = first["mlflow_run_id"]
                mobs.enqueue(
                    run_id,
                    {
                        "op": "span-start",
                        "key": "subagent:convert-1",
                        "name": "agent.convert",
                        "kind": "agent",
                    },
                    root=root,
                )
                mobs.enqueue(
                    run_id,
                    {"op": "span-end", "key": "subagent:convert-1", "status": "OK"},
                    root=root,
                )
                mobs.enqueue(
                    run_id,
                    {"op": "metric", "key": "tables_landed", "value": 12},
                    root=root,
                )
                mobs.serve_loop(run_id, root=root, once=True)
                c = mctx.load_context(run_id, root=root)
                assert c is not None
                self.assertNotEqual(c.get("mlflow_run_id"), first_id)
                self.assertNotIn("subagent:convert-1", c.get("open_spans") or {})
                consumed = root / "agents" / "out" / run_id / "spans.consumed.jsonl"
                self.assertTrue(consumed.is_file())
                self.assertEqual(len(consumed.read_text().splitlines()), 3)
                backend = mobs.get_backend()
                assert isinstance(backend, mobs.MemoryBackend)
                self.assertTrue(any(k == "tables_landed" and v == 12.0 for k, v, _ in backend.metrics))

    def test_force_init_terminates_previous(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "force-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            a = mobs.init_run(run_id, root=root)
            first = a["mlflow_run_id"]
            b = mobs.init_run(run_id, root=root, force=True)
            self.assertNotEqual(first, b["mlflow_run_id"])
            backend = mobs.get_backend()
            assert isinstance(backend, mobs.MemoryBackend)
            self.assertIn(first, backend.ended_runs)
            live = [r for r in backend.runs if r["status"] == "RUNNING"]
            self.assertEqual(len(live), 1)

    def test_experiment_purge(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            for run_id in ("purge-a", "purge-b"):
                (root / "agents" / "out" / run_id).mkdir(parents=True)
                mobs.init_run(run_id, root=root)
            backend = mobs.get_backend()
            assert isinstance(backend, mobs.MemoryBackend)
            self.assertGreaterEqual(len(backend.runs), 2)
            result = mobs.experiment_purge(delete_experiment=True)
            self.assertGreaterEqual(result["purged"], 2)
            self.assertTrue(result["experiment_deleted"])
            self.assertEqual(backend.runs, [])

    def test_experiment_purge_skips_rest_on_memory(self) -> None:
        with mock.patch.object(mobs, "_databricks_rest_purge") as rest:
            rest.return_value = {"purged": 99}
            result = mobs.experiment_purge(delete_experiment=False)
            rest.assert_not_called()
            self.assertNotEqual(result.get("purged"), 99)

    def test_cli_init_prints_announce(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "cli-init-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            with mock.patch.dict(os.environ, {"EDW_SKIP_VENV_REEXEC": "1"}, clear=False):
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


class EnqueueSpanTests(unittest.TestCase):
    def test_enqueue_lines_appends_under_lock(self) -> None:
        import enqueue_span as enq

        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "spans.buf.jsonl"
            enq.enqueue_lines(path, [{"op": "span-start", "key": "a"}, {"op": "span-end", "key": "a"}])
            lines = path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 2)
            self.assertEqual(json.loads(lines[0])["op"], "span-start")
            self.assertTrue((Path(str(path) + ".lock")).is_file())

    def test_cli_stdin(self) -> None:
        import enqueue_span as enq

        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "q.jsonl"
            with mock.patch("sys.stdin", new=__import__("io").StringIO('{"op":"metric","key":"k","value":1}\n')):
                rc = enq.main([str(path)])
            self.assertEqual(rc, 0)
            rec = json.loads(path.read_text().splitlines()[0])
            self.assertEqual(rec["op"], "metric")
            self.assertIn("ts", rec)


class _LiveCheckingBackend:
    """Mirrors MlflowBackend._live: parent must exist on *this* instance."""

    instances: list = []

    def __init__(self, uri: str) -> None:
        self.uri = uri
        self._live: dict = {}
        self.runs: list = []
        type(self).instances.append(self)

    def get_or_create_experiment(self, name: str) -> str:
        return "exp-1"

    def search_runs(self, *args: object, **kwargs: object) -> list:
        return []

    def create_run(self, experiment_id: str, run_name: str, tags: dict) -> str:
        rid = "mlrun-1"
        self.runs.append({"id": rid, "tags": dict(tags)})
        return rid

    def start_trace(self, name, span_type, experiment_id, run_id, attributes=None, inputs=None):
        sid = "root-live-1"
        self._live[sid] = {"name": name}
        return "tr-live-1", sid

    def start_span(self, name, trace_id, parent_id, span_type, inputs=None, attributes=None):
        if parent_id and parent_id not in self._live:
            raise RuntimeError(f"Parent span with ID '{parent_id}' not found.")
        sid = f"child-{len(self._live)}"
        self._live[sid] = {"parent": parent_id, "name": name}
        return sid

    def end_span(self, trace_id, span_id, outputs=None, status="OK"):
        self._live.pop(span_id, None)

    def set_terminated(self, run_id, status="FINISHED"):
        return None


class DatabricksBackendReuseTests(unittest.TestCase):
    """Databricks path must reuse one client so InMemoryTraceManager / _live stay valid."""

    def setUp(self) -> None:
        self._backend_env = os.environ.get("EDW_MLFLOW_BACKEND")
        os.environ.pop("EDW_MLFLOW_BACKEND", None)
        os.environ["DATABRICKS_HOST"] = "https://dbc.example.com"
        os.environ["MLFLOW_TRACKING_URI"] = "databricks"
        _LiveCheckingBackend.instances = []
        mobs.reset_memory_backend()

    def tearDown(self) -> None:
        if self._backend_env is None:
            os.environ.pop("EDW_MLFLOW_BACKEND", None)
        else:
            os.environ["EDW_MLFLOW_BACKEND"] = self._backend_env
        mobs.reset_memory_backend()

    def test_span_start_reuses_live_root_across_get_backend_calls(self) -> None:
        """init_run then span_start must not raise Parent span missing (one client)."""
        with (
            mock.patch.object(mobs, "MlflowBackend", _LiveCheckingBackend),
            mock.patch.object(mobs, "_MLFLOW_OK", True),
            tempfile.TemporaryDirectory() as td,
        ):
            root = Path(td)
            run_id = "reuse-1"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            mobs.init_run(run_id, root=root)
            c = mobs.span_start(
                run_id,
                key="subagent:x",
                name="agent.x",
                kind="agent",
                root=root,
            )
            self.assertNotIn("Parent span", str(c.get("last_error") or ""), c)
            self.assertIn("subagent:x", c.get("open_spans") or {})
            self.assertIs(mobs.get_backend(), mobs.get_backend())
            self.assertEqual(len(_LiveCheckingBackend.instances), 1)


class _FakeTrackingClient:
    def __init__(self, existing: object | None = None) -> None:
        self.existing = existing
        self.created: list[tuple[str, dict | None]] = []
        self.tags_set: list[tuple[str, str, str]] = []

    def get_experiment_by_name(self, name: str) -> object | None:
        return self.existing

    def create_experiment(self, name: str, artifact_location: str | None = None, tags: dict | None = None) -> str:
        self.created.append((name, dict(tags) if tags else None))
        return "exp-new"

    def set_experiment_tag(self, experiment_id: str, key: str, value: str) -> None:
        self.tags_set.append((experiment_id, key, value))


class ExperimentKindTests(unittest.TestCase):
    def _backend(self, client: _FakeTrackingClient) -> mobs.MlflowBackend:
        backend = object.__new__(mobs.MlflowBackend)
        backend.client = client
        backend.tracking_uri = "databricks"
        backend._live = {}
        return backend

    def test_create_experiment_sets_genai_kind_tag(self) -> None:
        client = _FakeTrackingClient(existing=None)
        backend = self._backend(client)
        eid = backend.get_or_create_experiment("/Shared/edw-migration")
        self.assertEqual(eid, "exp-new")
        self.assertTrue(client.created)
        tags = client.created[0][1] or {}
        self.assertEqual(tags.get("mlflow.experimentKind"), "genai_development")

    def test_existing_experiment_gets_genai_kind_tag(self) -> None:
        existing = type("Exp", (), {"experiment_id": "exp-old", "tags": {}})()
        client = _FakeTrackingClient(existing=existing)
        backend = self._backend(client)
        eid = backend.get_or_create_experiment("/Shared/edw-migration")
        self.assertEqual(eid, "exp-old")
        self.assertEqual(client.created, [])
        self.assertIn(("exp-old", "mlflow.experimentKind", "genai_development"), client.tags_set)


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
