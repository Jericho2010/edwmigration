#!/usr/bin/env python3
"""Unit tests for publish_run_notebooks import plan + CLI auth host matching."""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

import databricks_cli_env as cli_env
import publish_run_notebooks as pub


class NormalizeHostTests(unittest.TestCase):
    def test_strips_slash_and_scheme(self) -> None:
        self.assertEqual(
            cli_env.normalize_host("https://dbc-example.cloud.databricks.com/"),
            "dbc-example.cloud.databricks.com",
        )
        self.assertEqual(
            cli_env.normalize_host("https://DBC-example.cloud.databricks.com"),
            "dbc-example.cloud.databricks.com",
        )


class MatchingProfileTests(unittest.TestCase):
    def test_prefers_default_on_same_host(self) -> None:
        profiles = [
            {
                "name": "other-profile",
                "host": "https://dbc-example.cloud.databricks.com",
                "valid": "yes",
            },
            {
                "name": "DEFAULT",
                "host": "https://dbc-example.cloud.databricks.com/",
                "valid": "yes",
            },
        ]
        self.assertEqual(
            cli_env.matching_profile(
                "https://dbc-example.cloud.databricks.com",
                profiles,
            ),
            "DEFAULT",
        )

    def test_ignores_other_workspace(self) -> None:
        profiles = [
            {
                "name": "other",
                "host": "https://adb-1.azuredatabricks.net",
                "valid": "yes",
            }
        ]
        self.assertIsNone(
            cli_env.matching_profile(
                "https://dbc-example.cloud.databricks.com",
                profiles,
            )
        )


class ImportPlanTests(unittest.TestCase):
    def test_prefers_rendered_skips_federation_setup(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "databricks" / "uc").mkdir(parents=True)
            (root / "databricks" / "bronze").mkdir()
            (root / "databricks" / "silver").mkdir()
            (root / "databricks" / "gold").mkdir()
            (root / "databricks" / "tests").mkdir()
            (root / "databricks" / "_rendered" / "bronze").mkdir(parents=True)
            (root / "databricks" / "_rendered" / "silver").mkdir(parents=True)
            (root / "databricks" / "uc" / "01_federation_setup.sql").write_text("-- secret\n")
            (root / "databricks" / "uc" / "02_federation_smoke.sql").write_text("SELECT 1;\n")
            (root / "databricks" / "bronze" / "10_land_all.sql").write_text("-- repo land\n")
            (root / "databricks" / "_rendered" / "bronze" / "10_land_all.sql").write_text("-- rendered land\n")
            (root / "databricks" / "silver" / "20_dims_scd1.sql").write_text("-- dims\n")
            (root / "databricks" / "_rendered" / "silver" / "24_migrate_city.sql").write_text("-- migrate\n")
            (root / "databricks" / "gold" / "30_mart_daily_sales.sql").write_text("-- mart\n")
            (root / "databricks" / "tests" / "reconcile.sql").write_text("-- recon\n")

            plan = pub.build_import_plan(root)
            names = {(i.layer, i.dest_name) for i in plan}
            self.assertNotIn(("uc", "01_federation_setup"), names)
            self.assertIn(("uc", "02_federation_smoke"), names)
            self.assertIn(("bronze", "10_land_all"), names)
            self.assertIn(("silver", "20_dims_scd1"), names)
            self.assertIn(("silver", "24_migrate_city"), names)
            self.assertIn(("gold", "30_mart_daily_sales"), names)
            self.assertIn(("tests", "reconcile"), names)
            land = next(i for i in plan if i.dest_name == "10_land_all")
            self.assertTrue(land.source.endswith("_rendered/bronze/10_land_all.sql"))

    def test_folder_date_stable(self) -> None:
        existing = {"folder_date": "20260115"}
        later = datetime(2026, 8, 27, tzinfo=timezone.utc)
        self.assertEqual(pub.folder_date_utc(existing, now=later), "20260115")
        self.assertEqual(pub.folder_date_utc({}, now=later), "20260827")

    def test_urls(self) -> None:
        folder = pub.workspace_folder("shaun@example.com", "20260827")
        self.assertEqual(folder, "/Users/shaun@example.com/edwmigration_20260827")
        host = "https://dbc.example.com"
        self.assertEqual(
            pub.folder_url(host, folder),
            "https://dbc.example.com/#workspace/Users/shaun@example.com/edwmigration_20260827",
        )
        self.assertEqual(
            pub.catalog_url(host, "edw_migration"),
            "https://dbc.example.com/explore/data/edw_migration",
        )
        self.assertEqual(pub.job_url(host, "123"), "https://dbc.example.com/jobs/123")

    def test_find_medallion_job_id(self) -> None:
        payload = {
            "jobs": [
                {"job_id": 1, "settings": {"name": "other"}},
                {
                    "job_id": 123456789012345,
                    "settings": {"name": "[dev shaun] [dev] edw_migration_medallion"},
                },
            ]
        }
        self.assertEqual(pub.find_medallion_job_id(payload), "123456789012345")

    def test_folders_from_local_runs(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run = root / "agents" / "out" / "abc"
            run.mkdir(parents=True)
            (run / "notebooks.json").write_text(
                json.dumps({"folder": "/Users/me@x.com/edwmigration_20260827"})
            )
            self.assertEqual(
                pub.folders_from_local_runs(root),
                ["/Users/me@x.com/edwmigration_20260827"],
            )

    def test_dry_run_writes_notebooks_json(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            run_id = "11111111-2222-3333-4444-555555555555"
            (root / "agents" / "out" / run_id).mkdir(parents=True)
            (root / "databricks" / "silver").mkdir(parents=True)
            (root / "databricks" / "silver" / "20_dims_scd1.sql").write_text("SELECT 1;\n")
            with mock.patch.dict(
                os.environ,
                {
                    "DATABRICKS_HOST": "https://dbc.example.com",
                    "DATABRICKS_CATALOG": "edw_migration",
                    "DATABRICKS_TOKEN": "x",
                },
                clear=False,
            ):
                data = pub.publish(
                    run_id,
                    root=root,
                    dry_run=True,
                    now=datetime(2026, 8, 27, tzinfo=timezone.utc),
                )
            self.assertTrue((root / "agents" / "out" / run_id / "notebooks.json").is_file())
            self.assertIn("edwmigration_20260827", data["folder"])
            self.assertTrue(data["folder_url"].endswith("/edwmigration_20260827"))
            self.assertIn("edw_migration", data["catalog_url"])
            self.assertTrue(any(p["dest_name"] == "20_dims_scd1" for p in data["plan"]))


if __name__ == "__main__":
    unittest.main()
