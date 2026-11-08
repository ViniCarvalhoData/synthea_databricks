-- Compares expected vs. actual tags on silver/gold and FAILS if any is missing.
-- status: OK | MISSING (expected but not found) | EXTRA (found but not listed)
-- Each statement runs in isolation (runner and job), so the expectations live in a table.
CREATE OR REPLACE TABLE synthea.governance.expected_tags (schema_name STRING, table_name STRING, column_name STRING, tag STRING, scenario STRING)
COMMENT 'Tags that propagation must produce on silver/gold (source: src/tests/10_propagation.sql)';

INSERT INTO synthea.governance.expected_tags VALUES
  ('silver', 'patients',                  'first_name',         'Personal',  'CTAS renamed copy'),
  ('silver', 'patients',                  'last_name',          'Personal',  'CTAS renamed copy'),
  ('silver', 'patients',                  'full_name',          'Personal',  'CTAS derived concat'),
  ('silver', 'patients',                  'ssn',                'Personal',  'CTAS copy'),
  ('silver', 'patients',                  'ssn_last4',          'Personal',  'CTAS derived right()'),
  ('silver', 'patients',                  'ssn_hash',           'Personal',  'CTAS derived sha2()'),
  ('silver', 'patients',                  'passport',           'Personal',  'CTAS 2 tags'),
  ('silver', 'patients',                  'passport',           'Sensitive', 'CTAS 2 tags'),
  ('silver', 'patients',                  'drivers_license',    'Personal',  'CTAS renamed copy'),
  ('silver', 'patients',                  'address',            'Personal',  'CTAS copy'),
  ('silver', 'patients',                  'race',               'Sensitive', 'CTAS copy'),
  ('silver', 'patients',                  'ethnicity',          'Sensitive', 'CTAS copy'),
  ('silver', 'encounters',                'patient_first_name', 'Personal',  'JOIN patients'),
  ('silver', 'encounters',                'patient_last_name',  'Personal',  'JOIN patients'),
  ('silver', 'encounters',                'patient_race',       'Sensitive', 'JOIN patients'),
  ('silver', 'encounters',                'provider_name',      'Personal',  'JOIN providers'),
  ('silver', 'patients_contact',          'full_name',          'Personal',  'INSERT derived concat'),
  ('silver', 'patients_contact',          'address',            'Personal',  'INSERT copy'),
  ('silver', 'patients_merge',            'first_name',         'Personal',  'MERGE'),
  ('silver', 'patients_merge',            'last_name',          'Personal',  'MERGE'),
  ('silver', 'patients_merge',            'ssn',                'Personal',  'MERGE'),
  ('silver', 'patients_merge',            'race',               'Sensitive', 'MERGE'),
  ('silver', 'v_patient_contact',         'first_name',         'Personal',  'VIEW'),
  ('silver', 'v_patient_contact',         'last_name',          'Personal',  'VIEW'),
  ('silver', 'v_patient_contact',         'address',            'Personal',  'VIEW'),
  ('gold',   'dim_patient',               'full_name',          'Personal',  'second hop'),
  ('gold',   'dim_patient',               'ssn_hash',           'Personal',  'second hop derived'),
  ('gold',   'dim_patient',               'race',               'Sensitive', 'second hop'),
  ('gold',   'dim_patient',               'ethnicity',          'Sensitive', 'second hop'),
  ('gold',   'patient_encounter_summary', 'patient_first_name', 'Personal',  'second hop GROUP BY'),
  ('gold',   'patient_encounter_summary', 'patient_last_name',  'Personal',  'second hop GROUP BY'),
  ('gold',   'demographics',              'race',               'Sensitive', 'second hop aggregate'),
  ('gold',   'demographics',              'ethnicity',          'Sensitive', 'second hop aggregate');

CREATE OR REPLACE VIEW synthea.governance.v_propagation_check AS
WITH actual AS (
  SELECT schema_name, table_name, column_name,
         CASE tag_name
           WHEN 'sap.PersonalData.isPotentiallyPersonal'  THEN 'Personal'
           WHEN 'sap.PersonalData.isPotentiallySensitive' THEN 'Sensitive'
         END AS tag
  FROM synthea.information_schema.column_tags
  WHERE catalog_name = 'synthea'
    AND schema_name IN ('silver', 'gold')
    AND tag_name LIKE 'sap.PersonalData.%'
)
SELECT
  coalesce(e.schema_name, a.schema_name) || '.' || coalesce(e.table_name, a.table_name) AS table_name,
  coalesce(e.column_name, a.column_name) AS column_name,
  coalesce(e.tag, a.tag)                 AS tag,
  CASE WHEN a.column_name IS NULL THEN 'MISSING'
       WHEN e.column_name IS NULL THEN 'EXTRA'
       ELSE 'OK' END                     AS status,
  e.scenario
FROM synthea.governance.expected_tags e
FULL OUTER JOIN actual a
  ON  e.schema_name = a.schema_name AND e.table_name = a.table_name
  AND e.column_name = a.column_name AND e.tag = a.tag;

-- Report
SELECT * FROM synthea.governance.v_propagation_check ORDER BY table_name, column_name, tag;

-- Assertion: fails the job/runner if a tag is missing. EXTRA does not fail (propagation is conservative).
SELECT CASE WHEN count(*) > 0
            THEN raise_error('Incomplete tag propagation: ' || string_agg(table_name || '.' || column_name || ' (' || tag || ')', ', '))
            ELSE 'OK: no missing tags' END AS result
FROM synthea.governance.v_propagation_check
WHERE status = 'MISSING';
