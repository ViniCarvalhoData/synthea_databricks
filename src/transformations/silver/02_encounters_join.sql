-- Scenario: CTAS with a JOIN of 3 bronze tables
-- Tests: propagation of columns coming from different sources (patients and providers).
CREATE OR REPLACE TABLE synthea.silver.encounters AS
SELECT
  e.Id               AS encounter_id,
  e.START            AS start_ts,
  e.STOP             AS stop_ts,
  e.ENCOUNTERCLASS   AS encounter_class,
  e.DESCRIPTION      AS description,
  e.TOTAL_CLAIM_COST AS total_claim_cost,
  e.PAYER_COVERAGE   AS payer_coverage,
  e.PATIENT          AS patient_id,
  p.FIRST            AS patient_first_name,   -- Personal (patients)
  p.LAST             AS patient_last_name,    -- Personal (patients)
  p.RACE             AS patient_race,         -- Sensitive (patients)
  e.PROVIDER         AS provider_id,
  pr.NAME            AS provider_name,        -- Personal (providers)
  pr.SPECIALITY      AS provider_speciality
FROM synthea.bronze.encounters e
LEFT JOIN synthea.bronze.patients  p  ON p.Id  = e.PATIENT
LEFT JOIN synthea.bronze.providers pr ON pr.Id = e.PROVIDER;
