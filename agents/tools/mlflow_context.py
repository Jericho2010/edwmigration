#!/usr/bin/env python3
"""Read/write agents/out/<run_id>/mlflow_context.json with flock."""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Callable

try:
    import fcntl
except ImportError:  # pragma: no cover
    fcntl = None  # type: ignore[assignment]

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_EXPERIMENT = "/Shared/edw-migration"
FALLBACK_EXPERIMENT = "edw-migration"
# Databricks Experiments UI: GenAI apps & agents vs Machine learning.
EXPERIMENT_KIND_TAG = "mlflow.experimentKind"
EXPERIMENT_KIND_GENAI = "genai_development"


def repo_root() -> Path:
    return ROOT


def run_dir(run_id: str, root: Path | None = None) -> Path:
    return (root or ROOT) / "agents" / "out" / run_id


def context_path(run_id: str, root: Path | None = None) -> Path:
    return run_dir(run_id, root) / "mlflow_context.json"


def empty_context(run_id: str) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "experiment_name": DEFAULT_EXPERIMENT,
        "experiment_id": "",
        "mlflow_run_id": "",
        "trace_id": "",
        "root_span_id": "",
        "open_spans": {},
        "observe_url": "",
        "enabled": False,
        "updated_at": _now(),
    }


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load_context(run_id: str, root: Path | None = None) -> dict[str, Any] | None:
    path = context_path(run_id, root)
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    return data


def save_context(run_id: str, data: dict[str, Any], root: Path | None = None) -> Path:
    path = context_path(run_id, root)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = dict(data)
    data["updated_at"] = _now()
    tmp = path.with_suffix(".json.tmp")
    payload = json.dumps(data, indent=2, sort_keys=True) + "\n"

    def _write() -> None:
        tmp.write_text(payload, encoding="utf-8")
        os.replace(tmp, path)

    _with_lock(path, _write)
    return path


def update_context(
    run_id: str,
    mutator: Callable[[dict[str, Any]], None],
    root: Path | None = None,
) -> dict[str, Any]:
    """Load-or-create, mutate under lock, save, return context."""
    path = context_path(run_id, root)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(".json.lock")

    def _locked() -> dict[str, Any]:
        ctx = load_context(run_id, root) or empty_context(run_id)
        mutator(ctx)
        ctx["updated_at"] = _now()
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(ctx, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(tmp, path)
        return ctx

    return _with_lock(lock_path, _locked)


def _with_lock(lock_path: Path, fn: Callable[[], Any]) -> Any:
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    if fcntl is None:
        return fn()
    with open(lock_path, "a+", encoding="utf-8") as lockf:
        fcntl.flock(lockf.fileno(), fcntl.LOCK_EX)
        try:
            return fn()
        finally:
            fcntl.flock(lockf.fileno(), fcntl.LOCK_UN)


def build_observe_url(
    host: str,
    experiment_id: str,
    trace_id: str = "",
) -> str:
    host = (host or "").rstrip("/")
    if not host or not experiment_id:
        return ""
    base = f"{host}/ml/experiments/{experiment_id}"
    if trace_id:
        return f"{base}/traces?selectedTraceId={trace_id}"
    return base
