#!/usr/bin/env bash
# Full isolated PG17 test. Do not run against Supabase production.
set -Eeuo pipefail
cd "$(dirname "$0")"
: "${PGHOST:?}" "${PGUSER:?}" "${PGDATABASE:?}"
[[ "$PGDATABASE" == "saly_queue_test" ]] || { echo 'FAIL ONLY DISPOSABLE DATABASE PERMITTED'; exit 2; }
PSQL=(psql -X -qAt -v ON_ERROR_STOP=1)
"${PSQL[@]}" -f fixture_pg17.sql >/dev/null
get(){ "${PSQL[@]}" -c "$1"; }
pass(){ [[ "$1" == "$2" ]] || { echo "FAIL $3 expected=[$2] actual=[$1]"; exit 1; }; echo "PASS $3"; }
# No extra psql substitutions in DO: use literal scripts instead, not assert_err.
snapshot='{"identity_versions":[{"version_id":7}],"source_refs":[],"screen_spec":{"screen":"HOME"}}'
pass "$(get 'select count(*) from saly.creative_queue_claims_v1')" 0 'fresh queue'
pass "$(get "select saly.creative_queue_claim_next_v1('W1',120)->>'status'")" CLAIMED 'first claim'
pass "$(get "select i.code from saly.creative_queue_claims_v1 c join saly.creative_order_items i on i.id=c.item_id where c.state='ACTIVE'")" HOME 'first item HOME'
pass "$(get "select saly.creative_queue_claim_next_v1('W2',120)->>'status'")" BUSY 'second worker blocked'
token="$(get "select claim_token from saly.creative_queue_claims_v1 where state='ACTIVE'")"
claim_id="$(get "select id from saly.creative_queue_claims_v1 where state='ACTIVE'")"
# A wrong token does not admit a run.
"${PSQL[@]}" <<SQL
DO \$\$BEGIN
  BEGIN
    PERFORM saly.creative_queue_admit_run_v1(gen_random_uuid(),1,'W1-1','$snapshot'::jsonb);
    RAISE EXCEPTION 'WRONG_TOKEN_ALLOWED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_STALE_TOKEN' THEN RAISE; END IF;
  END;
END\$\$;
SQL
echo 'PASS wrong token denied at admission'
# A direct SQL insert (even with known claim id) cannot bypass proof-of-possession.
"${PSQL[@]}" <<SQL
DO \$\$BEGIN
  BEGIN
    INSERT INTO saly.creative_runs(id,order_id,item_id,attempt_number,idempotency_key,state,input_snapshot,queue_claim_id)
    SELECT nextval('saly.creative_runs_id_seq'),order_id,item_id,1,'direct','EN_COLA','$snapshot'::jsonb,id
    FROM saly.creative_queue_claims_v1 WHERE state='ACTIVE';
    RAISE EXCEPTION 'DIRECT_RUN_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_TOKEN_REQUIRED' THEN RAISE; END IF;
  END;
END\$\$;
SQL
echo 'PASS direct RUN denied even with claim id'
run_id="$(get "select saly.creative_queue_admit_run_v1('$token'::uuid,1,'W1-1','$snapshot'::jsonb)->>'run_id'")"
pass "$(get "select queue_claim_id from saly.creative_runs where id=$run_id")" "$claim_id" 'RUN bound to claim'
pass "$(get "select (input_snapshot ? 'queue_claim_token')::text from saly.creative_runs where id=$run_id")" false 'token not injected into canonical snapshot'
# Direct status transition without token must fail before old trigger is bypassed.
"${PSQL[@]}" <<SQL
DO \$\$BEGIN
  BEGIN
    UPDATE saly.creative_runs SET state='EJECUTANDO',worker_ref='W1' WHERE id=$run_id;
    RAISE EXCEPTION 'DIRECT_TRANSITION_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_TOKEN_REQUIRED' THEN RAISE; END IF;
  END;
END\$\$;
SQL
echo 'PASS direct transition denied'
pass "$(get "select saly.creative_queue_advance_run_v1('$token'::uuid,$run_id,'EJECUTANDO')->>'state'")" EJECUTANDO 'RUN executing with token'
"${PSQL[@]}" <<SQL
DO \$\$BEGIN
  BEGIN
    PERFORM saly.creative_queue_release_v1('$token'::uuid,'DONE');
    RAISE EXCEPTION 'EARLY_RELEASE_ALLOWED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
  END;
END\$\$;
SQL
echo 'PASS early DONE denied'
output='{"artifact_ref":"test://image-home","sha256":"'$(printf 'a%.0s' {1..64})'","worker_receipt":"render-receipt-1"}'
pass "$(get "select saly.creative_queue_advance_run_v1('$token'::uuid,$run_id,'EXITOSO','$output'::jsonb)->>'state'")" EXITOSO 'RUN successful via guarded transition'
pass "$(get "select state from saly.creative_runs where id=$run_id")" EXITOSO 'real creative_run_guard_l1 retained'
# Real creative_item_guard_l1 requires independent technical QA.
get "update saly.creative_order_items set status='EN_QA' where id=(select item_id from saly.creative_runs where id=$run_id)" >/dev/null
"${PSQL[@]}" <<SQL
DO \$\$BEGIN
  BEGIN
    UPDATE saly.creative_order_items SET status='APROBADO',approved_at=clock_timestamp(),
      approved_by='W1',qa_receipt=jsonb_build_object('run_id','$run_id','verdict','PASS','reviewer_ref','W1')
    WHERE id=(SELECT item_id FROM saly.creative_runs WHERE id=$run_id);
    RAISE EXCEPTION 'SAME_WORKER_APPROVED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING' THEN RAISE; END IF;
  END;
END\$\$;
SQL
echo 'PASS independent QA required by real trigger'
get "update saly.creative_order_items set status='APROBADO',approved_at=clock_timestamp(),approved_by='QA-1',qa_receipt=jsonb_build_object('run_id','$run_id','verdict','PASS','reviewer_ref','QA-1') where id=(select item_id from saly.creative_runs where id=$run_id)" >/dev/null
echo 'PASS internal independent QA'
"${PSQL[@]}" <<SQL
DO \$\$BEGIN
  BEGIN
    PERFORM saly.creative_queue_release_v1('$token'::uuid,'DONE');
    RAISE EXCEPTION 'UNDELIVERED_RELEASE_ALLOWED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_DELIVERY_NOT_VERIFIED' THEN RAISE; END IF;
  END;
END\$\$;
SQL
echo 'PASS release requires delivery receipt'
pass "$(get "select saly.creative_queue_record_delivery_v1('$token'::uuid,$run_id,'test-adapter','test-message-id-001')->>'status'")" DELIVERY_RECORDED 'artifact and delivery recorded'
pass "$(get "select saly.creative_queue_release_v1('$token'::uuid,'DONE')->>'status'")" RELEASED 'done after QA and delivery'
pass "$(get "select status from saly.creative_orders where code='ACTIVE_A'")" PLANIFICADO 'not closed until all required items'
pass "$(get "select saly.creative_queue_claim_next_v1('W3',120)->>'status'")" CLAIMED 'dependency now satisfied'
pass "$(get "select i.code from saly.creative_queue_claims_v1 c join saly.creative_order_items i on i.id=c.item_id where c.state='ACTIVE'")" ADELANTO 'next item ADELANTO'
old_token="$(get "select claim_token from saly.creative_queue_claims_v1 where state='ACTIVE'")"
# Transaction rollback must not mutate actual claim.
"${PSQL[@]}" <<SQL >/dev/null
BEGIN;
UPDATE saly.creative_queue_claims_v1 SET state='FAILED', finished_at=clock_timestamp() WHERE state='ACTIVE';
ROLLBACK;
SQL
pass "$(get "select count(*) from saly.creative_queue_claims_v1 where state='ACTIVE'")" 1 'rollback restores claim'
get "update saly.creative_queue_claims_v1 set claimed_at=clock_timestamp()-interval '5 minutes',lease_until=clock_timestamp()-interval '1 second' where state='ACTIVE'" >/dev/null
pass "$(get "select saly.creative_queue_claim_next_v1('W4',120)->>'status'")" CLAIMED 'expired claim reclaimed'
"${PSQL[@]}" -c "select saly.creative_queue_admit_run_v1('$old_token'::uuid,1,'stale','$snapshot'::jsonb)" >/dev/null 2>&1 && { echo 'FAIL stale token accepted'; exit 1; } || echo 'PASS stale token rejected'
new_token="$(get "select claim_token from saly.creative_queue_claims_v1 where state='ACTIVE'")"
get "update saly.creative_order_items set status='BLOQUEADO' where id=(select item_id from saly.creative_queue_claims_v1 where state='ACTIVE')" >/dev/null
pass "$(get "select saly.creative_queue_release_v1('$new_token'::uuid,'BLOCKED')->>'status'")" RELEASED 'blocked item does not false-complete'
pass "$(get "select saly.creative_queue_claim_next_v1('W5',120)->>'status'")" CLAIMED 'one-item order claimed'
pass "$(get "select o.code from saly.creative_queue_claims_v1 c join saly.creative_orders o on o.id=c.order_id where c.state='ACTIVE'")" ACTIVE_B 'next order B'
token_b="$(get "select claim_token from saly.creative_queue_claims_v1 where state='ACTIVE'")"
run_b="$(get "select saly.creative_queue_admit_run_v1('$token_b'::uuid,1,'W5-1','$snapshot'::jsonb)->>'run_id'")"
get "select saly.creative_queue_advance_run_v1('$token_b'::uuid,$run_b,'EJECUTANDO')" >/dev/null
get "select saly.creative_queue_advance_run_v1('$token_b'::uuid,$run_b,'EXITOSO','$output'::jsonb)" >/dev/null
get "update saly.creative_order_items set status='EN_QA' where id=(select item_id from saly.creative_runs where id=$run_b)" >/dev/null
get "update saly.creative_order_items set status='APROBADO',approved_at=clock_timestamp(),approved_by='QA-5',qa_receipt=jsonb_build_object('run_id','$run_b','verdict','PASS','reviewer_ref','QA-5') where id=(select item_id from saly.creative_runs where id=$run_b)" >/dev/null
get "select saly.creative_queue_record_delivery_v1('$token_b'::uuid,$run_b,'test-adapter','test-message-id-002')" >/dev/null
pass "$(get "select saly.creative_queue_release_v1('$token_b'::uuid,'DONE')->>'order_closed'")" true 'auto-close without user approval'
pass "$(get "select status from saly.creative_orders where code='ACTIVE_B'")" COMPLETADO 'real close guard allows terminal order'
# A completed order cannot reopen, ensured by real trigger.
"${PSQL[@]}" <<'SQL'
DO $$BEGIN
  BEGIN
    UPDATE saly.creative_orders SET status='EN_PROCESO' WHERE code='ACTIVE_B';
    RAISE EXCEPTION 'CLOSED_ORDER_MUTATED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'CREATIVE_COMPLETED_ORDER_IMMUTABLE' THEN RAISE; END IF;
  END;
END $$;
SQL
echo 'PASS completed order immutable'
# Pending items must never enter the queue: C is PENDIENTE.
pass "$(get "select saly.creative_queue_claim_next_v1('W6',120)->>'status'")" EMPTY 'PENDIENTE excluded'
# Verify serial behavior under two independent PG connections (fresh eligible C).
get "update saly.creative_order_items set status='LISTO' where order_id=(select id from saly.creative_orders where code='ACTIVE_C')" >/dev/null
out1=$(mktemp); out2=$(mktemp)
"${PSQL[@]}" -c "select saly.creative_queue_claim_next_v1('C1',120)->>'status'" > "$out1" & p1=$!
"${PSQL[@]}" -c "select saly.creative_queue_claim_next_v1('C2',120)->>'status'" > "$out2" & p2=$!
wait "$p1"; wait "$p2"
combined="$(cat "$out1" "$out2" | sort | tr '\n' ' ')"; rm -f "$out1" "$out2"
pass "$combined" 'BUSY CLAIMED ' 'two physical PG17 connections serialized'
pass "$(get "select count(*) from saly.creative_queue_claims_v1 where state='ACTIVE'")" 1 'only one active claim'
# Global RUN uniqueness across unrelated orders enforced by index in addition to token guard.
get "insert into saly.creative_orders(code,status,scope_json) values('LEGACY1','PLANIFICADO','{\"rendering_authority\":true}'::jsonb),('LEGACY2','PLANIFICADO','{\"rendering_authority\":true}'::jsonb)" >/dev/null
get "insert into saly.creative_order_items(order_id,code,ordinal,status) select id,'HOME',1,'LISTO' from saly.creative_orders where code in ('LEGACY1','LEGACY2')" >/dev/null
get "insert into saly.creative_runs(order_id,item_id,attempt_number,idempotency_key,state,input_snapshot) select o.id,i.id,1,'legacy-active','EN_COLA','$snapshot'::jsonb from saly.creative_orders o join saly.creative_order_items i on i.order_id=o.id where o.code='LEGACY1'" >/dev/null
"${PSQL[@]}" <<SQL
DO \$\$BEGIN
  BEGIN
    INSERT INTO saly.creative_runs(order_id,item_id,attempt_number,idempotency_key,state,input_snapshot)
      SELECT o.id,i.id,1,'legacy-active-2','EN_COLA','$snapshot'::jsonb
      FROM saly.creative_orders o JOIN saly.creative_order_items i ON i.order_id=o.id
      WHERE o.code='LEGACY2';
    RAISE EXCEPTION 'TWO_ACTIVE_RUNS_ALLOWED';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END\$\$;
SQL
echo 'PASS global active RUN uniqueness'
echo 'PG17 BINDING AND REAL TRIGGERS TESTS PASS'