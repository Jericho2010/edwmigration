#!/usr/bin/env python3
"""MLflow observation for EDW subagents (additive live traces).

Soft dependency: missing mlflow or tracking failure → no-op (exit 0).
Uses MlflowClient start_trace / start_span / end_span with explicit parent_id
so Cursor hooks (separate processes) can share one tree via mlflow_context.json.

CLI:
  python3 agents/tools/mlflow_observe.py init --run-id UUID
  python3 agents/tools/mlflow_observe.py span-start --run-id UUID --key K --name N --kind agent|tool|chain
  python3 agents/tools/mlflow_observe.py span-end --run-id UUID --key K [--status OK]
  python3 agents/tools/mlflow_observe.py stage --run-id UUID --agent A --event E [--detail D]
  python3 agents/tools/mlflow_observe.py metric --run-id UUID --key K --value V
  python3 agents/tools/mlflow_observe.py end-run --run-id UUID [--gate-pass 0|1]
  python3 agents/tools/mlflow_observe.py trace-url --run-id UUID
"""
from __future__ import annotations

import argparse
import os
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
        self._spans: dict[str, dict[str, Any]] = {}

    def get_or_create_experiment(self, name: str) -> str:
        return "mem-exp-1"

    def create_run(self, experiment_id: str, run_name: str, tags: dict[str, str]) -> str:
        return f"mem-run-{uuid.uuid4().hex[:12]}"

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
        return

    def end_trace(
        self,
        trace_id: str,
        outputs: Any = None,
        status: str = "OK",
    ) -> None:
        return

    def log_metric(self, run_id: str, key: str, value: float, step: int | None = None) -> None:
        self.metrics.append((key, float(value), step))

    def set_terminated(self, run_id: str) -> None:
        self.ended_runs.append(run_id)


class MlflowBackend:
    """Databricks / URI-backed MlflowClient."""

    def __init__(self, tracking_uri: str) -> None:
        if not _MLFLOW_OK:
            raise RuntimeError("mlflow not installed")
        mlflow.set_tracking_uri(tracking_uri)
        self.client = MlflowClient(tracking_uri)
        self.tracking_uri = tracking_uri

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
        st = _span_type(span_type)
        span = self.client.start_span(
            name=name,
            trace_id=trace_id,
            parent_id=parent_id,
            span_type=st,
            inputs=inputs,
            attributes=attributes or {},
        )
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

    def set_terminated(self, run_id: str) -> None:
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


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def init_run(run_id: str, root: Path | None = None, force: bool = False) -> dict[str, Any]:
    """Start MLflow run + root span; write mlflow_context.json."""
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
    """Lazy-init when context.json exists for this run."""
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

    try:
        parent_id = c.get("root_span_id") or ""
        if parent_key and (c.get("open_spans") or {}).get(parent_key):
            parent_id = c["open_spans"][parent_key]
        elif kind.lower() == "tool":
            parent_id = _active_parent_id(c) or parent_id

        span_type = {"agent": "AGENT", "tool": "TOOL", "chain": "CHAIN"}.get(
            kind.lower(), "UNKNOWN"
        )
        attrs = dict(attributes or {})
        attrs.setdefault("edw.run_id", run_id)
        attrs.setdefault("edw.span_key", key)

        span_id = backend.start_span(
            name=name,
            trace_id=c["trace_id"],
            parent_id=parent_id,
            span_type=span_type,
            inputs=truncate_io(inputs) if inputs is not None else None,
            attributes=attrs,
        )

        def mut(data: dict[str, Any]) -> None:
            opens = dict(data.get("open_spans") or {})
            opens[key] = span_id
            data["open_spans"] = opens

        return ctx.update_context(run_id, mut, root)
    except Exception as exc:
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
    try:
        span_id = backend.start_span(
            name=name,
            trace_id=c["trace_id"],
            parent_id=c["root_span_id"],
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
            trace_id=c["trace_id"],
            span_id=span_id,
            outputs={"agent": agent, "event": event},
            status="OK",
        )
        try:
            backend.log_metric(c["mlflow_run_id"], f"events_by_{agent}", 1.0)
        except Exception:
            pass

        if agent == "gate" and event == "completed":
            detail_l = (detail or "").strip().lower()
            gate_pass = 0.0 if "fail" in detail_l else (1.0 if "pass" in detail_l else 0.0)
            try:
                backend.log_metric(c["mlflow_run_id"], "gate_pass", gate_pass)
            except Exception:
                pass
            return end_run(run_id, outputs={"gate": detail}, gate_pass=gate_pass, root=root)
    except Exception as exc:
        def mut_err(data: dict[str, Any]) -> None:
            data["last_error"] = truncate_io(exc, 500)

        return ctx.update_context(run_id, mut_err, root)

    return c


def log_metric_value(
    run_id: str,
    key: str,
    value: float,
    step: int | None = None,
    root: Path | None = None,
) -> dict[str, Any]:
    root = root or ROOT
    c = ensure_init(run_id, root)
    if not c.get("enabled"):
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
                status="OK",
            )
        except Exception:
            pass
        try:
            backend.set_terminated(c["mlflow_run_id"])
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


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _cmd_init(args: argparse.Namespace) -> int:
    load_env()
    data = init_run(args.run_id, force=bool(args.force))
    announce_observe_url(str(data.get("observe_url") or ""))
    print(
        f"[mlflow_observe] init run_id={args.run_id} enabled={data.get('enabled')}",
        flush=True,
    )
    return 0


def _cmd_span_start(args: argparse.Namespace) -> int:
    load_env()
    attrs = {}
    if args.agent:
        attrs["edw.agent"] = args.agent
    span_start(
        args.run_id,
        key=args.key,
        name=args.name,
        kind=args.kind,
        inputs=args.detail or args.tool or None,
        attributes=attrs,
        parent_key=args.parent_key,
    )
    return 0


def _cmd_span_end(args: argparse.Namespace) -> int:
    load_env()
    span_end(args.run_id, key=args.key, outputs=args.detail, status=args.status)
    return 0


def _cmd_stage(args: argparse.Namespace) -> int:
    load_env()
    stage(args.run_id, args.agent, args.event, detail=args.detail or "", tool=args.tool or "")
    return 0


def _cmd_metric(args: argparse.Namespace) -> int:
    load_env()
    log_metric_value(args.run_id, args.key, float(args.value), step=args.step)
    return 0


def _cmd_end_run(args: argparse.Namespace) -> int:
    load_env()
    gp = None if args.gate_pass is None else float(args.gate_pass)
    end_run(args.run_id, outputs=args.detail, gate_pass=gp)
    url = trace_url(args.run_id)
    if url:
        print(f"observe_url: {url}", flush=True)
    print(f"[mlflow_observe] end-run run_id={args.run_id}", flush=True)
    return 0


def _cmd_trace_url(args: argparse.Namespace) -> int:
    load_env()
    url = trace_url(args.run_id)
    print(url)
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="EDW MLflow observe (soft no-op)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init")
    p.add_argument("--run-id", required=True)
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=_cmd_init)

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

    p = sub.add_parser("trace-url")
    p.add_argument("--run-id", required=True)
    p.set_defaults(func=_cmd_trace_url)

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
        print(f"[mlflow_observe] WARNING: {exc}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
