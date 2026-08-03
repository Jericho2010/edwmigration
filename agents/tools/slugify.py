#!/usr/bin/env python3
"""Stable snake_case landing names from source schema + table."""
from __future__ import annotations

import re


def _clean(s: str) -> str:
    raw = s.strip().lower().replace(" ", "_").replace("-", "_").replace(".", "_")
    raw = re.sub(r"[^a-z0-9_]+", "_", raw)
    return re.sub(r"_+", "_", raw).strip("_")


def slugify_ident(schema: str, name: str) -> str:
    """Derive bronze/source_fed landing name.

    Convention (generic, not WWI-hardcoded beyond common DW schema labels):
      Dimension.<Name> -> dim_<name>
      Fact.<Name>      -> fact_<name>
      otherwise        -> <schema>_<name>
    """
    s = schema.strip()
    n = _clean(name)
    sl = s.lower()
    if sl == "dimension":
        raw = f"dim_{n}"
    elif sl == "fact":
        raw = f"fact_{n}"
    else:
        raw = f"{_clean(s)}_{n}"
    if not raw:
        raw = "object"
    if raw[0].isdigit():
        raw = f"t_{raw}"
    return raw


def backtick(ident: str) -> str:
    return "`" + ident.replace("`", "``") + "`"


def fqn(catalog: str, schema: str, table: str) -> str:
    return f"{backtick(catalog)}.{backtick(schema)}.{backtick(table)}"
