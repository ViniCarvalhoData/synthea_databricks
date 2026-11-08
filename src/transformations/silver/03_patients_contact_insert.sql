-- Scenario: table created with explicit DDL (no tags) + INSERT INTO ... SELECT
-- Tests: propagation into a pre-existing table that was not born from a CTAS.
CREATE TABLE IF NOT EXISTS synthea.silver.patients_contact (
  patient_id STRING,
  full_name  STRING,
  address    STRING,
  city       STRING,
  state      STRING
);

TRUNCATE TABLE synthea.silver.patients_contact;

INSERT INTO synthea.silver.patients_contact
SELECT Id, concat_ws(' ', FIRST, LAST), ADDRESS, CITY, STATE
FROM synthea.bronze.patients;
