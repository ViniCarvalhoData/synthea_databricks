# synthea_databricks

A PII governance lab on Databricks using [Synthea](https://synthetichealth.github.io/synthea/) data:

- **Governed tags** (`sap.PersonalData.*`) applied **only to bronze**
- **[Tag propagation](https://docs.databricks.com/aws/en/admin/governed-tags/tag-propagation)** carries the tags to silver and gold through lineage
- **ABAC policies** at the catalog level: redaction (`***`), pseudonymization (hash), "removal" (NULL) and group-based rules

## Setup

```powershell
winget install Databricks.DatabricksCLI   # CLI
winget install astral-sh.uv               # Python runner
databricks auth login --host https://<your-workspace>.cloud.databricks.com --profile synthea
```

## Workflow

```powershell
# 1. identities (once)
#    Free Edition has no account API access -> create the synthea_* groups in the UI
#    (Settings > Identity and access > Groups). With Account Console access:
powershell -ExecutionPolicy Bypass -File ./src/scripts/setup_identities.ps1 -WorkspaceId <workspace-id>

# 2. governance: bronze tags, functions, policies
uv run src/scripts/run_sql.py src/governance/10_tags_bronze.sql src/governance/20_functions.sql src/governance/30_policies.sql

# 3. medallion (run as an identity that is a member of synthea_pipeline!)
uv run src/scripts/run_sql.py src/transformations/silver/*.sql src/transformations/gold/*.sql

# 4. tests
uv run src/scripts/run_sql.py src/tests/10_propagation.sql   # expected vs. actual tags (fails if any is missing)
uv run src/scripts/run_sql.py src/tests/20_masking.sql       # what the current persona sees
```

You can also run it through the bundle: `databricks bundle deploy`, then `databricks bundle run synthea_governance` and `databricks bundle run synthea_medallion`.

The job runs as whoever deployed it (or as the service principal in `run_as`). `run_as` does not accept groups, so that identity must be a **member** of `synthea_pipeline` to write unmasked data. No schema ownership transfer is needed; that is only required to build the tables with the role assumed (see `05_grants.sql`).

## Propagation scenarios

| File | Operation | What it tests |
|---|---|---|
| `silver/01_patients_ctas.sql` | CTAS | renaming, `concat`, `right()`, `sha2()` |
| `silver/02_encounters_join.sql` | CTAS + JOIN | columns coming from `patients` and `providers` |
| `silver/03_patients_contact_insert.sql` | DDL + `INSERT ... SELECT` | pre-existing table |
| `silver/04_patients_merge.sql` | `MERGE` | incremental upsert |
| `silver/05_v_patient_contact_view.sql` | `CREATE VIEW` | views |
| `gold/01..03` | CTAS over silver | second hop, `GROUP BY`, aggregate over a sensitive column |

## Policies (`src/governance/30_policies.sql`)

| Policy | Tagged column | Applies to | Effect |
|---|---|---|---|
| `pii_personal_redact` | Personal (and not Sensitive) | `account users` except pipeline, pii_readers and analysts | `***` |
| `pii_personal_pseudonymize` | Personal (and not Sensitive) | `synthea_analysts`, except pipeline and pii_readers | SHA-256 |
| `pii_sensitive_remove` | Sensitive (and not Personal) | `account users` except pipeline and sensitive_readers | `NULL` |
| `pii_personal_and_sensitive` | Personal **and** Sensitive (e.g. `PASSPORT`) | `account users` except pipeline | `NULL`, unless the user is in pii_readers **and** sensitive_readers |

The groups are **independent axes**: `pii_readers` unlocks personal columns and `sensitive_readers` unlocks sensitive ones. Seeing everything requires both. `EXCEPT` can only express "or" between groups, so the "and" in the 4th policy lives inside the function (`is_account_group_member`).

## Personas via roles

A group can be assumed as a **role** ([Switch roles](https://docs.databricks.com/aws/en/security/auth/rbac/switch-roles)). The role replaces the user's permissions, and policies evaluate the role. In the UI this is the role switcher. In the CLI, create one profile per persona and pick the role in the browser:

```bash
databricks auth login --host https://<your-workspace>.cloud.databricks.com --profile synthea-as-analysts
# same for: synthea-as-pii_readers, synthea-as-sensitive_readers, synthea-as-pipeline
bash src/tests/run_personas.sh   # persona x column type matrix
```

With a role assumed, `current_user()` returns the group name and `is_account_group_member('<the role itself>')` returns **false**. Mask functions must check both (see `mask_requires_pii_and_sensitive`).

## Results so far (2026-10-20)

- **Propagation: 33/33 OK, no extra tags.** Tags showed up within seconds for CTAS, JOIN, INSERT, MERGE, VIEW and the second hop into gold, even with gold running right after silver. Untagged columns (`city`, `gender`, `healthcare_expenses`) stayed untagged.
- **Propagation is conservative.** Derived columns (`full_name`, `ssn_last4`, `ssn_hash`) and aggregates (`gold.demographics.race`) inherit the tag. A hash computed in the pipeline gets masked too. To release a derived column, change the policy (e.g. pseudonymize it), not the tag.
- **Pitfall: a CTAS run by a masked user physically writes `***`.** That is what happened to `bronze.patients_v2` and to the first silver/gold run: `ssn_hash` ended up with 1 distinct value across 1,163 rows. That is why the `synthea_pipeline` group is in `EXCEPT`. After the old `PII_policy` was dropped, silver and gold were rebuilt with intact data (1,163 distinct hashes), and tags stayed at 33/33 after `CREATE OR REPLACE`.
- **`EXCEPT synthea_pipeline` is enough on its own.** With all 4 policies active, the `synthea_medallion` job ran as a user who was a member **only** of `synthea_pipeline` (`is_account_group_member()` false for the 3 reader groups). Result: 1,163 distinct hashes, 6 races, 887 passports, no `***` written and no missing tags.
- **Propagation also works from jobs:** bundle SQL tasks on a serverless warehouse propagate just like ad hoc queries.
