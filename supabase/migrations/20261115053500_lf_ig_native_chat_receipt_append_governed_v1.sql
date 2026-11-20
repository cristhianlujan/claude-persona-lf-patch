-- LF / IG B09 Step70. Append-only issuance of context receipts in the EXISTING table.
-- Sandbox, no new RUN, no provider attestation, no Step70 PASS, no production GO.
BEGIN;
DO $preimage$
DECLARE v_trigger text;
BEGIN
 IF to_regprocedure('public.lf_ig_native_chat_receipt_append_v1(text,text,jsonb,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_NATIVE_CHAT_WRITER_FUNCTION_PREEXISTS_DRIFT'; END IF;
 IF to_regclass('public.lf_ig_native_chat_receipt_v1') IS NULL
 OR to_regclass('public.lf_operation_execution_steps') IS NULL
 OR to_regclass('public.lf_operation_execution') IS NULL
 OR to_regprocedure('public.lf_profile_step70_clean_eval_context_verify_v1(text,jsonb)') IS NULL
 OR to_regprocedure('extensions.digest(bytea,text)') IS NULL
 OR to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL
 THEN RAISE EXCEPTION 'LF_NATIVE_CHAT_WRITER_DEPENDENCY_DRIFT'; END IF;
 SELECT pg_get_triggerdef(t.oid) INTO v_trigger FROM pg_trigger t
 WHERE t.tgrelid='public.lf_ig_native_chat_receipt_v1'::regclass
   AND t.tgname='lf_ig_native_chat_receipt_no_mutation_v1'
   AND t.tgenabled='O' AND NOT t.tgisinternal;
 IF v_trigger IS NULL
   OR v_trigger NOT LIKE '%BEFORE DELETE OR UPDATE%'
   OR v_trigger NOT LIKE '%lf_ig_native_chat_receipt_immutable_guard_v1%'
 THEN RAISE EXCEPTION 'LF_NATIVE_CHAT_WRITER_IMMUTABILITY_TRIGGER_DRIFT'; END IF;
 IF has_table_privilege('service_role',
    'public.lf_ig_native_chat_receipt_v1','INSERT')
 THEN RAISE EXCEPTION 'LF_NATIVE_CHAT_WRITER_DIRECT_TABLE_INSERT_DRIFT'; END IF;
END $preimage$;

CREATE FUNCTION public.lf_ig_native_chat_receipt_append_v1(
 p_execution_id text,p_kind text,p_event jsonb,p_writer_receipt_ref text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $writer$
DECLARE
 e public.lf_operation_execution%ROWTYPE;
 s40 public.lf_operation_execution_steps%ROWTYPE;
 s50 public.lf_operation_execution_steps%ROWTYPE;
 s60 public.lf_operation_execution_steps%ROWTYPE;
 r public.lf_ig_native_chat_receipt_v1%ROWTYPE;
 existing public.lf_ig_native_chat_receipt_v1%ROWTYPE;
 n integer:=0;
 wanted integer;
 tip text:=repeat('0',64);
 calc text;
 nonce_value text;
 candidate text;
 scope_hash text;
 bundle_hash text;
 source_schema text;
 source_eval text;
 req jsonb;
 producer jsonb;
 prev_kind text;
 writer_sha text;
 raw_sha text;
 chain_sha text;
 raw_text_value text;
 event_final jsonb;
 event_readback jsonb;
BEGIN
 -- Only the official service_role RPC can invoke this function (GRANT below).
 IF coalesce(p_execution_id,'') !~ '^EXEC-[A-Za-z0-9_-]{8,}$'
   OR p_kind IS NULL OR p_kind NOT IN ('REQUEST','EXECUTOR','JUDGE')
   OR jsonb_typeof(p_event) IS DISTINCT FROM 'object'
   OR nullif(btrim(coalesce(p_writer_receipt_ref,'')),'') IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','LF_NATIVE_CHAT_WRITER_INPUT_DRIFT'); END IF;

 -- All provenance and chain linkage are server-owned. Never trust caller hashes/nonce.
 IF p_event ?| ARRAY[
   'stage','execution_id','nonce','candidate_sha256','scope_packet_sha256',
   'frozen_bundle_sha256','seq','raw_text','raw_sha256','prev_sha256',
   'chain_sha256','writer_receipt_sha256','writer_receipt_ref','recorded_at'
 ] THEN RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','LF_NATIVE_CHAT_WRITER_CALLER_PROVENANCE_DRIFT'); END IF;

 -- Serializes all issues and replays on this SAME governed RUN.
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id FOR UPDATE;
 IF NOT FOUND OR e.status<>'IN_PROGRESS'
   OR e.operation_code<>'EJECUCION_PERFIL_LF'
   OR e.target_type<>'PERFIL'
   OR e.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
   OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
   OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
   OR e.manifest->>'governed_repair_write'<>'true'
   OR e.manifest->>'no_promotion'<>'true'
   OR e.manifest ? 'queue_request_id'
   OR nullif(e.manifest->>'runtime_target','') IS NOT NULL
 THEN RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','LF_NATIVE_CHAT_WRITER_RUN_AUTHORITY_DRIFT'); END IF;

 SELECT * INTO s40 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT * INTO s50 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile'
    AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT * INTO s60 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';
 IF s40.step_id IS NULL OR s50.step_id IS NULL OR s60.step_id IS NULL
 OR s60.evidence_payload#>>'{deterministic_validation,status}' IS DISTINCT FROM 'PASS'
 OR s60.evidence_payload->>'output_contract_result' IS DISTINCT FROM 'PASS'
 THEN RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','LF_NATIVE_CHAT_WRITER_UPSTREAM_NOT_PASS_DRIFT'); END IF;

 candidate:=s50.evidence_payload->>'raw_output_sha256';
 scope_hash:=replace(coalesce(s40.evidence_payload->>'scope_authority_packet_sha256',''),
     'sha256:','');
 source_schema:=s50.evidence_payload#>>'{profile_output,profile_pack_id}';
 source_eval:=s60.evidence_payload#>>'{deterministic_validation,source_bound_validation,schema}';
 IF coalesce(candidate,'') !~ '^[0-9a-f]{64}$'
 OR coalesce(scope_hash,'') !~ '^[0-9a-f]{64}$'
 OR s50.evidence_ref IS NULL OR s50.evidence_ref=''
 OR s50.evidence_payload->'profile_output' IS NULL
 OR encode(extensions.digest(
       convert_to((s50.evidence_payload->'profile_output')::text,'UTF8'),
       'sha256'),'hex') IS DISTINCT FROM candidate
 OR s60.evidence_payload->>'raw_output_sha256' IS DISTINCT FROM candidate
 OR nullif(source_schema,'') IS NULL
 OR nullif(source_eval,'') IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','LF_NATIVE_CHAT_WRITER_SOURCE_SHA_DRIFT'); END IF;

 bundle_hash:=encode(extensions.digest(convert_to(
    'LF_STEP70_FROZEN_BUNDLE_V1|'||candidate||'|'||scope_hash||'|'||s50.evidence_ref,
    'UTF8'),'sha256'),'hex');

 -- Read and verify the complete existing chain before ANY replay or append.
 FOR r IN SELECT * FROM public.lf_ig_native_chat_receipt_v1
  WHERE execution_id=p_execution_id ORDER BY seq LOOP
   n:=n+1;
   IF n>3 OR r.seq<>n
    OR r.kind<>(CASE n WHEN 1 THEN 'REQUEST' WHEN 2 THEN 'EXECUTOR' WHEN 3 THEN 'JUDGE' END)
   THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','LF_NATIVE_CHAT_WRITER_SEQUENCE_DRIFT'); END IF;
   IF encode(extensions.digest(convert_to(r.raw_text,'UTF8'),'sha256'),'hex')
       IS DISTINCT FROM r.raw_sha256
    OR r.prev_sha256 IS DISTINCT FROM tip
    OR encode(extensions.digest(convert_to(
        r.writer_receipt_ref||'|'||r.raw_sha256,'UTF8'),'sha256'),'hex')
          IS DISTINCT FROM r.writer_receipt_sha256
   THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','LF_NATIVE_CHAT_WRITER_RAW_OR_WRITER_SHA_DRIFT'); END IF;
   calc:=encode(extensions.digest(convert_to(
     'LF_NATIVE_CHAT_EVENT_V1|'||r.execution_id||'|'||r.seq::text||'|'||
      r.kind||'|'||r.raw_sha256||'|'||r.prev_sha256||'|'||
      r.writer_receipt_sha256,'UTF8'),'sha256'),'hex');
   IF calc IS DISTINCT FROM r.chain_sha256
   THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','LF_NATIVE_CHAT_WRITER_CHAIN_DRIFT'); END IF;
   event_readback:=r.raw_text::jsonb;
   IF jsonb_typeof(event_readback) IS DISTINCT FROM 'object'
     OR event_readback->>'stage' IS DISTINCT FROM r.kind
     OR event_readback->>'execution_id' IS DISTINCT FROM p_execution_id
     OR event_readback->>'candidate_sha256' IS DISTINCT FROM candidate
     OR event_readback->>'scope_packet_sha256' IS DISTINCT FROM scope_hash
     OR event_readback->>'frozen_bundle_sha256' IS DISTINCT FROM bundle_hash
     OR coalesce(event_readback->>'nonce','')=''
     OR (nonce_value IS NOT NULL
          AND event_readback->>'nonce' IS DISTINCT FROM nonce_value)
   THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','LF_NATIVE_CHAT_WRITER_CONTEXT_BINDING_DRIFT'); END IF;
   IF n=1 THEN
     req:=event_readback;
     nonce_value:=event_readback->>'nonce';
   ELSIF n=2 THEN producer:=event_readback;
   END IF;
   tip:=r.chain_sha256;
 END LOOP;

 wanted:=CASE p_kind WHEN 'REQUEST' THEN 1 WHEN 'EXECUTOR' THEN 2 ELSE 3 END;
 -- Replay is accepted ONLY for the exact previously recorded caller event and
 -- the same evidence ref. REQUEST server nonce is removed before comparison.
 IF n>=wanted THEN
   SELECT * INTO existing FROM public.lf_ig_native_chat_receipt_v1
    WHERE execution_id=p_execution_id AND seq=wanted;
   IF existing.kind IS DISTINCT FROM p_kind
    OR (existing.raw_text::jsonb - ARRAY[
       'stage','execution_id','candidate_sha256','scope_packet_sha256',
       'frozen_bundle_sha256','nonce']::text[]) IS DISTINCT FROM p_event
   THEN RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','LF_NATIVE_CHAT_WRITER_REPLAY_DRIFT'); END IF;
   RETURN jsonb_build_object('status','ALREADY_RECORDED',
       'execution_id',p_execution_id,'kind',p_kind,'seq',wanted,
       'nonce',nonce_value,'candidate_sha256',candidate,
       'scope_packet_sha256',scope_hash,'frozen_bundle_sha256',bundle_hash,
       'raw_sha256',existing.raw_sha256,'chain_sha256',existing.chain_sha256,
       'writer_receipt_ref',existing.writer_receipt_ref);
 END IF;
 IF n<>wanted-1 THEN
   RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','LF_NATIVE_CHAT_WRITER_SEQUENCE_DRIFT',
       'recorded_event_count',n,'requested_kind',p_kind);
 END IF;
 IF wanted=1 THEN
   nonce_value:=encode(extensions.gen_random_bytes(24),'hex');
   IF coalesce(nonce_value,'') !~ '^[0-9a-f]{48}$' THEN
      RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','LF_NATIVE_CHAT_WRITER_NONCE_ISSUANCE_DRIFT'); END IF;
 ELSIF wanted=2 THEN
   IF nullif(btrim(coalesce(p_event->>'executor_context_ref','')),'') IS NULL
      OR p_event->>'producer_schema_id' IS DISTINCT FROM source_schema
      OR p_event->>'producer_eval_id' IS DISTINCT FROM source_eval
      OR p_event->>'producer_profile_id' IS DISTINCT FROM e.target_code
   THEN RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','LF_NATIVE_CHAT_WRITER_PRODUCER_CONFIG_DRIFT'); END IF;
 ELSIF wanted=3 THEN
   IF producer IS NULL OR nullif(btrim(coalesce(producer->>'executor_context_ref','')),'') IS NULL
      OR nullif(btrim(coalesce(p_event->>'reviewer_context_ref','')),'') IS NULL
      OR p_event->>'reviewer_context_ref'
          IS NOT DISTINCT FROM producer->>'executor_context_ref'
      OR p_event->>'reviewer_schema_id'
          IS DISTINCT FROM 'LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1'
      OR p_event->>'reviewer_schema_id'
          IS NOT DISTINCT FROM producer->>'producer_schema_id'
      OR p_event->>'reviewer_eval_id'
          IS DISTINCT FROM 'LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1'
      OR p_event->>'reviewer_eval_id'
          IS NOT DISTINCT FROM producer->>'producer_eval_id'
      OR nullif(btrim(coalesce(p_event->>'reviewer_profile_id','')),'') IS NULL
      OR p_event->>'reviewer_profile_id'
          IS NOT DISTINCT FROM producer->>'producer_profile_id'
      OR p_event->>'review_mode'
          IS DISTINCT FROM 'INDEPENDENT_EVAL_CONTEXT'
      OR p_event->>'reviewer_context_cleared' IS DISTINCT FROM 'true'
      OR (p_event->>'eval_status' IS DISTINCT FROM 'PASS'
       AND p_event->>'eval_status' IS DISTINCT FROM 'FAIL')
      OR jsonb_typeof(p_event->'review_payload') IS DISTINCT FROM 'object'
      OR p_event#>>'{review_payload,review_mode}'
          IS DISTINCT FROM 'INDEPENDENT_EVAL_CONTEXT'
      OR p_event#>>'{review_payload,candidate_sha256}' IS DISTINCT FROM candidate
      OR p_event#>>'{review_payload,scope_packet_sha256}' IS DISTINCT FROM scope_hash
      OR p_event#>>'{review_payload,reviewer_context_ref}'
          IS DISTINCT FROM p_event->>'reviewer_context_ref'
   THEN RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','LF_NATIVE_CHAT_WRITER_JUDGE_CONTEXT_DRIFT'); END IF;
 END IF;

 event_final:=p_event||jsonb_build_object(
   'stage',p_kind,'execution_id',p_execution_id,'nonce',nonce_value,
   'candidate_sha256',candidate,'scope_packet_sha256',scope_hash,
   'frozen_bundle_sha256',bundle_hash);
 raw_text_value:=event_final::text;
 raw_sha:=encode(extensions.digest(convert_to(raw_text_value,'UTF8'),'sha256'),'hex');
 writer_sha:=encode(extensions.digest(
   convert_to(p_writer_receipt_ref||'|'||raw_sha,'UTF8'),'sha256'),'hex');
 chain_sha:=encode(extensions.digest(convert_to(
     'LF_NATIVE_CHAT_EVENT_V1|'||p_execution_id||'|'||wanted::text||'|'||
     p_kind||'|'||raw_sha||'|'||tip||'|'||writer_sha,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_ig_native_chat_receipt_v1(
   execution_id,seq,kind,raw_text,raw_sha256,prev_sha256,chain_sha256,
   writer_receipt_ref,writer_receipt_sha256)
 VALUES(p_execution_id,wanted,p_kind,raw_text_value,raw_sha,tip,chain_sha,
        p_writer_receipt_ref,writer_sha);
 RETURN jsonb_build_object('status','RECEIPT_APPENDED',
    'execution_id',p_execution_id,'kind',p_kind,'seq',wanted,
    'nonce',nonce_value,'candidate_sha256',candidate,
    'scope_packet_sha256',scope_hash,'frozen_bundle_sha256',bundle_hash,
    'raw_sha256',raw_sha,'chain_sha256',chain_sha,
    'writer_receipt_ref',p_writer_receipt_ref);
EXCEPTION WHEN invalid_text_representation THEN
  RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','LF_NATIVE_CHAT_WRITER_RAW_JSON_DRIFT');
END
$writer$;

REVOKE ALL ON FUNCTION public.lf_ig_native_chat_receipt_append_v1(text,text,jsonb,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_native_chat_receipt_append_v1(text,text,jsonb,text)
 TO service_role;
-- Table privileges remain unchanged. No direct INSERT grants.
COMMIT;
