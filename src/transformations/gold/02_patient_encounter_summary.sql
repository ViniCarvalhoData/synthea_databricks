-- Scenario: aggregation with GROUP BY keeping personal columns as keys
CREATE OR REPLACE TABLE synthea.gold.patient_encounter_summary AS
SELECT
  patient_id,
  patient_first_name,
  patient_last_name,
  count(*)              AS encounters,
  sum(total_claim_cost) AS total_claim_cost,
  max(start_ts)         AS last_encounter_ts
FROM synthea.silver.encounters
GROUP BY patient_id, patient_first_name, patient_last_name;
