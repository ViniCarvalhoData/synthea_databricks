-- Scenario: VIEW
-- Tests: propagation into views. Note: CREATE OR REPLACE VIEW clears the view's direct
-- tags/policies; propagation should reapply them. ABAC enforcement on views
-- requires the "ABAC on Views" preview (DBR 19+).
CREATE OR REPLACE VIEW synthea.silver.v_patient_contact AS
SELECT Id AS patient_id, FIRST AS first_name, LAST AS last_name, ADDRESS AS address, CITY AS city
FROM synthea.bronze.patients;
