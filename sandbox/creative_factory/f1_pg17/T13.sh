#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 && "${PGDATABASE:-}" == lf_creative_f1_ci && "${PGUSER:-}" == postgres ]] || { echo 'T13|FAIL unsafe'; exit 2; }
psql -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;
DO $$
DECLARE p text:='CI LF F1 sealed prompt';h text;review jsonb;cl jsonb;pkt jsonb;vis jsonb;snap jsonb;adm jsonb;tok uuid;rid bigint;win int;
BEGIN
 h:=encode(extensions.digest(convert_to(p,'UTF8'),'sha256'),'hex');
 review:=jsonb_build_object('prompt_sha256',h,'verdict','PASS','checks',jsonb_build_array(
  jsonb_build_object('code','PROMPT_LITERAL_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_IDENTITY_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_CONTEXT_MATCH','verdict','PASS','evidence','CI'),
  jsonb_build_object('code','PROMPT_HASH_MATCH','verdict','PASS','evidence','CI')));
 PERFORM saly.creative_lf_prompt_seal_v1(2501,p,'GPT_NATIVE','CLAUDE_NATIVE',review);
 cl:=saly.creative_queue_claim_by_id_v1(25,'T13_WORKER',86400);tok:=(cl->>'claim_token')::uuid;
 IF extract(epoch from ((cl->>'lease_until')::timestamptz-clock_timestamp())) NOT BETWEEN 86390 AND 86400.1 THEN RAISE EXCEPTION 'T13_CLAIM_WINDOW_NOT_86400:%',cl; END IF;
 pkt:=saly.creative_item_work_packet_l2c(2501);vis:=saly.creative_item_visual_contract_l3b(2501);
 snap:=(pkt->'input_snapshot')||jsonb_build_object('visual_contract',vis->'contract','visual_contract_sha256',vis->>'contract_sha256');
 adm:=saly.creative_queue_admit_run_v1(tok,1,'T13-RUN-1',snap);rid:=(adm->>'run_id')::bigint;
 PERFORM saly.creative_queue_advance_run_v1(tok,rid,'EJECUTANDO');
 SELECT (execution_policy->>'EXECUTION_WINDOW_SECONDS')::int INTO win FROM saly.creative_runs WHERE id=rid;
 IF win<>86400 THEN RAISE EXCEPTION 'T13_RUN_WINDOW_NOT_PINNED:%',win; END IF;
 INSERT INTO saly.config_global(scope,config_key,config_value,value_type,value_status,description,valid_from)
 VALUES('CREATIVE_FACTORY_LF','EXECUTION_WINDOW_SECONDS','60','INTEGER','REAL','T13 later config',clock_timestamp());
 SELECT (execution_policy->>'EXECUTION_WINDOW_SECONDS')::int INTO win FROM saly.creative_runs WHERE id=rid;
 IF win<>86400 THEN RAISE EXCEPTION 'T13_STORED_POLICY_CHANGED:%',win; END IF;
 UPDATE saly.creative_queue_claims_v1 SET claimed_at=clock_timestamp()-interval '2 days', lease_until=clock_timestamp()-interval '1 second' WHERE claim_token=tok;
 PERFORM set_config('saly.creative_queue_token',tok::text,true);
 BEGIN
  UPDATE saly.creative_runs SET state='EXITOSO',output_evidence=jsonb_build_object('artifact_ref','CI','sha256',repeat('a',64)) WHERE id=rid;
  RAISE EXCEPTION 'T13_EXPIRED_CLAIM_DID_NOT_BLOCK';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'CREATIVE_QUEUE_RUN_CLAIM_INVALID' THEN RAISE EXCEPTION 'T13_WRONG_ERROR:%',SQLERRM; END IF;
 END;
END $$;
ROLLBACK;
SQL
echo 'T13|PASS'
