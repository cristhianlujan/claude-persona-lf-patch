#!/usr/bin/env bash
# LF Phase 1: disposable and candidate-only qualification. Never Supabase.
set -euo pipefail
: "${SELECTOR_EXP_DISPOSABLE_DB:?set SELECTOR_EXP_DISPOSABLE_DB=YES}"
[[ "$SELECTOR_EXP_DISPOSABLE_DB" == "YES" ]]
[[ "${PGHOST:-}" == "127.0.0.1" ]]
[[ "${PGUSER:-}" == "postgres" ]]
[[ -n "${PGPASSWORD:-}" ]]
export PROFILE_CANDIDATE_HEAD_SHA="$(git rev-parse HEAD)"
echo "LF_PHASE1_CANDIDATE_HEAD=$PROFILE_CANDIDATE_HEAD_SHA"
echo "LF_PHASE1_AUTHORITY=CANDIDATE_SANDBOX_ONLY"
base=sandbox/lf_contract_gate_test/programming_agent_four_stage
dbs=()
cleanup() {
  for db in "${dbs[@]}"; do
    dropdb -h 127.0.0.1 -U postgres --if-exists "$db" || true
  done
}
trap cleanup EXIT
next_db() {
  local name="selector_exp_test_phase1_${GITHUB_RUN_ID:-local}_$1"
  createdb -h 127.0.0.1 -U postgres "$name"
  dbs+=("$name")
  export SELECTOR_EXP_TEST_DSN="postgresql://postgres:${PGPASSWORD}@127.0.0.1:5432/$name"
}
echo "SUITE PG00 PIN / SOURCE DRIFT"
python3 "$base/programmer_profiles_exp/stack_skills_exp/test_pg00_pinned_catalog.py"
echo "SUITE PROFILE PACKS / ROLE + EXPERT STACK"
python3 "$base/programmer_profiles_exp/test_profile_packs.py"
echo "SUITE SELECTOR ORIGINAL PARITY - DB A"
next_db parity
python3 "$base/selector_experimental/tests/test_parity.py"
echo "SUITE SELECTOR EXPERIMENTAL - DB B"
next_db experimental
python3 "$base/selector_experimental/tests/test_experimental.py"
echo "SUITE PG04->PG07 BRIDGE - DB C"
next_db bridge
python3 "$base/selector_experimental/integration/test_pg04_pg07_selector_bridge_v1.py"
echo "SUITE PG04->PG14 REGRESSION - ORIGINAL CANDIDATE PRODUCERS"
python3 -m unittest discover -s "$base/ex5c_real_chain_candidate/tests" -p 'test_ex5c_real_chain_pg04_pg14_v2.py' -v
echo "LF_PHASE1_PASE_VISIBLE_SUITES_COMPLETE"
