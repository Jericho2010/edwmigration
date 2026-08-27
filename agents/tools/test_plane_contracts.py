#!/usr/bin/env python3
"""Plane-contract tests: dashboard SQL, vocab, land run_id, handoff, allocate, merge wave."""
from __future__ import annotations

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "agents" / "tools"))

import allocate_target_paths as alloc  # noqa: E402
import edw_handoff as hand  # noqa: E402
import edw_vocab as vocab  # noqa: E402
import generate_from_inventory as gen  # noqa: E402
import merge_convert_results as merge  # noqa: E402
import persist_manifest as persist  # noqa: E402
import validate_backlog_paths as vbp  # noqa: E402
import validate_converted_sql as vcs  # noqa: E402


class VocabTests(unittest.TestCase):
    def test_pass_is_ship(self):
        self.assertEqual(vocab.gate_pass_value("pass"), 1.0)
        self.assertEqual(vocab.gate_pass_value("ship"), 1.0)
        self.assertEqual(vocab.gate_pass_value("fail"), 0.0)
        self.assertIn("pass", vocab.GATE_PASS_SQL)
        self.assertIn("ship", vocab.GATE_PASS_SQL)

    def test_persist_metric_uses_vocab(self):
        self.assertEqual(persist.gate_pass_value("pass"), 1.0)


class DashboardContractTests(unittest.TestCase):
    def setUp(self):
        dash = json.loads(
            (ROOT / "databricks" / "dashboards" / "agent_events.lvdash.json").read_text()
        )
        self.queries = {
            d["name"]: "".join(d.get("queryLines") or []) for d in dash["datasets"]
        }
        self.layout = dash["pages"][0]["layout"]

    def test_gate_case_pass_and_ship(self):
        q = self.queries["gate_hero"]
        self.assertIn("lower(gate) IN ('pass', 'ship')", q)

    def test_ship_widget_title(self):
        titles = json.dumps(self.layout)
        self.assertIn('"displayName": "SHIP"', titles)

    def test_heroes_use_live_ops(self):
        self.assertIn("load_control", self.queries["tables_landed_hero"])
        self.assertIn("proc_conversion_map", self.queries["procs_converted_hero"])
        self.assertIn("NOT LIKE '%staging%'", self.queries["tables_landed"])

    def test_handoff_dataset(self):
        self.assertIn("handoff", self.queries["handoffs"])
        self.assertIn("get_json_object", self.queries["handoffs"])

    def test_lifecycle_filter(self):
        self.assertIn("subagentstart", self.queries["events_by_agent"])
        self.assertIn("handoff", self.queries["latest_events"])


class LandSqlTests(unittest.TestCase):
    def test_emit_land_includes_run_id_and_fed_name(self):
        sql = gen.emit_land(
            [
                {
                    "source_schema": "Dimension",
                    "source_name": "Payment Method",
                    "landing_name": "dim_payment_method",
                    "skip": False,
                }
            ],
            "c",
            "f",
            "azure_sql",
            run_id="run-abc",
        )
        self.assertIn("v_run_id", sql)
        self.assertIn("run_id", sql)
        self.assertIn("PaymentMethod", sql)
        self.assertNotIn("Payment Method", sql.split("FROM", 1)[-1] if "FROM" in sql else sql)
        self.assertIn("DELETE FROM", sql)
        self.assertIn("run_id = v_run_id", sql)


class HandoffTests(unittest.TestCase):
    def test_roundtrip_and_arrow(self):
        payload = hand.handoff_detail(
            from_agent="coordinator",
            to_agent="convert",
            item_id="item-015",
            action="launch",
            artifact="databricks/gold/40_migrate_order.sql",
            outcome="ok",
        )
        raw = hand.format_detail(payload)
        parsed = hand.parse_detail(raw)
        self.assertEqual(parsed["from"], "coordinator")
        self.assertIn("→", hand.format_arrow(payload))
        self.assertEqual(hand.mlflow_status_for_outcome("blocked"), "OK")
        self.assertEqual(hand.mlflow_status_for_outcome("fail"), "ERROR")

    def test_required_callers_emit_handoff(self):
        tools = ROOT / "agents" / "tools"
        must_call = (
            "persist_backlog.py",
            "persist_manifest.py",
            "persist_reconcile_report.py",
            "merge_convert_results.py",
            "dual_write_agent_lifecycle.sh",
            "wait_job_run.sh",
        )
        for name in must_call:
            text = (tools / name).read_text()
            self.assertTrue(
                "emit_handoff" in text or "edw_handoff.py" in text,
                msg=f"{name} must call emit_handoff",
            )
        launch = (tools / "launch_convert_wave.sh").read_text()
        self.assertIn("dual_write_agent_lifecycle.sh", launch)


class AllocateTests(unittest.TestCase):
    def test_assigns_from_20_on_empty_root(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "databricks" / "silver").mkdir(parents=True)
            (root / "databricks" / "gold").mkdir(parents=True)
            backlog = [
                {
                    "item_id": "item-a",
                    "legacy_proc": "dbo.MigrateCity",
                    "classification": "migrate",
                    "target_layer": "silver",
                    "target_path": "",
                    "status": "pending",
                },
                {
                    "item_id": "item-b",
                    "legacy_proc": "dbo.MigrateOrder",
                    "classification": "migrate",
                    "target_layer": "gold",
                    "target_path": "",
                    "status": "pending",
                },
            ]
            out = alloc.allocate(backlog, root=root)
            paths = [i["target_path"] for i in out]
            self.assertEqual(len(set(paths)), 2)
            for tp in paths:
                m = re.search(r"/(\d+)_", tp)
                self.assertIsNotNone(m)
                self.assertGreaterEqual(int(m.group(1)), 20)


class ValidateSqlTests(unittest.TestCase):
    def test_fails_create_procedure_and_fed_window(self):
        bad = """
-- Source dialect: tsql
-- Classification: migrate
CREATE PROCEDURE dbo.P AS BEGIN SELECT 1 END;
SELECT x, ROW_NUMBER() OVER (ORDER BY id) FROM wwi_dw_fed.Dimension.City;
"""
        errors = vcs.validate_sql(bad)
        self.assertTrue(any("PROCEDURE" in e for e in errors))
        self.assertTrue(any("federated" in e.lower() or "wwi_dw_fed" in e for e in errors))

    def test_ok_bronze_land_first(self):
        good = """
-- Source dialect: tsql
-- Classification: migrate
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.x AS
SELECT * FROM __UC_CATALOG__.bronze.dim_city;
SELECT COUNT(*) FROM __UC_CATALOG__.gold.x;
"""
        self.assertEqual(vcs.validate_sql(good), [])


class ValidateBacklogPathTests(unittest.TestCase):
    def test_rejects_duplicates(self):
        errors = vbp.validate(
            [
                {
                    "item_id": "a",
                    "target_path": "databricks/silver/20_foo.sql",
                    "status": "pending",
                    "target_layer": "silver",
                },
                {
                    "item_id": "b",
                    "target_path": "databricks/silver/20_foo.sql",
                    "status": "pending",
                    "target_layer": "silver",
                },
            ]
        )
        self.assertTrue(any("duplicate" in e for e in errors))

    def test_accepts_20_prefix(self):
        errors = vbp.validate(
            [
                {
                    "item_id": "a",
                    "target_path": "databricks/silver/20_foo.sql",
                    "status": "pending",
                    "target_layer": "silver",
                }
            ]
        )
        self.assertEqual(errors, [])


class MergeWaveTests(unittest.TestCase):
    def test_missing_json_fails_only_for_wave_paths(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "wave-1"
            run = root / "agents" / "out" / run_id
            (run / "convert").mkdir(parents=True)
            backlog = [
                {
                    "item_id": "item-wave",
                    "legacy_proc": "dbo.A",
                    "target_path": "databricks/gold/40_migrate_a.sql",
                    "target_layer": "gold",
                    "status": "pending",
                },
                {
                    "item_id": "item-other",
                    "legacy_proc": "dbo.B",
                    "target_path": "databricks/gold/41_migrate_b.sql",
                    "target_layer": "gold",
                    "status": "pending",
                },
            ]
            (run / "migration_backlog.json").write_text(json.dumps(backlog))
            (run / "convert_wave.json").write_text(
                json.dumps({"item_ids": ["item-wave"], "target_paths": [backlog[0]["target_path"]]})
            )
            orig_root = merge.ROOT
            merge.ROOT = root
            try:
                with self.assertRaises(FileNotFoundError):
                    merge.merge(run_id, skip_ops=True)
            finally:
                merge.ROOT = orig_root

    def test_no_wave_file_does_not_require_json(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "nowave-1"
            run = root / "agents" / "out" / run_id
            (run / "convert").mkdir(parents=True)
            backlog = [
                {
                    "item_id": "item-x",
                    "legacy_proc": "dbo.A",
                    "target_path": "databricks/gold/40_migrate_a.sql",
                    "target_layer": "gold",
                    "status": "pending",
                }
            ]
            (run / "migration_backlog.json").write_text(json.dumps(backlog))
            orig_root = merge.ROOT
            merge.ROOT = root
            try:
                summary = merge.merge(run_id, skip_ops=True)
            finally:
                merge.ROOT = orig_root
            self.assertEqual(summary["missing_results"], 1)
            self.assertEqual(summary["blocked"], 1)


class GenieContractTests(unittest.TestCase):
    def test_example_sql_ids_and_keywords(self):
        cfg = json.loads((ROOT / "databricks" / "genie" / "space_config.json").read_text())
        hex32 = re.compile(r"^[0-9a-f]{32}$")
        space = cfg["serialized_space"]["config"]
        for q in space["sample_questions"]:
            self.assertRegex(q["id"], hex32)
        sqls = space["example_question_sqls"]
        blob = json.dumps(sqls)
        self.assertIn("handoff", blob)
        self.assertIn("proc_conversion_map", blob)
        self.assertIn("pass", blob)
        self.assertIn("ship", blob)
        self.assertIn("run_id", blob)
        for row in sqls:
            self.assertRegex(row["id"], hex32)


class MaterializeReuseTests(unittest.TestCase):
    def test_reuses_existing_rg_location(self):
        text = (ROOT / "agents" / "tools" / "materialize_demo_env.sh").read_text()
        self.assertIn("az group show", text)
        self.assertIn("location", text)


class AliasProbeTests(unittest.TestCase):
    def test_alias_views_from_information_schema(self):
        script = (ROOT / "agents" / "tools" / "ensure_source_alias_views.sh").read_text()
        self.assertIn("INFORMATION_SCHEMA.TABLES", script)
        self.assertIn("LIKE '% %'", script)
        self.assertNotIn("PaymentMethod", script)
        probe = (ROOT / "databricks" / "uc" / "02b_alias_probe.sql").read_text()
        self.assertIn("alias_probe_skipped", probe)
        self.assertNotIn("PaymentMethod", probe)
        bootstrap = (ROOT / "infra" / "azure" / "bootstrap.sh").read_text()
        self.assertIn("CREATE OR ALTER VIEW", bootstrap)
        self.assertGreaterEqual(bootstrap.count("sqlcmd"), 5)

    def test_no_committed_silver_gold_sql(self):
        silver = list((ROOT / "databricks" / "silver").glob("*.sql"))
        gold = list((ROOT / "databricks" / "gold").glob("*.sql"))
        self.assertEqual(silver, [])
        self.assertEqual(gold, [])

    def test_map_agent_type_first(self):
        import subprocess

        script = ROOT / ".cursor" / "hooks" / "_map_agent.sh"
        payload = json.dumps(
            {
                "subagent_type": "edw-convert",
                "prompt": "read inventory and backlog then convert",
            }
        )
        out = subprocess.check_output(["bash", str(script), payload], text=True).strip()
        self.assertEqual(out, "convert")


class ObserveStatusArrowTests(unittest.TestCase):
    def test_script_prints_arrow(self):
        text = (ROOT / "agents" / "tools" / "observe_status.sh").read_text()
        self.assertIn("→", text)


if __name__ == "__main__":
    unittest.main()
