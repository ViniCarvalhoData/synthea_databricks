-- Scenario: MERGE (incremental upsert)
-- Tests: propagation through MERGE, a common incremental silver pattern.
CREATE TABLE IF NOT EXISTS synthea.silver.patients_merge (
  patient_id STRING,
  first_name STRING,
  last_name  STRING,
  ssn        STRING,
  race       STRING,
  updated_at TIMESTAMP
);

MERGE INTO synthea.silver.patients_merge t
USING (
  SELECT Id AS patient_id, FIRST AS first_name, LAST AS last_name, SSN AS ssn, RACE AS race
  FROM synthea.bronze.patients
) s
ON t.patient_id = s.patient_id
WHEN MATCHED THEN UPDATE SET
  first_name = s.first_name, last_name = s.last_name, ssn = s.ssn, race = s.race,
  updated_at = current_timestamp()
WHEN NOT MATCHED THEN INSERT (patient_id, first_name, last_name, ssn, race, updated_at)
  VALUES (s.patient_id, s.first_name, s.last_name, s.ssn, s.race, current_timestamp());
