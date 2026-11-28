#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo F1_SETUP_UNSAFE_TARGET; exit 2; }
[[ -n "${F1_CANDIDATE:-}" && -f "$F1_CANDIDATE" ]] || { echo F1_CANDIDATE_NOT_AVAILABLE; exit 3; }
[[ -n "${F1_CANDIDATE_SHA256:-}" ]] || { echo F1_CANDIDATE_SHA_MISSING; exit 4; }
printf '%s  %s\n' "$F1_CANDIDATE_SHA256" "$F1_CANDIDATE" | sha256sum -c -

export PGDATABASE=postgres
psql -XAt -v ON_ERROR_STOP=1 -c 'show server_version_num' | grep -qE '^17[0-9]{4}$' || { echo F1_SETUP_PG17_REQUIRED; exit 5; }

for db in lf_creative_f1_baseline lf_creative_f1_candidate lf_creative_f1_ci; do
  dropdb --if-exists --maintenance-db=postgres "$db"
done
createdb --maintenance-db=postgres lf_creative_f1_ci
export PGDATABASE=lf_creative_f1_ci

mapfile -t baseline < <(find "$ROOT/baseline" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort)
[[ "${#baseline[@]}" -ge 16 ]] || { echo F1_BASELINE_FILES_INCOMPLETE; printf '%s\n' "${baseline[@]}"; exit 6; }
for f in "${baseline[@]}"; do
  PGOPTIONS='-c check_function_bodies=off' psql -X -v ON_ERROR_STOP=1 -f "$ROOT/baseline/$f"
done

expected=$'creative_item_context_l2a|223cbd0aa8389fbec25ad9d573db325e\ncreative_item_work_packet_l2c|f52aed44b80baa594a0759e82dcf00a3\ncreative_item_visual_contract_l3b|d5740e72b1b432af151cbb0dd58855ea\ncreative_native_render_wire_v1|fb423d064be4e487d3e9e5c80bc03694\ncreative_queue_claim_by_id_v1|2038b1ccb96a94cc50025cadd5e64382\ncreative_run_guard_l1|49bb962b43bb23b3424c480f9557a4b4\ncreative_execution_policy_for_item_v1|0d1977f3bc73f3ec99545e37451e4225'
actual="$(psql -XAt -F '|' -v ON_ERROR_STOP=1 <<'SQL'
select p.proname,md5(pg_get_functiondef(p.oid))
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='saly' and p.proname in (
 'creative_item_context_l2a','creative_item_work_packet_l2c','creative_item_visual_contract_l3b',
 'creative_native_render_wire_v1','creative_queue_claim_by_id_v1','creative_run_guard_l1',
 'creative_execution_policy_for_item_v1')
order by array_position(array[
 'creative_item_context_l2a','creative_item_work_packet_l2c','creative_item_visual_contract_l3b',
 'creative_native_render_wire_v1','creative_queue_claim_by_id_v1','creative_run_guard_l1',
 'creative_execution_policy_for_item_v1'],p.proname);
SQL
)"
[[ "$actual" == "$expected" ]] || { echo F1_BASELINE_FUNCTION_MD5_DRIFT; diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true; exit 7; }
echo F1_BASELINE_MD5_7_7_PASS

export PGDATABASE=postgres
createdb --maintenance-db=postgres -T lf_creative_f1_ci lf_creative_f1_baseline
export PGDATABASE=lf_creative_f1_ci
psql -X -v ON_ERROR_STOP=1 -f "$F1_CANDIDATE"

# Candidate must actually replace the seven bridge functions.
changed="$(psql -XAt -v ON_ERROR_STOP=1 <<'SQL'
select count(*)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='saly' and p.proname in (
 'creative_item_context_l2a','creative_item_work_packet_l2c','creative_item_visual_contract_l3b',
 'creative_native_render_wire_v1','creative_queue_claim_by_id_v1','creative_run_guard_l1',
 'creative_execution_policy_for_item_v1')
and md5(pg_get_functiondef(p.oid)) not in (
 '223cbd0aa8389fbec25ad9d573db325e','f52aed44b80baa594a0759e82dcf00a3',
 'd5740e72b1b432af151cbb0dd58855ea','fb423d064be4e487d3e9e5c80bc03694',
 '2038b1ccb96a94cc50025cadd5e64382','49bb962b43bb23b3424c480f9557a4b4',
 '0d1977f3bc73f3ec99545e37451e4225');
SQL
)"
[[ "$changed" -ge 7 ]] || { echo F1_CANDIDATE_BRIDGES_NOT_REPLACED; exit 8; }

export PGDATABASE=postgres
createdb --maintenance-db=postgres -T lf_creative_f1_ci lf_creative_f1_candidate
export PGDATABASE=lf_creative_f1_ci
printf 'F1_SETUP_PASS|baseline=lf_creative_f1_baseline|candidate=lf_creative_f1_candidate|sha256=%s\n' "$F1_CANDIDATE_SHA256"
