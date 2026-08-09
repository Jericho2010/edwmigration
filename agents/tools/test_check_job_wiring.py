#!/usr/bin/env python3
"""Unit tests for check_job_wiring propose/apply."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import check_job_wiring as cjw

MINIMAL_JOB = """\
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

        - task_key: silver_dims
          depends_on:
            - task_key: bronze_land
          timeout_seconds: 1800
          sql_task:
            file:
              path: ../_rendered/silver/20_dims_scd1.sql
            warehouse_id: ${var.warehouse_id}

        - task_key: gold_daily_sales
          depends_on:
            - task_key: silver_dims
          timeout_seconds: 1800
          sql_task:
            file:
              path: ../_rendered/gold/30_mart_daily_sales.sql
            warehouse_id: ${var.warehouse_id}

        - task_key: reconcile
          depends_on:
            - task_key: gold_daily_sales
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


class TestNormalizeAndKeys(unittest.TestCase):
    def test_repo_path_to_job_path(self):
        self.assertEqual(
            cjw.repo_path_to_job_path("databricks/gold/36_foo.sql"),
            "../_rendered/gold/36_foo.sql",
        )
        self.assertEqual(
            cjw.repo_path_to_job_path("databricks/silver/40_bar.sql"),
            "../_rendered/silver/40_bar.sql",
        )

    def test_task_key_dedup(self):
        existing = {"gold_36_foo"}
        self.assertEqual(
            cjw.task_key_for_path("databricks/gold/36_foo.sql", existing),
            "gold_36_foo_2",
        )


class TestProposeApply(unittest.TestCase):
    def test_propose_missing_silver(self):
        proposal = cjw.propose_patch(
            MINIMAL_JOB,
            ["databricks/silver/40_new_dim.sql"],
        )
        self.assertEqual(len(proposal.tasks), 1)
        task = proposal.tasks[0]
        self.assertEqual(task.task_key, "silver_40_new_dim")
        self.assertEqual(task.job_path, "../_rendered/silver/40_new_dim.sql")
        # Safe serial: first new task waits on current reconcile deps
        self.assertIn("gold_daily_sales", task.depends_on)

    def test_propose_missing_gold_updates_reconcile(self):
        proposal = cjw.propose_patch(
            MINIMAL_JOB,
            ["databricks/gold/36_new_mart.sql"],
        )
        self.assertEqual(len(proposal.tasks), 1)
        self.assertEqual(proposal.tasks[0].task_key, "gold_36_new_mart")
        self.assertIn("gold_36_new_mart", proposal.reconcile_depends_on)

    def test_already_wired_noop(self):
        proposal = cjw.propose_patch(
            MINIMAL_JOB,
            ["databricks/gold/30_mart_daily_sales.sql"],
        )
        self.assertEqual(proposal.tasks, [])
        self.assertTrue(proposal.noop)

    def test_apply_idempotent(self):
        missing = ["databricks/gold/36_new_mart.sql"]
        once = cjw.apply_patch(MINIMAL_JOB, missing)
        twice = cjw.apply_patch(once, missing)
        self.assertEqual(once, twice)
        keys = [t["task_key"] for t in cjw.parse_tasks(once)]
        self.assertEqual(keys.count("gold_36_new_mart"), 1)
        self.assertIn("../_rendered/gold/36_new_mart.sql", once)
        # reconcile must depend on the new gold task
        recon_idx = once.index("task_key: reconcile")
        lineage_idx = once.index("task_key: lineage_check")
        recon_block = once[recon_idx:lineage_idx]
        self.assertIn("gold_36_new_mart", recon_block)

    def test_apply_serial_chain_keeps_peak_le_five(self):
        missing = [
            f"databricks/gold/3{i}_extra.sql" for i in range(6, 10)
        ]
        patched = cjw.apply_patch(MINIMAL_JOB, missing)
        tasks = cjw.parse_tasks(patched)
        self.assertLessEqual(cjw.peak_concurrency(tasks), 5)

    def test_peak_concurrency_rejects_unsafe_fanout(self):
        # Five independent tasks after a root → peak 5. Adding a sixth
        # with the same deps would exceed the Free Edition limit.
        fanout_job = """\
resources:
  jobs:
    edw_migration_medallion:
      tasks:
        - task_key: root
          sql_task:
            file:
              path: ../_rendered/uc/02_federation_smoke.sql
            warehouse_id: ${var.warehouse_id}
"""
        for i in range(1, 6):
            fanout_job += f"""
        - task_key: leaf_{i}
          depends_on:
            - task_key: root
          sql_task:
            file:
              path: ../_rendered/gold/3{i}_x.sql
            warehouse_id: ${{var.warehouse_id}}
"""
        fanout_job += """
        - task_key: reconcile
          depends_on:
            - task_key: leaf_1
            - task_key: leaf_2
            - task_key: leaf_3
            - task_key: leaf_4
            - task_key: leaf_5
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
            job.write_text(MINIMAL_JOB)
            backlog = tmp_path / "backlog.json"
            backlog.write_text(
                json.dumps(
                    [
                        {
                            "item_id": "item-new",
                            "legacy_proc": "dbo.P",
                            "classification": "migrate",
                            "reads": "dbo.T",
                            "writes": "dbo.T",
                            "target_layer": "gold",
                            "target_path": "databricks/gold/36_cli_mart.sql",
                            "priority": "high",
                            "risk_flags": "",
                            "status": "converted",
                        }
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
            self.assertIn("gold_36_cli_mart", text)
            self.assertIn("../_rendered/gold/36_cli_mart.sql", text)


if __name__ == "__main__":
    unittest.main()
