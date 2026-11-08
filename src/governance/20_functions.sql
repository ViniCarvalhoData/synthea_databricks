-- =====================================================================
-- Functions used by the ABAC policies. They live in a schema separate from the data.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS synthea.governance COMMENT 'Mask/filter functions used by ABAC policies';

-- Redaction: replaces the value with '***' (equivalent to the UI-created mask_value)
CREATE OR REPLACE FUNCTION synthea.governance.mask_redact(value STRING)
RETURNS STRING
DETERMINISTIC
COMMENT 'ABAC: replaces the value with ***'
RETURN CASE WHEN value IS NULL THEN NULL ELSE '***' END;

-- Column "removal": ABAC does not drop columns from the schema; the equivalent is
-- returning NULL. VARIANT lets the same function serve any column type.
CREATE OR REPLACE FUNCTION synthea.governance.mask_remove(value VARIANT)
RETURNS VARIANT
DETERMINISTIC
COMMENT 'ABAC: nulls the value (any type)'
RETURN NULL::VARIANT;

-- Personal + Sensitive columns (e.g. PASSPORT): require membership in BOTH groups.
-- A policy's EXCEPT can only express "or" between groups; the "and" lives in the function.
-- With an assumed role, current_user() = the group name and is_account_group_member()
-- on the role itself is FALSE (a role is not a member of itself) -> check both.
CREATE OR REPLACE FUNCTION synthea.governance.mask_requires_pii_and_sensitive(value VARIANT)
RETURNS VARIANT
COMMENT 'ABAC: value only for users in synthea_pii_readers AND synthea_sensitive_readers'
RETURN CASE
  WHEN (is_account_group_member('synthea_pii_readers')       OR current_user() = 'synthea_pii_readers')
   AND (is_account_group_member('synthea_sensitive_readers') OR current_user() = 'synthea_sensitive_readers')
  THEN value
  ELSE NULL::VARIANT
END;

-- Pseudonymization: deterministic hash; keeps joins/counts working without exposing the value.
-- The suffix acts as a "version"/salt; in production, move the salt into a secret.
CREATE OR REPLACE FUNCTION synthea.governance.mask_pseudonymize(value STRING)
RETURNS STRING
DETERMINISTIC
COMMENT 'ABAC: deterministic SHA-256 hash (pseudonym)'
RETURN CASE WHEN value IS NULL THEN NULL ELSE sha2(concat(value, ':synthea-v1'), 256) END;
