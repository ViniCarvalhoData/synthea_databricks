-- =====================================================================
-- Source of truth for PII tags.
-- Tags are applied ONLY to the bronze layer; silver/gold receive them through
-- tag propagation (lineage). Do not add SET TAGS on silver/gold.
--
-- Tags (governed, with propagation enabled):
--   sap.PersonalData.isPotentiallyPersonal  = 'true'  -> personal identifier (LGPD art. 5, I)
--   sap.PersonalData.isPotentiallySensitive = 'true'  -> sensitive data       (LGPD art. 5, II)
--
-- WARNING: the text mask functions return STRING. Tagging a DATE/INT/DOUBLE
-- column as "Personal" breaks reads (casting '***' fails).
-- =====================================================================

-- patients: direct identifiers
ALTER TABLE synthea.bronze.patients ALTER COLUMN SSN      SET TAGS ('sap.PersonalData.isPotentiallyPersonal' = 'true');
ALTER TABLE synthea.bronze.patients ALTER COLUMN DRIVERS  SET TAGS ('sap.PersonalData.isPotentiallyPersonal' = 'true');
ALTER TABLE synthea.bronze.patients ALTER COLUMN PASSPORT SET TAGS ('sap.PersonalData.isPotentiallyPersonal' = 'true');
ALTER TABLE synthea.bronze.patients ALTER COLUMN FIRST    SET TAGS ('sap.PersonalData.isPotentiallyPersonal' = 'true');
ALTER TABLE synthea.bronze.patients ALTER COLUMN LAST     SET TAGS ('sap.PersonalData.isPotentiallyPersonal' = 'true');
ALTER TABLE synthea.bronze.patients ALTER COLUMN ADDRESS  SET TAGS ('sap.PersonalData.isPotentiallyPersonal' = 'true');

-- patients: sensitive data
ALTER TABLE synthea.bronze.patients ALTER COLUMN RACE      SET TAGS ('sap.PersonalData.isPotentiallySensitive' = 'true');
ALTER TABLE synthea.bronze.patients ALTER COLUMN ETHNICITY SET TAGS ('sap.PersonalData.isPotentiallySensitive' = 'true');
-- PASSPORT carries both tags on purpose: test case for policy conflicts
ALTER TABLE synthea.bronze.patients ALTER COLUMN PASSPORT  SET TAGS ('sap.PersonalData.isPotentiallySensitive' = 'true');

-- providers: practitioner name and address (tests propagation through JOIN)
ALTER TABLE synthea.bronze.providers ALTER COLUMN NAME    SET TAGS ('sap.PersonalData.isPotentiallyPersonal' = 'true');
ALTER TABLE synthea.bronze.providers ALTER COLUMN ADDRESS SET TAGS ('sap.PersonalData.isPotentiallyPersonal' = 'true');
