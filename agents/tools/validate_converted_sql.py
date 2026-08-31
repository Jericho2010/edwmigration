#!/usr/bin/env python3
"""Validate converted Spark SQL before convert JSON / validate_artifact.

Fails on CREATE PROCEDURE, federated catalog writes/reads, missing land-first
bronze reads, missing header, missing smoke SELECT.

Usage:
  python3 agents/tools/validate_converted_sql.py --file databricks/gold/20_x.sql
  python3 agents/tools/validate_converted_sql.py --file path.sql --expect-path databricks/gold/20_x.sql
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

HEADER_KEYS = ("Source dialect", "Classification")
FED_NAMES = (
    "source_fed",
    "wwi_dw_fed",
    "sqlserver_fed",
    "mysql_fed",
    os.environ.get("FOREIGN_CATALOG") or "",
)
FED_ALT = "|".join(re.escape(n) for n in FED_NAMES if n)
FED_WRITE = re.compile(
    rf"\b(INSERT|MERGE|CREATE\s+OR\s+REPLACE\s+TABLE|DELETE)\b[^;]*\b({FED_ALT})\b",
    re.I | re.S,
)
WINDOW_OVER = re.compile(r"\bOVER\s*\(", re.I)
CREATE_PROC = re.compile(r"\bCREATE\s+(OR\s+ALTER\s+)?PROC(EDURE)?\b", re.I)
BRONZE = re.compile(r"\b(bronze\.|__UC_CATALOG__\.bronze\.)", re.I)
SMOKE_SELECT = re.compile(r"\bSELECT\b", re.I)
FOUR_PART = re.compile(r"\[[^\]]+\]\s*\.\s*\[[^\]]+\]\s*\.\s*\[[^\]]+\]\s*\.\s*\[[^\]]+\]")
FROM_FED = re.compile(rf"\bFROM\s+({FED_ALT})\b", re.I) if FED_ALT else re.compile(r"(?!)")
# Parallel job tasks racing CREATE of these shared tables fail with
# TABLE_OR_VIEW_ALREADY_EXISTS even when OR REPLACE is present.
BOOKKEEPING_CREATE_RE = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?TABLE\s+[^\s;]*silver\."
    r"(integration_lineage|integration_etl_cutoff)\b",
    re.I,
)
BOOKKEEPING_TABLES = ("integration_lineage", "integration_etl_cutoff")


def validate_sql(text: str, *, expect_path: str = "") -> list[str]:
    errors: list[str] = []
    header = "\n".join(text.splitlines()[:20])
    for key in HEADER_KEYS:
        if key.lower() not in header.lower():
            errors.append(f"missing header field: {key}")
    if CREATE_PROC.search(text):
        errors.append("CREATE PROCEDURE is not allowed")
    if FOUR_PART.search(text):
        errors.append("federated four-part name is not allowed")
    if FED_WRITE.search(text):
        errors.append("writes to federated/source_fed catalog are not allowed")
    if WINDOW_OVER.search(text) and FROM_FED.search(text):
        errors.append("window query must not SELECT FROM a federated catalog (read bronze)")
    if FROM_FED.search(text):
        errors.append("FROM federated catalog is not land-first; read bronze Delta")
    if not BRONZE.search(text):
        errors.append("land-first: SQL must reference bronze. or __UC_CATALOG__.bronze.")
    if not SMOKE_SELECT.search(text):
        errors.append("missing smoke SELECT")
    if expect_path:
        # caller already chose the file; this is a documentation check
        pass
    return errors


def bookkeeping_create_files(sql_dir: Path) -> dict[str, list[str]]:
    """Map shared silver bookkeeping tables to convert files that CREATE them."""
    found: dict[str, list[str]] = {name: [] for name in BOOKKEEPING_TABLES}
    if not sql_dir.is_dir():
        return found
    for path in sorted(sql_dir.glob("*.sql")):
        text = path.read_text()
        for match in BOOKKEEPING_CREATE_RE.finditer(text):
            found[match.group(1).lower()].append(path.name)
    return found


def bookkeeping_create_errors(sql_dir: Path) -> list[str]:
    """At most one convert file may CREATE each shared silver bookkeeping table."""
    errors: list[str] = []
    for table, files in bookkeeping_create_files(sql_dir).items():
        if len(files) > 1:
            errors.append(
                f"{table} CREATE appears in {len(files)} files (need ≤1): {', '.join(files)}"
            )
    return errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--file", required=True)
    ap.add_argument("--expect-path", default="")
    args = ap.parse_args()
    path = Path(args.file)
    if not path.is_absolute():
        path = ROOT / path
    if not path.is_file():
        print(f"[validate_converted_sql] missing {path}", file=sys.stderr)
        return 1
    if args.expect_path:
        rel = str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)
        exp = args.expect_path.replace("\\", "/")
        if rel.replace("\\", "/") != exp:
            print(
                f"[validate_converted_sql] file {rel} != --expect-path {exp}",
                file=sys.stderr,
            )
            return 1
    errors = validate_sql(path.read_text(), expect_path=args.expect_path)
    if errors:
        print("[validate_converted_sql] FAIL:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"[validate_converted_sql] OK {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
