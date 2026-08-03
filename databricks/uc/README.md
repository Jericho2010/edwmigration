# databricks/uc

| File | Purpose |
|---|---|
| `01_federation_setup.sql` | CONNECTION + foreign catalog + managed catalog/schemas |
| `02_federation_smoke.sql` | Foreign BASE TABLE count + managed schemas |
| `03_ops_and_views.sql` | ops.* control tables including `migration_inventory` |
| `04_lineage_check.sql` | Sample UC lineage query |

Always run via `make render` then `agents/tools/run_sql.sh --file databricks/_rendered/uc/...`.
