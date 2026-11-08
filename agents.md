# agents.md

Instructions for agents (Claude Code etc.) working in this repository.

## Context
PII governance lab on Databricks (Unity Catalog) with Synthea data: governed tags
applied only to bronze, **tag propagation** carrying them to silver/gold, and
catalog-level **ABAC policies** masking whatever is tagged.

- Workspace: Databricks Free Edition, accessed through CLI profile `synthea` (host lives only in `~/.databrickscfg`, never in the repo)
- Catalog: `synthea` | schemas: `bronze` (source), `silver`, `gold`, `governance` (functions, test tables),
  `test` (analyst sandbox: the only schema where `synthea_analysts` can create tables)
- Warehouse: `Serverless Starter Warehouse` (resolved by name in `databricks.yml`)

## Running SQL
```bash
uv run src/scripts/run_sql.py <files.sql...>            # multiple statements per file
uv run src/scripts/run_sql.py -q "SELECT ..."           # runs after the files
uv run src/scripts/run_sql.py -q "..." --json out.json  # result of the last query ('-' = stdout)
```
Or via the bundle: `databricks bundle deploy` / `databricks bundle run synthea_medallion`.

## Rules
1. **Tags only in `src/governance/10_tags_bronze.sql`.** Never `SET TAGS` on silver/gold:
   the point is to prove that propagation covers everything downstream.
2. **Build silver/gold only with operations that propagate, on serverless:** CTAS,
   `INSERT INTO ... SELECT`, `MERGE`, `CREATE VIEW`. Declarative pipelines (DLT) and
   pipeline materialized views do NOT propagate.
3. **Whoever builds silver/gold must be in the masks' `EXCEPT`** (member of
   `synthea_pipeline`). Otherwise CTAS physically writes `***` (lost data).
   Check: `count(DISTINCT ssn_hash)` in `silver.patients` should be ~= row count.
4. **One distinct mask per column per user.** When adding a policy, make sure its
   `MATCH COLUMNS` + `TO/EXCEPT` do not overlap an existing one with a different function.
5. Text masks return STRING: do not tag non-string columns with
   `isPotentiallyPersonal` without switching to a VARIANT function (see `mask_remove`).
6. Personas = CLI profiles with an assumed role (`synthea-as-<group>`). In mask UDFs,
   test `is_account_group_member(g) OR current_user() = g` (a role is not a member of itself).
7. When adding a silver/gold scenario, add its expected rows to
   `src/tests/10_propagation.sql` and its task to `resources/medallion.job.yml`.
8. **Analysts write only to `synthea.test`.** Their CTAS stores what their masks show
   (SHA-256 for personal columns, `NULL` for sensitive ones). Grants live in
   `src/governance/05_grants.sql`; never give `synthea_analysts` CREATE on the catalog.
9. Repository content (docs, comments, messages, object comments) is in English.

## Layout
```
databricks.yml                     bundle (dev target)
resources/*.job.yml                jobs: synthea_governance, synthea_medallion
src/governance/                    05 grants | 10 bronze tags | 20 functions | 30 policies
src/transformations/silver|gold/   one propagation scenario per file
src/tests/                         10 propagation (blocking) | 20 masking | 30 persona matrix
src/scripts/                       run_sql.py (runner) | setup_identities.ps1 (groups/SP)
```
