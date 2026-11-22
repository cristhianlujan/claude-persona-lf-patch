#!/usr/bin/env bash
# V12 scoped pending-only PG17: isolated test database ONLY.
set -Eeuo pipefail
cd "$(dirname "$0")/../../.."
test "$PGHOST" = 127.0.0.1 && test "$PGUSER" = postgres && test "$PGDATABASE" = saly_queue_test || { echo BLOCK_NON_DISPOSABLE_DB; exit 2; }
test -z "$(printenv PGPASSWORD || true)" && test -z "$(printenv LF_SUPABASE_DB_PASSWORD || true)" || { echo BLOCK_LIVE_CREDENTIAL_ENV; exit 2; }
psql -XAt -v ON_ERROR_STOP=1 -c "show server_version_num" | grep -qE '^17[0-9]{4}$' || { echo BLOCK_NON_PG17; exit 2; }
psql -Xq -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v02/fixture_pg17.sql >/dev/null
psql -Xq -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v12/001_pending_only_begin_candidate.sql >/dev/null
psql -Xq -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v12/setup_pg17.sql >/dev/null
db(){ psql -XAt -v ON_ERROR_STOP=1 -c "$1"; }
eq(){ if test "$1" != "$2"; then echo "FAIL $3 expected=$2 got=$1"; exit 1; fi; echo "PASS_V12_$3"; }
snapshot='{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'
psql -Xq -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE result jsonb;
BEGIN
 BEGIN
  PERFORM saly.creative_chat_begin_pending_v1('UNKNOWN',ARRAY['HOME'],'V12','key',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb);
  RAISE EXCEPTION 'BAD_ORDER_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_ORDER_NOT_ACTIVE' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM saly.creative_chat_begin_pending_v1('V12_REVIEW',ARRAY['HOME'],'V12','key',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb);
  RAISE EXCEPTION 'REVIEW_ONLY_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_RENDER_NOT_AUTHORIZED' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM saly.creative_chat_begin_pending_v1('V12_CHAT',ARRAY[]::text[],'V12','key',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb);
  RAISE EXCEPTION 'EMPTY_SCOPE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CHAT_BAD_INPUT' THEN RAISE; END IF;
 END;
 SELECT saly.creative_chat_begin_pending_v1('V12_EMPTY',ARRAY['HOME'],'V12','key',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb)
 INTO result;
 IF result->>'status'<>'NO_PENDING_IN_SCOPE' THEN RAISE EXCEPTION 'EMPTY_ORDER_CHANGED'; END IF;
END $$;
BEGIN;
DELETE FROM saly.config_global WHERE scope='CREATIVE_FACTORY' AND config_key='LEASE_SECONDS';
DO $$
BEGIN
 BEGIN
  PERFORM saly.creative_chat_begin_pending_v1('V12_CHAT',ARRAY['HOME'],'V12','key',
    '{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'::jsonb);
  RAISE EXCEPTION 'POLICY_BYPASS';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CREATIVE_CONFIG_MISSING:LEASE_SECONDS' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;
SQL
echo PASS_V12_NEGATIVES_EXACT_AND_CONFIG
eq "$(db "select count(*) from saly.creative_runs")" 0 ZERO_INITIAL_RUNS
out1=$(mktemp); out2=$(mktemp)
trap 'rm -f "$out1" "$out2"' EXIT
query="SELECT saly.creative_chat_begin_pending_v1('V12_CHAT',ARRAY['HOME','ADELANTO','REWARDS'],'CHAT-WORKER','V12-001','$snapshot'::jsonb)"
psql -XAt -v ON_ERROR_STOP=1 -c "$query" >"$out1" 2>&1 & p1=$!
psql -XAt -v ON_ERROR_STOP=1 -c "$query" >"$out2" 2>&1 & p2=$!
s1=0; wait "$p1" || s1=$?
s2=0; wait "$p2" || s2=$?
if ! { { test "$s1" -eq 0 && test "$s2" -ne 0; } || { test "$s2" -eq 0 && test "$s1" -ne 0; }; }; then
 echo "FAIL V12 CONCURRENCY statuses $s1 $s2"; cat "$out1" "$out2"; exit 1
fi
cat "$out1" "$out2" | grep -q '"status": "PROCESSING_STARTED"' || { echo 'FAIL NO PROCESSING_STARTED'; cat "$out1" "$out2"; exit 1; }
cat "$out1" "$out2" | grep -q 'CREATIVE_CHAT_CLAIM_SCOPE_OR_POLICY_BLOCKED' || { echo 'FAIL SECOND INVOCATION NOT REJECTED'; cat "$out1" "$out2"; exit 1; }
eq "$(db "select count(*) from saly.creative_runs where state='EJECUTANDO'")" 1 ONE_EXECUTING_RUN
eq "$(db "select count(*) from saly.creative_queue_claims_v1 where state='ACTIVE'")" 1 ONE_ACTIVE_CLAIM
eq "$(db "select count(*) from saly.creative_order_items i join saly.creative_orders o on o.id=i.order_id where o.code='V12_CHAT' and i.code='HOME' and i.status='PRODUCIENDO'")" 1 HOME_PROCESSING
eq "$(db "select count(*) from saly.creative_order_items i join saly.creative_orders o on o.id=i.order_id where o.code='V12_CHAT' and i.code in ('ADELANTO','REWARDS') and i.status='PENDIENTE'")" 2 OTHER_TWO_STILL_PENDING
eq "$(db "select count(*) from saly.creative_order_items i join saly.creative_orders o on o.id=i.order_id where o.code='V12_OTHER' and i.status='PENDIENTE'")" 1 FOREIGN_UNTOUCHED
eq "$(db "select status from saly.creative_orders where code='V12_CHAT'")" EN_PROCESO ORDER_PROCESSING
eq "$(db "select saly.creative_chat_begin_pending_v1('V12_CHAT',ARRAY['HOME'],'CHAT-WORKER','V12-REPEAT','$snapshot'::jsonb)->>'status'")" NO_PENDING_IN_SCOPE NO_RECLAIM_HOME
eq "$(db "select count(*) from saly.creative_queue_delivery_receipts_v1")" 0 NO_FAKE_DELIVERY
echo PASS_V12_CONCURRENT_PHYSICAL_CONNECTIONS
psql -Xq -v ON_ERROR_STOP=1 -f sandbox/creative_factory/queue_v02/fixture_pg17.sql >/dev/null
eq "$(db "select coalesce(to_regprocedure('saly.creative_chat_begin_pending_v1(text,text[],text,text,jsonb)')::text,'NONE')")" NONE RESTORED_FIXTURE
echo PASS_V12_COMPLETE
