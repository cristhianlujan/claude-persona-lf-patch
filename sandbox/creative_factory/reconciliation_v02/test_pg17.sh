#!/usr/bin/env bash
# Test actual source-bound TERMINADO migration on disposable PostgreSQL 17 only.
set -Eeuo pipefail
cd "$(dirname "$0")/../../.."
[[ "$(printenv PGHOST || true)" == '127.0.0.1'
&& "$(printenv PGDATABASE || true)" == 'saly_queue_test'
&& "$(printenv PGUSER || true)" == 'postgres'
&& -z "$(printenv PGPASSWORD || true)"
&& -z "$(printenv LF_SUPABASE_DB_PASSWORD || true)" ]] ||
 { echo BLOCK_NON_DISPOSABLE_DATABASE; exit 2; }
psql -XAt -v ON_ERROR_STOP=1 -c 'SHOW server_version_num' | grep -qE '^17[0-9]{4}$' || { echo BLOCK_NON_PG17; exit 2; }
fixture='sandbox/creative_factory/reconciliation_v02/fixture_pg17.sql'
migration='supabase/migrations/20261123005500_lf_saly_creative_chat_judge_terminal_v1.sql'
db(){ psql -XAt -v ON_ERROR_STOP=1 -c "$1"; }
eq(){ [[ "$1" == "$2" ]] || { echo "FAIL_V02_$3 expected=$2 actual=$1"; exit 1; }; echo "PASS_V02_$3"; }
reset(){ psql -Xq -v ON_ERROR_STOP=1 -f "$fixture" >/dev/null; }
negative(){
 local code="$1" path="$2"; shift 2
 if psql -Xq -v ON_ERROR_STOP=1 "$@" >"$path" 2>&1; then
   echo "FAIL_V02_UNEXPECTED_ACCEPTED:$code"; exit 1
 fi
 grep -q "$code" "$path" || { cat "$path"; echo "FAIL_V02_WRONG_REJECTION:$code"; exit 1; }
 echo "PASS_V02_NEGATIVE:$code"
}
reset
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE status='PENDIENTE'")" 6 PRESTATE_6_PENDING_WITH_FOREIGN
psql -Xq -v ON_ERROR_STOP=1 -f "$migration" >/dev/null
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE status='TERMINADO'")" 5 EXACT_FIVE_TERMINADO
eq "$(db "SELECT count(*) FROM saly.creative_orders WHERE status='TERMINADO'")" 2 EXACT_TWO_ORDERS_TERMINADO
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE id IN(5,6,7,8,9) AND approved_at IS NULL AND approved_by IS NULL")" 5 NO_FAKE_APPROVAL
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE id IN(5,6,7,8,9) AND qa_receipt#>>'{chat_judge_v1,semantic_independence_proven}'='false' AND qa_receipt#>>'{chat_judge_v1,production_approved}'='false' AND qa_receipt#>>'{chat_judge_v1,run_verified}'='false'")" 5 HONEST_JUDGE_AUTHORITY
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE id IN(5,6,7,8,9) AND qa_receipt#>>'{chat_judge_v1,qa_comment}' IS NOT NULL")" 5 QA_COMMENTS_SAVED
eq "$(db "SELECT count(*) FROM saly.creative_runs")" 0 NO_FAKE_RUN
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE id=10 AND status='PENDIENTE'")" 1 FOREIGN_ITEM_UNCHANGED
eq "$(db "SELECT count(*) FROM saly.creative_orders WHERE id=6 AND status='PLANIFICADO'")" 1 FOREIGN_ORDER_UNCHANGED
eq "$(db "SELECT jsonb_array_length(qa_receipt#>'{chat_judge_v1,observations}') FROM saly.creative_order_items WHERE id=7")" 2 REWARDS_OBSERVATIONS_PERSISTED
eq "$(db "SELECT qa_receipt#>>'{chat_judge_v1,technical_verdict}' FROM saly.creative_order_items WHERE id=6")" PASS_TECHNICAL_WITH_OBSERVATIONS ADELANTO_QA_HONEST
log=$(mktemp)
trap 'rm -f "$log"' EXIT
negative SALY_CHAT_TERMINAL_PRESTATE_DRIFT "$log" -f "$migration"
negative SALY_CHAT_TERMINAL_ITEM_IMMUTABLE "$log" -c "UPDATE saly.creative_order_items SET status='PENDIENTE' WHERE id=5"
negative SALY_CHAT_TERMINAL_ITEM_IMMUTABLE "$log" -c "DELETE FROM saly.creative_order_items WHERE id=5"
negative SALY_CHAT_TERMINAL_ORDER_IMMUTABLE "$log" -c "UPDATE saly.creative_orders SET status='PLANIFICADO' WHERE id=4"
negative SALY_CHAT_TERMINAL_ORDER_IMMUTABLE "$log" -c "DELETE FROM saly.creative_orders WHERE id=4"
negative CREATIVE_ITEM_NOT_IN_QA "$log" -c "UPDATE saly.creative_order_items SET status='APROBADO',approved_at=now(),approved_by='FAKE' WHERE id=10"
negative SALY_CHAT_TERMINAL_JUDGE_OR_DEPENDENCY_MISSING "$log" -c "UPDATE saly.creative_order_items SET status='TERMINADO' WHERE id=10"
negative SALY_CHAT_TERMINAL_ORDER_DETAILS_INCOMPLETE "$log" -c "UPDATE saly.creative_orders SET status='TERMINADO',completed_at=now() WHERE id=6"
echo PASS_V02_POSITIVE_TERMINAL_AND_NEGATIVE_GUARDS

reset
db "UPDATE saly.creative_order_items SET qa_receipt=jsonb_set(qa_receipt,'{chat_artifact_reconciliation_v1,sha256}',to_jsonb(repeat('0',64))) WHERE id=6" >/dev/null
negative SALY_CHAT_TERMINAL_MANIFEST_OR_PRESTATE_DRIFT "$log" -f "$migration"
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE status='PENDIENTE'")" 6 ATOMIC_ROLLBACK_AFTER_HASH_DRIFT
eq "$(db "SELECT count(*) FROM pg_constraint WHERE conrelid='saly.creative_order_items'::regclass AND conname='creative_order_items_status_check' AND pg_get_constraintdef(oid) LIKE '%TERMINADO%'")" 0 NO_SCHEMA_DRIFT_ON_ROLLBACK
echo PASS_V02_NEGATIVE_SOURCE_HASH_REVOKES_ALL_WRITES

reset
db "INSERT INTO saly.creative_runs(id,order_id,item_id,state) VALUES(99,4,5,'EXITOSO')" >/dev/null
negative SALY_CHAT_TERMINAL_PRESTATE_DRIFT "$log" -f "$migration"
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE status='TERMINADO'")" 0 NO_RETRO_RUN_FABRICATION
reset
eq "$(db "SELECT count(*) FROM saly.creative_order_items WHERE status='PENDIENTE'")" 6 FIXTURE_RESTORED
echo PASS_SALY_JUDGE_TERMINAL_PG17_5_ITEMS_2_ORDERS_SOURCE_BOUND
