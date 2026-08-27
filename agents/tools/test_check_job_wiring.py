#!/usr/bin/env python3
"""Unit tests for check_job_wiring propose/apply."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import check_job_wiring as cjw

SKELETON_JOB = """\
resources:
  jobs:
    edw_migration_medallion:
      name: test_job
      tasks:
        - task_key: federation_smoke
          sql_task:
            file:
              path: ../_rendered/uc/02_federation_smoke.sql
            warehouse_id: ${var.warehouse_id}

        - task_key: bronze_land
          depends_on:
            - task_key: federation_smoke
          sql_task:
            file:
              path: ../_rendered/bronze/10_land_all.sql
            warehouse_id: ${var.warehouse_id}

        - task_key: stage_fixtures
          depends_on:
            - task_key: federation_smoke
          sql_task:
            file:
              path: ../_rendered/tests/13_stage_fixture_expectations.sql
            warehouse_id: ${var.warehouse_id}

        - task_key: reconcile
          depends_on:
            - task_key: bronze_land
          timeout_seconds: 900
          sql_task:
            file:
              path: ../_rendered/tests/reconcile.sql
            warehouse_id: ${var.warehouse_id}

        - task_key: lineage_check
          depends_on:
            - task_key: reconcile
          sql_task:
            file:
              path: ../_rendered/uc/04_lineage_check.sql
            warehouse_id: ${var.warehouse_id}
"""


def _item(
    item_id: str,
    path: str,
    *,
    reads: str = "",
    writes: str = "",
    layer: str = "silver",
) -> dict:
    return {
        "item_id": item_id,
        "legacy_proc": f"dbo.{item_id}",
        "classification": "migrate",
        "reads": reads,
        "writes": writes,
        "target_layer": layer,
        "target_path": path,
        "priority": "high",
        "risk_flags": "",
        "status": "pending",
    }


class TestNormalizeAndKeys(unittest.TestCase):
    def test_repo_path_to_job_path(self):
        self.assertEqual(
            cjw.repo_path_to_job_path("databricks/gold/36_foo.sql"),
            "../_rendered/gold/36_foo.sql",
        )
        self.assertEqual(
            cjw.repo_path_to_job_path("databricks/silver/20_bar.sql"),
            "../_rendered/silver/20_bar.sql",
        )

    def test_task_key_dedup(self):
        existing = {"gold_36_foo"}
        self.assertEqual(
            cjw.task_key_for_path("databricks/gold/36_foo.sql", existing),
            "gold_36_foo_2",
        )

    def test_table_tokens_dimension_fact(self):
        toks = cjw.table_tokens("Dimension.City, Fact.Sale")
        self.assertIn("dim_city", toks)
        self.assertIn("fact_sale", toks)


class TestProposeApply(unittest.TestCase):
    def test_propose_missing_silver_depends_on_bronze_land(self):
        proposal = cjw.propose_patch(
            SKELETON_JOB,
            ["databricks/silver/20_new_dim.sql"],
        )
        self.assertEqual(len(proposal.tasks), 1)
        task = proposal.tasks[0]
        self.assertEqual(task.task_key, "silver_20_new_dim")
        self.assertEqual(task.job_path, "../_rendered/silver/20_new_dim.sql")
        self.assertEqual(task.depends_on, ["bronze_land"])

    def test_propose_missing_gold_updates_reconcile(self):
        proposal = cjw.propose_patch(
            SKELETON_JOB,
            ["databricks/gold/21_new_mart.sql"],
        )
        self.assertEqual(len(proposal.tasks), 1)
        self.assertEqual(proposal.tasks[0].task_key, "gold_21_new_mart")
        self.assertIn("gold_21_new_mart", proposal.reconcile_depends_on)

    def test_already_wired_noop(self):
        patched = cjw.apply_patch(SKELETON_JOB, ["databricks/gold/21_new_mart.sql"])
        proposal = cjw.propose_patch(patched, ["databricks/gold/21_new_mart.sql"])
        self.assertEqual(proposal.tasks, [])
        self.assertTrue(proposal.noop)

    def test_apply_idempotent(self):
        missing = ["databricks/gold/21_new_mart.sql"]
        once = cjw.apply_patch(SKELETON_JOB, missing)
        twice = cjw.apply_patch(once, missing)
        self.assertEqual(once, twice)
        keys = [t["task_key"] for t in cjw.parse_tasks(once)]
        self.assertEqual(keys.count("gold_21_new_mart"), 1)
        self.assertIn("../_rendered/gold/21_new_mart.sql", once)
        recon_idx = once.index("task_key: reconcile")
        lineage_idx = once.index("task_key: lineage_check")
        recon_block = once[recon_idx:lineage_idx]
        self.assertIn("gold_21_new_mart", recon_block)

    def test_apply_serial_chain_keeps_peak_le_five(self):
        missing = [f"databricks/gold/2{i}_extra.sql" for i in range(6, 10)]
        patched = cjw.apply_patch(SKELETON_JOB, missing)
        tasks = cjw.parse_tasks(patched)
        self.assertLessEqual(cjw.peak_concurrency(tasks), 5)

    def test_reads_writes_edge(self):
        backlog = [
            _item("a", "databricks/silver/20_dim_x.sql", writes="Dimension.X"),
            _item(
                "b",
                "databricks/gold/21_fact_y.sql",
                reads="Dimension.X",
                writes="Fact.Y",
                layer="gold",
            ),
        ]
        proposal = cjw.propose_patch(
            SKELETON_JOB,
            [i["target_path"] for i in backlog],
            backlog=backlog,
        )
        by_key = {t.task_key: t for t in proposal.tasks}
        self.assertIn("bronze_land", by_key["silver_20_dim_x"].depends_on)
        self.assertIn("silver_20_dim_x", by_key["gold_21_fact_y"].depends_on)

    def test_cycle_fails_closed(self):
        backlog = [
            _item("a", "databricks/silver/20_a.sql", reads="dbo.B", writes="dbo.A"),
            _item("b", "databricks/silver/21_b.sql", reads="dbo.A", writes="dbo.B"),
        ]
        with self.assertRaises(cjw.CycleError):
            cjw.propose_patch(
                SKELETON_JOB,
                [i["target_path"] for i in backlog],
                backlog=backlog,
            )

    def test_six_independent_pack_peak_le_five(self):
        missing = [f"databricks/silver/2{i}_dim.sql" for i in range(6)]
        patched = cjw.apply_patch(SKELETON_JOB, missing)
        tasks = cjw.parse_tasks(patched)
        self.assertLessEqual(cjw.peak_concurrency(tasks), 5)
        waves = cjw.compute_ready_waves(tasks)
        convert_waves = [
            [k for k in w if k.startswith("silver_")] for w in waves
        ]
        convert_waves = [w for w in convert_waves if w]
        self.assertTrue(any(len(w) == 5 for w in convert_waves))
        self.assertTrue(any(len(w) == 1 for w in convert_waves))

    def test_peak_concurrency_rejects_unsafe_fanout(self):
        fanout_job = """\
resources:
  jobs:
    edw_migration_medallion:
      tasks:
        - task_key: bronze_land
          sql_task:
            file:
              path: ../_rendered/bronze/10_land_all.sql
            warehouse_id: ${var.warehouse_id}
"""
        for i in range(1, 6):
            fanout_job += f"""
        - task_key: leaf_{i}
          depends_on:
            - task_key: bronze_land
          sql_task:
            file:
              path: ../_rendered/gold/2{i}_x.sql
            warehouse_id: ${{var.warehouse_id}}
"""
        fanout_job += """
        - task_key: reconcile
          depends_on:
            - task_key: leaf_1
          sql_task:
            file:
              path: ../_rendered/tests/reconcile.sql
            warehouse_id: ${var.warehouse_id}
"""
        tasks = cjw.parse_tasks(fanout_job)
        self.assertEqual(cjw.peak_concurrency(tasks), 5)

        with self.assertRaises(cjw.ConcurrencyLimitError):
            cjw.apply_patch(
                fanout_job,
                ["databricks/gold/99_too_many.sql"],
                serialize=False,
            )


class TestCliApply(unittest.TestCase):
    def test_cli_apply_writes_job(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            job = tmp_path / "job.yml"
            job.write_text(SKELETON_JOB)
            backlog = tmp_path / "backlog.json"
            backlog.write_text(
                json.dumps(
                    [
                        _item(
                            "item-new",
                            "databricks/gold/21_cli_mart.sql",
                            writes="dbo.T",
                            layer="gold",
                        )
                    ]
                )
            )
            rc = cjw.main_with_args(
                [
                    "--backlog",
                    str(backlog),
                    "--job",
                    str(job),
                    "--apply",
                ]
            )
            self.assertEqual(rc, 0)
            text = job.read_text()
            self.assertIn("gold_21_cli_mart", text)
            self.assertIn("../_rendered/gold/21_cli_mart.sql", text)


class TestSkeletonContract(unittest.TestCase):
    def test_committed_job_is_skeleton(self):
        text = Path(cjw.JOB_YAML).read_text()
        keys = {t["task_key"] for t in cjw.parse_tasks(text)}
        self.assertEqual(
            keys,
            {
                "federation_smoke",
                "bronze_land",
                "stage_fixtures",
                "reconcile",
                "lineage_check",
            },
        )
        for banned in (
            "20_dims",
            "22_fact_sale",
            "fact_sale",
            "MigrateCity",
            "40_migrate",
            "30_mart",
        ):
            self.assertNotIn(banned, text)


if __name__ == "__main__":
    unittest.main()
