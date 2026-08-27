#!/usr/bin/env python3
"""Unit tests for persist_reconcile_report ops SQL (no warehouse)."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

import persist_reconcile_report as persist

SAMPLE = Path(__file__).resolve().parents[2] / "agents" / "samples" / "run" / "reconcile_report.json"


class BuildUpsertSqlTests(unittest.TestCase):
    def test_delete_then_insert_uses_table_field(self) -> None:
        doc = json.loads(SAMPLE.read_text())
        sql = persist.build_upsert_sql("edw_migration", doc["run_id"], doc["checks"])
        self.assertIn(
            "DELETE FROM `edw_migration`.ops.reconcile_results WHERE run_id = "
            f"'{doc['run_id']}';",
            sql,
        )
        self.assertIn("bronze_vs_source_fact_sale_rowcount", sql)
        self.assertIn("bronze.fact_sale", sql)
        self.assertIn("(check_id, table_name, expected, actual, delta, result, run_id, ts)", sql)
        self.assertIn("current_timestamp()", sql)

    def test_escapes_quotes(self) -> None:
        sql = persist.build_upsert_sql(
            "c",
            "rid",
            [
                {
                    "check_id": "x",
                    "table": "bronze.t",
                    "expected": "O'Brien",
                    "actual": "1",
                    "delta": "0",
                    "result": "pass",
                }
            ],
        )
        self.assertIn("'O''Brien'", sql)


if __name__ == "__main__":
    unittest.main()
