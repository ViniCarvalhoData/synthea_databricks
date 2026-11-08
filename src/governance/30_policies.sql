-- =====================================================================
-- CATALOG-level ABAC policies: they apply to bronze, silver and gold.
-- Because tags propagate, derived tables get masked with no extra setup.
--
-- Groups (account-level; created in the UI on Free Edition, or by
-- src/scripts/setup_identities.ps1):
--   synthea_pipeline          -> identity that builds silver/gold. MUST be in the
--                                EXCEPT of every mask; otherwise CTAS physically
--                                writes '***' (what happened to patients_v2).
--   synthea_pii_readers       -> sees personal data in clear text
--   synthea_analysts          -> sees personal data pseudonymized (hash)
--   synthea_sensitive_readers -> sees sensitive data (race/ethnicity) in clear text
--
-- The groups are independent axes: pii_readers unlocks Personal,
-- sensitive_readers unlocks Sensitive. Seeing everything requires both.
--
-- Conflict rule: for a given user, only ONE distinct mask may resolve per
-- column; otherwise the query fails. That is why the MATCH clauses are disjoint:
--   Personal  and not Sensitive -> redact (account users) | pseudonymize (analysts)
--   Sensitive and not Personal  -> remove
--   Personal  and Sensitive     -> requires_pii_and_sensitive (e.g. PASSPORT)
-- =====================================================================

-- The old PII_policy (table-level on bronze.patients, created in the UI) was dropped
-- on 2026-10-20: it would conflict with the policies below. DROP POLICY has no IF EXISTS.

-- 1) Personal data -> '***' for everyone except those with access
CREATE OR REPLACE POLICY pii_personal_redact
ON CATALOG synthea
COMMENT 'LGPD art. 5 I: redacts personal identifiers'
COLUMN MASK synthea.governance.mask_redact
TO `account users`
EXCEPT `synthea_pipeline`, `synthea_pii_readers`, `synthea_analysts`
FOR TABLES
MATCH COLUMNS has_tag_value('sap.PersonalData.isPotentiallyPersonal', 'true')
          AND NOT has_tag_value('sap.PersonalData.isPotentiallySensitive', 'true') AS m
ON COLUMN m;

-- 2) Personal data -> hash for analysts (group-based)
CREATE OR REPLACE POLICY pii_personal_pseudonymize
ON CATALOG synthea
COMMENT 'Analysts see pseudonyms: joins/counts work without identifying anyone'
COLUMN MASK synthea.governance.mask_pseudonymize
TO `synthea_analysts`
EXCEPT `synthea_pipeline`, `synthea_pii_readers`   -- pii_readers takes precedence over analysts
FOR TABLES
MATCH COLUMNS has_tag_value('sap.PersonalData.isPotentiallyPersonal', 'true')
          AND NOT has_tag_value('sap.PersonalData.isPotentiallySensitive', 'true') AS m
ON COLUMN m;

-- 3) Sensitive data -> NULL ("removal") for everyone except authorized readers
CREATE OR REPLACE POLICY pii_sensitive_remove
ON CATALOG synthea
COMMENT 'LGPD art. 5 II: nulls sensitive data'
COLUMN MASK synthea.governance.mask_remove
TO `account users`
EXCEPT `synthea_pipeline`, `synthea_sensitive_readers`
FOR TABLES
MATCH COLUMNS has_tag_value('sap.PersonalData.isPotentiallySensitive', 'true')
          AND NOT has_tag_value('sap.PersonalData.isPotentiallyPersonal', 'true') AS s
ON COLUMN s;

-- 4) Personal AND sensitive -> only for users in both groups ("and" logic in the function)
CREATE OR REPLACE POLICY pii_personal_and_sensitive
ON CATALOG synthea
COMMENT 'Columns with both tags require pii_readers AND sensitive_readers'
COLUMN MASK synthea.governance.mask_requires_pii_and_sensitive
TO `account users`
EXCEPT `synthea_pipeline`
FOR TABLES
MATCH COLUMNS has_tag_value('sap.PersonalData.isPotentiallyPersonal', 'true')
          AND has_tag_value('sap.PersonalData.isPotentiallySensitive', 'true') AS ps
ON COLUMN ps;
