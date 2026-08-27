# databricks/

Medallion + DAB for the migration engine.

| Path | Role |
|---|---|
| `uc/` | Federation + ops templates (`__UC_CATALOG__`) |
| `bronze/10_land_all.sql` | Placeholder; replaced by generated land |
| `silver/` `gold/` | Convert **run artifacts** (gitignored `.sql`; README only in git) |
| `generated/` | Gitignored output of `generate_from_inventory.py` / alias probe |
| `_rendered/` | Gitignored render for deploy |
| `jobs/edw_migration_medallion.yml` | Engine skeleton (`federation_smoke` → `bronze_land` → `stage_fixtures` → `reconcile` → `lineage_check`); `--apply` adds Convert tasks |
| `jobs/edw_migration_medallion.skeleton.yml` | Restore original (`make reset-sink`) |
| `dashboards/` | Control Plane AI/BI JSON |
| `genie/` | Copilot space config + create script |

WWI teaching notebooks (not executed, not copied into the job): [`demo/wwi/reference/`](../demo/wwi/reference/).

```bash
make render && make deploy && make run
```
