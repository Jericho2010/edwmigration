#!/usr/bin/env python3
"""Validate a JSON artifact against an agents/contracts schema.

Usage:
  python3 agents/tools/validate_artifact.py \\
    --schema agents/contracts/convert_result.schema.json \\
    --file agents/out/<run_id>/convert/item-001.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def validate(doc: object, schema: dict) -> list[str]:
    try:
        from jsonschema import Draft7Validator
    except ImportError:
        errors: list[str] = []
        if isinstance(doc, dict):
            for key in schema.get("required", []):
                if key not in doc:
                    errors.append(f"missing required property: {key}")
        elif schema.get("type") == "array" and not isinstance(doc, list):
            errors.append("expected JSON array")
        return errors
    return [e.message for e in Draft7Validator(schema).iter_errors(doc)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--schema", required=True, help="Path to JSON Schema (draft-07)")
    ap.add_argument("--file", required=True, help="JSON file to validate")
    args = ap.parse_args()

    schema_path = Path(args.schema)
    if not schema_path.is_absolute():
        schema_path = ROOT / schema_path
    file_path = Path(args.file)
    if not file_path.is_absolute():
        file_path = ROOT / file_path

    if not schema_path.is_file():
        print(f"[validate_artifact] schema not found: {schema_path}", file=sys.stderr)
        return 1
    if not file_path.is_file():
        print(f"[validate_artifact] file not found: {file_path}", file=sys.stderr)
        return 1

    schema = json.loads(schema_path.read_text())
    doc = json.loads(file_path.read_text())
    errors = validate(doc, schema)
    if errors:
        print(f"[validate_artifact] FAIL {file_path}", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(f"[validate_artifact] OK {file_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
