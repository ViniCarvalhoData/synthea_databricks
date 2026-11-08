-- Shows what the CURRENT user sees. Run it as different personas
-- (switching roles or joining/leaving the synthea_* groups) and compare.
SELECT
  current_user()                                           AS user_name,
  is_account_group_member('synthea_pipeline')              AS pipeline,
  is_account_group_member('synthea_pii_readers')           AS pii_readers,
  is_account_group_member('synthea_analysts')              AS analysts,
  is_account_group_member('synthea_sensitive_readers')     AS sensitive_readers;

-- bronze (direct tags)
SELECT 'bronze.patients' AS source, FIRST AS first_name, SSN AS ssn, PASSPORT AS passport, RACE AS race, CITY AS city
FROM synthea.bronze.patients LIMIT 3;

-- silver (tags propagated by CTAS)
SELECT 'silver.patients' AS source, first_name, ssn, ssn_last4, left(ssn_hash, 12) AS ssn_hash, passport, race, city
FROM synthea.silver.patients LIMIT 3;

-- silver (JOIN with providers)
SELECT 'silver.encounters' AS source, patient_first_name, provider_name, patient_race, encounter_class
FROM synthea.silver.encounters LIMIT 3;

-- gold (second hop)
SELECT 'gold.dim_patient' AS source, full_name, left(ssn_hash, 12) AS ssn_hash, race, ethnicity, gender
FROM synthea.gold.dim_patient LIMIT 3;

-- gold aggregate: is the sensitive dimension nulled out?
SELECT race, ethnicity, sum(patients) AS patients
FROM synthea.gold.demographics GROUP BY race, ethnicity ORDER BY patients DESC LIMIT 5;

-- Integrity of the materialized data (only meaningful when run as the pipeline):
-- 1 distinct hash = silver was built by a masked user and stored '***'.
SELECT count(DISTINCT ssn_hash) AS distinct_hashes, count(*) AS row_count FROM synthea.silver.patients;
