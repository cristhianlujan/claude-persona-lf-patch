#!/usr/bin/env bash
# Run against a disposable PG17 database only.
set -Eeuo pipefail
cd "$(dirname "$0")"
: "${PGHOST:?}" "${PGUSER:?}" "${PGDATABASE:?}"
[[ "$PGDATABASE" == "saly_queue_test" ]] || { echo "ERROR: only disposable database saly_queue_test is allowed" >&2; exit 2; }
PSQL=(psql -X -qAt -v ON_ERROR_STOP=1)
"${PSQL[@]}" -f fixture_pg17.sql >/dev/null
get() { "${PSQL[@]}" -c "$1"; }
check() { [[ "$1" == "$2" ]] || { echo "FAIL $3 (expected=$2 got=$1)" >&2; exit 1; }; echo "PASS $3"; }
check "$(get "select count(*) from saly.creative_queue_claims_v1")" '0' 'fixture empty'
# Strict FIFO: earlier unauthorized LEGACY and REVIEW do not qualify.
claim="$(get "select saly.creative_queue_claim_next_v1('W1',120)::text")"
echo "$claim" | grep -q '"status": "CLAIMED"' || { echo "FAIL first claim: $claim"; exit 1; }
first_item="$(get "select i.code from saly.creative_queue_claims_v1 c join saly.creative_order_items i on i.id=c.item_id where c.state='ACTIVE'")"
check "$first_item" 'HOME' 'first home claimed'
check "$(get "select c.item_id=(select i.id from saly.creative_order_items i join saly.creative_orders o on o.id=i.order_id where o.code='ACTIVE_A' and i.code='HOME') from saly.creative_queue_claims_v1 c where c.state='ACTIVE'")" 't' 'FIFO with authorization'
check "$(get "select saly.creative_queue_claim_next_v1('W2',120)->>'status'")" 'BUSY' 'second worker blocked'
# Token fencing: unauthorized release and invalid result are rejected by SQL.
"${PSQL[@]}" <<'SQL'
DO $$BEGIN
  BEGIN PERFORM saly.creative_queue_release_v1(gen_random_uuid(),'DONE'); RAISE EXCEPTION 'INVALID_TOKEN_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='INVALID_TOKEN_ACCEPTED' THEN RAISE; END IF;
  END;
  BEGIN PERFORM saly.creative_queue_release_v1((SELECT claim_token FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE'),'DONE');
    RAISE EXCEPTION 'DELIVERY_WITHOUT_QA_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='DELIVERY_WITHOUT_QA_ACCEPTED' THEN RAISE; END IF;
  END;
END $$;
SQL
echo 'PASS invalid token and no evidence'
# Verify PostgreSQL transaction rollback really removes tentative claim.
"${PSQL[@]}" <<'SQL'
BEGIN;
UPDATE saly.creative_queue_claims_v1 SET state='FAILED',finished_at=clock_timestamp() WHERE state='ACTIVE';
DO $$BEGIN
 IF EXISTS (SELECT 1 FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE') THEN RAISE EXCEPTION 'ROLLBACK_SETUP_INVALID'; END IF;
END $$;
ROLLBACK;
SQL
check "$(get "select count(*) from saly.creative_queue_claims_v1 where state='ACTIVE'")" '1' 'ROLLBACK restores claim'
# Healthy lease extension; mark first delivery and release without user approval.
token="$(get "select claim_token from saly.creative_queue_claims_v1 where state='ACTIVE'")"
check "$(get "select saly.creative_queue_heartbeat_v1('$token'::uuid,120)->>'status'")" 'EXTENDED' 'heartbeats active token'
"${PSQL[@]}" <<'SQL'
UPDATE saly.creative_order_items SET status='APROBADO' WHERE id=(SELECT item_id FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE');
INSERT INTO saly.creative_runs(order_id,item_id,state,output_evidence)
SELECT order_id,item_id,'EXITOSO',jsonb_build_object('artifact_ref','test://image','worker_receipt','fixture','sha256',repeat('a',64))
FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE';
SQL
check "$(get "select saly.creative_queue_release_v1('$token'::uuid,'DONE')->>'status'")" 'RELEASED' 'internal QA releases claim'
check "$(get "select status from saly.creative_orders where code='ACTIVE_A'")" 'PLANIFICADO' 'not closed until all required items'
# Dependency now approved, next item ADELANTO can be claimed before later order B.
check "$(get "select saly.creative_queue_claim_next_v1('W3',120)->>'status'")" 'CLAIMED' 'take next sequential item'
check "$(get "select i.code from saly.creative_queue_claims_v1 c join saly.creative_order_items i on i.id=c.item_id where c.state='ACTIVE'")" 'ADELANTO' 'dependency respected'
# Expiration: force expiry in fixture and check old token fenced.
oldtoken="$(get "select claim_token from saly.creative_queue_claims_v1 where state='ACTIVE'")"
get "update saly.creative_queue_claims_v1 set claimed_at=clock_timestamp()-interval '5 minutes',lease_until=clock_timestamp()-interval '1 second' where state='ACTIVE'" >/dev/null
check "$(get "select saly.creative_queue_claim_next_v1('W4',120)->>'status'")" 'CLAIMED' 'expired claim reclaimed'
check "$(get "select count(*) from saly.creative_queue_claims_v1 where state='ACTIVE'")" '1' 'only one active claim'
"${PSQL[@]}" -c "select saly.creative_queue_heartbeat_v1('$oldtoken'::uuid,120)" >/dev/null 2>&1 && { echo 'FAIL old token allowed'; exit 1; } || echo 'PASS stale token denied'
# Release of required blocked item.
get "update saly.creative_order_items set status='BLOQUEADO' where id=(select item_id from saly.creative_queue_claims_v1 where state='ACTIVE')" >/dev/null
newtoken="$(get "select claim_token from saly.creative_queue_claims_v1 where state='ACTIVE'")"
check "$(get "select saly.creative_queue_release_v1('$newtoken'::uuid,'BLOCKED')->>'status'")" 'RELEASED' 'blocked task released without false completion'
# A one-item order closes automatically after delivered artefact and internal QA.
check "$(get "select saly.creative_queue_claim_next_v1('W5',120)->>'status'")" 'CLAIMED' 'next order claimed'
check "$(get "select o.code from saly.creative_queue_claims_v1 c join saly.creative_orders o on o.id=c.order_id where c.state='ACTIVE'")" 'ACTIVE_B' 'FIFO next order B'
get "update saly.creative_order_items set status='APROBADO' where id=(select item_id from saly.creative_queue_claims_v1 where state='ACTIVE')" >/dev/null
get "insert into saly.creative_runs(order_id,item_id,state,output_evidence) select order_id,item_id,'EXITOSO',jsonb_build_object('artifact_ref','test://imageB','worker_receipt','fixtureB','sha256',repeat('b',64)) from saly.creative_queue_claims_v1 where state='ACTIVE'" >/dev/null
token_b="$(get "select claim_token from saly.creative_queue_claims_v1 where state='ACTIVE'")"
check "$(get "select saly.creative_queue_release_v1('$token_b'::uuid,'DONE')->>'order_closed'")" 'true' 'auto-close after internal QA (no user approval)'
check "$(get "select status from saly.creative_orders where code='ACTIVE_B'")" 'COMPLETADO' 'closed order persists'
# Global RUN uniqueness must hold for active runs on DIFFERENT items.
"${PSQL[@]}" <<'SQL'
INSERT INTO saly.creative_runs(order_id,item_id,state)
SELECT o.id,i.id,'EN_COLA' FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id
WHERE o.code='ACTIVE_C' AND i.code='HOME';
DO $$BEGIN
  BEGIN
    INSERT INTO saly.creative_runs(order_id,item_id,state)
    SELECT o.id,i.id,'EN_COLA' FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id
    WHERE o.code='ACTIVE_A' AND i.code='HOME';
    RAISE EXCEPTION 'GLOBAL_RUN_UNIQUENESS_BROKEN';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
SQL
echo 'PASS two parallel active RUNs denied'
check "$(get "select saly.creative_queue_claim_next_v1('W5',120)->>'status'")" 'RUN_ACTIVE' 'RUN active blocks new claim'
# Concurrency: prepare fresh state, simultaneously claim with independent psql clients.
get "update saly.creative_runs set state='CANCELADO' where state='EN_COLA'" >/dev/null
"${PSQL[@]}" <<'SQL'
TRUNCATE saly.creative_queue_claims_v1 RESTART IDENTITY;
SQL
out1=$(mktemp);out2=$(mktemp)
"${PSQL[@]}" -c "select saly.creative_queue_claim_next_v1('C1',120)->>'status'" > "$out1" & pid1=$!
"${PSQL[@]}" -c "select saly.creative_queue_claim_next_v1('C2',120)->>'status'" > "$out2" & pid2=$!
wait "$pid1";wait "$pid2"
combined="$(cat "$out1" "$out2" | sort | tr '\n' ' ')";rm -f "$out1" "$out2"
check "$combined" 'BUSY CLAIMED ' 'two simultaneous PG17 connections serialized'
check "$(get "select count(*) from saly.creative_queue_claims_v1 where state='ACTIVE'")" '1' 'unique active persisted'
echo 'PG17 CONTRACT TESTS PASS'