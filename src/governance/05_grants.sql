-- Privileges. Read access: `account users` already has USE CATALOG/USE SCHEMA/SELECT/EXECUTE
-- on the catalog (Free Edition default), so the reader roles need no extra grants.
--
-- Analysts: they may create tables ONLY in the `test` sandbox schema. A CTAS run by an
-- analyst reads through their masks and stores what they see: SSN/names as SHA-256 and
-- sensitive columns (RACE, PASSPORT) as NULL (bronze.patients_v3/v4, 2026-11-08). Such a
-- copy must never land in bronze/silver/gold, so no CREATE privilege on the catalog.
REVOKE CREATE TABLE, CREATE MATERIALIZED VIEW, CREATE SCHEMA ON CATALOG synthea FROM `synthea_analysts`;
CREATE SCHEMA IF NOT EXISTS synthea.test COMMENT 'Sandbox for analysts; tables here hold masked copies';
GRANT USE SCHEMA, CREATE TABLE ON SCHEMA synthea.test TO `synthea_analysts`;
--
-- Pipeline: the bundle job runs as a user/service principal (run_as does not accept
-- groups) that is a MEMBER of synthea_pipeline. It uses its own permissions (it owns
-- the tables), so no grant is needed here.
--
-- Only run the block below to build silver/gold with the synthea_pipeline role
-- ASSUMED (profile synthea-as-pipeline): the role replaces the user's permissions,
-- and only the schema owner can replace/drop the tables inside it.
--
-- ALTER SCHEMA synthea.silver OWNER TO `synthea_pipeline`;
-- ALTER SCHEMA synthea.gold   OWNER TO `synthea_pipeline`;
-- GRANT USE SCHEMA, SELECT ON SCHEMA synthea.bronze TO `synthea_pipeline`;
