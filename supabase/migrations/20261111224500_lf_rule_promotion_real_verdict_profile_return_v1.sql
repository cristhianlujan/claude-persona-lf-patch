-- LF #3779 L5 CANDIDATE. Never deploy without real measurement and registry readback.
-- No new IG, no extra judge/model, no RUN mutations. PG18 fixture only.
BEGIN;
DO $gate$
BEGIN
 IF md5(pg_get_functiondef('public.lf_rule_promotion_profile_owner_verify_v1(text)'::regprocedure))
    IS DISTINCT FROM 'ae4491480e09dcf28ea0f97d0a352472'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_profile_approve_v1(text,text)'::regprocedure))
    IS DISTINCT FROM '466f7e769d8592685b965d780b8cd1c5'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure))
    IS DISTINCT FROM '58c348bd9f8bcba8e5106eee18b3020c'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
    IS DISTINCT FROM '2b880ccb3b6868a630b483119660224a'
 THEN RAISE EXCEPTION 'BLOCK_L5_UPSTREAM_MD5_DRIFT'; END IF;
END $gate$;

-- Owners are NOT simulated in this registry: no seed/INSERT. The only
-- writer in deployment is the authorized GOVERNANCE MIGRATION OWNER after an
-- approved lf_decisiones_gov decision explicitly binds rule_code, owner_profile_code,
-- source_decision_sha256 and PROMOCION_REGLA_LF scope. IG, profile and service_role
-- have SELECT-only (no DML). Neither can self-assign or alter a binding.
COMMENT ON TABLE public.lf_rule_promotion_profile_owner_v1 IS
 'L5 governed rule->owner mapping. Writer: migration/decision-ledger custodian after approved source. Reader: L4D gate SECURITY DEFINER. No IG/profile self-write, service_role SELECT ONLY.';
REVOKE INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER
 ON TABLE public.lf_rule_promotion_profile_owner_v1
 FROM PUBLIC,anon,authenticated,service_role;

-- L5: consume one case-level REAL measurement only via EXISTING #3682 receipt.
-- No caller-supplied verdict, no second model/judge. If the real list has not
-- been transported through the existing IG receipt, fail closed.
ALTER TABLE public.lf_rule_promotion_v1
 ADD COLUMN l5_blind_case_id text,
 ADD COLUMN l5_blind_case_sha256 text,
 ADD COLUMN l5_blind_case_binding_sha256 text,
 ADD COLUMN rule_return_status text,
 ADD COLUMN rule_return_error text,
 ADD COLUMN rule_return_payload jsonb,
 ADD COLUMN rule_return_sha256 text;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_blind_verdict_verify_v1(
 p_promotion_id text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $real_verify$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE;
 c jsonb; r lf_ops.reglas%ROWTYPE; actual_sha text;
 v_case_sha text; v_binding_sha text; v_expected_bind jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.ig_semantic_external_receipt IS NULL OR p.ig_semantic_run_id IS NULL THEN
   RETURN jsonb_build_object('status','RETRY_REQUIRED','blocking_code','L5_IG_RECEIPT_REQUIRED'); END IF;
 IF p.ig_semantic_external_receipt_sha256 IS DISTINCT FROM
  encode(extensions.digest(convert_to(p.ig_semantic_external_receipt::text,'UTF8'),'sha256'),'hex') THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
      'blocking_code','L5_EXTERNAL_RECEIPT_SHA_DRIFT'); END IF;
 c:=p.ig_semantic_external_receipt->'l5_blind_case_verdict';
 IF jsonb_typeof(c) IS DISTINCT FROM 'object' THEN
   RETURN jsonb_build_object('status','RETRY_REQUIRED',
     'blocking_code','L5_REAL_BLIND_CASE_RECEIPT_NOT_PROVIDED'); END IF;
 IF p.ig_semantic_external_receipt->>'test_only_synthetic'='true'
    OR c->>'test_only_synthetic'='true' THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
     'blocking_code','L5_SYNTHETIC_CASE_RECEIPT_REJECTED'); END IF;
 IF coalesce(c->>'id','') !~ '^K[A-F0-9]{8,32}$'
    OR c->>'verdict' NOT IN ('ALLOW','BLOCK','INCONCLUSIVE')
    OR nullif(btrim(coalesce(c->>'exact_excerpt','')),'') IS NULL
    OR jsonb_typeof(c) IS DISTINCT FROM 'object'
    OR c->>'source_code' IS NULL
    OR c->>'source_sha256' !~ '^[a-f0-9]{64}$'
    OR c->>'rule_snapshot_sha256' IS DISTINCT FROM p.request_snapshot_sha256
    OR c->>'packet_sha256' IS DISTINCT FROM p.ig_semantic_packet_sha256
    OR c->>'candidate_sha256' IS DISTINCT FROM p.ig_semantic_candidate_sha256
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code','L5_BLIND_CASE_SCHEMA_OR_HASH_MISMATCH'); END IF;
 IF c->>'source_code' IS DISTINCT FROM p.rule_code THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
      'blocking_code','L5_BLIND_CASE_SOURCE_NOT_PROMOTED_RULE'); END IF;
 SELECT * INTO r FROM lf_ops.reglas WHERE codigo=c->>'source_code';
 actual_sha:=public.lf_asset_snapshot_sha_v1('REGLA',c->>'source_code');
 IF NOT FOUND OR actual_sha IS DISTINCT FROM c->>'source_sha256'
    OR actual_sha IS DISTINCT FROM p.request_snapshot_sha256
    OR position(c->>'exact_excerpt' IN r.descripcion)=0 THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
      'blocking_code','L5_BLIND_CASE_CITATION_OR_RULE_DRIFT'); END IF;
 v_case_sha:=encode(extensions.digest(convert_to(c::text,'UTF8'),'sha256'),'hex');
 v_expected_bind:=jsonb_build_object(
   'promotion_id',p_promotion_id,'case_id',c->>'id','case_sha256',v_case_sha,
   'ig_run_id',p.ig_semantic_run_id,'rule_sha256',p.request_snapshot_sha256,
   'packet_sha256',p.ig_semantic_packet_sha256,
   'candidate_sha256',p.ig_semantic_candidate_sha256,
   'ig_receipt_sha256',p.ig_semantic_external_receipt_sha256,
   'ig_binding_sha256',p.ig_semantic_binding_sha256);
 v_binding_sha:=encode(extensions.digest(convert_to(
     v_expected_bind::text,'UTF8'),'sha256'),'hex');
 IF p.l5_blind_case_id IS DISTINCT FROM c->>'id'
    OR p.l5_blind_case_sha256 IS DISTINCT FROM v_case_sha
    OR p.l5_blind_case_binding_sha256 IS DISTINCT FROM v_binding_sha THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
     'blocking_code','L5_BLIND_CASE_NOT_PINNED_OR_BINDING_DRIFT'); END IF;
 IF c->>'verdict' IN ('BLOCK','INCONCLUSIVE') THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code',CASE WHEN c->>'verdict'='BLOCK'
          THEN 'L5_NATIVE_BLOCK_NEVER_PROMOTES' ELSE 'L5_NATIVE_INCONCLUSIVE_NEVER_PROMOTES' END,
    'case_id',c->>'id','verdict',c->>'verdict'); END IF;
 RETURN jsonb_build_object('status','REAL_VERDICT_ALLOW_VERIFIED',
   'case_id',c->>'id','verdict','ALLOW',
   'rule_snapshot_sha256',actual_sha,
   'packet_sha256',p.ig_semantic_packet_sha256,
   'ig_external_receipt_sha256',p.ig_semantic_external_receipt_sha256,
   'case_binding_sha256',v_binding_sha,'independence_attested',false);
END $real_verify$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_blind_verdict_verify_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_blind_verdict_verify_v1(text) TO service_role;

-- Pin only a case already present in existing IG readback. It can never
-- receive a verdict/quote/authority supplied by the invoking caller.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_blind_verdict_pin_v1(
 p_promotion_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $pin$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE; c jsonb;
 v_case_sha text; v_binding_sha text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND OR p.status<>'PENDING' THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','PROMOTION_NOT_PENDING'); END IF;
 c:=p.ig_semantic_external_receipt->'l5_blind_case_verdict';
 IF jsonb_typeof(c) IS DISTINCT FROM 'object' THEN RETURN jsonb_build_object(
   'status','RETRY_REQUIRED','blocking_code','L5_REAL_BLIND_CASE_RECEIPT_NOT_PROVIDED'); END IF;
 IF c->>'id' !~ '^K[A-F0-9]{8,32}$'
    OR c->>'verdict' NOT IN ('ALLOW','BLOCK','INCONCLUSIVE')
    OR c->>'test_only_synthetic'='true'
    OR nullif(c->>'exact_excerpt','') IS NULL
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
   'blocking_code','L5_BLIND_CASE_REJECTED'); END IF;
 v_case_sha:=encode(extensions.digest(convert_to(c::text,'UTF8'),'sha256'),'hex');
 v_binding_sha:=encode(extensions.digest(convert_to(
   jsonb_build_object('promotion_id',p_promotion_id,'case_id',c->>'id',
     'case_sha256',v_case_sha,'ig_run_id',p.ig_semantic_run_id,
     'rule_sha256',p.request_snapshot_sha256,
     'packet_sha256',p.ig_semantic_packet_sha256,
     'candidate_sha256',p.ig_semantic_candidate_sha256,
     'ig_receipt_sha256',p.ig_semantic_external_receipt_sha256,
     'ig_binding_sha256',p.ig_semantic_binding_sha256)::text,'UTF8'),'sha256'),'hex');
 UPDATE public.lf_rule_promotion_v1
 SET l5_blind_case_id=c->>'id',l5_blind_case_sha256=v_case_sha,
     l5_blind_case_binding_sha256=v_binding_sha
 WHERE promotion_id=p_promotion_id;
 RETURN public.lf_rule_promotion_blind_verdict_verify_v1(p_promotion_id);
END $pin$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_blind_verdict_pin_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_blind_verdict_pin_v1(text) TO service_role;

-- Canonical readback uses server-read rule row, not an external flag.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_rule_readback_v1(p_rule_code text)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog','public','extensions' AS $rb$
 SELECT jsonb_build_object('estado',r.estado,
  'rule_code',r.codigo,
  'snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r.codigo))
 FROM lf_ops.reglas r WHERE r.codigo=p_rule_code
$rb$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_rule_readback_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_rule_readback_v1(text) TO service_role;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_profile_owner_verify_v1(
 p_promotion_id text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $owner_verify$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 owner_map public.lf_rule_promotion_profile_owner_v1%ROWTYPE;
 reviewer public.lf_operation_execution%ROWTYPE;
 step70 public.lf_operation_execution_steps%ROWTYPE;
 j jsonb; gate jsonb; expected jsonb; recorded jsonb;
 receipt_sha text; bind_sha text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 j:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);
 IF public.lf_rule_promotion_blind_verdict_verify_v1(p_promotion_id)->>'status'
      IS DISTINCT FROM 'REAL_VERDICT_ALLOW_VERIFIED' THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
      'blocking_code','OWNER_APPROVAL_REQUIRES_REAL_BLIND_ALLOW'); END IF;
 -- Preserve the L4 legacy enforcement guard: an unresolved semantic
 -- Step70 enforcement EKB must not be bypassed by an owner-profile receipt.
 IF to_regclass('public.lf_error_knowledge') IS NULL THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code','PROFILE_SEMANTIC_JUDGE_EKB_READBACK_UNAVAILABLE'); END IF;
 IF NOT EXISTS(
   SELECT 1 FROM public.lf_error_knowledge k
    WHERE k.codigo='PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001'
      AND k.estado IN ('RESOLVED','VALIDATED_TESTED')
 ) THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code','PROFILE_SEMANTIC_JUDGE_EKB_NOT_RESOLVED'); END IF;
 SELECT * INTO owner_map FROM public.lf_rule_promotion_profile_owner_v1
 WHERE rule_code=p.rule_code AND status='ACTIVE';
 IF NOT FOUND OR owner_map.owner_profile_code IS NULL
    OR owner_map.owner_profile_code=p.requested_by_profile
    OR owner_map.owner_profile_code=p.ig_semantic_validator_identity
    OR owner_map.owner_profile_code ~ '^(HUMAN:|INPUT_VALIDATOR:|IG:)'
    OR owner_map.source_decision_sha256 IS DISTINCT FROM j->>'source_decision_sha256'
    OR NOT EXISTS (
     SELECT 1 FROM public.lf_decisiones_gov g
     JOIN lf_ops.reglas r ON r.origen=g.id_decision
     WHERE r.codigo=p.rule_code
       AND g.estado_normalizado IN ('VIGENTE','APROBADA')
       AND g.raw_payload->>'owner_profile_code'=owner_map.owner_profile_code
       AND g.raw_payload->>'rule_code'=p.rule_code
   )
    OR NOT EXISTS (
     SELECT 1 FROM public.lf_profile_write_authority_v1 a
     WHERE a.profile_code=owner_map.owner_profile_code
       AND a.operation_code='PROMOCION_REGLA_LF' AND a.status='ACTIVE'
    )
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code','PROFILE_OWNER_RULE_AUTHORITY_NOT_ATTESTED'); END IF;
 IF p.owner_approval_receipt IS NULL THEN RETURN jsonb_build_object(
   'status','PROFILE_APPROVAL_REQUIRED',
   'blocking_code','PROFILE_OWNER_APPROVAL_RECEIPT_MISSING',
   'owner_profile_code',owner_map.owner_profile_code); END IF;

 SELECT * INTO reviewer FROM public.lf_operation_execution
 WHERE execution_id=p.owner_approval_execution_id
   AND operation_code='EJECUCION_PERFIL_LF' AND status='COMPLETED'
   AND target_code=owner_map.owner_profile_code
   AND execution_id<>p.request_execution_id
   AND manifest->>'profile_decision_mode'='RULE_PROMOTION_OWNER_APPROVAL';
 IF NOT FOUND THEN RETURN jsonb_build_object(
   'status','HUMAN_DECISION_REQUIRED',
   'blocking_code','PROFILE_OWNER_EXECUTION_NOT_ATTESTED'); END IF;
 SELECT * INTO step70 FROM public.lf_operation_execution_steps
 WHERE execution_id=reviewer.execution_id AND step_id='semantic_judge'
    AND status='STEP_PASS_WITH_EVIDENCE';
 IF NOT FOUND OR nullif(step70.evidence_ref,'') IS NULL
    OR step70.created_by_execution_id IS DISTINCT FROM reviewer.execution_id
    OR step70.evidence_payload->>'test_only_synthetic'='true'
    OR step70.evidence_payload#>>'{semantic_judge_result,test_only_synthetic}'='true'
    OR step70.evidence_payload#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
    OR step70.evidence_payload#>>'{semantic_judge_result,validator_status}' IS DISTINCT FROM 'PASS'
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
   'blocking_code','PROFILE_OWNER_STEP70_NOT_ATTESTED'); END IF;

 recorded:=step70.evidence_payload->'rule_promotion_owner_approval';
 expected:=jsonb_build_object(
   'schema_version','LF_RULE_PROMOTION_OWNER_APPROVAL_V1',
   'decision','APPROVE',
   'promotion_id',p.promotion_id,
   'owner_profile_code',owner_map.owner_profile_code,
   'owner_execution_id',reviewer.execution_id,
   'proposer_profile_code',p.requested_by_profile,
   'ig_proposer_identity',p.ig_semantic_validator_identity,
   'ig_run_id',p.ig_semantic_run_id,
   'rule_code',p.rule_code,
   'rule_snapshot_sha256',p.request_snapshot_sha256,
   'packet_sha256',p.ig_semantic_packet_sha256,
   'candidate_sha256',p.ig_semantic_candidate_sha256,
   'ig_external_receipt_sha256',p.ig_semantic_external_receipt_sha256,
   'ig_review_sha256',p.ig_semantic_review_sha256,
   'ig_binding_sha256',p.ig_semantic_binding_sha256,
   'policy_sha256',p.ig_semantic_policy_set_sha256,
   'dependency_sha256',p.ig_semantic_dependency_sha256,
   'source_decision_sha256',owner_map.source_decision_sha256);
 IF recorded IS DISTINCT FROM expected
    OR p.owner_approval_receipt IS DISTINCT FROM recorded
    OR p.owner_approval_profile_code IS DISTINCT FROM owner_map.owner_profile_code
    OR p.owner_approval_authority_source_sha256 IS DISTINCT FROM owner_map.source_decision_sha256
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code','PROFILE_OWNER_APPROVAL_BINDING_MISMATCH'); END IF;
 receipt_sha:=encode(extensions.digest(convert_to(recorded::text,'UTF8'),'sha256'),'hex');
 bind_sha:=encode(extensions.digest(convert_to(jsonb_build_object(
     'promotion_id',p.promotion_id,
     'owner_profile_code',owner_map.owner_profile_code,
     'owner_execution_id',reviewer.execution_id,
     'owner_receipt_sha256',receipt_sha,
     'ig_binding_sha256',p.ig_semantic_binding_sha256,
     'source_decision_sha256',owner_map.source_decision_sha256
 )::text,'UTF8'),'sha256'),'hex');
 IF receipt_sha IS DISTINCT FROM p.owner_approval_receipt_sha256
    OR bind_sha IS DISTINCT FROM p.owner_approval_binding_sha256
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code','PROFILE_OWNER_RECEIPT_HASH_DRIFT'); END IF;
 RETURN jsonb_build_object('status','VERIFIED_PROFILE_OWNER',
   'owner_profile_code',owner_map.owner_profile_code,
   'owner_execution_id',reviewer.execution_id,
   'owner_approval_receipt_sha256',receipt_sha,
   'owner_approval_binding_sha256',bind_sha,
   'independence_attested',false);
END $owner_verify$;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_profile_approve_v1(
 p_promotion_id text,p_owner_execution_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $owner_approve$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 reviewer public.lf_operation_execution%ROWTYPE;
 st public.lf_operation_execution_steps%ROWTYPE;
 owner_map public.lf_rule_promotion_profile_owner_v1%ROWTYPE;
 gate jsonb; judgement jsonb; v_receipt jsonb; v_receipt_sha text; v_binding_sha text;
 check_owner jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND OR p.status<>'PENDING' THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING'); END IF;
 judgement:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);
 IF judgement->>'classification'<>'AUTO_APPROVABLE' THEN
   RETURN public.lf_rule_promotion_governed_decide_v1(p_promotion_id,
     'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1'); END IF;
 gate:=public.lf_rule_promotion_ig_semantic_verify_v1(p_promotion_id);
 IF gate->>'status' IS DISTINCT FROM 'READY_FOR_PROFILE_APPROVAL' THEN
   RETURN public.lf_rule_promotion_governed_decide_v1(p_promotion_id,
     'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1'); END IF;
 IF public.lf_rule_promotion_blind_verdict_verify_v1(p_promotion_id)->>'status'
     IS DISTINCT FROM 'REAL_VERDICT_ALLOW_VERIFIED' THEN
   RETURN public.lf_rule_promotion_governed_decide_v1(p_promotion_id,
     'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1'); END IF;
 SELECT * INTO owner_map FROM public.lf_rule_promotion_profile_owner_v1
 WHERE rule_code=p.rule_code AND status='ACTIVE';
 IF NOT FOUND OR owner_map.owner_profile_code IS NULL
    OR owner_map.owner_profile_code=p.requested_by_profile
    OR owner_map.owner_profile_code=p.ig_semantic_validator_identity
    OR owner_map.owner_profile_code ~ '^(HUMAN:|INPUT_VALIDATOR:|IG:)'
    OR owner_map.source_decision_sha256 IS DISTINCT FROM judgement->>'source_decision_sha256'
    OR NOT EXISTS (
     SELECT 1 FROM public.lf_decisiones_gov g
     JOIN lf_ops.reglas r ON r.origen=g.id_decision
     WHERE r.codigo=p.rule_code
       AND g.estado_normalizado IN ('VIGENTE','APROBADA')
       AND g.raw_payload->>'owner_profile_code'=owner_map.owner_profile_code
       AND g.raw_payload->>'rule_code'=p.rule_code
   )
    OR NOT EXISTS (
     SELECT 1 FROM public.lf_profile_write_authority_v1 a
     WHERE a.profile_code=owner_map.owner_profile_code
       AND a.operation_code='PROMOCION_REGLA_LF' AND a.status='ACTIVE'
    )
 THEN RETURN public.lf_rule_promotion_governed_decide_v1(p_promotion_id,
      'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1'); END IF;

 SELECT * INTO reviewer FROM public.lf_operation_execution
 WHERE execution_id=p_owner_execution_id
   AND operation_code='EJECUCION_PERFIL_LF' AND status='COMPLETED'
   AND target_code=owner_map.owner_profile_code
   AND execution_id<>p.request_execution_id
   AND manifest->>'profile_decision_mode'='RULE_PROMOTION_OWNER_APPROVAL';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
   'blocking_code','PROFILE_OWNER_EXECUTION_NOT_ATTESTED'); END IF;
 SELECT * INTO st FROM public.lf_operation_execution_steps
 WHERE execution_id=reviewer.execution_id AND step_id='semantic_judge'
   AND status='STEP_PASS_WITH_EVIDENCE';
 IF NOT FOUND OR st.evidence_ref IS NULL
    OR st.created_by_execution_id IS DISTINCT FROM reviewer.execution_id
    OR st.evidence_payload->>'test_only_synthetic'='true'
    OR st.evidence_payload#>>'{semantic_judge_result,test_only_synthetic}'='true'
    OR st.evidence_payload#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
    OR st.evidence_payload#>>'{semantic_judge_result,validator_status}' IS DISTINCT FROM 'PASS'
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
   'blocking_code','PROFILE_OWNER_STEP70_NOT_ATTESTED'); END IF;
 v_receipt:=st.evidence_payload->'rule_promotion_owner_approval';
 IF jsonb_typeof(v_receipt) IS DISTINCT FROM 'object' THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
     'blocking_code','PROFILE_OWNER_APPROVAL_RECEIPT_MISSING'); END IF;
 v_receipt_sha:=encode(extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),'hex');
 v_binding_sha:=encode(extensions.digest(convert_to(jsonb_build_object(
     'promotion_id',p_promotion_id,
     'owner_profile_code',owner_map.owner_profile_code,
     'owner_execution_id',reviewer.execution_id,
     'owner_receipt_sha256',v_receipt_sha,
     'ig_binding_sha256',p.ig_semantic_binding_sha256,
     'source_decision_sha256',owner_map.source_decision_sha256
 )::text,'UTF8'),'sha256'),'hex');
 UPDATE public.lf_rule_promotion_v1 SET
   owner_approval_profile_code=owner_map.owner_profile_code,
   owner_approval_execution_id=reviewer.execution_id,
   owner_approval_receipt=v_receipt,
   owner_approval_receipt_sha256=v_receipt_sha,
   owner_approval_binding_sha256=v_binding_sha,
   owner_approval_authority_source_sha256=owner_map.source_decision_sha256
 WHERE promotion_id=p_promotion_id;
 check_owner:=public.lf_rule_promotion_profile_owner_verify_v1(p_promotion_id);
 IF check_owner->>'status' IS DISTINCT FROM 'VERIFIED_PROFILE_OWNER' THEN
   UPDATE public.lf_rule_promotion_v1 SET
     owner_approval_profile_code=NULL,owner_approval_execution_id=NULL,
     owner_approval_receipt=NULL,owner_approval_receipt_sha256=NULL,
     owner_approval_binding_sha256=NULL,owner_approval_authority_source_sha256=NULL
   WHERE promotion_id=p_promotion_id;
   RETURN check_owner; END IF;
 RETURN public.lf_rule_promotion_governed_decide_v1(p_promotion_id,
   'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1');
END $owner_approve$;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_governed_decide_v1(
 p_promotion_id text,p_decider_actor text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions','lf_ops'
AS $governed$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 judgement jsonb; gate jsonb; owner_gate jsonb; real_gate jsonb; v_sha text;
 actor constant text:='LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1';
 v_code text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.status<>'PENDING' THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING'); END IF;
 IF p_decider_actor IS DISTINCT FROM actor
    OR p_decider_actor=p.requested_by_profile OR p_decider_actor=p.request_execution_id
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','DECIDER_NOT_SEPARATE_FROM_REQUESTER'); END IF;

 judgement:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);
 v_sha:=encode(extensions.digest(convert_to(judgement::text,'UTF8'),'sha256'),'hex');
 UPDATE public.lf_rule_promotion_v1 SET judge_receipt=judgement,
   judge_receipt_sha256=v_sha,decision_route=judgement->>'classification'
 WHERE promotion_id=p_promotion_id;
 IF p.ig_semantic_bind_failure_code IN (
      'BLOCK_IG_SEMANTIC_CITATION_NOT_IN_CURRENT_SOURCE',
      'BLOCK_IG_SEMANTIC_CITATION_MALFORMED',
      'BLOCK_IG_SEMANTIC_CITATION_COUNT_INVALID',
      'BLOCK_IG_SEMANTIC_REVIEW_BINDING_INVALID'
    ) THEN
      UPDATE public.lf_rule_promotion_v1 SET decision_route='HUMAN_DECISION_REQUIRED'
      WHERE promotion_id=p_promotion_id;
      RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
        'blocking_code',p.ig_semantic_bind_failure_code,'promotion_id',p_promotion_id);
 END IF;
 IF judgement->>'classification'='HUMAN_DECISION_REQUIRED' THEN
   UPDATE public.lf_rule_promotion_v1 SET decision_route='HUMAN_DECISION_REQUIRED'
      WHERE promotion_id=p_promotion_id;
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
     'blocking_codes',judgement->'blocking_codes','promotion_id',p_promotion_id); END IF;
 IF judgement->>'classification'<>'AUTO_APPROVABLE' THEN
   -- A policy/dependency drift is not silently hidden by a deterministic
   -- BLOCK. It is sent to HUMAN for investigation; no apply is authorized.
   gate:=public.lf_rule_promotion_ig_semantic_verify_v1(p_promotion_id);
   IF gate->>'blocking_code'='BLOCK_IG_SEMANTIC_POLICY_DEPENDENCY_DRIFT' THEN
     UPDATE public.lf_rule_promotion_v1 SET decision_route='HUMAN_DECISION_REQUIRED'
       WHERE promotion_id=p_promotion_id;
     RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
       'blocking_code',gate->>'blocking_code',
       'deterministic_blocking_codes',judgement->'blocking_codes',
       'promotion_id',p_promotion_id); END IF;
   RETURN jsonb_build_object('status','BLOCKED','blocking_codes',
     judgement->'blocking_codes','promotion_id',p_promotion_id); END IF;

 gate:=public.lf_rule_promotion_ig_semantic_verify_v1(p_promotion_id);
 v_code:=gate->>'blocking_code';
 IF gate->>'status' IS DISTINCT FROM 'READY_FOR_PROFILE_APPROVAL' THEN
   IF v_code IN (
     'BLOCK_IG_NATIVE_SEMANTIC_CONTRADICTION',
     'RETRY_IG_NATIVE_SEMANTIC_INCONCLUSIVE',
     'BLOCK_IG_SEMANTIC_CITATION_NOT_IN_CURRENT_SOURCE',
     'BLOCK_IG_SEMANTIC_CITATION_MALFORMED',
     'BLOCK_IG_SEMANTIC_CITATION_COUNT_INVALID',
     'BLOCK_IG_SEMANTIC_REVIEW_BINDING_INVALID',
     'BLOCK_IG_SEMANTIC_RULE_SNAPSHOT_DRIFT',
     'BLOCK_IG_SEMANTIC_POLICY_DEPENDENCY_DRIFT',
     'BLOCK_IG_SEMANTIC_RECEIPT_HASH_DRIFT',
     'BLOCK_IG_SEMANTIC_BINDING_HASH_DRIFT',
     'BLOCK_IG_NATIVE_SEMANTIC_VERDICT_UNSUPPORTED',
     'BLOCK_EXISTING_IG_SEMANTIC_AUDIT'
   ) THEN
      UPDATE public.lf_rule_promotion_v1 SET decision_route='HUMAN_DECISION_REQUIRED'
      WHERE promotion_id=p_promotion_id;
      RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
        'blocking_code',v_code,'promotion_id',p_promotion_id,
        'semantic_gate',gate,'independence_attested',false); END IF;
   RETURN jsonb_build_object('status',gate->>'status',
     'blocking_code',v_code,'promotion_id',p_promotion_id,'semantic_gate',gate); END IF;

 real_gate:=public.lf_rule_promotion_blind_verdict_verify_v1(p_promotion_id);
 IF real_gate->>'status'='HUMAN_DECISION_REQUIRED' THEN
   UPDATE public.lf_rule_promotion_v1 SET decision_route='HUMAN_DECISION_REQUIRED'
   WHERE promotion_id=p_promotion_id;
   RETURN real_gate || jsonb_build_object('promotion_id',p_promotion_id); END IF;
 IF real_gate->>'status' IS DISTINCT FROM 'REAL_VERDICT_ALLOW_VERIFIED' THEN
   RETURN real_gate || jsonb_build_object('promotion_id',p_promotion_id); END IF;

 owner_gate:=public.lf_rule_promotion_profile_owner_verify_v1(p_promotion_id);
 IF owner_gate->>'status'='HUMAN_DECISION_REQUIRED' THEN
   UPDATE public.lf_rule_promotion_v1 SET decision_route='HUMAN_DECISION_REQUIRED'
   WHERE promotion_id=p_promotion_id;
   RETURN owner_gate || jsonb_build_object('promotion_id',p_promotion_id); END IF;
 IF owner_gate->>'status' IS DISTINCT FROM 'VERIFIED_PROFILE_OWNER' THEN
   UPDATE public.lf_rule_promotion_v1 SET decision_route='PROFILE_OWNER_APPROVAL_REQUIRED'
   WHERE promotion_id=p_promotion_id;
   RETURN owner_gate || jsonb_build_object('promotion_id',p_promotion_id); END IF;

 UPDATE public.lf_rule_promotion_v1 SET status='APPROVED',
   decision_route='PROFILE_OWNER_APPROVED',
   decided_by='PROFILE:'||p.owner_approval_profile_code,decided_at=now()
 WHERE promotion_id=p_promotion_id AND status='PENDING';
 RETURN jsonb_build_object('status','APPROVED','promotion_id',p_promotion_id,
   'decided_by','PROFILE:'||p.owner_approval_profile_code,
   'owner_approval_binding_sha256',p.owner_approval_binding_sha256,
   'independence_attested',false);
END $governed$;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $apply$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE; gate jsonb; owner_gate jsonb;
   real_gate jsonb; rb jsonb; v_expected text; v_after text; v_error text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.status<>'APPROVED' THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); END IF;
 gate:=public.lf_rule_promotion_ig_semantic_verify_v1(p_promotion_id);
 IF gate->>'status' IS DISTINCT FROM 'READY_FOR_PROFILE_APPROVAL' THEN
   RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','PROMOTION_IG_SEMANTIC_RECEIPT_NOT_CURRENT','semantic_gate',gate); END IF;
 real_gate:=public.lf_rule_promotion_blind_verdict_verify_v1(p_promotion_id);
 IF real_gate->>'status' IS DISTINCT FROM 'REAL_VERDICT_ALLOW_VERIFIED' THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','PROMOTION_REAL_BLIND_VERDICT_NOT_CURRENT','real_gate',real_gate); END IF;
 owner_gate:=public.lf_rule_promotion_profile_owner_verify_v1(p_promotion_id);
 IF owner_gate->>'status' IS DISTINCT FROM 'VERIFIED_PROFILE_OWNER' THEN
   RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','PROMOTION_OWNER_APPROVAL_RECEIPT_NOT_CURRENT',
    'owner_gate',owner_gate); END IF;
 IF p.decided_by IS DISTINCT FROM 'PROFILE:'||p.owner_approval_profile_code
    OR p.decision_route IS DISTINCT FROM 'PROFILE_OWNER_APPROVED'
    OR p.judge_receipt IS NULL
    OR p.judge_receipt_sha256 IS DISTINCT FROM encode(
         extensions.digest(convert_to(p.judge_receipt::text,'UTF8'),'sha256'),'hex')
    OR p.judge_receipt IS DISTINCT FROM public.lf_rule_promotion_quality_judge_v1(p_promotion_id)
    OR p.judge_receipt->>'classification' IS DISTINCT FROM 'AUTO_APPROVABLE'
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','PROMOTION_JUDGE_RECEIPT_NOT_CURRENT'); END IF;
 IF public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) IS DISTINCT FROM p.request_snapshot_sha256 THEN
   UPDATE public.lf_rule_promotion_v1 SET status='STALE' WHERE promotion_id=p_promotion_id;
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); END IF;
 -- Compute canonical expected post-transition snapshot from the same row
 -- BEFORE any write. Readback can only succeed if exactly this state lands.
 SELECT encode(extensions.digest(convert_to(
    (to_jsonb(r) || jsonb_build_object('estado','VIGENTE'))::text,'UTF8'),'sha256'),'hex')
 INTO v_expected FROM lf_ops.reglas r WHERE r.codigo=p.rule_code AND r.estado='CANDIDATO';
 IF v_expected IS NULL THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','PROMOTION_RULE_ROW_NOT_CANDIDATE'); END IF;

 -- Subtransaction ensures rollback of the VIGENTE update when readback fails.
 -- The retry marker is stored OUTSIDE that subtransaction.
 v_error:=NULL;
 BEGIN
   UPDATE lf_ops.reglas SET estado='VIGENTE'
     WHERE codigo=p.rule_code AND estado='CANDIDATO';
   IF NOT FOUND THEN RAISE EXCEPTION 'L5_NO_CANDIDATE_ROW'; END IF;
   rb:=public.lf_rule_promotion_rule_readback_v1(p.rule_code);
   IF rb->>'estado' IS DISTINCT FROM 'VIGENTE'
      OR rb->>'snapshot_sha256' IS DISTINCT FROM v_expected THEN
      RAISE EXCEPTION 'L5_READBACK_MISMATCH';
   END IF;
 EXCEPTION WHEN OTHERS THEN
   v_error:=SQLSTATE||':'||SQLERRM;
 END;
 IF v_error IS NOT NULL THEN
   UPDATE public.lf_rule_promotion_v1 SET
     rule_return_status='RETRY_REQUIRED',
     rule_return_error='RULE_READBACK_FAILED',
     rule_return_payload=jsonb_build_object(
       'status','RETRY_REQUIRED','rule_code',p.rule_code,
       'owner_execution_id',p.owner_approval_execution_id,
       'expected_sha256',v_expected,
       'reason','READBACK_MISMATCH_OR_WRITE_FAILURE',
       'no_vigente_accredited',true)
     WHERE promotion_id=p_promotion_id;
   RETURN jsonb_build_object('status','RETRY_REQUIRED',
     'blocking_code','RULE_READBACK_FAILED_NO_VIGENTE',
     'promotion_id',p_promotion_id,'rule_code',p.rule_code,
     'readback_error',v_error,'apply_authorized',false);
 END IF;
 v_after:=rb->>'snapshot_sha256';
 UPDATE public.lf_rule_promotion_v1 SET
   status='APPLIED',applied_at=now(),
   rule_return_status='READY',rule_return_error=NULL,
   rule_return_payload=jsonb_build_object(
     'status','READY','promotion_id',p_promotion_id,
     'rule_code',p.rule_code,
     'owner_profile_code',p.owner_approval_profile_code,
     'owner_execution_id',p.owner_approval_execution_id,
     'estado','VIGENTE','readback_snapshot_sha256',v_after,
     'owner_approval_binding_sha256',p.owner_approval_binding_sha256,
     'ig_external_receipt_sha256',p.ig_semantic_external_receipt_sha256,
     'blind_case_binding_sha256',p.l5_blind_case_binding_sha256)
   WHERE promotion_id=p_promotion_id;
 UPDATE public.lf_rule_promotion_v1 SET
   rule_return_sha256=encode(extensions.digest(convert_to(
      rule_return_payload::text,'UTF8'),'sha256'),'hex')
   WHERE promotion_id=p_promotion_id;
 RETURN jsonb_build_object('status','APPLIED','rule_code',p.rule_code,
   'readback_status','VERIFIED','readback_snapshot_sha256',v_after,
   'profile_return_status','READY',
   'independence_attested',false);
END $apply$;
-- Profile consumes this result only through its existing governed
-- EXECUCION_PERFIL_LF continuation; this does NOT write Step80 or close RUN.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_profile_return_readback_v1(
 p_promotion_id text,p_owner_execution_id text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $return$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE; rb jsonb; v_sha text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p_owner_execution_id IS DISTINCT FROM p.owner_approval_execution_id THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','WRONG_PROFILE_EXECUTION'); END IF;
 IF p.rule_return_status='RETRY_REQUIRED' THEN
   RETURN coalesce(p.rule_return_payload,jsonb_build_object('status','RETRY_REQUIRED'));
 END IF;
 IF p.status<>'APPLIED' OR p.rule_return_status<>'READY' THEN
   RETURN jsonb_build_object('status','RETRY_REQUIRED',
     'blocking_code','RULE_PROMOTION_RETURN_NOT_READY'); END IF;
 v_sha:=encode(extensions.digest(convert_to(p.rule_return_payload::text,'UTF8'),'sha256'),'hex');
 rb:=public.lf_rule_promotion_rule_readback_v1(p.rule_code);
 IF v_sha IS DISTINCT FROM p.rule_return_sha256
    OR rb->>'estado' IS DISTINCT FROM 'VIGENTE'
    OR rb->>'snapshot_sha256' IS DISTINCT FROM p.rule_return_payload->>'readback_snapshot_sha256'
    OR public.lf_rule_promotion_blind_verdict_verify_v1(p_promotion_id)->>'status'
        IS DISTINCT FROM 'REAL_VERDICT_ALLOW_VERIFIED'
 THEN RETURN jsonb_build_object('status','RETRY_REQUIRED',
   'blocking_code','RULE_PROMOTION_PROFILE_RETURN_READBACK_DRIFT'); END IF;
 RETURN p.rule_return_payload || jsonb_build_object(
   'readback_verified',true,'readback_receipt_sha256',p.rule_return_sha256,
   'profile_return_contract','EXISTING_PROFILE_CONTINUATION_NO_NEW_TRANSPORT');
END $return$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_profile_return_readback_v1(text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_profile_return_readback_v1(text,text)
 TO service_role;

COMMIT;
