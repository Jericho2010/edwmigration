-- 02_federation_smoke.sql — verify foreign catalog + managed catalog are usable.
-- Placeholders: __UC_CATALOG__  __FOREIGN_CATALOG__

DECLARE OR REPLACE VARIABLE v_tables BIGINT DEFAULT 0;

SET VAR v_tables = (
  SELECT COUNT(*) FROM __FOREIGN_CATALOG__.information_schema.tables
  WHERE table_type = 'BASE TABLE'
    AND table_schema NOT IN ('sys', 'INFORMATION_SCHEMA', 'guest')
);

SELECT 'federation_smoke_ok' AS check_name,
       v_tables AS foreign_base_tables,
       (SELECT COUNT(*) > 0 FROM __UC_CATALOG__.information_schema.schemata
        WHERE schema_name IN ('bronze', 'silver', 'gold', 'ops', 'source_fed')) AS managed_schemas_ok;
