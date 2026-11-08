-- One row per run: how the current persona sees each column type.
-- Run with each role profile: bash src/tests/run_personas.sh
-- Classification: clear | *** | hash | NULL  (via aggregates, independent of which row)
WITH v AS (
  SELECT
    (SELECT max(first_name) FROM synthea.silver.patients)    AS personal_silver,
    (SELECT max(full_name)  FROM synthea.gold.dim_patient)   AS personal_gold,
    (SELECT max(race)       FROM synthea.gold.demographics)  AS sensitive_gold,
    (SELECT max(passport)   FROM synthea.silver.patients)    AS personal_and_sensitive
)
SELECT
  current_user() AS persona,
  CASE WHEN personal_silver IS NULL THEN 'NULL' WHEN personal_silver = '***' THEN '***'
       WHEN length(personal_silver) = 64 THEN 'hash' ELSE 'clear' END AS personal_silver,
  CASE WHEN personal_gold IS NULL THEN 'NULL' WHEN personal_gold = '***' THEN '***'
       WHEN length(personal_gold) = 64 THEN 'hash' ELSE 'clear' END   AS personal_gold,
  CASE WHEN sensitive_gold IS NULL THEN 'NULL' ELSE 'clear' END       AS sensitive_gold,
  CASE WHEN personal_and_sensitive IS NULL THEN 'NULL' ELSE 'clear' END AS personal_and_sensitive
FROM v;
