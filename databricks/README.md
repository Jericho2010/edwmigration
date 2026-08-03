# databricks/

Medallion + DAB for the migration engine.

| Path | Role |
|---|---|
| `uc/` | Federation + ops templates (`__UC_CATALOG__`) |
| `bronze/10_land_all.sql` | Placeholder; replaced by generated land |
| `silver/` `gold/` | Convert outputs (+ WWI demo known-good) |
| `generated/` | Gitignored output of `generate_from_inventory.py` |
| `_rendered/` | Gitignored render for deploy |
| `jobs/` | Lakeflow job + dashboard resource |
| `dashboards/` | Control Plane AI/BI JSON |
| `genie/` | Copilot space config + create script |

```bash
make render && make deploy && make run
```
