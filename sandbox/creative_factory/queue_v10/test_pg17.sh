#!/usr/bin/env bash
# ONLY PostgreSQL 17 disposable DB, never production/Supabase.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${PGHOST:?}" "${PGUSER:?}" "${PGDATABASE:?}"
[[ "$PGDATABASE" == "saly_queue_test" &&
   ( "$PGHOST" == "127.0.0.1" || "$PGHOST" == "localhost" ) ]] || {
 echo BLOCK_NON_DISPOSABLE_DB; exit 2;
}
[[ -z "${PGPASSWORD:-}" && -z "${LF_SUPABASE_DB_PASSWORD:-}" ]] || {
 echo BLOCK_DB_SECRET_ENV; exit 2;
}
psql -XAt -v ON_ERROR_STOP=1 -c "show server_version_num" | grep -qE '^17[0-9]{4}$' || {
 echo BLOCK_PG17_REQUIRED; exit 2;
}
reset(){
 psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/queue_v02/fixture_pg17.sql" >/dev/null
}
prepare(){
 reset
 psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/queue_v05/001_saly_native_render_wire_candidate.sql" >/dev/null
 psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/queue_v06/001_saly_delivery_attestation_guard_candidate.sql" >/dev/null
 psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/queue_v10/001_saly_native_dispatch_reservation_candidate.sql" >/dev/null
 psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/queue_v10/setup_pg17.sql" >/dev/null
}
prepare
echo 'V10 PG17 real V05 producer + V06 DONE gate + SQL rollback tests'
psql -X -q -v ON_ERROR_STOP=1 -f "$ROOT/queue_v10/test_pg17_candidate.sql"
[[ "$(psql -XAt -v ON_ERROR_STOP=1 -c "select count(*) from saly.creative_queue_native_dispatch_reservations_v1")" == "0" ]] || {
 echo BLOCK_V10_NEGATIVE_TEST_ROLLBACK_LEAK; exit 1;
}
echo 'V10 B7 concurrency: 2 real psql processes, 1 idempotent row'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
q="SELECT saly.creative_queue_native_reserve_dispatch_v1(
 c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,
 'V10-CONCURRENT-001')->>'status' FROM saly.test_v10_context c"
psql -XAt -v ON_ERROR_STOP=1 -c "$q" > "$tmp/one" 2> "$tmp/one.err" &
p1=$!
psql -XAt -v ON_ERROR_STOP=1 -c "$q" > "$tmp/two" 2> "$tmp/two.err" &
p2=$!
s1=0;s2=0
wait "$p1" || s1=$?
wait "$p2" || s2=$?
if ((s1!=0 || s2!=0)); then cat "$tmp/"*.err; echo V10_CONCURRENT_SQL_FAILED; exit 1; fi
sort "$tmp/one" "$tmp/two" > "$tmp/sorted"
printf '%s\n' "ALREADY_RESERVED_NOT_DISPATCHED" "RESERVED_NOT_DISPATCHED" > "$tmp/expected"
cmp -s "$tmp/sorted" "$tmp/expected" || {
 cat "$tmp/sorted"; echo V10_CONCURRENT_IDEMPOTENCY_FAILURE; exit 1;
}
[[ "$(psql -XAt -v ON_ERROR_STOP=1 -c "select count(*) from saly.creative_queue_native_dispatch_reservations_v1")" == "1" ]] || {
 echo V10_CONCURRENT_DUPLICATE; exit 1;
}
[[ "$(psql -XAt -v ON_ERROR_STOP=1 -c "select count(*) from saly.creative_queue_native_delivery_evidence_v1")" == "0" ]] || {
 echo V10_FALSE_HOST_DELIVERY; exit 1;
}
echo 'PASS_B7_TWO_REAL_WORKERS_ONE_RESERVATION_ZERO_DISPATCH'
python3 "$ROOT/queue_v10/test_mutations_pg17.py"
echo 'RESTORE_TEST_FIXTURE_AFTER_ALL_MUTANTS'
reset
[[ "$(psql -XAt -v ON_ERROR_STOP=1 -c "select coalesce(to_regclass('saly.creative_queue_native_dispatch_reservations_v1')::text,'NONE')")" == "NONE" ]] || {
 echo V10_RESTORE_FAILED; exit 1;
}
echo 'PASS_V10_PG17_NEGATIVE_ROLLBACK_CONCURRENCY_MUTATIONS_RESTORE'
