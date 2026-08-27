#!/usr/bin/env python3
"""MLflow observation for EDW subagents (additive live traces).

Soft dependency: missing mlflow or tracking failure → no-op (exit 0).

Cross-process Cursor hooks cannot share an in-memory MLflow trace. CLI
span/stage/metric/end-run calls therefore *enqueue* JSON records to
agents/out/<run_id>/spans.buf.jsonl. A single `serve` process per run_id
owns the MLflow run + trace and applies those records in-process so
spans actually nest.

Direct Python APIs (init_run, span_start, …) still talk to the backend
in-process — used by the serve loop and by unit tests.

CLI:
  python3 agents/tools/mlflow_observe.py init --run-id UUID
  python3 agents/tools/mlflow_observe.py serve --run-id UUID
  python3 agents/tools/mlflow_observe.py span-start --run-id UUID --key K --name N --kind agent|tool|chain
  python3 agents/tools/mlflow_observe.py span-end --run-id UUID --key K [--status OK]
  python3 agents/tools/mlflow_observe.py stage --run-id UUID --agent A --event E [--detail D]
  python3 agents/tools/mlflow_observe.py metric --run-id UUID --key K --value V
  python3 agents/tools/mlflow_observe.py end-run --run-id UUID [--gate-pass 0|1]
  python3 agents/tools/mlflow_observe.py trace-url --run-id UUID
  python3 agents/tools/mlflow_observe.py experiment-purge [--delete-experiment]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

import mlflow_context as ctx

ROOT = Path(__file__).resolve().parents[2]
TRUNCATE_LIMIT = 4096


def prefer_repo_venv() -> None:
    """Re-exec under repo .venv/bin/python when mlflow is missing on current interpreter."""
    if os.environ.get("EDW_SKIP_VENV_REEXEC", "").strip().lower() in ("1", "true", "yes"):
        return
    # Already have mlflow on this interpreter — stay put (tests / activated venv).
    try:
        import mlflow  # noqa: F401

        return
    except Exception:
        pass
    venv_py = ROOT / ".venv" / "bin" / "python"
    if not venv_py.is_file():
        return
    try:
        if Path(sys.executable).resolve() == venv_py.resolve():
            return
    except OSError:
        return
    os.execv(str(venv_py), [str(venv_py), *sys.argv])


try:
    import mlflow
    from mlflow import MlflowClient
    from mlflow.entities import SpanType

    _MLFLOW_OK = True
except Exception:  # pragma: no cover - optional dep
    mlflow = None  # type: ignore[assignment]
    MlflowClient = None  # type: ignore[assignment,misc]
    SpanType = None  # type: ignore[assignment,misc]
    _MLFLOW_OK = False


def truncate_io(value: object, limit: int = TRUNCATE_LIMIT) -> str:
    text = "" if value is None else str(value)
    if limit < 0:
        limit = 0
    if len(text) <= limit:
        return text
    omitted = len(text) - limit
    return text[:limit] + f"\n…[truncated {omitted} chars]"


def load_env(root: Path | None = None) -> None:
    env_path = (root or ROOT) / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def mlflow_available() -> bool:
    return _MLFLOW_OK


# ---------------------------------------------------------------------------
# Backends
# ---------------------------------------------------------------------------


class MemoryBackend:
    """In-process fake backend for tests (EDW_MLFLOW_BACKEND=memory)."""

    def __init__(self) -> None:
        self.metrics: list[tuple[str, float, int | None]] = []
        self.ended_runs: list[str] = []
        self.deleted_runs: list[str] = []
        self.runs: list[dict[str, Any]] = []
        self._spans: dict[str, dict[str, Any]] = {}
        self.experiment_id = "mem-exp-1"
        self.experiment_deleted = False

    def get_or_create_experiment(self, name: str) -> str:
        return self.experiment_id

    def get_experiment_by_name(self, name: str) -> str | None:
        return self.experiment_id

    def create_run(self, experiment_id: str, run_name: str, tags: dict[str, str]) -> str:
        rid = f"mem-run-{uuid.uuid4().hex[:12]}"
        self.runs.append(
            {
                "id": rid,
                "experiment_id": experiment_id,
                "name": run_name,
                "tags": dict(tags),
                "status": "RUNNING",
            }
        )
        return rid

    def search_runs(
        self, experiment_id: str, filter_string: str = "", max_results: int = 1000
    ) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        wanted_tag = ""
        m = re.search(r"tags\.edw_run_id\s*=\s*'([^']*)'", filter_string or "")
        if m:
            wanted_tag = m.group(1)
        for r in self.runs:
            if r["experiment_id"] != experiment_id:
                continue
            if wanted_tag and r.get("tags", {}).get("edw_run_id") != wanted_tag:
                continue
            out.append(r)
            if len(out) >= max_results:
                break
        return out

    def delete_run(self, run_id: str) -> None:
        self.deleted_runs.append(run_id)
        self.runs = [r for r in self.runs if r["id"] != run_id]

    def delete_experiment(self, experiment_id: str) -> None:
        self.experiment_deleted = True
        self.runs = [r for r in self.runs if r["experiment_id"] != experiment_id]

    def start_trace(
        self,
        name: str,
        span_type: str,
        experiment_id: str,
        run_id: str,
        attributes: dict[str, Any] | None = None,
        inputs: Any = None,
    ) -> tuple[str, str]:
        tid = f"tr-mem-{uuid.uuid4().hex[:16]}"
        sid = uuid.uuid4().hex[:16]
        self._spans[sid] = {"trace_id": tid, "name": name, "parent": None}
        return tid, sid

    def start_span(
        self,
        name: str,
        trace_id: str,
        parent_id: str,
        span_type: str,
        inputs: Any = None,
        attributes: dict[str, Any] | None = None,
    ) -> str:
        if parent_id and parent_id not in self._spans:
            raise RuntimeError(f"Parent span with ID '{parent_id}' not found.")
        sid = uuid.uuid4().hex[:16]
        self._spans[sid] = {"trace_id": trace_id, "name": name, "parent": parent_id}
        return sid

    def end_span(
        self,
        trace_id: str,
        span_id: str,
        outputs: Any = None,
        status: str = "OK",
    ) -> None:
        self._spans[span_id] = {
            **(self._spans.get(span_id) or {}),
            "ended": True,
            "status": status,
            "outputs": outputs,
        }

    def end_trace(
        self,
        trace_id: str,
        outputs: Any = None,
        status: str = "OK",
    ) -> None:
        return

    def log_metric(self, run_id: str, key: str, value: float, step: int | None = None) -> None:
        self.metrics.append((key, float(value), step))

    def set_terminated(self, run_id: str, status: str = "FINISHED") -> None:
        self.ended_runs.append(run_id)
        for r in self.runs:
            if r["id"] == run_id:
                r["status"] = status or "FINISHED"


class MlflowBackend:
    """Databricks / URI-backed MlflowClient."""

    def __init__(self, tracking_uri: str) -> None:
        if not _MLFLOW_OK:
            raise RuntimeError("mlflow not installed")
        mlflow.set_tracking_uri(tracking_uri)
        self.client = MlflowClient(tracking_uri)
        self.tracking_uri = tracking_uri
        self._live: dict[str, Any] = {}

    def get_or_create_experiment(self, name: str) -> str:
        for candidate in (name, ctx.FALLBACK_EXPERIMENT if name == ctx.DEFAULT_EXPERIMENT else name):
            try:
                exp = self.client.get_experiment_by_name(candidate)
                if exp is not None:
                    return exp.experiment_id
            except Exception:
                pass
            try:
                return self.client.create_experiment(candidate)
            except Exception:
                continue
        # last resort
        exp = mlflow.set_experiment(ctx.FALLBACK_EXPERIMENT)
        return exp.experiment_id

    def create_run(self, experiment_id: str, run_name: str, tags: dict[str, str]) -> str:
        run = self.client.create_run(experiment_id, run_name=run_name, tags=tags)
        return run.info.run_id

    def start_trace(
        self,
        name: str,
        span_type: str,
        experiment_id: str,
        run_id: str,
        attributes: dict[str, Any] | None = None,
        inputs: Any = None,
    ) -> tuple[str, str]:
        st = _span_type(span_type)
        root = self.client.start_trace(
            name=name,
            span_type=st,
            experiment_id=experiment_id,
            run_id=run_id,
            attributes={k: str(v) for k, v in (attributes or {}).items()},
            inputs=inputs,
        )
        self._live[root.span_id] = root
        return root.trace_id, root.span_id

    def start_span(
        self,
        name: str,
        trace_id: str,
        parent_id: str,
        span_type: str,
        inputs: Any = None,
        attributes: dict[str, Any] | None = None,
    ) -> str:
        if parent_id and parent_id not in self._live:
            raise RuntimeError(f"Parent span with ID '{parent_id}' not found.")
        st = _span_type(span_type)
        span = self.client.start_span(
            name=name,
            trace_id=trace_id,
            parent_id=parent_id,
            span_type=st,
            inputs=inputs,
            attributes=attributes or {},
        )
        self._live[span.span_id] = span
        return span.span_id

    def end_span(
        self,
        trace_id: str,
        span_id: str,
        outputs: Any = None,
        status: str = "OK",
    ) -> None:
        self.client.end_span(
            trace_id=trace_id,
            span_id=span_id,
            outputs=outputs,
            status=status,
        )
        self._live.pop(span_id, None)

    def end_trace(
        self,
        trace_id: str,
        outputs: Any = None,
        status: str = "OK",
    ) -> None:
        self.client.end_trace(trace_id=trace_id, outputs=outputs, status=status)

    def log_metric(self, run_id: str, key: str, value: float, step: int | None = None) -> None:
        if step is None:
            self.client.log_metric(run_id, key, float(value))
        else:
            self.client.log_metric(run_id, key, float(value), step=step)

    def get_experiment_by_name(self, name: str) -> str | None:
        try:
            exp = self.client.get_experiment_by_name(name)
        except Exception:
            return None
        if exp is None:
            return None
        return str(exp.experiment_id)

    def search_runs(
        self, experiment_id: str, filter_string: str = "", max_results: int = 1000
    ) -> list[Any]:
        out: list[Any] = []
        page_token = None
        remaining = max(1, max_results)
        pages = 0
        while remaining > 0 and pages < 20:
            kwargs: dict[str, Any] = {
                "experiment_ids": [experiment_id],
                "max_results": min(100, remaining),
            }
            if filter_string:
                kwargs["filter_string"] = filter_string
            if page_token:
                kwargs["page_token"] = page_token
            page = self.client.search_runs(**kwargs)
            batch = list(page) if page is not None else []
            out.extend(batch)
            remaining = max_results - len(out)
            pages += 1
            page_token = getattr(page, "token", None) or None
            if not page_token or not batch:
                break
        return out

    def delete_run(self, run_id: str) -> None:
        self.client.delete_run(run_id)

    def delete_experiment(self, experiment_id: str) -> None:
        self.client.delete_experiment(experiment_id)

    def set_terminated(self, run_id: str, status: str = "FINISHED") -> None:
        # MlflowClient.set_terminated(run_id, status=..., end_time=...)
        try:
            self.client.set_terminated(run_id, status=status)
        except TypeError:
            self.client.set_terminated(run_id)


_MEMORY_SINGLETON: MemoryBackend | None = None


def _span_type(kind: str) -> str:
    k = (kind or "UNKNOWN").upper()
    mapping = {
        "AGENT": "AGENT",
        "TOOL": "TOOL",
        "CHAIN": "CHAIN",
        "UNKNOWN": "UNKNOWN",
    }
    if _MLFLOW_OK and SpanType is not None:
        return getattr(SpanType, mapping.get(k, "UNKNOWN"), mapping.get(k, "UNKNOWN"))
    return mapping.get(k, "UNKNOWN")


def _apply_cli_auth() -> None:
    """Overlay matching-profile PAT when HOST is set without TOKEN. No-op if TOKEN exists."""
    if (os.environ.get("DATABRICKS_TOKEN") or "").strip():
        return
    try:
        tools = str(Path(__file__).resolve().parent)
        if tools not in sys.path:
            sys.path.insert(0, tools)
        import databricks_cli_env as cli_env

        cli_env.apply_cli_auth()
    except Exception:
        return


def resolve_tracking_uri() -> str | None:
    """Return tracking URI, 'memory', or None (disabled)."""
    backend = (os.environ.get("EDW_MLFLOW_BACKEND") or "").strip().lower()
    if backend == "memory":
        return "memory"
    if backend in ("off", "none", "0", "false"):
        return None
    explicit = (os.environ.get("EDW_MLFLOW_TRACKING_URI") or os.environ.get("MLFLOW_TRACKING_URI") or "").strip()
    if explicit:
        return explicit
    if (os.environ.get("DATABRICKS_HOST") or "").strip():
        return "databricks"
    return None


def get_backend(uri: str | None = None) -> Any | None:
    global _MEMORY_SINGLETON
    resolved = uri if uri is not None else resolve_tracking_uri()
    if resolved is None:
        return None
    if resolved == "memory":
        if _MEMORY_SINGLETON is None:
            _MEMORY_SINGLETON = MemoryBackend()
        return _MEMORY_SINGLETON
    _apply_cli_auth()
    if not _MLFLOW_OK:
        return None
    try:
        return MlflowBackend(resolved)
    except Exception:
        return None


def reset_memory_backend() -> None:
    """Test helper: clear singleton MemoryBackend."""
    global _MEMORY_SINGLETON
    _MEMORY_SINGLETON = None


def _run_id_of(run_obj: Any) -> str:
    if isinstance(run_obj, dict):
        return str(run_obj.get("id") or "")
    info = getattr(run_obj, "info", None)
    if info is not None:
        return str(getattr(info, "run_id", "") or "")
    return str(getattr(run_obj, "run_id", "") or "")


def _run_status_of(run_obj: Any) -> str:
    if isinstance(run_obj, dict):
        return str(run_obj.get("status") or "")
    info = getattr(run_obj, "info", None)
    if info is not None:
        return str(getattr(info, "status", "") or "")
    return str(getattr(run_obj, "status", "") or "")


def _terminate_quietly(backend: Any, mlflow_run_id: str, status: str = "KILLED") -> None:
    if not mlflow_run_id:
        return
    try:
        backend.set_terminated(mlflow_run_id, status=status)
    except TypeError:
        try:
            backend.set_terminated(mlflow_run_id)
        except Exception:
            pass
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Span queue (cross-process → single writer)
# ---------------------------------------------------------------------------


def spans_buf_path(run_id: str, root: Path | None = None) -> Path:
    return ctx.run_dir(run_id, root) / "spans.buf.jsonl"


def serve_pid_path(run_id: str, root: Path | None = None) -> Path:
    return ctx.run_dir(run_id, root) / "mlflow_serve.pid"


def enqueue(run_id: str, record: dict[str, Any], root: Path | None = None) -> Path:
    """Append one JSON record to the per-run span queue. Fast; no MLflow I/O."""
    root = root or ROOT
    path = spans_buf_path(run_id, root)
    path.parent.mkdir(parents=True, exist_ok=True)
    rec = dict(record)
    rec.setdefault("ts", time.time())
    payload = json.dumps(rec, separators=(",", ":")) + "\n"
    lock = Path(str(path) + ".lock")

    def _write() -> None:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(payload)

    ctx._with_lock(lock, _write)
    return path


def _inline_cli() -> bool:
    """True when CLI should apply spans in-process (tests / memory backend)."""
    flag = (os.environ.get("EDW_MLFLOW_INLINE") or "").strip().lower()
    if flag in ("1", "true", "yes"):
        return True
    return resolve_tracking_uri() == "memory"


def _should_spawn_serve() -> bool:
    if (os.environ.get("EDW_MLFLOW_NO_SERVE") or "").strip().lower() in ("1", "true", "yes"):
        return False
    if _inline_cli():
        return False
    if resolve_tracking_uri() in (None, "memory"):
        return False
    return True


def is_serve_alive(run_id: str, root: Path | None = None) -> bool:
    path = serve_pid_path(run_id, root)
    if not path.is_file():
        return False
    try:
        pid = int(path.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def spawn_serve_daemon(run_id: str, root: Path | None = None, force: bool = False) -> int | None:
    """Start `serve` in the background. Returns PID or None."""
    root = root or ROOT
    if is_serve_alive(run_id, root):
        try:
            return int(serve_pid_path(run_id, root).read_text(encoding="utf-8").strip())
        except (OSError, ValueError):
            return None
    rundir = ctx.run_dir(run_id, root)
    rundir.mkdir(parents=True, exist_ok=True)
    log = rundir / "mlflow_serve.log"
    cmd = [sys.executable, str(Path(__file__).resolve()), "serve", "--run-id", run_id]
    if force:
        cmd.append("--force")
    env = os.environ.copy()
    env["EDW_SKIP_VENV_REEXEC"] = "1"
    with open(log, "a", encoding="utf-8") as lf:
        proc = subprocess.Popen(
            cmd,
            cwd=str(root),
            stdout=lf,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env=env,
        )
    serve_pid_path(run_id, root).write_text(str(proc.pid) + "\n", encoding="utf-8")
    return proc.pid


def wait_for_context(
    run_id: str, root: Path | None = None, timeout: float = 15.0
) -> dict[str, Any]:
    root = root or ROOT
    deadline = time.time() + timeout
    last: dict[str, Any] | None = None
    while time.time() < deadline:
        last = ctx.load_context(run_id, root)
        if last and last.get("enabled") and last.get("trace_id"):
            return last
        time.sleep(0.2)
    return last or ctx.empty_context(run_id)


def apply_queue_record(run_id: str, rec: dict[str, Any], root: Path | None = None) -> str:
    """Apply one queued record in-process. Returns op name (or 'shutdown')."""
    op = str(rec.get("op") or "")
    if op == "span-start":
        span_start(
            run_id,
            key=str(rec.get("key") or ""),
            name=str(rec.get("name") or "span"),
            kind=str(rec.get("kind") or "agent"),
            inputs=rec.get("detail") or rec.get("inputs"),
            attributes={"edw.agent": rec["agent"]} if rec.get("agent") else None,
            parent_key=rec.get("parent_key"),
            root=root,
        )
    elif op == "span-end":
        span_end(
            run_id,
            key=str(rec.get("key") or ""),
            outputs=rec.get("detail") or rec.get("outputs"),
            status=str(rec.get("status") or "OK"),
            root=root,
        )
    elif op == "stage":
        stage(
            run_id,
            agent=str(rec.get("agent") or ""),
            event=str(rec.get("event") or ""),
            detail=str(rec.get("detail") or ""),
            tool=str(rec.get("tool") or ""),
            root=root,
        )
    elif op == "metric":
        step = rec.get("step")
        log_metric_value(
            run_id,
            key=str(rec.get("key") or ""),
            value=float(rec.get("value") or 0),
            step=int(step) if step is not None else None,
            root=root,
        )
    elif op in ("end-run", "shutdown"):
        gp = rec.get("gate_pass")
        end_run(
            run_id,
            outputs=rec.get("detail") or rec.get("outputs"),
            gate_pass=float(gp) if gp is not None else None,
            root=root,
        )
        return "shutdown"
    return op


def drain_queue(run_id: str, root: Path | None = None) -> str | None:
    """Move pending spans.buf.jsonl records into the live trace.

    Returns 'shutdown' if an end-run/shutdown record was applied,
    'drained' if any records were applied, 'blocked' if a span-start
    failed (parent missing — records left in the buf), or None if empty.
    """
    root = root or ROOT
    buf = spans_buf_path(run_id, root)
    if not buf.is_file() or buf.stat().st_size == 0:
        return None
    consumed = ctx.run_dir(run_id, root) / "spans.consumed.jsonl"
    lock = Path(str(buf) + ".lock")
    records: list[dict[str, Any]] = []

    def _locked() -> None:
        try:
            lines = buf.read_text(encoding="utf-8").splitlines()
        except OSError:
            return
        buf.write_text("", encoding="utf-8")
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(rec, dict):
                records.append(rec)

    ctx._with_lock(lock, _locked)
    if not records:
        return None
    shutdown = False
    applied = False
    remaining: list[dict[str, Any]] = []
    for i, rec in enumerate(records):
        result = apply_queue_record(run_id, rec, root)
        after = ctx.load_context(run_id, root) or {}
        err = str(after.get("last_error") or "")
        if rec.get("op") == "span-start" and _parent_span_missing(err):
            remaining = records[i:]
            break
        with open(consumed, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, separators=(",", ":")) + "\n")
        applied = True
        if result == "shutdown":
            shutdown = True
            remaining = records[i + 1 :]
            break
    if remaining:
        def _put_back() -> None:
            existing = ""
            try:
                existing = buf.read_text(encoding="utf-8")
            except OSError:
                existing = ""
            extra = "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in remaining)
            buf.write_text(existing + extra, encoding="utf-8")

        ctx._with_lock(lock, _put_back)
        return "blocked"
    if shutdown:
        return "shutdown"
    if applied:
        return "drained"
    return None


def serve_loop(
    run_id: str,
    root: Path | None = None,
    force: bool = True,
    once: bool = False,
    idle_timeout: float | None = None,
    poll_interval: float = 0.2,
) -> dict[str, Any]:
    """Own the MLflow trace for this run_id and apply queued span records.

    Always force-init: InMemoryTraceManager is per-process, so a respawned
    daemon cannot attach to a previous process's root span.
    """
    root = root or ROOT
    data = init_run(run_id, root=root, force=True)
    idle = 0.0
    while True:
        result = drain_queue(run_id, root)
        if result == "shutdown":
            return ctx.load_context(run_id, root) or data
        if result is None:
            if once:
                return ctx.load_context(run_id, root) or data
            if idle_timeout is not None and idle >= idle_timeout:
                return ctx.load_context(run_id, root) or data
            time.sleep(poll_interval)
            idle += poll_interval
        else:
            idle = 0.0
            if once:
                return ctx.load_context(run_id, root) or data


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def init_run(run_id: str, root: Path | None = None, force: bool = False) -> dict[str, Any]:
    """Start MLflow run + root span; write mlflow_context.json.

    Idempotent: reuses existing enabled context unless force=True.
    On force, terminates the previous MLflow run so it does not stay RUNNING.
    Never creates a second live run for the same edw_run_id tag.
    """
    root = root or ROOT
    existing = ctx.load_context(run_id, root)
    if existing and existing.get("enabled") and existing.get("trace_id") and not force:
        return existing

    backend = get_backend()
    if backend is None:
        data = ctx.empty_context(run_id)
        data["enabled"] = False
        ctx.save_context(run_id, data, root)
        return data

    try:
        exp_name = ctx.DEFAULT_EXPERIMENT
        experiment_id = backend.get_or_create_experiment(exp_name)
        # Kill any leftover RUNNING runs tagged with this edw_run_id.
        try:
            for run_obj in backend.search_runs(
                experiment_id, filter_string=f"tags.edw_run_id = '{run_id}'"
            ):
                rid = _run_id_of(run_obj)
                status = _run_status_of(run_obj).upper()
                if rid and status in ("", "RUNNING"):
                    _terminate_quietly(backend, rid, "KILLED")
        except Exception:
            pass
        if force and existing and existing.get("mlflow_run_id"):
            _terminate_quietly(backend, str(existing["mlflow_run_id"]), "KILLED")

        mlflow_run_id = backend.create_run(
            experiment_id,
            run_name=f"edw-{run_id[:8]}",
            tags={"edw_run_id": run_id, "observation": "mlflow"},
        )
        trace_id, root_span_id = backend.start_trace(
            name="edw.run",
            span_type="CHAIN",
            experiment_id=experiment_id,
            run_id=mlflow_run_id,
            attributes={"edw.run_id": run_id},
            inputs={"run_id": run_id},
        )
        host = (os.environ.get("DATABRICKS_HOST") or "").rstrip("/")
        observe_url = ctx.build_observe_url(host, experiment_id, trace_id)
        data = {
            "run_id": run_id,
            "experiment_name": exp_name,
            "experiment_id": str(experiment_id),
            "mlflow_run_id": mlflow_run_id,
            "trace_id": trace_id,
            "root_span_id": root_span_id,
            "open_spans": {},
            "observe_url": observe_url,
            "enabled": True,
            "updated_at": ctx.empty_context(run_id)["updated_at"],
        }
        ctx.save_context(run_id, data, root)
        return data
    except Exception as exc:
        data = ctx.empty_context(run_id)
        data["enabled"] = False
        data["error"] = truncate_io(exc, 500)
        ctx.save_context(run_id, data, root)
        return data


def ensure_init(run_id: str, root: Path | None = None) -> dict[str, Any]:
    """Lazy-init when context.json exists for this run.

    Parent-span-missing is *not* treated as corruption — never mint a new run.
    """
    root = root or ROOT
    existing = ctx.load_context(run_id, root)
    if existing and existing.get("enabled") and existing.get("trace_id"):
        return existing
    context_json = ctx.run_dir(run_id, root) / "context.json"
    if not context_json.is_file() and run_id == "unknown":
        return existing or ctx.empty_context(run_id)
    return init_run(run_id, root=root)


def _active_parent_id(c: dict[str, Any]) -> str:
    opens = c.get("open_spans") or {}
    # Prefer an open subagent span as parent for tools
    for key, sid in opens.items():
        if str(key).startswith("subagent:"):
            return str(sid)
    return str(c.get("root_span_id") or "")


def _parent_span_missing(exc: BaseException | str) -> bool:
    text = str(exc)
    return "Parent span" in text and "not found" in text


def span_start(
    run_id: str,
    key: str,
    name: str,
    kind: str = "agent",
    inputs: Any = None,
    attributes: dict[str, Any] | None = None,
    parent_key: str | None = None,
    root: Path | None = None,
) -> dict[str, Any]:
    root = root or ROOT
    c = ensure_init(run_id, root)
    if not c.get("enabled"):
        return c

    backend = get_backend()
    if backend is None:
        return c

    def _do_start(ctx_data: dict[str, Any]) -> dict[str, Any]:
        parent_id = ctx_data.get("root_span_id") or ""
        if parent_key and (ctx_data.get("open_spans") or {}).get(parent_key):
            parent_id = ctx_data["open_spans"][parent_key]
        elif kind.lower() == "tool":
            parent_id = _active_parent_id(ctx_data) or parent_id

        span_type = {"agent": "AGENT", "tool": "TOOL", "chain": "CHAIN"}.get(
            kind.lower(), "UNKNOWN"
        )
        attrs = dict(attributes or {})
        attrs.setdefault("edw.run_id", run_id)
        attrs.setdefault("edw.span_key", key)
        detail = ""
        if isinstance(inputs, dict):
            detail = str(inputs.get("detail") or "")
        elif inputs:
            detail = str(inputs)
        try:
            from edw_handoff import parse_detail

            parsed = parse_detail(detail)
            if parsed:
                for hk in ("from", "to", "item_id", "artifact", "outcome"):
                    if parsed.get(hk):
                        attrs.setdefault(f"edw.{hk}", str(parsed[hk]))
        except Exception:
            pass

        span_id = backend.start_span(
            name=name,
            trace_id=ctx_data["trace_id"],
            parent_id=parent_id,
            span_type=span_type,
            inputs=truncate_io(inputs) if inputs is not None else None,
            attributes=attrs,
        )

        def mut(data: dict[str, Any]) -> None:
            opens = dict(data.get("open_spans") or {})
            opens[key] = span_id
            data["open_spans"] = opens
            data.pop("last_error", None)

        return ctx.update_context(run_id, mut, root)

    try:
        return _do_start(c)
    except Exception as exc:
        # Never mint a new run on parent-missing — the serve process owns the
        # trace. Record the error and leave the existing run in place.
        def mut_err(data: dict[str, Any]) -> None:
            data["last_error"] = truncate_io(exc, 500)

        return ctx.update_context(run_id, mut_err, root)


def span_end(
    run_id: str,
    key: str,
    outputs: Any = None,
    status: str = "OK",
    root: Path | None = None,
) -> dict[str, Any]:
    root = root or ROOT
    c = ctx.load_context(run_id, root) or ctx.empty_context(run_id)
    if not c.get("enabled"):
        return c
    span_id = (c.get("open_spans") or {}).get(key)
    if not span_id:
        return c

    backend = get_backend()
    if backend is None:
        return c

    try:
        from edw_handoff import mlflow_status_for_outcome, parse_detail

        parsed = parse_detail(str(outputs) if outputs is not None else "")
        if parsed and parsed.get("outcome"):
            status = mlflow_status_for_outcome(str(parsed["outcome"]))
        elif str(status).upper() in ("ERROR", "FAILED", "FAIL"):
            blob = str(outputs or "").lower()
            if "blocked" in blob and "fail" not in blob:
                status = "OK"
            else:
                status = "ERROR"
        else:
            status = "OK"
    except Exception:
        if str(status).upper() in ("ERROR", "FAILED", "FAIL"):
            status = "ERROR"
        else:
            status = "OK"

    try:
        backend.end_span(
            trace_id=c["trace_id"],
            span_id=span_id,
            outputs=truncate_io(outputs) if outputs is not None else None,
            status=status,
        )
    except Exception:
        pass

    def mut(data: dict[str, Any]) -> None:
        opens = dict(data.get("open_spans") or {})
        opens.pop(key, None)
        data["open_spans"] = opens

    return ctx.update_context(run_id, mut, root)


def stage(
    run_id: str,
    agent: str,
    event: str,
    detail: str = "",
    tool: str = "",
    root: Path | None = None,
) -> dict[str, Any]:
    """Point-in-time CHAIN span for a milestone + metric tick."""
    root = root or ROOT
    c = ensure_init(run_id, root)
    if not c.get("enabled"):
        return c

    backend = get_backend()
    if backend is None:
        return c

    name = f"stage.{agent}.{event}"
    key = f"stage:{agent}/{event}:{int(time.time() * 1000)}"

    def _do_stage(ctx_data: dict[str, Any]) -> dict[str, Any]:
        span_id = backend.start_span(
            name=name,
            trace_id=ctx_data["trace_id"],
            parent_id=ctx_data["root_span_id"],
            span_type="CHAIN",
            inputs={
                "agent": agent,
                "event": event,
                "tool": truncate_io(tool, 200),
                "detail": truncate_io(detail, 1000),
            },
            attributes={"edw.run_id": run_id, "edw.agent": agent, "edw.event": event},
        )
        backend.end_span(
            trace_id=ctx_data["trace_id"],
            span_id=span_id,
            outputs={"agent": agent, "event": event},
            status="OK",
        )
        try:
            backend.log_metric(ctx_data["mlflow_run_id"], f"events_by_{agent}", 1.0)
        except Exception:
            pass

        # Log gate_pass but do NOT end the run — retries must keep the daemon.
        # Coordinator calls end-run at Done.
        if agent == "gate" and event == "completed":
            from edw_vocab import gate_pass_value

            gate_pass = gate_pass_value(detail)
            try:
                backend.log_metric(ctx_data["mlflow_run_id"], "gate_pass", gate_pass)
            except Exception:
                pass

        def mut_ok(data: dict[str, Any]) -> None:
            data.pop("last_error", None)

        return ctx.update_context(run_id, mut_ok, root)

    try:
        return _do_stage(c)
    except Exception as exc:
        def mut_err(data: dict[str, Any]) -> None:
            data["last_error"] = truncate_io(exc, 500)

        return ctx.update_context(run_id, mut_err, root)


def log_metric_value(
    run_id: str,
    key: str,
    value: float,
    step: int | None = None,
    root: Path | None = None,
) -> dict[str, Any]:
    root = root or ROOT
    c = ctx.load_context(run_id, root) or ctx.empty_context(run_id)
    if not c.get("enabled") or not c.get("mlflow_run_id"):
        return c
    backend = get_backend()
    if backend is None:
        return c
    try:
        backend.log_metric(c["mlflow_run_id"], key, float(value), step=step)
    except Exception:
        pass
    return c


def end_run(
    run_id: str,
    outputs: Any = None,
    gate_pass: float | None = None,
    root: Path | None = None,
) -> dict[str, Any]:
    root = root or ROOT
    c = ctx.load_context(run_id, root) or ctx.empty_context(run_id)
    if not c.get("enabled"):
        return c
    backend = get_backend()
    if backend is None:
        return c

    try:
        # Close any dangling open spans
        for key, span_id in list((c.get("open_spans") or {}).items()):
            try:
                backend.end_span(c["trace_id"], span_id, status="OK")
            except Exception:
                pass
        if gate_pass is not None:
            try:
                backend.log_metric(c["mlflow_run_id"], "gate_pass", float(gate_pass))
            except Exception:
                pass
        try:
            backend.end_trace(
                c["trace_id"],
                outputs=truncate_io(outputs) if outputs is not None else None,
                status="OK" if (gate_pass is None or float(gate_pass) >= 1.0) else "ERROR",
            )
        except Exception:
            pass
        term_status = "FINISHED"
        if gate_pass is not None and float(gate_pass) < 1.0:
            term_status = "FAILED"
        try:
            backend.set_terminated(c["mlflow_run_id"], status=term_status)
        except TypeError:
            try:
                backend.set_terminated(c["mlflow_run_id"])
            except Exception:
                pass
        except Exception:
            pass
    except Exception:
        pass

    def mut(data: dict[str, Any]) -> None:
        data["open_spans"] = {}
        data["ended"] = True

    return ctx.update_context(run_id, mut, root)


def trace_url(run_id: str, root: Path | None = None) -> str:
    c = ctx.load_context(run_id, root or ROOT)
    if not c:
        return ""
    if c.get("observe_url"):
        return str(c["observe_url"])
    host = (os.environ.get("DATABRICKS_HOST") or "").rstrip("/")
    return ctx.build_observe_url(host, str(c.get("experiment_id") or ""), str(c.get("trace_id") or ""))


def announce_observe_url(url: str, stream=None) -> None:
    """Colony-style early announce. No-op when url empty."""
    u = (url or "").strip()
    if not u:
        return
    out = stream if stream is not None else sys.stdout
    print(f"observe_url: {u}", file=out, flush=True)
    print(f"Observed by MLflow: {u}", file=out, flush=True)


def nest_probe(run_id: str, root: Path | None = None) -> dict[str, Any]:
    """In-process parent/child probe. FAIL if Parent span is missing.

    Starts agent.probe under the live root span and tool.probe under that
    agent using in-process span objects (not reconstructed JSON parent ids).
    """
    root = root or ROOT
    data = ensure_init(run_id, root)
    result: dict[str, Any] = {"ok": False, "run_id": run_id}
    if not data.get("enabled") or not data.get("root_span_id"):
        result["error"] = "observe not enabled or root span missing"
        return result
    backend = get_backend()
    if backend is None:
        result["error"] = "no mlflow backend"
        return result
    parent = str(data["root_span_id"])
    try:
        agent_id = backend.start_span(
            name="agent.probe",
            trace_id=str(data["trace_id"]),
            parent_id=parent,
            span_type="AGENT",
            inputs={"probe": True},
            attributes={"edw.run_id": run_id, "edw.outcome": "ok"},
        )
        tool_id = backend.start_span(
            name="tool.probe",
            trace_id=str(data["trace_id"]),
            parent_id=agent_id,
            span_type="TOOL",
            inputs={"probe": True},
            attributes={"edw.run_id": run_id},
        )
        backend.end_span(str(data["trace_id"]), tool_id, outputs={"probe": "ok"}, status="OK")
        backend.end_span(str(data["trace_id"]), agent_id, outputs={"probe": "ok"}, status="OK")
    except Exception as exc:
        err = truncate_io(exc, 500)

        def mut_err(d: dict[str, Any]) -> None:
            d["last_error"] = err

        ctx.update_context(run_id, mut_err, root)
        result["error"] = err
        return result

    after = ctx.load_context(run_id, root) or {}
    last = str(after.get("last_error") or "")
    if _parent_span_missing(last):
        result["error"] = last
        return result
    child = getattr(backend, "_spans", {}).get(tool_id) if hasattr(backend, "_spans") else None
    if isinstance(child, dict) and child.get("parent") and child.get("parent") != agent_id:
        result["error"] = "tool.probe not nested under agent.probe"
        return result
    result["ok"] = True
    result["agent_span_id"] = agent_id
    result["tool_span_id"] = tool_id
    return result


def _rest_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def _rest_json(method: str, url: str, token: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    import urllib.error
    import urllib.request

    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=_rest_headers(token))
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode() or "{}"
            return json.loads(raw)
    except urllib.error.HTTPError as exc:
        err = exc.read().decode(errors="replace")[:400]
        raise RuntimeError(f"{method} {url} -> {exc.code} {err}") from exc


def _databricks_rest_purge(delete_experiment: bool = False) -> dict[str, Any] | None:
    """Parallel REST delete. Returns None if host/token missing (caller falls back)."""
    _apply_cli_auth()
    host = (os.environ.get("DATABRICKS_HOST") or "").rstrip("/")
    token = os.environ.get("DATABRICKS_TOKEN") or ""
    if not host or not token:
        return None
    import urllib.parse
    from concurrent.futures import ThreadPoolExecutor, as_completed

    exp = None
    for name in (ctx.DEFAULT_EXPERIMENT, ctx.FALLBACK_EXPERIMENT):
        q = urllib.parse.quote(name, safe="")
        print(f"[mlflow_observe] experiment-purge: REST lookup {name}", flush=True)
        try:
            exp = _rest_json(
                "GET",
                f"{host}/api/2.0/mlflow/experiments/get-by-name?experiment_name={q}",
                token,
            )
        except Exception as exc:
            print(f"[mlflow_observe] lookup failed for {name}: {truncate_io(exc, 200)}", flush=True)
            exp = None
        if exp and exp.get("experiment"):
            break
    if not exp or not exp.get("experiment"):
        return {"purged": 0, "enabled": True, "error": "experiment not found"}

    eid = str(exp["experiment"]["experiment_id"])
    print(f"[mlflow_observe] experiment-purge: experiment_id={eid} listing runs…", flush=True)
    ids: list[str] = []
    try:
        page = None
        while True:
            body: dict[str, Any] = {"experiment_ids": [eid], "max_results": 100}
            if page:
                body["page_token"] = page
            out = _rest_json("POST", f"{host}/api/2.0/mlflow/runs/search", token, body)
            for run in out.get("runs") or []:
                rid = (run.get("info") or {}).get("run_id")
                if rid:
                    ids.append(str(rid))
            page = out.get("next_page_token")
            if not page:
                break
    except Exception as exc:
        return {"purged": 0, "experiment_id": eid, "error": truncate_io(exc, 500)}
    print(f"[mlflow_observe] experiment-purge: {len(ids)} run(s) to delete (parallel)", flush=True)

    purged = 0
    errors: list[str] = []

    def _del(rid: str) -> str | None:
        try:
            _rest_json("POST", f"{host}/api/2.0/mlflow/runs/delete", token, {"run_id": rid})
            return None
        except Exception as exc:
            return f"{rid}: {truncate_io(exc, 120)}"

    if ids:
        workers = min(16, len(ids))
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futs = {pool.submit(_del, rid): rid for rid in ids}
            done = 0
            for fut in as_completed(futs):
                done += 1
                err = fut.result()
                if err:
                    errors.append(err)
                else:
                    purged += 1
                if done % 25 == 0 or done == len(ids):
                    print(f"[mlflow_observe] deleted {purged}/{len(ids)}", flush=True)

    deleted_exp = False
    if delete_experiment:
        try:
            _rest_json(
                "POST",
                f"{host}/api/2.0/mlflow/experiments/delete",
                token,
                {"experiment_id": eid},
            )
            deleted_exp = True
            print("[mlflow_observe] experiment deleted", flush=True)
        except Exception as exc:
            errors.append(f"experiment: {truncate_io(exc, 200)}")
    return {
        "purged": purged,
        "experiment_id": eid,
        "experiment_deleted": deleted_exp,
        "errors": errors,
    }


def experiment_purge(delete_experiment: bool = False) -> dict[str, Any]:
    """Delete all runs in /Shared/edw-migration (and optionally the experiment)."""
    print("[mlflow_observe] experiment-purge: starting", flush=True)
    uri = resolve_tracking_uri()
    if uri not in (None, "memory"):
        rest = _databricks_rest_purge(delete_experiment=delete_experiment)
        if rest is not None:
            return rest
    backend = get_backend()
    if backend is None:
        return {"purged": 0, "enabled": False, "error": "no backend"}
    exp_id = None
    getter = getattr(backend, "get_experiment_by_name", None)
    names = [ctx.DEFAULT_EXPERIMENT, ctx.FALLBACK_EXPERIMENT]
    for name in names:
        print(f"[mlflow_observe] experiment-purge: lookup {name}", flush=True)
        try:
            if getter is not None:
                exp_id = getter(name)
            else:
                exp_id = backend.get_or_create_experiment(name)
        except Exception as exc:
            print(f"[mlflow_observe] lookup failed for {name}: {truncate_io(exc, 200)}", flush=True)
            exp_id = None
        if exp_id:
            break
    if not exp_id:
        return {"purged": 0, "enabled": True, "error": "experiment not found"}
    print(f"[mlflow_observe] experiment-purge: experiment_id={exp_id} listing runs…", flush=True)
    purged = 0
    errors: list[str] = []
    try:
        runs = backend.search_runs(str(exp_id), filter_string="")
    except Exception as exc:
        return {"purged": 0, "experiment_id": str(exp_id), "error": truncate_io(exc, 500)}
    print(f"[mlflow_observe] experiment-purge: {len(runs)} run(s) to delete", flush=True)
    for run_obj in runs:
        rid = _run_id_of(run_obj)
        if not rid:
            continue
        try:
            backend.delete_run(rid)
            purged += 1
        except Exception as exc:
            errors.append(f"{rid}: {truncate_io(exc, 120)}")
    deleted_exp = False
    if delete_experiment:
        try:
            backend.delete_experiment(str(exp_id))
            deleted_exp = True
        except Exception as exc:
            errors.append(f"experiment: {truncate_io(exc, 200)}")
    return {
        "purged": purged,
        "experiment_id": str(exp_id),
        "experiment_deleted": deleted_exp,
        "errors": errors,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _cmd_init(args: argparse.Namespace) -> int:
    load_env()
    if _should_spawn_serve() and not getattr(args, "no_serve", False):
        spawn_serve_daemon(args.run_id, force=bool(args.force))
        data = wait_for_context(args.run_id, timeout=20.0)
    else:
        data = init_run(args.run_id, force=bool(args.force))
    announce_observe_url(str(data.get("observe_url") or ""))
    print(
        f"[mlflow_observe] init run_id={args.run_id} enabled={data.get('enabled')}",
        flush=True,
    )
    return 0


def _cmd_serve(args: argparse.Namespace) -> int:
    load_env()
    pid_path = serve_pid_path(args.run_id)
    pid_path.parent.mkdir(parents=True, exist_ok=True)
    pid_path.write_text(str(os.getpid()) + "\n", encoding="utf-8")
    idle = args.idle_timeout if getattr(args, "idle_timeout", None) is not None else None
    try:
        print(
            f"[mlflow_observe] serve start run_id={args.run_id} pid={os.getpid()}",
            flush=True,
        )
        serve_loop(
            args.run_id,
            force=bool(args.force),
            once=bool(args.once),
            idle_timeout=idle,
        )
        print(f"[mlflow_observe] serve stop run_id={args.run_id}", flush=True)
    finally:
        try:
            if pid_path.is_file() and pid_path.read_text(encoding="utf-8").strip() == str(
                os.getpid()
            ):
                pid_path.unlink()
        except OSError:
            pass
    return 0


def _cmd_span_start(args: argparse.Namespace) -> int:
    load_env()
    rec = {
        "op": "span-start",
        "key": args.key,
        "name": args.name,
        "kind": args.kind,
        "agent": args.agent or "",
        "detail": args.detail or args.tool or "",
        "parent_key": args.parent_key,
    }
    if _inline_cli():
        apply_queue_record(args.run_id, rec)
    else:
        enqueue(args.run_id, rec)
    return 0


def _cmd_span_end(args: argparse.Namespace) -> int:
    load_env()
    rec = {
        "op": "span-end",
        "key": args.key,
        "detail": args.detail,
        "status": args.status,
    }
    if _inline_cli():
        apply_queue_record(args.run_id, rec)
    else:
        enqueue(args.run_id, rec)
    return 0


def _cmd_stage(args: argparse.Namespace) -> int:
    load_env()
    rec = {
        "op": "stage",
        "agent": args.agent,
        "event": args.event,
        "detail": args.detail or "",
        "tool": args.tool or "",
    }
    if _inline_cli():
        apply_queue_record(args.run_id, rec)
    else:
        enqueue(args.run_id, rec)
    return 0


def _cmd_metric(args: argparse.Namespace) -> int:
    load_env()
    rec = {"op": "metric", "key": args.key, "value": float(args.value), "step": args.step}
    if _inline_cli():
        apply_queue_record(args.run_id, rec)
    else:
        enqueue(args.run_id, rec)
    return 0


def _cmd_end_run(args: argparse.Namespace) -> int:
    load_env()
    gp = None if args.gate_pass is None else float(args.gate_pass)
    rec = {"op": "end-run", "detail": args.detail, "gate_pass": gp}
    if _inline_cli():
        apply_queue_record(args.run_id, rec)
    else:
        enqueue(args.run_id, rec)
    url = trace_url(args.run_id)
    if url:
        print(f"observe_url: {url}", flush=True)
    print(f"[mlflow_observe] end-run run_id={args.run_id}", flush=True)
    return 0


def _cmd_nest_probe(args: argparse.Namespace) -> int:
    load_env()
    result = nest_probe(args.run_id)
    if result.get("ok"):
        print(
            f"[mlflow_observe] nest-probe OK run_id={args.run_id} "
            f"agent={result.get('agent_span_id')} tool={result.get('tool_span_id')}",
            flush=True,
        )
        return 0
    print(
        f"[mlflow_observe] nest-probe FAIL run_id={args.run_id} "
        f"error={result.get('error')}",
        file=sys.stderr,
        flush=True,
    )
    return 1


def _cmd_trace_url(args: argparse.Namespace) -> int:
    load_env()
    url = trace_url(args.run_id)
    print(url)
    return 0


def _cmd_experiment_purge(args: argparse.Namespace) -> int:
    print("[mlflow_observe] experiment-purge starting", flush=True)
    load_env()
    result = experiment_purge(delete_experiment=bool(args.delete_experiment))
    print(
        f"[mlflow_observe] experiment-purge purged={result.get('purged')} "
        f"experiment_id={result.get('experiment_id')} "
        f"experiment_deleted={result.get('experiment_deleted')}",
        flush=True,
    )
    for err in result.get("errors") or []:
        print(f"[mlflow_observe] WARN: {err}", file=sys.stderr)
    if result.get("error"):
        print(f"[mlflow_observe] WARN: {result['error']}", file=sys.stderr)
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="EDW MLflow observe (soft no-op)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init")
    p.add_argument("--run-id", required=True)
    p.add_argument("--force", action="store_true")
    p.add_argument("--no-serve", action="store_true")
    p.set_defaults(func=_cmd_init)

    p = sub.add_parser("serve")
    p.add_argument("--run-id", required=True)
    p.add_argument("--force", action="store_true")
    p.add_argument("--once", action="store_true", help="Drain the queue once and exit")
    p.add_argument(
        "--idle-timeout",
        type=float,
        default=None,
        help="Exit after this many idle seconds (tests)",
    )
    p.set_defaults(func=_cmd_serve)

    p = sub.add_parser("span-start")
    p.add_argument("--run-id", required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--kind", default="agent", choices=["agent", "tool", "chain"])
    p.add_argument("--agent", default="")
    p.add_argument("--tool", default="")
    p.add_argument("--detail", default="")
    p.add_argument("--parent-key", default=None)
    p.set_defaults(func=_cmd_span_start)

    p = sub.add_parser("span-end")
    p.add_argument("--run-id", required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--detail", default=None)
    p.add_argument("--status", default="OK")
    p.set_defaults(func=_cmd_span_end)

    p = sub.add_parser("stage")
    p.add_argument("--run-id", required=True)
    p.add_argument("--agent", required=True)
    p.add_argument("--event", required=True)
    p.add_argument("--detail", default="")
    p.add_argument("--tool", default="")
    p.set_defaults(func=_cmd_stage)

    p = sub.add_parser("metric")
    p.add_argument("--run-id", required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--value", required=True)
    p.add_argument("--step", type=int, default=None)
    p.set_defaults(func=_cmd_metric)

    p = sub.add_parser("end-run")
    p.add_argument("--run-id", required=True)
    p.add_argument("--detail", default=None)
    p.add_argument("--gate-pass", default=None)
    p.set_defaults(func=_cmd_end_run)

    p = sub.add_parser("nest-probe")
    p.add_argument("--run-id", required=True)
    p.set_defaults(func=_cmd_nest_probe)

    p = sub.add_parser("trace-url")
    p.add_argument("--run-id", required=True)
    p.set_defaults(func=_cmd_trace_url)

    p = sub.add_parser("experiment-purge")
    p.add_argument(
        "--delete-experiment",
        action="store_true",
        help="Also delete the /Shared/edw-migration experiment itself",
    )
    p.set_defaults(func=_cmd_experiment_purge)

    return ap


def main(argv: list[str] | None = None) -> int:
    # Ensure agents/tools is on path when invoked as script
    tools = str(Path(__file__).resolve().parent)
    if tools not in sys.path:
        sys.path.insert(0, tools)
    prefer_repo_venv()
    ap = build_parser()
    args = ap.parse_args(argv)
    try:
        return int(args.func(args))
    except Exception as exc:
        cmd = getattr(args, "cmd", "")
        print(f"[mlflow_observe] WARNING: {exc}", file=sys.stderr)
        if cmd == "nest-probe":
            return 1
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
