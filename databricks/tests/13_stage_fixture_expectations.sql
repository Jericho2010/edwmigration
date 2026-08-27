-- 13_stage_fixture_expectations.sql
-- Engine: empty expectations table. Demo-pack CSVs are optional and not required to run.

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.fixture_expectations (
  fixture_name STRING NOT NULL,
  target_table STRING NOT NULL,
  metric STRING NOT NULL,
  expected BIGINT,
  compare STRING NOT NULL,
  notes STRING,
  staged_at TIMESTAMP
) USING DELTA;

ALTER TABLE __UC_CATALOG__.ops.fixture_expectations
  ADD COLUMN IF NOT EXISTS staged_at TIMESTAMP;

DELETE FROM __UC_CATALOG__.ops.fixture_expectations;

SELECT * FROM __UC_CATALOG__.ops.fixture_expectations ORDER BY fixture_name;
