#!/usr/bin/env bash
# SALY creative config seed: disposable PostgreSQL 17 ONLY.
set -euo pipefail
[[ "${PGDATABASE:-}" == "saly_policy_test" && "${PGHOST:-}" == "127.0.0.1" ]] || {
  echo "BLOCK_PG17_NON_ISOLATED_TARGET"; exit 2;
}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FIX="$ROOT/sandbox/creative_factory/queue_v13/fixture_policy_pg17.sql"
MIG="$ROOT/supabase/migrations/20261123020000_lf_saly_creative_factory_policy_seed_v1.sql"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
reset_db() { psql -v ON_ERROR_STOP=1 -X -q -f "$FIX" >/dev/null; }
policy_readback() {
  psql -v ON_ERROR_STOP=1 -X -A -t -c \
  "SELECT count(*)::text||'|'||
    (saly.creative_execution_policy_v1(now())->>'QUEUE_MAX')||'|'||
    (saly.creative_execution_policy_v1(now())->>'MAX_ATTEMPTS')||'|'||
    (saly.creative_execution_policy_v1(now())->>'QUEUE_TIMEOUT_SECONDS')||'|'||
    (saly.creative_execution_policy_v1(now())->>'LEASE_SECONDS')
   FROM saly.config_global WHERE scope='CREATIVE_FACTORY';"
}
must_fail() {
  local code="$1"; shift
  set +e; "$@" >"$TMP/negative.log" 2>&1; local rc=$?; set -e
  if [[ "$rc" -eq 0 ]] || ! grep -Fq "$code" "$TMP/negative.log"; then
    echo "FAIL_EXPECTED_CONTROL:$code rc=$rc"; cat "$TMP/negative.log"; exit 1
  fi
  echo "PASS_NEGATIVE:$code"
}
reset_db
psql -v ON_ERROR_STOP=1 -X -q -f "$MIG" >"$TMP/positive.log"
[[ "$(policy_readback)" == "4|1|2|900|600" ]] || { echo "FAIL_POLICY_READBACK"; exit 1; }
echo "PASS_POLICY_4_4_SQL_READBACK"
must_fail "SALY_CREATIVE_POLICY_ALREADY_DEFINED" psql -v ON_ERROR_STOP=1 -X -q -f "$MIG"
[[ "$(policy_readback)" == "4|1|2|900|600" ]] || exit 1

reset_db
sed "s/('LEASE_SECONDS','600'/('LEASE_SECONDS','601'/" "$MIG" >"$TMP/mutant.sql"
must_fail "SALY_CREATIVE_POLICY_READBACK_MISMATCH" psql -v ON_ERROR_STOP=1 -X -q -f "$TMP/mutant.sql"
[[ "$(psql -v ON_ERROR_STOP=1 -X -Atc "SELECT count(*) FROM saly.config_global WHERE scope='CREATIVE_FACTORY'")" == "0" ]] || { echo "FAIL_MUTATION_ROLLBACK"; exit 1; }
echo "PASS_MUTATION_ROLLBACK"
reset_db
psql -v ON_ERROR_STOP=1 -X -q -c "INSERT INTO saly.creative_runs(state) VALUES ('EJECUTANDO')" >/dev/null
must_fail "SALY_CREATIVE_POLICY_ACTIVE_RUN_BLOCK" psql -v ON_ERROR_STOP=1 -X -q -f "$MIG"
reset_db
psql -v ON_ERROR_STOP=1 -X -q -c "DROP FUNCTION saly.creative_execution_policy_v1(timestamptz)" >/dev/null
must_fail "SALY_CREATIVE_POLICY_SCHEMA_REQUIRED" psql -v ON_ERROR_STOP=1 -X -q -f "$MIG"

reset_db
set +e
psql -v ON_ERROR_STOP=1 -X -q -f "$MIG" >"$TMP/a.log" 2>&1 & a=$!
psql -v ON_ERROR_STOP=1 -X -q -f "$MIG" >"$TMP/b.log" 2>&1 & b=$!
wait "$a"; ra=$?
wait "$b"; rb=$?
set -e
if [[ $(( (ra==0) + (rb==0) )) -ne 1 ]]; then
  echo "FAIL_CONCURRENT_SINGLE_WINNER:ra=$ra rb=$rb"; cat "$TMP/a.log" "$TMP/b.log"; exit 1
fi
grep -Fq "SALY_CREATIVE_POLICY_ALREADY_DEFINED" "$TMP/a.log" "$TMP/b.log" || { echo "FAIL_CONCURRENT_LOSER_CONTROL"; exit 1; }
[[ "$(policy_readback)" == "4|1|2|900|600" ]] || { echo "FAIL_CONCURRENT_READBACK"; exit 1; }
echo "PASS_CONCURRENT_SINGLE_WRITER"
echo "PASS_SALY_CREATIVE_FACTORY_SEED_PG17"
