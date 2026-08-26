#!/usr/bin/env python3
"""Overlay Databricks CLI auth when .env sets HOST without TOKEN.

.env often exports DATABRICKS_HOST + WAREHOUSE_ID but no PAT. The CLI then
ignores ~/.databrickscfg. This helper copies env from a *valid* profile whose
host matches DATABRICKS_HOST (prefer DEFAULT). Never targets another workspace.

Usage:
  eval "$(python3 agents/tools/databricks_cli_env.py --export)"
  python3 -c "import databricks_cli_env as a; a.apply_cli_auth()"
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from typing import Any
from urllib.parse import urlparse


def normalize_host(host: str) -> str:
    h = (host or "").strip().rstrip("/")
    if not h:
        return ""
    if "://" not in h:
        h = "https://" + h
    parsed = urlparse(h)
    netloc = (parsed.netloc or parsed.path).lower()
    return netloc.split("@")[-1]


def _run_json(args: list[str]) -> Any | None:
    try:
        raw = subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError):
        return None
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def list_profiles() -> list[dict[str, str]]:
    """Return [{name, host, valid}, ...] from `databricks auth profiles`."""
    data = _run_json(["databricks", "auth", "profiles", "-o", "json"])
    rows: list[dict[str, str]] = []
    if isinstance(data, dict):
        items = data.get("profiles") or data.get("items") or []
        if isinstance(items, list):
            for p in items:
                if not isinstance(p, dict):
                    continue
                rows.append(
                    {
                        "name": str(p.get("name") or p.get("profile") or ""),
                        "host": str(p.get("host") or p.get("url") or ""),
                        "valid": str(p.get("valid") or p.get("status") or "").lower(),
                    }
                )
            if rows:
                return rows
    elif isinstance(data, list):
        for p in data:
            if isinstance(p, dict):
                rows.append(
                    {
                        "name": str(p.get("name") or p.get("profile") or ""),
                        "host": str(p.get("host") or ""),
                        "valid": str(p.get("valid") or "").lower(),
                    }
                )
        if rows:
            return rows

    try:
        text = subprocess.check_output(
            ["databricks", "auth", "profiles"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("name"):
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        name, host, valid = parts[0], parts[1], parts[-1]
        rows.append({"name": name, "host": host, "valid": valid.lower()})
    return rows


def matching_profile(host: str, profiles: list[dict[str, str]] | None = None) -> str | None:
    want = normalize_host(host)
    if not want:
        return None
    profiles = profiles if profiles is not None else list_profiles()
    matches = [
        p
        for p in profiles
        if normalize_host(p.get("host") or "") == want
        and str(p.get("valid") or "").lower() in ("yes", "true", "1", "valid")
    ]
    if not matches:
        # Fall back to any same-host profile if validity column is missing.
        matches = [p for p in profiles if normalize_host(p.get("host") or "") == want]
    if not matches:
        return None
    for p in matches:
        if p.get("name") == "DEFAULT":
            return "DEFAULT"
    return matches[0].get("name") or None


def auth_env_for_profile(profile: str) -> dict[str, str]:
    data = _run_json(["databricks", "auth", "env", "--profile", profile])
    if isinstance(data, dict):
        inner = data.get("env") if isinstance(data.get("env"), dict) else data
        out: dict[str, str] = {}
        for k, v in inner.items():
            if v is None:
                continue
            key = str(k)
            if key.startswith("DATABRICKS_"):
                out[key] = str(v)
        return out
    return {}


def apply_cli_auth(host: str | None = None) -> dict[str, str]:
    """Mutate os.environ. Returns keys applied (values not logged by caller)."""
    if (os.environ.get("DATABRICKS_TOKEN") or "").strip():
        return {}
    host = host if host is not None else (os.environ.get("DATABRICKS_HOST") or "")
    profile = matching_profile(host)
    if not profile:
        return {}
    overlay = auth_env_for_profile(profile)
    token = (overlay.get("DATABRICKS_TOKEN") or "").strip()
    if not token:
        return {}
    applied: dict[str, str] = {}
    for key in ("DATABRICKS_TOKEN", "DATABRICKS_AUTH_TYPE", "DATABRICKS_CONFIG_PROFILE"):
        val = overlay.get(key)
        if val:
            os.environ[key] = val
            applied[key] = val
    if overlay.get("DATABRICKS_HOST") and not (os.environ.get("DATABRICKS_HOST") or "").strip():
        os.environ["DATABRICKS_HOST"] = overlay["DATABRICKS_HOST"]
        applied["DATABRICKS_HOST"] = overlay["DATABRICKS_HOST"]
    os.environ.setdefault("DATABRICKS_CONFIG_PROFILE", profile)
    return applied


def export_bash() -> str:
    apply_cli_auth()
    keys = ("DATABRICKS_TOKEN", "DATABRICKS_AUTH_TYPE", "DATABRICKS_CONFIG_PROFILE")
    lines = []
    for key in keys:
        val = os.environ.get(key)
        if val:
            lines.append(f"export {key}={shlex.quote(val)}")
    return "\n".join(lines) + ("\n" if lines else "")


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] in ("-h", "--help"):
        print(__doc__.strip(), file=sys.stderr)
        return 0
    if "--export" in args:
        sys.stdout.write(export_bash())
        return 0
    apply_cli_auth()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
