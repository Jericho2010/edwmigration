#!/usr/bin/env python3
"""Discover base tables (via UC foreign catalog) and user procs (via sqlcmd).

Writes agents/out/<run_id>/inventory.json and optionally prints SQL to load ops.migration_inventory.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from slugify import slugify_ident  # noqa: E402

SYSTEM_SCHEMAS = {
    "sys",
    "information_schema",
    "guest",
    "db_owner",
    "db_accessadmin",
    "db_securityadmin",
    "db_ddladmin",
    "db_backupoperator",
    "db_datareader",
    "db_datawriter",
    "db_denydatareader",
    "db_denydatawriter",
}


def load_env() -> None:
    env_path = ROOT / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def run_sql(sql: str) -> str:
    script = ROOT / "agents" / "tools" / "run_sql.sh"
    proc = subprocess.run(
        [str(script), "--sql", sql],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"run_sql failed: {proc.stderr or proc.stdout}")
    return proc.stdout


def discover_tables(foreign_catalog: str) -> list[dict]:
    sql = f"""
SELECT table_schema, table_name
FROM {foreign_catalog}.information_schema.tables
WHERE table_type = 'BASE TABLE'
ORDER BY table_schema, table_name
"""
    out = run_sql(sql)
    tables: list[dict] = []
    # run_sql.sh prints TSV: header row then data rows
    for i, line in enumerate(out.splitlines()):
        line = line.strip()
        if not line or line.startswith("[run_sql]"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        schema, name = parts[0], parts[1]
        if i == 0 and schema.lower() in {"table_schema", "table_name"}:
            continue
        if schema.lower() in SYSTEM_SCHEMAS:
            continue
        tables.append(
            {
                "object_type": "table",
                "source_schema": schema,
                "source_name": name,
                "landing_name": slugify_ident(schema, name),
                "skip": False,
                "skip_reason": None,
            }
        )
    return tables


def export_procs(out_dir: Path) -> list[dict]:
    server = os.environ.get("AZ_SQL_SERVER") or ""
    admin = os.environ.get("AZ_SQL_ADMIN", "edwadmin")
    password = os.environ.get("AZ_SQL_PASSWORD", "")
    db = os.environ.get("AZ_SQL_DB", "WideWorldImportersDW")
    if not server or not password:
        print("[discover] AZ_SQL_SERVER/PASSWORD missing — skipping proc export", file=sys.stderr)
        return []

    out_dir.mkdir(parents=True, exist_ok=True)
    query = """
SET NOCOUNT ON;
SELECT s.name AS schema_name, o.name AS proc_name, m.definition AS definition
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'P'
  AND s.name NOT IN ('sys','guest','INFORMATION_SCHEMA')
ORDER BY s.name, o.name;
"""
    server_arg = f"tcp:{server}.database.windows.net,1433"
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as tf:
        tf.write(query)
        qpath = tf.name
    try:
        proc = subprocess.run(
            [
                "sqlcmd",
                "-S",
                server_arg,
                "-U",
                admin,
                "-P",
                password,
                "-d",
                db,
                "-C",
                "-l",
                "60",
                "-h",
                "-1",
                "-W",
                "-y",
                "0",
                "-i",
                qpath,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        os.unlink(qpath)

    if proc.returncode != 0:
        print(f"[discover] sqlcmd proc export failed: {proc.stderr}", file=sys.stderr)
        return []

    # sqlcmd with multi-line definitions is brittle; prefer calling export_proc_source.sh
    export_sh = ROOT / "legacy" / "procs" / "export_proc_source.sh"
    if export_sh.is_file():
        subprocess.run([str(export_sh)], cwd=str(ROOT), check=False)
        procs = []
        for p in sorted((ROOT / "legacy" / "procs").glob("*.sql")):
            if p.name.startswith("export"):
                continue
            # Schema.Proc.sql
            stem = p.stem
            if "." not in stem:
                continue
            schema, name = stem.split(".", 1)
            dest = out_dir / p.name
            dest.write_text(p.read_text())
            procs.append(
                {
                    "object_type": "proc",
                    "source_schema": schema,
                    "source_name": name,
                    "landing_name": None,
                    "skip": False,
                    "skip_reason": None,
                    "source_path": str(dest.relative_to(ROOT)),
                }
            )
        return procs
    return []


def main() -> int:
    load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--foreign-catalog", default=os.environ.get("FOREIGN_CATALOG", "wwi_dw_fed"))
    ap.add_argument("--warn-threshold", type=int, default=int(os.environ.get("INVENTORY_WARN_THRESHOLD", "200")))
    args = ap.parse_args()

    out_dir = ROOT / "agents" / "out" / args.run_id
    out_dir.mkdir(parents=True, exist_ok=True)
    procs_dir = out_dir / "procs"

    tables = discover_tables(args.foreign_catalog)
    procs = export_procs(procs_dir)

    inventory = {
        "run_id": args.run_id,
        "discovered_at": datetime.now(timezone.utc).isoformat(),
        "foreign_catalog": args.foreign_catalog,
        "tables": tables,
        "procs": procs,
        "tables_total": len(tables),
        "procs_total": len(procs),
        "warn_threshold": args.warn_threshold,
        "requires_confirm": len(tables) > args.warn_threshold,
    }
    path = out_dir / "inventory.json"
    path.write_text(json.dumps(inventory, indent=2) + "\n")
    print(f"[discover] wrote {path} tables={len(tables)} procs={len(procs)}")
    if inventory["requires_confirm"]:
        print(
            f"[discover] WARNING: {len(tables)} tables exceeds warn threshold {args.warn_threshold}. "
            "Confirm before land.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
