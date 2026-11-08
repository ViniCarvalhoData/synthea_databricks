-- Scenario: second hop (bronze -> silver -> gold)
-- Tests: whether the tag propagated to silver carries on to gold. Propagation is
-- asynchronous, so gold may run before silver's tags land (see src/tests/).
CREATE SCHEMA IF NOT EXISTS synthea.gold COMMENT 'Gold layer - no direct tags, only propagated ones';

CREATE OR REPLACE TABLE synthea.gold.dim_patient AS
SELECT patient_id, full_name, ssn_hash, gender, race, ethnicity, city, state, birth_date, is_deceased
FROM synthea.silver.patients;
