#!/usr/bin/env bash
# Isolated PostgreSQL only; never invoke on Supabase production.
# Requires schema-equivalent non-production DB and psql in PATH.
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
migration="$root/supabase/migrations/20261117084800_lf_ig_retention_10y_parameter_candidate_v1.sql"
test_sql="$root/sandbox/lf_contract_gate_test/input_governance/retention_10y_candidate_rollback_v1.sql"
test "$(printenv LF_PG_ISOLATED_TEST || true)" = "YES" || { echo "BLOCK_PG_ONLY_ISOLATED_TEST"; exit 3; }
python3 - "$migration" "$test_sql" <<'PY' | psql -X -v ON_ERROR_STOP=1
import pathlib, re, sys
migration=pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
assert len(re.findall(r'(?m)^BEGIN;\s*$',migration)) == 1
assert len(re.findall(r'(?m)^COMMIT;\s*$',migration)) == 1
migration=re.sub(r'(?m)^BEGIN;\s*$', '-- migrated BEGIN is owned by test', migration)
migration=re.sub(r'(?m)^COMMIT;\s*$', '-- migrated COMMIT intentionally suppressed',migration)
checks=pathlib.Path(sys.argv[2]).read_text(encoding='utf-8')
assert '\\ir' not in checks
print('BEGIN;')
print(migration)
print(checks)
print('ROLLBACK;')
PY
echo 'PASS_COMPOSED_RETENTION_10Y_PG_ROLLBACK_EXECUTED'
