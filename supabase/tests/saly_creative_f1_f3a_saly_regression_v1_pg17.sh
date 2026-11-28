#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PGHOST="${PGHOST:-127.0.0.1}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
[[ "$PGHOST" == 127.0.0.1 && "$PGUSER" == postgres ]] || { echo SALY_REG_UNSAFE_TARGET; exit 2; }
[[ -z "${PGPORT:-}" && -z "${PGSERVICE:-}" && -z "${PGSERVICEFILE:-}" && -z "${PGHOSTADDR:-}" && -z "${PGOPTIONS:-}" ]] || { echo SALY_REG_UNEXPECTED_CONNECTION_OVERRIDE; exit 3; }

shopt -s nullglob
F1S=("$ROOT"/supabase/migrations/*_lf_saly_creative_f1_enablement_v1.sql)
F3S=("$ROOT"/supabase/migrations/*_lf_saly_creative_lf_f3a_prompt_compile_v1.sql)
[[ "${#F1S[@]}" -eq 1 && "${#F3S[@]}" -eq 1 ]] || { echo SALY_REG_CANDIDATE_FILES_INVALID; exit 4; }
F1="${F1S[0]}"
F3="${F3S[0]}"
TOKENS="$ROOT/sandbox/creative_factory/f1_pg17/fixtures/saly_real_tokens_55_v1.sql"
FIXTURE="$ROOT/sandbox/creative_factory/f1_pg17/fixtures/saly_real_regression_v1.sql"
[[ -f "$TOKENS" && -f "$FIXTURE" ]] || { echo SALY_REG_FIXTURE_MISSING; exit 5; }

export PGDATABASE=lf_creative_f1_ci
F1_CANDIDATE="$F1" F1_CANDIDATE_SHA256="$(sha256sum "$F1" | awk '{print $1}')" \
  bash "$ROOT/sandbox/creative_factory/f1_pg17/setup.sh" >/tmp/saly_reg_setup.log 2>&1
grep -q 'F1_SETUP_PASS' /tmp/saly_reg_setup.log || { cat /tmp/saly_reg_setup.log; exit 6; }

export PGDATABASE=postgres
dropdb --if-exists --maintenance-db=postgres lf_creative_saly_f3a
createdb --maintenance-db=postgres -T lf_creative_f1_candidate lf_creative_saly_f3a
export PGDATABASE=lf_creative_saly_f3a
psql -X -v ON_ERROR_STOP=1 -f "$F3" >/tmp/saly_reg_f3a.log 2>&1
grep -q 'LF_F3A_COMPILER_MIGRATION|PASS' /tmp/saly_reg_f3a.log || { cat /tmp/saly_reg_f3a.log; exit 7; }

LANES=(lf_creative_f1_baseline lf_creative_f1_candidate lf_creative_saly_f3a)
for db in "${LANES[@]}"; do
  PGDATABASE="$db" psql -X -v ON_ERROR_STOP=1 -f "$TOKENS" >"/tmp/saly_reg_tokens_${db}.log" 2>&1 || { cat "/tmp/saly_reg_tokens_${db}.log"; exit 8; }
  grep -q 'SALY_REAL_TOKEN_SNAPSHOT|PASS|versions=55' "/tmp/saly_reg_tokens_${db}.log" || { cat "/tmp/saly_reg_tokens_${db}.log"; exit 8; }
  PGDATABASE="$db" psql -X -v ON_ERROR_STOP=1 -f "$FIXTURE" >"/tmp/saly_reg_fixture_${db}.log" 2>&1 || {
    cat "/tmp/saly_reg_fixture_${db}.log"; exit 8;
  }
  grep -q 'SALY_REG_REAL_FIXTURE|PASS|tokens=55' "/tmp/saly_reg_fixture_${db}.log" || {
    cat "/tmp/saly_reg_fixture_${db}.log"; exit 9;
  }
done

r1_calc() {
  local db="$1"
  PGDATABASE="$db" psql -XqAt -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
CREATE TEMP TABLE r1_result(k text primary key,v text);
DO $$
DECLARE
 l2a jsonb;l2c jsonb;l3b jsonb;snap jsonb;cl jsonb;adm jsonb;wire jsonb;
 rj jsonb;tok uuid;rid bigint;
BEGIN
 l2a:=saly.creative_item_context_l2a(9226);
 l2c:=saly.creative_item_work_packet_l2c(9226);
 l3b:=saly.creative_item_visual_contract_l3b(9226);
 IF l2c->>'readiness_code'<>'READY_FOR_NATIVE_HANDOFF'
    OR l3b#>>'{contract,production_manifest,dispatch_readiness}'<>'READY_FOR_NATIVE_HANDOFF'
 THEN RAISE EXCEPTION 'R1_REAL_SALY_NOT_READY'; END IF;
 snap:=(l2c->'input_snapshot')||
      jsonb_build_object('visual_contract',l3b->'contract',
                         'visual_contract_sha256',l3b->>'contract_sha256');
 cl:=saly.creative_queue_claim_by_id_v1(9220,'R1_WORKER',600);
 IF cl->>'status'<>'CLAIMED' THEN RAISE EXCEPTION 'R1_CLAIM:%',cl; END IF;
 tok:=(cl->>'claim_token')::uuid;
 adm:=saly.creative_queue_admit_run_v1(tok,1,'R1-RUN-1',snap);
 rid:=(adm->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(tok,rid,'EJECUTANDO');
 wire:=saly.creative_native_render_wire_v1(tok,rid,'GPT_NATIVE');
 SELECT to_jsonb(r)-'created_at'-'updated_at'-'deadline_at'-'started_at'-'finished_at'
 INTO rj FROM saly.creative_runs r WHERE r.id=rid;
 INSERT INTO r1_result VALUES
 ('L2A',encode(extensions.digest(convert_to(l2a::text,'UTF8'),'sha256'),'hex')),
 ('L2C',encode(extensions.digest(convert_to(l2c::text,'UTF8'),'sha256'),'hex')),
 ('L3B',encode(extensions.digest(convert_to(l3b::text,'UTF8'),'sha256'),'hex')),
 ('RUN',encode(extensions.digest(convert_to(rj::text,'UTF8'),'sha256'),'hex')),
 ('WIRE',encode(extensions.digest(convert_to(wire::text,'UTF8'),'sha256'),'hex'));
END $$;
SELECT k||'='||v FROM r1_result ORDER BY k;
ROLLBACK;
SQL
}
declare -A R1
for db in "${LANES[@]}"; do R1["$db"]="$(r1_calc "$db")"; done
[[ "${R1[lf_creative_f1_baseline]}" == "${R1[lf_creative_f1_candidate]}" ]] || {
  echo 'R1|FAIL|baseline_candidate'; diff -u <(printf '%s\n' "${R1[lf_creative_f1_baseline]}") <(printf '%s\n' "${R1[lf_creative_f1_candidate]}") || true; exit 10;
}
[[ "${R1[lf_creative_f1_candidate]}" == "${R1[lf_creative_saly_f3a]}" ]] || {
  echo 'R1|FAIL|candidate_f3a'; diff -u <(printf '%s\n' "${R1[lf_creative_f1_candidate]}") <(printf '%s\n' "${R1[lf_creative_saly_f3a]}") || true; exit 11;
}
while IFS= read -r line; do echo "R1|PASS|$line"; done <<<"${R1[lf_creative_f1_baseline]}"

r2_calc() {
  local db="$1"
  PGDATABASE="$db" psql -XqAt -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
CREATE TEMP TABLE r2_result(v text);
DO $$
DECLARE rid bigint;rj jsonb;cl jsonb;adm jsonb;tok uuid;
BEGIN
 IF EXISTS (SELECT 1 FROM saly.creative_order_items WHERE id=9231 AND context_json#>'{screen_spec,visual_blueprint}' IS NOT NULL)
 THEN RAISE EXCEPTION 'R2_FIXTURE_NOT_LEGACY'; END IF;
 cl:=saly.creative_queue_claim_by_id_v1(9230,'R2_WORKER',600);
 IF cl->>'status'<>'CLAIMED' THEN RAISE EXCEPTION 'R2_LEGACY_CLAIM:%',cl; END IF;
 tok:=(cl->>'claim_token')::uuid;
 adm:=saly.creative_queue_admit_run_v1(tok,1,'R2-LEGACY-1','{}'::jsonb);
 rid:=(adm->>'run_id')::bigint;
 SELECT to_jsonb(r)-'id'-'queue_claim_id'-'created_at'-'updated_at'-'deadline_at'-'started_at'-'finished_at'
 INTO rj FROM saly.creative_runs r WHERE r.id=rid;
 INSERT INTO r2_result VALUES(encode(extensions.digest(convert_to(rj::text,'UTF8'),'sha256'),'hex'));
END $$;
SELECT v FROM r2_result;
ROLLBACK;
SQL
}
R2_BASE="$(r2_calc lf_creative_f1_baseline)"
R2_CAND="$(r2_calc lf_creative_f1_candidate)"
R2_F3A="$(r2_calc lf_creative_saly_f3a)"
[[ "$R2_BASE" =~ ^[0-9a-f]{64}$ && "$R2_BASE" == "$R2_CAND" && "$R2_CAND" == "$R2_F3A" ]] || {
  echo "R2|FAIL|baseline=$R2_BASE|candidate=$R2_CAND|f3a=$R2_F3A"; exit 12;
}
echo "R2|PASS|legacy_run_hash=$R2_BASE"

r3_calc() {
  local db="$1"
  PGDATABASE="$db" psql -XqAt -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
CREATE TEMP TABLE r3_result(v text);
DO $$
DECLARE
 l2c jsonb;l3b jsonb;snap jsonb;cl jsonb;adm jsonb;tok uuid;rid bigint;
 outj jsonb;sem jsonb;sem_checks jsonb;tech_checks jsonb;receipt jsonb;bad jsonb;
 contract_sha text;sem_sha text;artifact_sha text:=repeat('a',64);
 evidence_id bigint; finalj jsonb;
BEGIN
 cl:=saly.creative_queue_claim_by_id_v1(9240,'R3_WORKER',600);
 IF cl->>'status'<>'CLAIMED' THEN RAISE EXCEPTION 'R3_CLAIM:%',cl; END IF;
 tok:=(cl->>'claim_token')::uuid;
 -- Canonical semantic-QA snapshot must be sealed after claim: claim changes
 -- the order from PLANIFICADO to EN_PROCESO, and L3B includes order_status.
 l2c:=saly.creative_item_work_packet_l2c(9241);
 l3b:=saly.creative_item_visual_contract_l3b(9241);
 IF l2c->>'readiness_code'<>'READY_FOR_NATIVE_HANDOFF'
    OR jsonb_array_length(l3b#>'{contract,qa_checks}')<>5
 THEN RAISE EXCEPTION 'R3_DUAL_QA_FIXTURE_NOT_READY'; END IF;
 snap:=(l2c->'input_snapshot')||
      jsonb_build_object('visual_contract',l3b->'contract','visual_contract_sha256',l3b->>'contract_sha256');
 adm:=saly.creative_queue_admit_run_v1(tok,1,'R3-RUN-1',snap);
 rid:=(adm->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(tok,rid,'EJECUTANDO');
 outj:=jsonb_build_object('artifact_ref','test://saly-regression-r3.png','sha256',artifact_sha,'worker_receipt','CI-R3-WORKER-RECEIPT');
 PERFORM saly.creative_queue_advance_run_v1(tok,rid,'EXITOSO',outj,NULL);
 INSERT INTO saly.creative_run_detection_v1(
   run_id,order_id,item_id,claim_id,artifact_ref,artifact_sha256,check_count,first_ready_elapsed_seconds,evidence)
 VALUES(rid,9240,9241,(cl->>'claim_id')::bigint,outj->>'artifact_ref',artifact_sha,3,60,
        '{"source":"CI_REGRESSION","ready":"VERIFIED"}'::jsonb);
 UPDATE saly.creative_order_items SET status='EN_QA' WHERE id=9241;

 sem:=(SELECT acceptance_json->'semantic_qa' FROM saly.creative_order_items WHERE id=9241);
 SELECT jsonb_agg(jsonb_build_object('code',x->>'code','verdict','PASS','evidence','independent CI semantic evidence') ORDER BY ord)
 INTO sem_checks FROM jsonb_array_elements(sem->'checks') WITH ORDINALITY AS q(x,ord);
 SELECT jsonb_agg(jsonb_build_object('code',x->>'code','verdict','PASS','evidence','independent CI technical evidence') ORDER BY ord)
 INTO tech_checks FROM jsonb_array_elements(l3b#>'{contract,qa_checks}') WITH ORDINALITY AS q(x,ord);
 contract_sha:=l3b->>'contract_sha256';
 sem_sha:=encode(extensions.digest(convert_to(sem::text,'UTF8'),'sha256'),'hex');
 receipt:=jsonb_build_object(
   'run_id',rid,'verdict','PASS','reviewer_ref','R3_REVIEWER',
   'artifact_ref',outj->>'artifact_ref','artifact_sha256',artifact_sha,'contract_sha256',contract_sha,
   'semantic_qa',jsonb_build_object(
      'original_request_sha256',sem->>'original_request_sha256','semantic_contract_sha256',sem_sha,
      'independent_interpretation','Independent CI review of stored governed contract',
      'verdict','PASS','checks',sem_checks),
   'technical_qa',jsonb_build_object('verdict','PASS','checks',tech_checks));

 bad:=jsonb_set(receipt,'{technical_qa,checks}',(receipt#>'{technical_qa,checks}')-4);
 BEGIN
   UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt=bad WHERE id=9241;
   RAISE EXCEPTION 'R3_EXPECTED_MISSING_TECH_CHECK_REJECTION';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_DUAL_QA_CHECK_COUNT' THEN RAISE; END IF;
 END;
 bad:=receipt||jsonb_build_object('reviewer_ref','R3_WORKER');
 BEGIN
   UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt=bad WHERE id=9241;
   RAISE EXCEPTION 'R3_EXPECTED_SAME_REVIEWER_REJECTION';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING' THEN RAISE; END IF;
 END;
 UPDATE saly.creative_order_items SET status='TERMINADO',qa_receipt=receipt WHERE id=9241;

 INSERT INTO saly.creative_queue_native_delivery_evidence_v1(
   claim_id,run_id,order_id,item_id,artifact_ref,artifact_sha256,host_surface,
   message_id,executor_mode,host_evidence_ref,host_evidence_sha256)
 VALUES((cl->>'claim_id')::bigint,rid,9240,9241,outj->>'artifact_ref',artifact_sha,
   'CHATGPT_CURRENT_CHAT','CI-R3-MESSAGE','GPT_NATIVE','test://saly-regression-host-proof',repeat('b',64))
 RETURNING id INTO evidence_id;
 BEGIN
   UPDATE saly.creative_queue_native_delivery_evidence_v1
      SET state='VERIFIED',verified_at=clock_timestamp(),verifier_ref='R3_WORKER' WHERE id=evidence_id;
   RAISE EXCEPTION 'R3_EXPECTED_SELF_DELIVERY_VERIFICATION_REJECTION';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'CREATIVE_NATIVE_DELIVERY_SELF_VERIFICATION' THEN RAISE; END IF;
 END;
 UPDATE saly.creative_queue_native_delivery_evidence_v1
    SET state='VERIFIED',verified_at=clock_timestamp(),verifier_ref='R3_DELIVERY_REVIEWER' WHERE id=evidence_id;

 SELECT jsonb_build_object(
   'run_state',(SELECT state FROM saly.creative_runs WHERE id=rid),
   'worker_receipt',(SELECT output_evidence->>'worker_receipt' FROM saly.creative_runs WHERE id=rid),
   'item_status',(SELECT status FROM saly.creative_order_items WHERE id=9241),
   'check_count',(SELECT check_count FROM saly.creative_run_detection_v1 WHERE run_id=rid),
   'first_ready_elapsed',(SELECT first_ready_elapsed_seconds FROM saly.creative_run_detection_v1 WHERE run_id=rid),
   'delivery_state',(SELECT state FROM saly.creative_queue_native_delivery_evidence_v1 WHERE id=evidence_id),
   'reviewer',(SELECT qa_receipt->>'reviewer_ref' FROM saly.creative_order_items WHERE id=9241)
 ) INTO finalj;
 IF finalj->>'run_state'<>'EXITOSO' OR finalj->>'worker_receipt'<>'CI-R3-WORKER-RECEIPT'
    OR finalj->>'item_status'<>'TERMINADO' OR finalj->>'check_count'<>'3'
    OR finalj->>'first_ready_elapsed'<>'60' OR finalj->>'delivery_state'<>'VERIFIED'
    OR finalj->>'reviewer'<>'R3_REVIEWER'
 THEN RAISE EXCEPTION 'R3_POSITIVE_FINAL_STATE_INVALID:%',finalj; END IF;
 INSERT INTO r3_result VALUES(encode(extensions.digest(convert_to(finalj::text,'UTF8'),'sha256'),'hex'));
END $$;
SELECT v FROM r3_result;
ROLLBACK;
SQL
}
R3_BASE="$(r3_calc lf_creative_f1_baseline)"
R3_CAND="$(r3_calc lf_creative_f1_candidate)"
R3_F3A="$(r3_calc lf_creative_saly_f3a)"
[[ "$R3_BASE" =~ ^[0-9a-f]{64}$ && "$R3_BASE" == "$R3_CAND" && "$R3_CAND" == "$R3_F3A" ]] || {
  echo "R3|FAIL|baseline=$R3_BASE|candidate=$R3_CAND|f3a=$R3_F3A"; exit 13;
}
echo "R3|PASS|dual_qa_5+5|missing_check=CREATIVE_DUAL_QA_CHECK_COUNT|same_reviewer=CREATIVE_QA_NOT_INDEPENDENT_OR_RUN_MISSING|hash=$R3_BASE"

r4_calc() {
  local db="$1"
  PGDATABASE="$db" psql -XAt -F '|' -v ON_ERROR_STOP=1 <<'SQL'
select p.proname,md5(pg_get_functiondef(p.oid))
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='saly' and p.proname in (
 'creative_queue_native_delivery_guard_v1','creative_assert_dual_qa_l3c',
 'creative_item_guard_l1','creative_queue_advance_run_v1')
order by p.proname;
SQL
}
EXPECTED_R4=$'creative_assert_dual_qa_l3c|3fb397abe1128485e9642e758e2074da\ncreative_item_guard_l1|c1eb590cd77a64a6fab30814eb0530e2\ncreative_queue_advance_run_v1|b8abbd62d2241357e6a34cb138c4641f\ncreative_queue_native_delivery_guard_v1|1576c45737b7050019c71ffdbef77d70'
for db in "${LANES[@]}"; do
  ACTUAL="$(r4_calc "$db")"
  [[ "$ACTUAL" == "$EXPECTED_R4" ]] || {
    echo "R4|FAIL|$db"; diff -u <(printf '%s\n' "$EXPECTED_R4") <(printf '%s\n' "$ACTUAL") || true; exit 14;
  }
done
while IFS= read -r line; do echo "R4|PASS|$line"; done <<<"$EXPECTED_R4"

r5_calc() {
  local db="$1"
  PGDATABASE="$db" psql -XAt -F '|' -v ON_ERROR_STOP=1 <<'SQL'
select coalesce(array_to_string(p.proacl,','),'NULL'),pg_get_userbyid(p.proowner),p.prosecdef::text,md5(pg_get_functiondef(p.oid))
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='saly' and p.proname='creative_native_render_wire_v1'
  and pg_get_function_identity_arguments(p.oid)='p_claim_token uuid, p_run_id bigint, p_executor_mode text';
SQL
}
R5_BASE="$(r5_calc lf_creative_f1_baseline)"
R5_CAND="$(r5_calc lf_creative_f1_candidate)"
R5_F3A="$(r5_calc lf_creative_saly_f3a)"
IFS='|' read -r BASE_ACL BASE_OWNER BASE_SEC BASE_MD5 <<<"$R5_BASE"
IFS='|' read -r CAND_ACL CAND_OWNER CAND_SEC CAND_MD5 <<<"$R5_CAND"
IFS='|' read -r F3A_ACL F3A_OWNER F3A_SEC F3A_MD5 <<<"$R5_F3A"
[[ "$BASE_OWNER" == postgres && "$BASE_SEC" == true ]] || { echo "R5|FAIL|baseline_owner_secdef=$R5_BASE"; exit 15; }
[[ "$CAND_ACL" == 'postgres=X/postgres' && "$CAND_OWNER" == postgres && "$CAND_SEC" == true && "$CAND_MD5" == '2915c3827aece1095bb9e9913a7c2010' ]] || {
  echo "R5|FAIL|candidate=$R5_CAND"; exit 16;
}
[[ "$F3A_ACL" == 'postgres=X/postgres' && "$F3A_OWNER" == postgres && "$F3A_SEC" == true && "$F3A_MD5" == '2915c3827aece1095bb9e9913a7c2010' ]] || {
  echo "R5|FAIL|f3a=$R5_F3A"; exit 17;
}
if [[ "$BASE_ACL" == 'postgres=X/postgres' ]]; then
  echo "R5|PASS|baseline_acl=$BASE_ACL|candidate_acl=$CAND_ACL|f3a_acl=$F3A_ACL|finding=NONE"
else
  echo "R5|PASS_WITH_FINDING|baseline_acl=$BASE_ACL|candidate_acl=$CAND_ACL|f3a_acl=$F3A_ACL|finding=BASELINE_WIRE_ACL_SNAPSHOT_DRIFT"
fi
echo 'SALY_F1_F3A_REAL_REGRESSION|PASS|R1=PASS|R2=PASS|R3=PASS|R4=PASS|R5=PASS'
