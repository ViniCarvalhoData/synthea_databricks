-- Scenario: CTAS (an operation supported by propagation)
-- Tests: column renaming, a column derived from 2 tagged columns,
--        a column derived through a function (right) and through a hash (sha2).
CREATE SCHEMA IF NOT EXISTS synthea.silver COMMENT 'Silver layer - no direct tags, only propagated ones';

CREATE OR REPLACE TABLE synthea.silver.patients AS
SELECT
  Id                          AS patient_id,
  FIRST                       AS first_name,      -- renamed copy
  LAST                        AS last_name,       -- renamed copy
  concat_ws(' ', FIRST, LAST) AS full_name,       -- derived from 2 tagged columns
  SSN                         AS ssn,
  right(SSN, 4)               AS ssn_last4,       -- derived through a function
  sha2(SSN, 256)              AS ssn_hash,        -- hash: should it be tagged?
  PASSPORT                    AS passport,        -- Personal + Sensitive
  DRIVERS                     AS drivers_license,
  ADDRESS                     AS address,
  CITY                        AS city,
  STATE                       AS state,
  ZIP                         AS zip,
  RACE                        AS race,
  ETHNICITY                   AS ethnicity,
  GENDER                      AS gender,
  BIRTHDATE                   AS birth_date,
  DEATHDATE                   AS death_date,
  DEATHDATE IS NOT NULL       AS is_deceased,
  HEALTHCARE_EXPENSES         AS healthcare_expenses,
  HEALTHCARE_COVERAGE         AS healthcare_coverage
FROM synthea.bronze.patients;
