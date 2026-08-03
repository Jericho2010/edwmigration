#!/usr/bin/env python3
"""Discover base tables (via UC foreign catalog) and procs/routines.

Tables: always via foreign catalog information_schema.
SQL Server procs: sqlcmd / export_proc_source.sh when credentials available.
MySQL routines: mysql CLI when available; otherwise skip with routines_skipped_reason.

Writes agents/out/<run_id>/inventory.json.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
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
    "mysql",
    "performance_schema",
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


def resolve_source() -> dict:
    """Normalize SOURCE_* from SOURCE_* and/or AZ_SQL_*."""
    st = (os.environ.get("SOURCE_TYPE") or "sqlserver").strip().lower()
    host = os.environ.get("SOURCE_HOST") or ""
    port = os.environ.get("SOURCE_PORT") or ""
    database = os.environ.get("SOURCE_DATABASE") or ""
    user = os.environ.get("SOURCE_USER") or ""
    password = os.environ.get("SOURCE_PASSWORD") or ""

    if st == "sqlserver":
        if not host:
            host = os.environ.get("AZ_SQL_HOST") or ""
            if not host and os.environ.get("AZ_SQL_SERVER"):
                host = f"{os.environ['AZ_SQL_SERVER']}.database.windows.net"
        port = port or "1433"
        database = database or os.environ.get("AZ_SQL_DB") or "WideWorldImportersDW"
        user = user or os.environ.get("AZ_SQL_ADMIN") or "edwadmin"
        password = password or os.environ.get("AZ_SQL_PASSWORD") or ""
        foreign = os.environ.get("FOREIGN_CATALOG") or "wwi_dw_fed"
    elif st == "mysql":
        port = port or "3306"
        foreign = os.environ.get("FOREIGN_CATALOG") or "mysql_fed"
    else:
        raise SystemExit(f"SOURCE_TYPE must be sqlserver or mysql (got {st})")

    return {
        "source_type": st,
        "host": host,
        "port": port,
        "database": database,
        "user": user,
        "password": password,
        "foreign_catalog": foreign,
        "az_sql_server": os.environ.get("AZ_SQL_SERVER") or "",
    }


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


def export_procs_sqlserver(out_dir: Path, src: dict) -> list[dict]:
    server = src["az_sql_server"]
    admin = src["user"]
    password = src["password"]
    db = src["database"]
    if not server or not password:
        # Fall back: host may be FQDN without AZ_SQL_SERVER
        if src["host"] and password:
            server_arg = f"tcp:{src['host']},{src['port']}"
        else:
            print(
                "[discover] SQL Server credentials missing — skipping proc export",
                file=sys.stderr,
            )
            return []
    else:
        server_arg = f"tcp:{server}.database.windows.net,1433"

    out_dir.mkdir(parents=True, exist_ok=True)
    export_sh = ROOT / "legacy" / "procs" / "export_proc_source.sh"
    if export_sh.is_file():
        subprocess.run([str(export_sh)], cwd=str(ROOT), check=False)
        procs = []
        for p in sorted((ROOT / "legacy" / "procs").glob("*.sql")):
            if p.name.startswith("export"):
                continue
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

    # Minimal sqlcmd fallback if export script missing
    query = """
SET NOCOUNT ON;
SELECT s.name AS schema_name, o.name AS proc_name
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'P'
  AND s.name NOT IN ('sys','guest','INFORMATION_SCHEMA')
ORDER BY s.name, o.name;
"""
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as tf:
        tf.write(query)
        qpath = tf.name
    try:
        if not shutil.which("sqlcmd"):
            print("[discover] sqlcmd not found — skipping proc export", file=sys.stderr)
            return []
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
        print(f"[discover] sqlcmd proc list failed: {proc.stderr}", file=sys.stderr)
        return []
    return []


def export_routines_mysql(out_dir: Path, src: dict) -> tuple[list[dict], str | None]:
    """Export MySQL routines via mysql CLI. Returns (procs, skip_reason)."""
    if not shutil.which("mysql"):
        return [], "mysql CLI not available — routines skipped; table land + reconcile still proceed"

    if not src["host"] or not src["user"] or not src["password"] or not src["database"]:
        return [], "SOURCE_* incomplete for mysql routine export — routines skipped"

    out_dir.mkdir(parents=True, exist_ok=True)
    # List routines (PROCEDURE + FUNCTION)
    list_sql = (
        "SELECT ROUTINE_SCHEMA, ROUTINE_NAME, ROUTINE_TYPE "
        "FROM information_schema.ROUTINES "
        f"WHERE ROUTINE_SCHEMA = '{src['database'].replace(chr(39), chr(39)+chr(39))}' "
        "ORDER BY ROUTINE_TYPE, ROUTINE_NAME;"
    )
    list_cmd = [
        "mysql",
        "-h",
        src["host"],
        "-P",
        str(src["port"]),
        "-u",
        src["user"],
        f"-p{src['password']}",
        "-N",
        "-B",
        "-e",
        list_sql,
    ]
    listed = subprocess.run(list_cmd, capture_output=True, text=True, check=False)
    if listed.returncode != 0:
        msg = (listed.stderr or listed.stdout or "mysql list failed").strip().splitlines()[-1:]
        reason = msg[0] if msg else "mysql routine list failed"
        print(f"[discover] {reason}", file=sys.stderr)
        return [], f"mysql routine list failed — routines skipped ({reason})"

    procs: list[dict] = []
    for line in listed.stdout.splitlines():
        parts = line.strip().split("\t")
        if len(parts) < 3:
            continue
        schema, name, rtype = parts[0], parts[1], parts[2]
        show = f"SHOW CREATE {rtype} `{schema}`.`{name}`;"
        show_cmd = [
            "mysql",
            "-h",
            src["host"],
            "-P",
            str(src["port"]),
            "-u",
            src["user"],
            f"-p{src['password']}",
            "-N",
            "-B",
            "-e",
            show,
        ]
        shown = subprocess.run(show_cmd, capture_output=True, text=True, check=False)
        if shown.returncode != 0:
            print(f"[discover] SHOW CREATE failed for {schema}.{name}", file=sys.stderr)
            continue
        # SHOW CREATE output: name \t create_stmt (may span; -B keeps tabs)
        create_sql = shown.stdout
        if "\t" in create_sql:
            create_sql = create_sql.split("\t", 1)[-1]
        fname = f"{schema}.{name}.sql"
        dest = out_dir / fname
        dest.write_text(f"-- MySQL {rtype} {schema}.{name}\n{create_sql.strip()}\n")
        procs.append(
            {
                "object_type": "proc" if rtype.upper() == "PROCEDURE" else "function",
                "source_schema": schema,
                "source_name": name,
                "landing_name": None,
                "skip": False,
                "skip_reason": None,
                "source_path": str(dest.relative_to(ROOT)),
                "routine_type": rtype.upper(),
            }
        )
    return procs, None


def main() -> int:
    load_env()
    src = resolve_source()
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-id", required=True)
    ap.add_argument(
        "--foreign-catalog",
        default=os.environ.get("FOREIGN_CATALOG") or src["foreign_catalog"],
    )
    ap.add_argument(
        "--warn-threshold",
        type=int,
        default=int(os.environ.get("INVENTORY_WARN_THRESHOLD", "200")),
    )
    args = ap.parse_args()

    out_dir = ROOT / "agents" / "out" / args.run_id
    out_dir.mkdir(parents=True, exist_ok=True)
    procs_dir = out_dir / "procs"

    tables = discover_tables(args.foreign_catalog)
    routines_skipped_reason: str | None = None

    if src["source_type"] == "mysql":
        procs, routines_skipped_reason = export_routines_mysql(procs_dir, src)
    else:
        procs = export_procs_sqlserver(procs_dir, src)

    inventory = {
        "run_id": args.run_id,
        "discovered_at": datetime.now(timezone.utc).isoformat(),
        "source_type": src["source_type"],
        "foreign_catalog": args.foreign_catalog,
        "tables": tables,
        "procs": procs,
        "tables_total": len(tables),
        "procs_total": len(procs),
        "warn_threshold": args.warn_threshold,
        "requires_confirm": len(tables) > args.warn_threshold,
        "routines_skipped_reason": routines_skipped_reason,
    }
    path = out_dir / "inventory.json"
    path.write_text(json.dumps(inventory, indent=2) + "\n")
    print(
        f"[discover] wrote {path} source_type={src['source_type']} "
        f"tables={len(tables)} procs={len(procs)}"
    )
    if routines_skipped_reason:
        print(f"[discover] NOTE: {routines_skipped_reason}", file=sys.stderr)
    if inventory["requires_confirm"]:
        print(
            f"[discover] WARNING: {len(tables)} tables exceeds warn threshold {args.warn_threshold}. "
            "Confirm before land.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
