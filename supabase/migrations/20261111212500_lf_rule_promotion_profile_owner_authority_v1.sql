-- LF #3779 Lote 4D CANDIDATE ONLY. Governed profile OWNER decision, not IG approval.
-- This does not grant IG authority. Human route remains blocked pending authenticated receipt.
-- IMPORTANT: PG18 ROLLBACK / DRAFT only; DO NOT apply in production.
BEGIN;
DO $guard$
BEGIN
 IF md5(pg_get_functiondef('public.lf_rule_promotion_ig_semantic_verify_v1(text)'::regprocedure))
      IS DISTINCT FROM 'f38a1466e9e1cc31ca97a04123bc175f'
    OR md5(pg_get_functiondef('public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure))
      IS DISTINCT FROM '7c9f4932ddf54abb188873d5a8b197f7'
    OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
      IS DISTINCT FROM 'b0e8ea53e051667cb6b7ffecaa7fbdaf'
    OR md5(pg_get_functiondef('public.lf_rule_promotion_bind_ig_semantic_v1(text,bigint,text,bigint,uuid,text)'::regprocedure))
      IS DISTINCT FROM '4d7c4a4b9f997a372aea3d22cebf38e5'
 THEN RAISE EXCEPTION 'BLOCK_L4D_UPSTREAM_GATE_MD5_DRIFT'; END IF;
END $guard$;

ALTER TABLE public.lf_rule_promotion_v1
 ADD COLUMN ig_semantic_bind_failure_code text;

-- Preserve citation failures in the promotion row so HUMAN escalation can
-- read back an invalid quote even though the IG binding itself was rejected.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_bind_ig_semantic_v1(
 p_promotion_id text,
 p_run_id bigint,
 p_validator_identity text,
 p_handoff_receipt_id bigint,
 p_ticket uuid,
 p_candidate_sha256 text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $bind$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 judgement jsonb;
 packet jsonb;
 receipt jsonb;
 packet_sha text;
 receipt_sha text;
 rule_sha text;
 review_sha text;
 binding_sha text;
 candidate_sha text;
 review jsonb;
 citation_gate jsonb;
 step70 jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1
  WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND OR p.status<>'PENDING' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING');
 END IF;
 IF p_run_id IS NULL OR p_run_id<1
    OR p_handoff_receipt_id IS NULL OR p_handoff_receipt_id<1
    OR p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','IG_SEMANTIC_BINDING_INPUT_INVALID'); END IF;

 SELECT evidence_payload INTO step70
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p.request_execution_id
   AND step_id='semantic_judge' AND status='STEP_PASS_WITH_EVIDENCE';
 IF coalesce(step70->>'test_only_synthetic','false')='true'
    OR coalesce(step70#>>'{semantic_judge_result,test_only_synthetic}','false')='true'
    OR coalesce(step70#>>'{semantic_judge_result,model_call_count}','1')='0'
 THEN RETURN jsonb_build_object('status','BLOCKED',
  'blocking_code','BLOCK_SYNTHETIC_PARENT_STEP70_EVIDENCE'); END IF;

 judgement:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);
 IF judgement->>'classification'<>'AUTO_APPROVABLE' THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','DETERMINISTIC_FIRST_FILTER_NOT_AUTO_APPROVABLE',
     'deterministic_classification',judgement->>'classification',
     'blocking_codes',judgement->'blocking_codes');
 END IF;

 rule_sha:=public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code);
 IF rule_sha IS DISTINCT FROM p.request_snapshot_sha256 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_RULE_SNAPSHOT_DRIFT');
 END IF;

 packet:=public.fn_input_governance_semantic_packet_v1(
   p_run_id,p_validator_identity,p_handoff_receipt_id,p_ticket);
 IF packet->>'run_id' IS DISTINCT FROM p_run_id::text
    OR packet->>'status' NOT IN ('READY_FOR_MODEL_CANDIDATE','REMEDIATION_REQUIRED','SOURCE_SNAPSHOT_PIN_REQUIRED')
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','IG_SEMANTIC_PACKET_INVALID','packet_status',packet->>'status'); END IF;

 packet_sha:=packet->>'db_packet_sha256';
 IF packet_sha IS NULL OR packet_sha !~ '^[a-f0-9]{64}$' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_PACKET_SHA_INVALID'); END IF;

 receipt:=public.fn_input_governance_semantic_external_receipt_readback_v1(
   p_run_id,p_validator_identity,p_handoff_receipt_id,p_ticket,p_candidate_sha256);
 IF receipt->>'run_id' IS DISTINCT FROM p_run_id::text THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','IG_SEMANTIC_RECEIPT_RUN_MISMATCH');
 END IF;
 IF receipt ? 'candidate_sha256'
    AND p_candidate_sha256 IS NOT NULL
    AND receipt->>'candidate_sha256' IS DISTINCT FROM p_candidate_sha256
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','IG_SEMANTIC_CANDIDATE_SHA_MISMATCH'); END IF;

 receipt_sha:=encode(extensions.digest(convert_to(receipt::text,'UTF8'),'sha256'),'hex');
 candidate_sha:=coalesce(receipt->>'candidate_sha256',p_candidate_sha256);
 review:=receipt->'semantic_review';

 IF review IS NOT NULL THEN
   citation_gate:=public.lf_rule_promotion_ig_citation_verify_v1(
     p_promotion_id,review,p_run_id,packet_sha,candidate_sha,rule_sha,
     judgement->>'security_policy_set_sha256',judgement->>'dependency_sha256');
   IF citation_gate->>'status' IS DISTINCT FROM 'VERIFIED_CITATIONS' THEN
     UPDATE public.lf_rule_promotion_v1
       SET ig_semantic_bind_failure_code=citation_gate->>'blocking_code'
     WHERE promotion_id=p_promotion_id;
     RETURN citation_gate; END IF;
 END IF;
 review_sha:=CASE WHEN review IS NOT NULL THEN
   encode(extensions.digest(convert_to(review::text,'UTF8'),'sha256'),'hex')
   ELSE NULL END;
 binding_sha:=encode(extensions.digest(convert_to(
     jsonb_build_object('promotion_id',p_promotion_id,'ig_run_id',p_run_id,
     'rule_sha',rule_sha,'packet_sha',packet_sha,'candidate_sha',candidate_sha,
     'receipt_sha',receipt_sha,'review_sha',review_sha,
     'policy_sha',judgement->>'security_policy_set_sha256',
     'dependency_sha',judgement->>'dependency_sha256')::text,'UTF8'),'sha256'),'hex');

 UPDATE public.lf_rule_promotion_v1
 SET ig_semantic_run_id=p_run_id,
     ig_semantic_validator_identity=p_validator_identity,
     ig_semantic_handoff_receipt_id=p_handoff_receipt_id,
     ig_semantic_candidate_sha256=candidate_sha,
     ig_semantic_packet_sha256=packet_sha,
     ig_semantic_external_receipt=receipt,
     ig_semantic_external_receipt_sha256=receipt_sha,
     ig_semantic_rule_snapshot_sha256=rule_sha,
     ig_semantic_policy_set_sha256=judgement->>'security_policy_set_sha256',
     ig_semantic_dependency_sha256=judgement->>'dependency_sha256',
     ig_semantic_review=review,
     ig_semantic_review_sha256=review_sha,
     ig_semantic_binding_sha256=binding_sha,
     ig_semantic_bind_failure_code=NULL
 WHERE promotion_id=p_promotion_id;

 RETURN jsonb_build_object(
   'status','BOUND_EXISTING_IG_SEMANTIC_EVIDENCE',
   'promotion_id',p_promotion_id,
   'ig_run_id',p_run_id,
   'packet_status',packet->>'status',
   'external_receipt_status',receipt->>'status',
   'packet_sha256',packet_sha,
   'external_receipt_sha256',receipt_sha,
   'rule_snapshot_sha256',rule_sha,
   'binding_sha256',binding_sha,
   'semantic_verdict',coalesce(review->>'verdict','NOT_TESTED'),
   'promotion_authorized',false,
   'independent_semantic_judge_attested',false);
END $bind$;

-- Authority is a rule-specific governable mapping, NEVER a field claimed by
-- the candidate rule. No initial rows, no self-service writes.
CREATE TABLE public.lf_rule_promotion_profile_owner_v1 (
 rule_code text PRIMARY KEY,
 owner_profile_code text NOT NULL,
 source_decision_sha256 text NOT NULL CHECK(source_decision_sha256 ~ '^[a-f0-9]{64}$'),
 status text NOT NULL CHECK(status IN ('ACTIVE','REVOKED')),
 CHECK (owner_profile_code !~ '^(HUMAN:|INPUT_VALIDATOR:|IG:)'),
 CHECK (length(owner_profile_code)>2)
);
REVOKE ALL ON public.lf_rule_promotion_profile_owner_v1
 FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.lf_rule_promotion_profile_owner_v1 TO service_role;
-- Populating this mapping requires a separate authorized governance source.
-- In PG18 only, tests insert mock mappings as a superuser then ROLLBACK.

ALTER TABLE public.lf_rule_promotion_v1
 ADD COLUMN owner_approval_profile_code text,
 ADD COLUMN owner_approval_execution_id text,
 ADD COLUMN owner_approval_receipt jsonb,
 ADD COLUMN owner_approval_receipt_sha256 text,
 ADD COLUMN owner_approval_binding_sha256 text,
 ADD COLUMN owner_approval_authority_source_sha256 text;

-- #3682 validates IG evidence but never authorizes promotion. This function
-- returns ONLY readiness for the owner profile's separate decision.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_ig_semantic_verify_v1(
 p_promotion_id text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $verify$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 current_rule_sha text;
 current_receipt_sha text;
 current_review_sha text;
 current_binding_sha text;
 judgement jsonb;
 cite_result jsonb;
 v_verdict text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.ig_semantic_run_id IS NULL OR p.ig_semantic_external_receipt IS NULL THEN
   RETURN jsonb_build_object('status','RETRY_REQUIRED','blocking_code','RETRY_EXISTING_IG_SEMANTIC_REVIEW_REQUIRED');
 END IF;
 current_rule_sha:=public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code);
 current_receipt_sha:=encode(extensions.digest(
   convert_to(p.ig_semantic_external_receipt::text,'UTF8'),'sha256'),'hex');
 current_review_sha:=CASE WHEN p.ig_semantic_review IS NOT NULL THEN
   encode(extensions.digest(convert_to(p.ig_semantic_review::text,'UTF8'),'sha256'),'hex')
   ELSE NULL END;
 judgement:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);

 IF current_rule_sha IS DISTINCT FROM p.request_snapshot_sha256
    OR current_rule_sha IS DISTINCT FROM p.ig_semantic_rule_snapshot_sha256
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_SEMANTIC_RULE_SNAPSHOT_DRIFT'); END IF;
 IF current_receipt_sha IS DISTINCT FROM p.ig_semantic_external_receipt_sha256
    OR current_review_sha IS DISTINCT FROM p.ig_semantic_review_sha256
    OR p.ig_semantic_review IS DISTINCT FROM p.ig_semantic_external_receipt->'semantic_review'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_SEMANTIC_RECEIPT_HASH_DRIFT'); END IF;
 IF judgement->>'security_policy_set_sha256' IS DISTINCT FROM p.ig_semantic_policy_set_sha256
    OR judgement->>'dependency_sha256' IS DISTINCT FROM p.ig_semantic_dependency_sha256
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_SEMANTIC_POLICY_DEPENDENCY_DRIFT'); END IF;

 current_binding_sha:=encode(extensions.digest(convert_to(
     jsonb_build_object('promotion_id',p.promotion_id,'ig_run_id',p.ig_semantic_run_id,
     'rule_sha',p.ig_semantic_rule_snapshot_sha256,
     'packet_sha',p.ig_semantic_packet_sha256,
     'candidate_sha',p.ig_semantic_candidate_sha256,
     'receipt_sha',p.ig_semantic_external_receipt_sha256,
     'review_sha',p.ig_semantic_review_sha256,
     'policy_sha',p.ig_semantic_policy_set_sha256,
     'dependency_sha',p.ig_semantic_dependency_sha256)::text,'UTF8'),'sha256'),'hex');
 IF current_binding_sha IS DISTINCT FROM p.ig_semantic_binding_sha256 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_SEMANTIC_BINDING_HASH_DRIFT'); END IF;

 IF p.ig_semantic_external_receipt->>'status' IN (
      'SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED',
      'INDEPENDENT_SEMANTIC_VERDICT_REQUIRED')
 THEN RETURN jsonb_build_object('status','RETRY_REQUIRED',
      'blocking_code','RETRY_EXISTING_IG_SEMANTIC_EVIDENCE_INCOMPLETE',
      'external_receipt_status',p.ig_semantic_external_receipt->>'status'); END IF;
 IF p.ig_semantic_external_receipt->>'status' IS DISTINCT FROM
       'SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE' THEN
   RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','BLOCK_EXISTING_IG_SEMANTIC_RECEIPT_STATUS_UNSUPPORTED'); END IF;
 IF p.ig_semantic_external_receipt->>'audit_verdict' IN ('FAIL','BLOCKED') THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','BLOCK_EXISTING_IG_SEMANTIC_AUDIT',
     'audit_verdict',p.ig_semantic_external_receipt->>'audit_verdict'); END IF;
 IF p.ig_semantic_external_receipt->>'audit_verdict' IS DISTINCT FROM 'PASS'
    OR p.ig_semantic_external_receipt->>'model_candidate_verified' IS DISTINCT FROM 'true'
    OR p.ig_semantic_external_receipt->>'auditor_verified' IS DISTINCT FROM 'true'
 THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','BLOCK_IG_EXTERNAL_AUDIT_NOT_VERIFIED'); END IF;

 cite_result:=public.lf_rule_promotion_ig_citation_verify_v1(
   p_promotion_id,p.ig_semantic_review,p.ig_semantic_run_id,
   p.ig_semantic_packet_sha256,p.ig_semantic_candidate_sha256,
   p.ig_semantic_rule_snapshot_sha256,p.ig_semantic_policy_set_sha256,
   p.ig_semantic_dependency_sha256);
 IF cite_result->>'status' IS DISTINCT FROM 'VERIFIED_CITATIONS' THEN
   RETURN cite_result; END IF;
 v_verdict:=p.ig_semantic_review->>'verdict';
 IF v_verdict='BLOQUEAR' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_NATIVE_SEMANTIC_CONTRADICTION'); END IF;
 IF v_verdict='INCONCLUSO' THEN
   RETURN jsonb_build_object('status','RETRY_REQUIRED','blocking_code','RETRY_IG_NATIVE_SEMANTIC_INCONCLUSIVE'); END IF;
 IF v_verdict IS DISTINCT FROM 'PERMITIR' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_NATIVE_SEMANTIC_VERDICT_UNSUPPORTED'); END IF;

 -- Every #3682 receipt explicitly forbids promotion even when its audit is PASS.
 -- A future grant must come from a separately governed authority contract,
 -- NOT a caller-supplied flag or an audit success.
 IF p.ig_semantic_external_receipt->>'promotion_authorized' IS DISTINCT FROM 'false'
    OR p.ig_semantic_external_receipt->>'semantic_independence_credited' IS DISTINCT FROM 'false'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_AUTHORITY_CONTRACT_DRIFT'); END IF;
 RETURN jsonb_build_object('status','READY_FOR_PROFILE_APPROVAL',
   'blocking_code','IG_EVIDENCE_VERIFIED_PROFILE_AUTHORITY_REQUIRED',
   'rule_snapshot_sha256',current_rule_sha,
   'cited_evidence_sha256',cite_result->>'cited_evidence_sha256',
   'semantic_verdict','PERMITIR','promotion_authorized',false,
   'semantic_independence_credited',false);
END $verify$;

-- Readback owner identity against its specific authority mapping, existing
-- execution & official Step70 source; compare every hash on EACH invocation.
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
 SELECT * INTO owner_map FROM public.lf_rule_promotion_profile_owner_v1
 WHERE rule_code=p.rule_code AND status='ACTIVE';
 IF NOT FOUND OR owner_map.owner_profile_code IS NULL
    OR owner_map.owner_profile_code=p.requested_by_profile
    OR owner_map.owner_profile_code=p.ig_semantic_validator_identity
    OR owner_map.owner_profile_code ~ '^(HUMAN:|INPUT_VALIDATOR:|IG:)'
    OR owner_map.source_decision_sha256 IS DISTINCT FROM j->>'source_decision_sha256'
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
REVOKE ALL ON FUNCTION public.lf_rule_promotion_profile_owner_verify_v1(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_profile_owner_verify_v1(text) TO service_role;

-- "Decider" is the existing deterministic coordinator, not a new approver.
-- Only a profile with a matching governed Step70 receipt can authorize approval.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_governed_decide_v1(
 p_promotion_id text,p_decider_actor text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions','lf_ops'
AS $governed$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 judgement jsonb; gate jsonb; owner_gate jsonb; v_sha text;
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

-- Receives ONLY an already recorded official owner profile RUN + Step70.
-- No caller-provided owner identity/verdict JSON and no second judge/model.
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
 SELECT * INTO owner_map FROM public.lf_rule_promotion_profile_owner_v1
 WHERE rule_code=p.rule_code AND status='ACTIVE';
 IF NOT FOUND OR owner_map.owner_profile_code IS NULL
    OR owner_map.owner_profile_code=p.requested_by_profile
    OR owner_map.owner_profile_code=p.ig_semantic_validator_identity
    OR owner_map.owner_profile_code ~ '^(HUMAN:|INPUT_VALIDATOR:|IG:)'
    OR owner_map.source_decision_sha256 IS DISTINCT FROM judgement->>'source_decision_sha256'
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
REVOKE ALL ON FUNCTION public.lf_rule_promotion_profile_approve_v1(text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_profile_approve_v1(text,text)
 TO service_role;

-- Apply is the existing application path, but its authorizer is now the
-- owner PROFILE (not the deterministic control and never the IG validator).
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $apply$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE; gate jsonb; owner_gate jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.status<>'APPROVED' THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); END IF;
 gate:=public.lf_rule_promotion_ig_semantic_verify_v1(p_promotion_id);
 IF gate->>'status' IS DISTINCT FROM 'READY_FOR_PROFILE_APPROVAL' THEN
   RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','PROMOTION_IG_SEMANTIC_RECEIPT_NOT_CURRENT','semantic_gate',gate); END IF;
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
 UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo=p.rule_code AND estado='CANDIDATO';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','PROMOTION_RULE_ROW_NOT_CANDIDATE'); END IF;
 UPDATE public.lf_rule_promotion_v1 SET status='APPLIED',applied_at=now() WHERE promotion_id=p_promotion_id;
 RETURN jsonb_build_object('status','APPLIED','rule_code',p.rule_code,
   'decided_by',p.decided_by,'ig_promotion_authorized',false,
   'independence_attested',false);
END $apply$;

COMMIT;
