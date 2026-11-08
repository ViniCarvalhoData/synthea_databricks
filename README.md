# synthea_databricks

A PII governance lab on Databricks using [Synthea](https://synthetichealth.github.io/synthea/) data:

- **Governed tags** (`sap.PersonalData.*`) applied **only to bronze**
- **[Tag propagation](https://docs.databricks.com/aws/en/admin/governed-tags/tag-propagation)** carries the tags to silver and gold through lineage
- **ABAC policies** at the catalog level: redaction (`***`), pseudonymization (hash), "removal" (NULL) and group-based rules

## Setup

Two tools are needed: the [Databricks CLI](https://docs.databricks.com/aws/en/dev-tools/cli/install) (auth, bundle) and [uv](https://docs.astral.sh/uv/) (runs `run_sql.py` with its dependencies, no virtualenv to manage). The workspace host is never stored in the repo: it lives in the `synthea` profile of your `~/.databrickscfg`, which both `run_sql.py` and the bundle read.

### Windows (PowerShell)

```powershell
winget install Databricks.DatabricksCLI
winget install astral-sh.uv
# open a new terminal so both are on PATH, then:
git clone https://github.com/<you>/synthea_databricks.git
cd synthea_databricks
databricks auth login --host https://<your-workspace>.cloud.databricks.com --profile synthea
```

The profile is saved to `%USERPROFILE%\.databrickscfg`. The bash script used for personas (`src/tests/run_personas.sh`) needs **Git Bash** (ships with Git for Windows) or WSL. Do not call it with `bash` from PowerShell: that may launch WSL's bash, which has its own PATH and its own `~/.databrickscfg`.

### WSL (Ubuntu)

```bash
sudo apt update && sudo apt install -y curl git unzip
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sudo sh
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc   # puts uv on PATH (or open a new shell)

# clone inside the Linux filesystem (~), not under /mnt/c: much faster, and away from OneDrive sync
cd ~ && git clone https://github.com/<you>/synthea_databricks.git
cd synthea_databricks
databricks auth login --host https://<your-workspace>.cloud.databricks.com --profile synthea
```

- WSL has its own `~/.databrickscfg`, separate from Windows: log in (and create the persona profiles) in each environment you use.
- If no browser opens during `auth login`, copy the URL the CLI prints into your Windows browser. WSL2 forwards the `localhost` callback, so the login completes.
- `setup_identities.ps1` needs PowerShell 7 (`pwsh`) on Linux. You only need it with Account Console access (see "Create the groups" below).

## Workspace preparation (once)

Everything below works on [Databricks Free Edition](https://www.databricks.com/learn/free-edition). Do it in this order: the governance scripts expect the data, the tags and the groups to already exist.

### 1. Get the Synthea data

[Synthea](https://synthetichealth.github.io/synthea/) generates realistic but fully synthetic patient records, so no real person's data is involved. You can get it in either of two ways:

- **Download a ready-made sample:** the [Synthea downloads page](https://synthea.mitre.org/downloads) has CSV datasets. The ~1K-patient CSV sample is enough.
- **Generate your own:** follow [Basic Setup and Running](https://github.com/synthetichealth/synthea/wiki/Basic-Setup-and-Running). With Java 17+ installed, download `synthea-with-dependencies.jar` and run `java -jar synthea-with-dependencies.jar -p 1000 --exporter.csv.export=true`. The CSVs land in `output/csv/`.

The lab only uses **`patients.csv`**, **`encounters.csv`** and **`providers.csv`**.

### 2. Create the catalog and load bronze

In the SQL editor, connected to a serverless SQL warehouse:

```sql
CREATE CATALOG IF NOT EXISTS synthea;
CREATE SCHEMA  IF NOT EXISTS synthea.bronze;
CREATE SCHEMA  IF NOT EXISTS synthea.silver;
CREATE SCHEMA  IF NOT EXISTS synthea.gold;
CREATE SCHEMA  IF NOT EXISTS synthea.governance;
CREATE VOLUME  IF NOT EXISTS synthea.bronze.raw;
```

Upload the three CSVs to the volume, either in the UI (**Catalog > synthea > bronze > raw > Upload to this volume**) or with the CLI:

```bash
databricks fs cp patients.csv   dbfs:/Volumes/synthea/bronze/raw/ --profile synthea
databricks fs cp encounters.csv dbfs:/Volumes/synthea/bronze/raw/ --profile synthea
databricks fs cp providers.csv  dbfs:/Volumes/synthea/bronze/raw/ --profile synthea
```

Then create the bronze tables, keeping Synthea's original column names (`Id`, `SSN`, `FIRST`, ...), since the scripts rely on them:

```sql
CREATE TABLE IF NOT EXISTS synthea.bronze.patients AS
SELECT * FROM read_files('/Volumes/synthea/bronze/raw/patients.csv', format => 'csv', header => true);

CREATE TABLE IF NOT EXISTS synthea.bronze.encounters AS
SELECT * FROM read_files('/Volumes/synthea/bronze/raw/encounters.csv', format => 'csv', header => true);

CREATE TABLE IF NOT EXISTS synthea.bronze.providers AS
SELECT * FROM read_files('/Volumes/synthea/bronze/raw/providers.csv', format => 'csv', header => true);
```

### 3. Create the governed tags

In **Catalog > Govern > Governed tags** (see [governed tags](https://docs.databricks.com/aws/en/admin/governed-tags/)), create these two tags with the allowed value `true`, and turn on [tag propagation](https://docs.databricks.com/aws/en/admin/governed-tags/tag-propagation) for both:

- `sap.PersonalData.isPotentiallyPersonal`: personal identifiers (name, SSN, address, ...)
- `sap.PersonalData.isPotentiallySensitive`: sensitive data (race, ethnicity, ...)

### 4. Create the groups

Free Edition has no account API, so create the groups in the UI (**Settings > Identity and access > Groups**):

| Group | Purpose |
|---|---|
| `synthea_pipeline` | builds silver/gold; exempt from every mask. **Add yourself to it**, or the pipeline writes `***` into the tables |
| `synthea_pii_readers` | sees personal columns in the clear |
| `synthea_sensitive_readers` | sees sensitive columns in the clear |
| `synthea_analysts` | sees personal columns pseudonymized (SHA-256) |

With Account Console access (not available on Free Edition), `src/scripts/setup_identities.ps1` creates the groups and a pipeline service principal for you:

```bash
# Windows
powershell -ExecutionPolicy Bypass -File ./src/scripts/setup_identities.ps1 -WorkspaceId <workspace-id>
# WSL
pwsh ./src/scripts/setup_identities.ps1 -WorkspaceId <workspace-id>
```

## Workflow

The `uv run` commands are the same in PowerShell, Git Bash and WSL. `run_sql.py` expands wildcards like `silver/*.sql` itself, because PowerShell passes them through unexpanded.

```bash
# 1. governance: bronze tags, functions, policies
uv run src/scripts/run_sql.py src/governance/10_tags_bronze.sql src/governance/20_functions.sql src/governance/30_policies.sql

# 2. medallion (run as an identity that is a member of synthea_pipeline!)
uv run src/scripts/run_sql.py src/transformations/silver/*.sql src/transformations/gold/*.sql

# 3. tests
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
```

Then run the persona x column type matrix from a bash shell. On Windows, use Git Bash. On WSL, use your regular terminal, and create the profiles inside WSL first:

```bash
bash src/tests/run_personas.sh
PROFILES="synthea synthea-as-analysts" bash src/tests/run_personas.sh   # subset of personas
```

With a role assumed, `current_user()` returns the group name and `is_account_group_member('<the role itself>')` returns **false**. Mask functions must check both (see `mask_requires_pii_and_sensitive`).

## Results so far (2026-10-20)

- **Propagation: 33/33 OK, no extra tags.** Tags showed up within seconds for CTAS, JOIN, INSERT, MERGE, VIEW and the second hop into gold, even with gold running right after silver. Untagged columns (`city`, `gender`, `healthcare_expenses`) stayed untagged.
- **Propagation is conservative.** Derived columns (`full_name`, `ssn_last4`, `ssn_hash`) and aggregates (`gold.demographics.race`) inherit the tag. A hash computed in the pipeline gets masked too. To release a derived column, change the policy (e.g. pseudonymize it), not the tag.
- **Pitfall: a CTAS run by a masked user physically writes `***`.** That is what happened to `bronze.patients_v2` and to the first silver/gold run: `ssn_hash` ended up with 1 distinct value across 1,163 rows. That is why the `synthea_pipeline` group is in `EXCEPT`. After the old `PII_policy` was dropped, silver and gold were rebuilt with intact data (1,163 distinct hashes), and tags stayed at 33/33 after `CREATE OR REPLACE`.
- **`EXCEPT synthea_pipeline` is enough on its own.** With all 4 policies active, the `synthea_medallion` job ran as a user who was a member **only** of `synthea_pipeline` (`is_account_group_member()` false for the 3 reader groups). Result: 1,163 distinct hashes, 6 races, 887 passports, no `***` written and no missing tags.
- **Propagation also works from jobs:** bundle SQL tasks on a serverless warehouse propagate just like ad hoc queries.
