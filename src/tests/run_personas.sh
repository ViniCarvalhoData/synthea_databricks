#!/usr/bin/env bash
# Runs the persona matrix with each CLI role profile.
# Create each profile once (picking the role in the browser):
#   databricks auth login --host https://<your-workspace>.cloud.databricks.com --profile synthea-as-analysts
# Expected profiles: synthea (you, no role) + synthea-as-<group without the synthea_ prefix>
set -uo pipefail
cd "$(dirname "$0")/../.."

PROFILES=${PROFILES:-"synthea synthea-as-analysts synthea-as-pii_readers synthea-as-sensitive_readers synthea-as-pipeline"}

printf "%-34s | %-15s | %-13s | %-14s | %s\n" persona personal_silver personal_gold sensitive_gold personal_and_sensitive
for p in $PROFILES; do
  out=$(uv run -q src/scripts/run_sql.py -p "$p" src/tests/30_persona_matrix.sql --json - 2>/dev/null)
  if [ -z "$out" ]; then echo "$p: failed (does the profile exist? is the role assumed?)"; continue; fi
  echo "$out" | uv run -q python -c "import json,sys; r=json.load(sys.stdin)[0]; print('%-34s | %-15s | %-13s | %-14s | %s' % (r['persona'], r['personal_silver'], r['personal_gold'], r['sensitive_gold'], r['personal_and_sensitive']))"
done
