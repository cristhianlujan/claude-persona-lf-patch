#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/../../.."
[[ "$(printenv PGHOST || true)" == "127.0.0.1" && "$(printenv PGDATABASE || true)" == "saly_queue_test" && "$(printenv PGUSER || true)" == "postgres" ]] || { echo BLOCK_REMOTE_OR_NONTEST_DATABASE; exit 2; }
[[ -z "$(printenv PGPASSWORD || true)" && -z "$(printenv LF_SUPABASE_DB_PASSWORD || true)" ]] || { echo BLOCK_PRODUCTION_CREDENTIALS; exit 2; }
psql -XAt -v ON_ERROR_STOP=1 -c "show server_version_num" | grep -qE '^17[0-9]{4}$' || { echo BLOCK_NOT_POSTGRESQL_17; exit 2; }
sql(){ psql -XAt -v ON_ERROR_STOP=1 -c "$1"; }
reset(){
  psql -Xq -v ON_ERROR_STOP=1 <<'SQL'
DROP SCHEMA IF EXISTS saly CASCADE;
CREATE SCHEMA saly;
CREATE TABLE saly.creative_orders(id bigint PRIMARY KEY,code text NOT NULL,status text NOT NULL);
CREATE TABLE saly.creative_order_items(id bigint PRIMARY KEY,order_id bigint NOT NULL REFERENCES saly.creative_orders(id),code text NOT NULL,status text NOT NULL,qa_receipt jsonb NOT NULL DEFAULT '{}'::jsonb);
CREATE TABLE saly.creative_runs(id bigint PRIMARY KEY,item_id bigint NOT NULL);
INSERT INTO saly.creative_orders VALUES
  (4,'SALY_HOME_BATCH_001','PLANIFICADO'),
  (5,'SALY_HOME_TEMPLATE_AB_001','PLANIFICADO');
INSERT INTO saly.creative_order_items(id,order_id,code,status)
VALUES (5,4,'HOME','PENDIENTE'),(6,4,'ADELANTO','PENDIENTE'),
 (7,4,'REWARDS','PENDIENTE'),(8,5,'HOME_A','PENDIENTE'),(9,5,'HOME_B','PENDIENTE');
SQL
}
migrate='supabase/migrations/20261122235500_lf_saly_creative_chat_artifact_reconciliation_v1.sql'
reset
psql -Xq -v ON_ERROR_STOP=1 -f "$migrate"
test "$(sql "SELECT count(*) FROM saly.creative_order_items WHERE status='PENDIENTE'")" = 5
test "$(sql "SELECT count(*) FROM saly.creative_runs")" = 0
test "$(sql "SELECT count(*) FROM saly.creative_order_items WHERE qa_receipt#>>'{chat_artifact_reconciliation_v1,status}'='ENTREGADO_EN_CHAT_PENDIENTE_QA_INDEPENDIENTE'")" = 5
test "$(sql "SELECT count(*) FROM saly.creative_order_items WHERE qa_receipt#>>'{chat_artifact_reconciliation_v1,avoid_regeneration}'='true'")" = 5
test "$(sql "SELECT qa_receipt#>>'{chat_artifact_reconciliation_v1,sha256}' FROM saly.creative_order_items WHERE id=6")" = 9f08caec72e426bd0253bf2d28cb2c9ef70e742fb5e83d42ca9dcfd1ee283a92
test "$(sql "SELECT count(*) FROM saly.creative_order_items WHERE qa_receipt#>>'{chat_artifact_reconciliation_v1,qa_verdict}'='PENDING_INDEPENDENT'")" = 5
echo PASS_SALY_CHAT_ARCHIVE_FIVE_QA_COMMENTS_NO_FAKE_TERMINAL_STATES

out=$(mktemp)
trap 'rm -f "$out"' EXIT
if psql -Xq -v ON_ERROR_STOP=1 -f "$migrate" >"$out" 2>&1; then
 echo FAIL_REPLAY_ALLOWED; exit 1
fi
grep -q 'SALY_CHAT_RECONCILE_STATE_OR_SCOPE_DRIFT:item=5' "$out" || { cat "$out"; exit 1; }
echo PASS_SALY_CHAT_ARCHIVE_REPLAY_REJECTED

reset
sql "UPDATE saly.creative_order_items SET status='PRODUCIENDO' WHERE id=6" >/dev/null
if psql -Xq -v ON_ERROR_STOP=1 -f "$migrate" >"$out" 2>&1; then
 echo FAIL_STALE_ITEM_ALLOWED; exit 1
fi
grep -q 'SALY_CHAT_RECONCILE_STATE_OR_SCOPE_DRIFT:item=6' "$out" || { cat "$out"; exit 1; }
test "$(sql "SELECT count(*) FROM saly.creative_order_items WHERE qa_receipt <> '{}'::jsonb")" = 0
echo PASS_SALY_CHAT_ARCHIVE_STALE_SCOPE_ROLLBACK_ATOMIC

reset
sql "INSERT INTO saly.creative_runs(id,item_id) VALUES (99,5)" >/dev/null
if psql -Xq -v ON_ERROR_STOP=1 -f "$migrate" >"$out" 2>&1; then
 echo FAIL_RETROACTIVE_RUN_ALLOWED; exit 1
fi
grep -q 'SALY_CHAT_RECONCILE_RUNS_EXIST' "$out" || { cat "$out"; exit 1; }
test "$(sql "SELECT count(*) FROM saly.creative_order_items WHERE qa_receipt <> '{}'::jsonb")" = 0
echo PASS_SALY_CHAT_ARCHIVE_RUN_CONFLICT_BLOCKS

reset
test "$(sql "SELECT count(*) FROM saly.creative_order_items WHERE status='PENDIENTE'")" = 5
echo PASS_SALY_CHAT_ARCHIVE_FIXTURE_RESTORED
