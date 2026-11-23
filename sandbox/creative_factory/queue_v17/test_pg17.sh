#!/usr/bin/env bash
set -euo pipefail
: "${PGHOST:?}" "${PGDATABASE:?}" "${PGUSER:?}"
if [[ "${PGHOST}" != '127.0.0.1' || "${PGDATABASE}" != 'saly_reserve_v17_test' ]]; then
 echo 'CREATIVE_V17_NON_DISPOSABLE_DB_FORBIDDEN'; exit 2
fi
if [[ "$(psql -XAt -v ON_ERROR_STOP=1 -c 'SHOW server_version_num' | cut -c 1-2)" != 17 ]]; then
 echo 'CREATIVE_V17_PG17_REQUIRED'; exit 2
fi
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v02/fixture_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v17/entry_prerequisites_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v05/001_saly_native_render_wire_candidate.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v06/001_saly_delivery_attestation_guard_candidate.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123084800_lf_saly_creative_chat_entry_qa_gate_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f supabase/migrations/20261123091700_lf_saly_creative_native_dispatch_reservation_v1.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v10/setup_pg17.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v10/test_pg17_candidate.sql
if [[ "$(psql -XAt -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM saly.creative_queue_native_dispatch_reservations_v1')" != "0" ]]; then
 echo 'CREATIVE_V17_TEST_ROLLBACK_LEAK'; exit 1
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
query="SELECT saly.creative_queue_native_reserve_dispatch_v1(
 c.claim_token,c.run_id,'GPT_NATIVE',c.wire_sha256,c.archive_sha256,
 'V17-CONCURRENT-001')->>'status' FROM saly.test_v10_context c"
psql -XAt -v ON_ERROR_STOP=1 -c "$query" > "$tmp/1" 2>"$tmp/1err" & p1=$!
psql -XAt -v ON_ERROR_STOP=1 -c "$query" > "$tmp/2" 2>"$tmp/2err" & p2=$!
wait "$p1"; wait "$p2"
sort "$tmp/1" "$tmp/2" > "$tmp/actual"
printf '%s\n' ALREADY_RESERVED_NOT_DISPATCHED RESERVED_NOT_DISPATCHED > "$tmp/expected"
if ! cmp -s "$tmp/actual" "$tmp/expected"; then
 cat "$tmp/actual" "$tmp/1err" "$tmp/2err"; echo 'CREATIVE_V17_CONCURRENCY_FAILED'; exit 1
fi
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM saly.creative_queue_native_dispatch_reservations_v1" | grep -qx 1
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM saly.creative_queue_native_delivery_evidence_v1" | grep -qx 0
psql -XAt -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM saly.creative_orders WHERE code IN ('SALY_HOME_V015_SINGLE_20261123','SALY_ADELANTO_V015_SINGLE_20261123') AND status='PLANIFICADO' AND scope_json->>'render_authorized'='false'" | grep -qx 2
echo 'PASS_SALY_V17_PG17_IDEMPOTENT_TWO_WORKERS_ONE_RESERVATION_ZERO_DISPATCH'
