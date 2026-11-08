-- Scenario: statistical aggregate over sensitive columns
-- Business question: is the aggregated column (race/ethnicity) still sensitive?
-- If the tag propagates, the "removal" policy will null out the report's dimension.
CREATE OR REPLACE TABLE synthea.gold.demographics AS
SELECT
  race,
  ethnicity,
  gender,
  count(*)                 AS patients,
  avg(healthcare_expenses) AS avg_healthcare_expenses
FROM synthea.silver.patients
GROUP BY race, ethnicity, gender;
