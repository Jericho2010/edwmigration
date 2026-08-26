#!/usr/bin/env python3
"""Import medallion SQL as Databricks SQL notebooks under edwmigration_YYYYMMDD.

Gallery only — the DAB job keeps sql_task. Coordinator calls this at Land,
after each Convert merge, and after deploy.

Usage:
  python3 agents/tools/publish_run_notebooks.py --run-id UUID
  python3 agents/tools/publish_run_notebooks.py --run-id UUID --dry-run
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SKIP_NAMES = frozenset({"01_federation_setup.sql"})
LAYERS = ("uc", "bronze", "silver", "gold", "tests")

try:
    import databricks_cli_env as cli_env
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import databricks_cli_env as cli_env  # type: ignore


def load_env(root: Path | None = None) -> None:
    env_path = (root or ROOT) / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def run_dir(run_id: str, root: Path | None = None) -> Path:
    return (root or ROOT) / "agents" / "out" / run_id


def notebooks_json_path(run_id: str, root: Path | None = None) -> Path:
    return run_dir(run_id, root) / "notebooks.json"


@dataclass(frozen=True)
class ImportItem:
    layer: str
    source: str
    dest_name: str


def _pick_source(root: Path, layer: str, name: str) -> Path | None:
    rendered = root / "databricks" / "_rendered" / layer / name
    repo = root / "databricks" / layer / name
    if rendered.is_file():
        return rendered
    if repo.is_file():
        return repo
    generated = root / "databricks" / "_rendered" / "generated" / name
    if layer == "bronze" and generated.is_file() and name == "10_land_all.sql":
        return generated
    return None


def build_import_plan(root: Path | None = None) -> list[ImportItem]:
    """SQL files to import. Prefer _rendered over repo. Skip federation setup."""
    root = root or ROOT
    items: list[ImportItem] = []
    seen: set[tuple[str, str]] = set()
    for layer in LAYERS:
        names: set[str] = set()
        for base in (root / "databricks" / "_rendered" / layer, root / "databricks" / layer):
            if not base.is_dir():
                continue
            for path in base.glob("*.sql"):
                names.add(path.name)
        if layer == "bronze" and (root / "databricks" / "_rendered" / "generated" / "10_land_all.sql").is_file():
            names.add("10_land_all.sql")
        for name in sorted(names):
            if name in SKIP_NAMES:
                continue
            src = _pick_source(root, layer, name)
            if src is None:
                continue
            key = (layer, name)
            if key in seen:
                continue
            seen.add(key)
            items.append(ImportItem(layer=layer, source=str(src), dest_name=src.stem))
    return items


def folder_date_utc(existing: dict[str, Any] | None = None, now: datetime | None = None) -> str:
    if existing and existing.get("folder_date"):
        return str(existing["folder_date"])
    stamp = now or datetime.now(timezone.utc)
    return stamp.strftime("%Y%m%d")


def workspace_folder(user: str, folder_date: str) -> str:
    user = user.strip().strip("/")
    return f"/Users/{user}/edwmigration_{folder_date}"


def folder_url(host: str, folder: str) -> str:
    host = (host or "").rstrip("/")
    path = folder if folder.startswith("/") else "/" + folder
    return f"{host}/#workspace{path}"


def catalog_url(host: str, catalog: str) -> str:
    host = (host or "").rstrip("/")
    return f"{host}/explore/data/{catalog}"


def job_url(host: str, job_id: str | int) -> str:
    host = (host or "").rstrip("/")
    return f"{host}/jobs/{job_id}"


def _cli_json(args: list[str]) -> Any | None:
    try:
        raw = subprocess.check_output(args, text=True, stderr=subprocess.PIPE)
    except (OSError, subprocess.CalledProcessError):
        return None
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def current_user_name() -> str:
    data = _cli_json(["databricks", "current-user", "me", "-o", "json"])
    if isinstance(data, dict):
        return str(data.get("userName") or data.get("user_name") or "").strip()
    return ""


def find_medallion_job_id(payload: Any) -> str:
    """Pick the edw_migration_medallion job id from a jobs list JSON."""
    rows: list[Any] = []
    if isinstance(payload, dict):
        rows = payload.get("jobs") or payload.get("items") or []
    elif isinstance(payload, list):
        rows = payload
    ranked: list[tuple[int, str]] = []
    for job in rows:
        if not isinstance(job, dict):
            continue
        settings = job.get("settings") if isinstance(job.get("settings"), dict) else {}
        name = str(settings.get("name") or job.get("name") or "")
        jid = job.get("job_id") or job.get("jobId") or job.get("id")
        if jid is None:
            continue
        lname = name.lower()
        if "edw_migration_medallion" not in lname and "edw migration medallion" not in lname:
            continue
        rank = 0 if lname.startswith("[dev") else 1
        ranked.append((rank, str(jid)))
    ranked.sort()
    return ranked[0][1] if ranked else ""


def lookup_job_id() -> str:
    data = _cli_json(["databricks", "jobs", "list", "-o", "json"])
    return find_medallion_job_id(data)


def list_user_edw_folders(user: str) -> list[str]:
    """Workspace paths /Users/<user>/edwmigration_* owned by this user only."""
    home = f"/Users/{user.strip().strip('/')}"
    data = _cli_json(["databricks", "workspace", "list", home, "-o", "json"])
    rows: list[Any] = []
    if isinstance(data, dict):
        rows = data.get("objects") or data.get("items") or []
    elif isinstance(data, list):
        rows = data
    out: list[str] = []
    prefix = f"{home}/edwmigration_"
    for obj in rows:
        if not isinstance(obj, dict):
            continue
        path = str(obj.get("path") or obj.get("object_path") or "")
        if path.startswith(prefix):
            out.append(path)
    return out


def folders_from_local_runs(root: Path) -> list[str]:
    out: list[str] = []
    base = root / "agents" / "out"
    if not base.is_dir():
        return out
    for path in base.glob("*/notebooks.json"):
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        folder = str((data or {}).get("folder") or "").strip()
        if folder.startswith("/Users/") and "/edwmigration_" in folder:
            out.append(folder)
    return out


def delete_published(root: Path | None = None) -> list[str]:
    """Delete this user's edwmigration_* notebook folders. Returns deleted paths."""
    root = root or ROOT
    load_env(root)
    cli_env.apply_cli_auth()
    folders: set[str] = set(folders_from_local_runs(root))
    user = current_user_name()
    if user:
        folders.update(list_user_edw_folders(user))
    deleted: list[str] = []
    for folder in sorted(folders):
        print(f"[publish_run_notebooks] deleting {folder}", flush=True)
        rc = _run(["databricks", "workspace", "delete", folder, "--recursive"])
        if rc == 0:
            deleted.append(folder)
        else:
            print(f"[publish_run_notebooks] WARN: delete failed {folder}", flush=True)
    return deleted


def _run(args: list[str]) -> int:
    try:
        return subprocess.call(args)
    except OSError:
        return 1


def import_notebooks(folder: str, items: list[ImportItem]) -> list[str]:
    """mkdirs + SOURCE SQL import. Returns dest paths imported."""
    imported: list[str] = []
    layers = sorted({it.layer for it in items})
    _run(["databricks", "workspace", "mkdirs", folder])
    for layer in layers:
        _run(["databricks", "workspace", "mkdirs", f"{folder}/{layer}"])
    for it in items:
        dest = f"{folder}/{it.layer}/{it.dest_name}"
        rc = _run(
            [
                "databricks",
                "workspace",
                "import",
                dest,
                "--file",
                it.source,
                "--language",
                "SQL",
                "--format",
                "SOURCE",
                "--overwrite",
            ]
        )
        if rc == 0:
            imported.append(dest)
        else:
            print(f"[publish_run_notebooks] WARN: import failed {dest}", flush=True)
    return imported


def load_notebooks_json(run_id: str, root: Path | None = None) -> dict[str, Any]:
    path = notebooks_json_path(run_id, root)
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def save_notebooks_json(run_id: str, data: dict[str, Any], root: Path | None = None) -> Path:
    path = notebooks_json_path(run_id, root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")
    return path


def publish(
    run_id: str,
    root: Path | None = None,
    dry_run: bool = False,
    now: datetime | None = None,
) -> dict[str, Any]:
    root = root or ROOT
    load_env(root)
    cli_env.apply_cli_auth()
    existing = load_notebooks_json(run_id, root)
    date = folder_date_utc(existing, now=now)
    host = (os.environ.get("DATABRICKS_HOST") or "").rstrip("/")
    catalog = os.environ.get("DATABRICKS_CATALOG") or "edw_migration"
    plan = build_import_plan(root)
    user = existing.get("user") or ("" if dry_run else current_user_name())
    if dry_run and not user:
        user = "dry-run@example.com"
    folder = workspace_folder(user, date) if user else ""
    job_id = existing.get("job_id") or ("" if dry_run else lookup_job_id())
    imported: list[str] = []
    if not dry_run:
        if not user:
            print("[publish_run_notebooks] ERROR: current-user unknown (auth?)", file=sys.stderr)
            data = {
                "run_id": run_id,
                "folder_date": date,
                "error": "current-user unknown",
                "published": False,
            }
            save_notebooks_json(run_id, data, root)
            return data
        imported = import_notebooks(folder, plan)
    data = {
        "run_id": run_id,
        "folder_date": date,
        "user": user,
        "folder": folder,
        "folder_url": folder_url(host, folder) if host and folder else "",
        "catalog": catalog,
        "catalog_url": catalog_url(host, catalog) if host else "",
        "job_id": job_id or "",
        "job_url": job_url(host, job_id) if host and job_id else "",
        "imported": imported if not dry_run else [f"{folder}/{it.layer}/{it.dest_name}" for it in plan],
        "plan": [asdict(it) for it in plan],
        "published": (not dry_run) and bool(imported),
        "dry_run": dry_run,
    }
    save_notebooks_json(run_id, data, root)
    if data.get("folder_url"):
        print(f"Notebooks: {data['folder_url']}", flush=True)
    if data.get("catalog_url"):
        print(f"Catalog: {data['catalog_url']}", flush=True)
    if data.get("job_url"):
        print(f"Job: {data['job_url']}", flush=True)
    elif not dry_run:
        print("Job: appears after make deploy", flush=True)
    print(f"[publish_run_notebooks] {len(plan)} notebook(s) → {folder or '(no folder)'}", flush=True)
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", default="")
    parser.add_argument("--root", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--delete-published", action="store_true")
    args = parser.parse_args(argv)
    root = Path(args.root) if args.root else ROOT
    if args.delete_published:
        delete_published(root)
        return 0
    run_id = (args.run_id or "").strip()
    if not run_id:
        current = root / "agents" / "out" / "CURRENT_RUN"
        if current.is_file():
            run_id = current.read_text().strip()
    if not run_id:
        print("usage: publish_run_notebooks.py --run-id UUID", file=sys.stderr)
        return 2
    data = publish(run_id, root=root, dry_run=args.dry_run)
    if data.get("error") and not args.dry_run:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
