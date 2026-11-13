-- B09: official OIDC -> canonical profile recorder, DOCUMENTAL SHA only.
-- DRAFT stacked dependency: #3829 Step70/G15 must be deployed first.
-- No alternate writer: ONLY public.lf_record_profile_execution_step_v1 handles receipts.
BEGIN;
DO $preflight$
BEGIN
 IF to_regclass('public.lf_ig_native_chat_receipt_v1') IS NULL
    OR to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL
    OR to_regprocedure('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)') IS NULL
    OR to_regprocedure('extensions.digest(bytea,text)') IS NULL
    OR to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL
    OR to_regclass('public.lf_ig_native_chat_nonce_v1') IS NOT NULL
    OR to_regprocedure('public.lf_ig_native_chat_official_writer_binding_receipt_v1(text)') IS NOT NULL
 THEN RAISE EXCEPTION 'B09_BINDING_PREREQUISITES_OR_PREIMAGE_DRIFT'; END IF;
 IF md5(pg_get_functiondef('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)'::regprocedure))
    IS DISTINCT FROM '7cf717887006e278356a716f3fd80182'
 OR position('PASS_SEMANTIC_COMPENSATED_SAME_MODEL' in
   pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'B09_BINDING_CANONICAL_RECORDER_OR_STEP70_DRIFT'; END IF;
END $preflight$;

CREATE TABLE public.lf_ig_native_chat_nonce_v1 (
  execution_id text PRIMARY KEY,
  nonce text NOT NULL UNIQUE CHECK (nonce ~ '^[0-9a-f]{48}$'),
  candidate_sha256 text NOT NULL CHECK (candidate_sha256 ~ '^[0-9a-f]{64}$'),
  scope_packet_sha256 text NOT NULL CHECK (scope_packet_sha256 ~ '^[0-9a-f]{64}$'),
  producer_prompt_sha256 text NOT NULL CHECK (producer_prompt_sha256 ~ '^[0-9a-f]{64}$'),
  issued_oidc_run_id text NOT NULL CHECK (issued_oidc_run_id ~ '^[0-9]{1,20}$'),
  oidc_workflow_ref text NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.lf_ig_native_chat_nonce_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_ig_native_chat_nonce_v1 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER lf_ig_native_chat_nonce_no_mutation_v1
 BEFORE UPDATE OR DELETE ON public.lf_ig_native_chat_nonce_v1
 FOR EACH ROW EXECUTE FUNCTION public.lf_ig_native_chat_receipt_immutable_guard_v1();

-- The EXISTING official profile recorder is the only receipt/nonce writer.
-- For the 11 canonical steps the original trust/core path is preserved verbatim.
-- Extra B09 keys are not profile steps and do NOT alter step ledger/terminal.
CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(
  p_execution_id text,p_step_id text,p_evidence_ref text,
  p_evidence_payload jsonb,p_actor_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $rec$
DECLARE
  v_trust jsonb;
  v_run public.lf_operation_execution%ROWTYPE;
  v_nonce public.lf_ig_native_chat_nonce_v1%ROWTYPE;
  v_oidc jsonb;
  v_method text;
  v_repo text;
  v_ref text;
  v_run_id text;
  v_sha text;
  v_nonce_issued text;
  v_seq integer;
  v_kind text;
  v_raw text;
  v_json jsonb;
  v_raw_sha text;
  v_prev text;
  v_writer_ref text;
  v_writer_sha text;
  v_tip text;
  v_count integer;
BEGIN
  IF p_step_id NOT IN ('b09_native_nonce_issue','b09_native_receipt_append') THEN
    v_trust:=public.lf_profile_execution_trust_validation_v2(
      p_execution_id,p_step_id,p_evidence_payload
    );
    RETURN public.lf_record_operation_step_core_v1(
      p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
      'EJECUCION_PERFIL_LF','PERFIL',
      'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
      v_trust,true,'lf_record_profile_execution_step_v1'
    );
  END IF;
  -- B09 is controlled by the already-authenticated OIDC Edge service_role.
  -- OIDC claims must be supplied by Edge from its verified JWT, not issue JSON.
  IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role'
    OR p_actor_execution_id IS DISTINCT FROM p_execution_id
    OR p_execution_id !~ '^EXEC-PROFILE-GATE2-[A-Za-z0-9]{8,64}$'
    OR jsonb_typeof(p_evidence_payload)<>'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_OFFICIAL_RECORDER_CALLER_INVALID');
  END IF;
  v_oidc:=p_evidence_payload->'_verified_oidc';
  v_method:=v_oidc->>'method';
  v_repo:=v_oidc->>'repository';
  v_ref:=v_oidc->>'workflow_ref';
  v_run_id:=v_oidc->>'run_id';
  v_sha:=v_oidc->>'workflow_sha';
  IF v_method IS DISTINCT FROM 'GITHUB_ACTIONS_OIDC_GOVERNED_NATIVE_PROFILE_CONTINUATION_V1'
     OR v_repo IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch'
     OR coalesce(v_ref,'') NOT LIKE 'cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-edge-deploy-credential-readback.yml@refs/heads/%'
     OR coalesce(v_run_id,'') !~ '^[0-9]{1,20}$'
     OR coalesce(v_sha,'') !~ '^[0-9a-f]{40}$'
     OR p_evidence_ref IS DISTINCT FROM 'actions://oidc/'||v_run_id||'/b09'
  THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_OIDC_EDGE_CONTEXT_INVALID'); END IF;
  SELECT * INTO v_run FROM public.lf_operation_execution
   WHERE execution_id=p_execution_id FOR SHARE;
  IF NOT FOUND OR v_run.operation_code IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_run.target_type IS DISTINCT FROM 'PERFIL'
     OR v_run.target_code IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
     OR v_run.status IS DISTINCT FROM 'IN_PROGRESS'
     OR v_run.manifest->>'executor_mode' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_run.manifest->>'executor_provider' IS DISTINCT FROM 'OPENAI_CHATGPT_NATIVE'
     OR v_run.manifest->>'no_promotion' IS DISTINCT FROM 'true'
     OR v_run.manifest ? 'queue_request_id'
  THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_NONCE_RUN_NOT_ELIGIBLE'); END IF;

  IF p_step_id='b09_native_nonce_issue' THEN
    IF coalesce(p_evidence_payload->>'candidate_sha256','') !~ '^[0-9a-f]{64}$'
      OR coalesce(p_evidence_payload->>'scope_packet_sha256','') !~ '^[0-9a-f]{64}$'
      OR coalesce(p_evidence_payload->>'producer_prompt_sha256','') !~ '^[0-9a-f]{64}$' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_NONCE_SCOPE_INVALID'); END IF;
    IF EXISTS(SELECT 1 FROM public.lf_ig_native_chat_nonce_v1 WHERE execution_id=p_execution_id)
       OR EXISTS(SELECT 1 FROM public.lf_ig_native_chat_receipt_v1 WHERE execution_id=p_execution_id) THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_NONCE_REPLAY_OR_ALREADY_ISSUED'); END IF;
    v_nonce_issued:=encode(extensions.gen_random_bytes(24),'hex');
    INSERT INTO public.lf_ig_native_chat_nonce_v1(
      execution_id,nonce,candidate_sha256,scope_packet_sha256,producer_prompt_sha256,
      issued_oidc_run_id,oidc_workflow_ref)
    VALUES(p_execution_id,v_nonce_issued,p_evidence_payload->>'candidate_sha256',
      p_evidence_payload->>'scope_packet_sha256',p_evidence_payload->>'producer_prompt_sha256',
      v_run_id,v_ref);
    RETURN jsonb_build_object('status','B09_SERVER_NONCE_ISSUED','execution_id',p_execution_id,
      'nonce',v_nonce_issued,'writer_transport','VERIFIED_GITHUB_OIDC_TO_CANONICAL_RECORDER',
      'identity_verified',false,'effect_authority',false);
  END IF;

  SELECT * INTO v_nonce FROM public.lf_ig_native_chat_nonce_v1
   WHERE execution_id=p_execution_id FOR SHARE;
  IF NOT FOUND OR v_nonce.oidc_workflow_ref IS DISTINCT FROM v_ref THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_NONCE_ISSUER_BINDING_MISSING'); END IF;
  IF v_nonce.issued_at < clock_timestamp() - interval '24 hours' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_NONCE_EXPIRED'); END IF;
  v_seq:=(p_evidence_payload->>'seq')::integer;
  v_raw:=p_evidence_payload->>'raw_text';
  v_kind:=CASE v_seq WHEN 1 THEN 'REQUEST' WHEN 2 THEN 'EXECUTOR'
                   WHEN 3 THEN 'JUDGE' ELSE NULL END;
  IF v_seq NOT BETWEEN 1 AND 3 OR v_kind IS NULL
    OR v_raw IS NULL OR length(v_raw)>50000
    OR (p_evidence_payload->>'kind') IS DISTINCT FROM v_kind THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_EVENT_SHAPE_INVALID'); END IF;
  BEGIN v_json:=v_raw::jsonb;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_EVENT_RAW_NOT_JSON'); END;
  IF v_json->>'stage' IS DISTINCT FROM v_kind
    OR v_json->>'execution_id' IS DISTINCT FROM p_execution_id
    OR v_json->>'nonce' IS DISTINCT FROM v_nonce.nonce
    OR v_json->>'candidate_sha256' IS DISTINCT FROM v_nonce.candidate_sha256
    OR v_json->>'scope_packet_sha256' IS DISTINCT FROM v_nonce.scope_packet_sha256
    OR v_json->>'producer_prompt_sha256' IS DISTINCT FROM v_nonce.producer_prompt_sha256 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_EVENT_NONCE_OR_SCOPE_NOT_BOUND'); END IF;
  SELECT count(*),coalesce(max(seq),0) INTO v_count,v_seq FROM public.lf_ig_native_chat_receipt_v1
     WHERE execution_id=p_execution_id;
  IF v_count <> v_seq OR v_count<>((p_evidence_payload->>'seq')::integer)-1 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_EVENT_SEQUENCE_OR_REPLAY'); END IF;
  v_seq:=(p_evidence_payload->>'seq')::integer;
  SELECT chain_sha256 INTO v_prev FROM public.lf_ig_native_chat_receipt_v1
     WHERE execution_id=p_execution_id AND seq=v_seq-1;
  v_prev:=coalesce(v_prev,repeat('0',64));
  v_raw_sha:=encode(extensions.digest(convert_to(v_raw,'UTF8'),'sha256'),'hex');
  v_writer_ref:='actions://'||v_run_id||'/'||v_sha||'/b09/'||v_seq::text;
  v_writer_sha:=encode(extensions.digest(convert_to(
    'B09_OFFICIAL_WRITER_V1|'||p_execution_id||'|'||v_seq::text||'|'||
    v_writer_ref||'|'||v_nonce.nonce||'|'||v_raw_sha,'UTF8'),'sha256'),'hex');
  v_tip:=encode(extensions.digest(convert_to(
    'LF_NATIVE_CHAT_EVENT_V1|'||p_execution_id||'|'||v_seq::text||'|'||
    v_kind||'|'||v_raw_sha||'|'||v_prev||'|'||v_writer_sha,'UTF8'),'sha256'),'hex');
  INSERT INTO public.lf_ig_native_chat_receipt_v1(
    execution_id,seq,kind,raw_text,raw_sha256,prev_sha256,chain_sha256,writer_receipt_ref,writer_receipt_sha256)
  VALUES(p_execution_id,v_seq,v_kind,v_raw,v_raw_sha,v_prev,v_tip,v_writer_ref,v_writer_sha);
  RETURN jsonb_build_object('status','B09_NATIVE_EVENT_RECORDED_DOCUMENTAL_ONLY',
    'execution_id',p_execution_id,'seq',v_seq,'chain_tip_sha256',v_tip,
    'provider_attested',false,'model_independence_proven',false,'effect_authority',false);
EXCEPTION WHEN unique_violation THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_NONCE_OR_EVENT_DUPLICATE_REPLAY');
WHEN invalid_text_representation THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_WRITER_INPUT_INVALID');
END
$rec$;
REVOKE ALL ON FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
 TO service_role;

-- Readback ONLY; writer is above and is the original canonical recorder.
CREATE FUNCTION public.lf_ig_native_chat_official_writer_binding_receipt_v1(p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $r$
DECLARE
  n public.lf_ig_native_chat_nonce_v1%ROWTYPE;
  v_verified jsonb;
  r record;
  v_count integer:=0;
  v_expected text;
BEGIN
  SELECT * INTO n FROM public.lf_ig_native_chat_nonce_v1 WHERE execution_id=p_execution_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_BINDING_NONCE_NOT_RESERVED'); END IF;
  IF n.issued_at < clock_timestamp() - interval '24 hours' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_BINDING_NONCE_EXPIRED'); END IF;
  v_verified:=public.lf_ig_verified_native_provider_receipt_v1(p_execution_id);
  IF v_verified->>'status' IS DISTINCT FROM 'SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_BINDING_DOCUMENTAL_CHAIN_NOT_VERIFIED'); END IF;
  FOR r IN SELECT * FROM public.lf_ig_native_chat_receipt_v1
    WHERE execution_id=p_execution_id ORDER BY seq LOOP
    v_count:=v_count+1;
    IF r.seq<>v_count OR r.writer_receipt_ref !~ '^actions://[0-9]{1,20}/[0-9a-f]{40}/b09/[123]$'
      OR (r.raw_text::jsonb)->>'nonce' IS DISTINCT FROM n.nonce
    THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_BINDING_WRITER_OR_NONCE_MISMATCH'); END IF;
    v_expected:=encode(extensions.digest(convert_to(
      'B09_OFFICIAL_WRITER_V1|'||p_execution_id||'|'||r.seq::text||'|'||
       r.writer_receipt_ref||'|'||n.nonce||'|'||r.raw_sha256,'UTF8'),'sha256'),'hex');
    IF v_expected IS DISTINCT FROM r.writer_receipt_sha256 THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_BINDING_OFFICIAL_WRITER_HASH_MISMATCH'); END IF;
  END LOOP;
  IF v_count<>3 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','B09_BINDING_CHAIN_NOT_COMPLETE'); END IF;
  RETURN jsonb_build_object('status','OFFICIAL_OIDC_WRITER_NONCE_CHAIN_BOUND',
    'execution_id',p_execution_id,
    'nonce_binding_verified',true,'canonical_recorder_bound',true,
    'chain_tip_sha256',v_verified->>'chain_tip_sha256',
    'integrity_verified',true,'identity_verified',false,
    'vendor_model_provenance_verified',false,
    'reviewer_model_independence_proven',false,'effect_authority',false);
END
$r$;
REVOKE ALL ON FUNCTION public.lf_ig_native_chat_official_writer_binding_receipt_v1(text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_ig_native_chat_official_writer_binding_receipt_v1(text)
 TO service_role;
COMMIT;
