#!/usr/bin/env python3
"""Shared Gate / dashboard vocabulary.

Keep these strings identical in persist_manifest, MLflow stage(), dashboard SQL,
and Genie certified questions so `gate=pass` and `gate=ship` cannot drift.

Dashboard / Genie SQL (Spark):
  CASE WHEN lower(gate) IN ('pass', 'ship') THEN 1 ELSE 0 END AS gate_pass
"""
from __future__ import annotations

GATE_SHIP_VALUES = frozenset({"pass", "ship"})
GATE_FAIL_VALUES = frozenset({"fail", "failed"})

# Spark SQL fragment used by the Control Plane Gate tile and Genie.
GATE_PASS_SQL = "CASE WHEN lower(gate) IN ('pass', 'ship') THEN 1 ELSE 0 END"

LIFECYCLE_EVENTS = (
    "started",
    "completed",
    "handoff",
    "blocked",
    "failed",
    "subagentstart",
    "subagentstop",
)

LIFECYCLE_EVENT_SQL = (
    "lower(event) IN ('started','completed','handoff','blocked','failed',"
    "'subagentstart','subagentstop')"
)

# load_control bar: skip empty staging copies so the chart is facts/dims.
LOAD_CONTROL_BAR_SQL = (
    "COALESCE(row_count, 0) > 0 AND lower(table_name) NOT LIKE '%staging%'"
)


def gate_is_ship(gate: str | None) -> bool:
    g = (gate or "").strip().lower()
    if not g:
        return False
    token = g.split()[0].strip(",.;:")
    if token in GATE_FAIL_VALUES or token.startswith("fail"):
        return False
    if token in GATE_SHIP_VALUES:
        return True
    return "pass" in g or "ship" in g


def gate_pass_value(gate: str | None) -> float:
    """1.0 when gate is pass/ship, else 0.0. Used by persist + MLflow metrics."""
    return 1.0 if gate_is_ship(gate) else 0.0
