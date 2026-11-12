-- LF #3779 Lote4B. Candidate only: reuse existing Input Governance semantic Validator.
-- NO deploy / NO production. Deterministic judge remains first filter.
-- This migration does NOT create a second semantic packet, reviewer, judge, Router path or IG.
BEGIN;

DO $guard$
BEGIN
 IF md5(pg_get_functiondef(
   'public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure))
    IS DISTINCT FROM '451864b7f9a49d9dc64b2780a4556774'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
    IS DISTINCT FROM '83660185fd06fa3905864fdb73f178e2'
 THEN RAISE EXCEPTION 'BLOCK_RULE_NATIVE_SEMANTIC_GATE_UPSTREAM_MD5_DRIFT'; END IF;

 IF to_regprocedure('public.fn_input_governance_semantic_packet_v1(bigint,text,bigint,uuid)') IS NULL
 OR to_regprocedure('public.fn_input_governance_semantic_external_receipt_readback_v1(bigint,text,bigint,uuid,text)') IS NULL
 THEN RAISE EXCEPTION 'BLOCK_EXISTING_IG_SEMANTIC_VALIDATOR_API_NOT_AVAILABLE'; END IF;
END $guard$;

ALTER TABLE public.lf_rule_promotion_v1
 ADD COLUMN ig_semantic_run_id bigint,
 ADD COLUMN ig_semantic_validator_identity text,
 ADD COLUMN ig_semantic_handoff_receipt_id bigint,
 ADD COLUMN ig_semantic_candidate_sha256 text,
 ADD COLUMN ig_semantic_packet_sha256 text,
 ADD COLUMN ig_semantic_external_receipt jsonb,
 ADD COLUMN ig_semantic_external_receipt_sha256 text,
 ADD COLUMN ig_semantic_rule_snapshot_sha256 text,
 ADD COLUMN ig_semantic_policy_set_sha256 text,
 ADD COLUMN ig_semantic_dependency_sha256 text,
 ADD COLUMN ig_semantic_review jsonb,
 ADD COLUMN ig_semantic_review_sha256 text,
 ADD COLUMN ig_semantic_binding_sha256 text;

CREATE UNIQUE INDEX lf_rule_promotion_one_ig_run_v1
 ON public.lf_rule_promotion_v1(ig_semantic_run_id)
 WHERE ig_semantic_run_id IS NOT NULL;


-- Read-only evidence validator. Proposals and quotations are UNTRUSTED DATA.
-- This is source-precision verification, NOT a semantic judge or a second IG.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_ig_citation_verify_v1(
 p_promotion_id text,p_review jsonb,p_ig_run_id bigint,
 p_packet_sha text,p_candidate_sha text,p_rule_sha text,
 p_policy_sha text,p_dependency_sha text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $citations$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 c jsonb; v_code text; v_quote text; v_source_sha text;
 v_valid boolean; v_citations jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF jsonb_typeof(p_review) IS DISTINCT FROM 'object' THEN
   RETURN jsonb_build_object('status','RETRY_REQUIRED','blocking_code','RETRY_IG_CITED_SEMANTIC_VERDICT_REQUIRED'); END IF;
 IF p_review->>'promotion_id' IS DISTINCT FROM p_promotion_id
    OR p_review->>'ig_run_id' IS DISTINCT FROM p_ig_run_id::text
    OR p_review->>'rule_code' IS DISTINCT FROM p.rule_code
    OR p_review->>'rule_snapshot_sha256' IS DISTINCT FROM p_rule_sha
    OR p_review->>'packet_sha256' IS DISTINCT FROM p_packet_sha
    OR p_review->>'candidate_sha256' IS DISTINCT FROM p_candidate_sha
    OR p_review->>'security_policy_set_sha256' IS DISTINCT FROM p_policy_sha
    OR p_review->>'dependency_sha256' IS DISTINCT FROM p_dependency_sha
    OR p_review->>'verdict' NOT IN ('PERMITIR','BLOQUEAR','INCONCLUSO')
    OR jsonb_typeof(p_review->'cited_evidence') IS DISTINCT FROM 'array'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_SEMANTIC_REVIEW_BINDING_INVALID'); END IF;
 v_citations:=p_review->'cited_evidence';
 IF jsonb_array_length(v_citations)<1 OR jsonb_array_length(v_citations)>24 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_SEMANTIC_CITATION_COUNT_INVALID'); END IF;

 FOR c IN SELECT value FROM jsonb_array_elements(v_citations) AS q(value) LOOP
   v_code:=nullif(btrim(coalesce(c->>'source_code','')),'');
   v_quote:=nullif(btrim(coalesce(c->>'exact_excerpt','')),'');
   v_source_sha:=c->>'source_sha256';
   IF jsonb_typeof(c) IS DISTINCT FROM 'object'
      OR v_code IS NULL OR v_quote IS NULL
      OR nullif(btrim(coalesce(c->>'implication','')),'') IS NULL
      OR coalesce(array_length(regexp_split_to_array(v_quote,E'\\s+'),1),0)>25
      OR v_source_sha !~ '^[a-f0-9]{64}$'
   THEN RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','BLOCK_IG_SEMANTIC_CITATION_MALFORMED'); END IF;
   SELECT EXISTS(
     SELECT 1 FROM lf_ops.reglas rr
     WHERE rr.codigo=v_code AND rr.estado IN ('VIGENTE','CANDIDATO')
       AND public.lf_asset_snapshot_sha_v1('REGLA',rr.codigo)=v_source_sha
       AND position(v_quote IN rr.descripcion)>0
   ) OR EXISTS(
     SELECT 1 FROM lf_ops.politicas_seguridad ps
     WHERE ps.policy_code=v_code AND ps.status='VIGENTE'
       AND v_source_sha=p_policy_sha
       AND position(v_quote IN ps.policy_config::text)>0
   ) INTO v_valid;
   IF NOT coalesce(v_valid,false) THEN
     RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','BLOCK_IG_SEMANTIC_CITATION_NOT_IN_CURRENT_SOURCE',
       'source_code',v_code); END IF;
 END LOOP;
 RETURN jsonb_build_object('status','VERIFIED_CITATIONS',
   'rule_snapshot_sha256',p_rule_sha,
   'cited_evidence_sha256',encode(extensions.digest(
       convert_to(v_citations::text,'UTF8'),'sha256'),'hex'),
   'review_verdict',p_review->>'verdict');
END $citations$;

REVOKE ALL ON FUNCTION public.lf_rule_promotion_ig_citation_verify_v1(text,jsonb,bigint,text,text,text,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_ig_citation_verify_v1(text,jsonb,bigint,text,text,text,text,text)
 TO service_role;

-- Thin adapter to existing IG Validator; no self-issued semantic receipt.
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
     ig_semantic_binding_sha256=binding_sha
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

-- Apply invokes this same verifier again. A forged or stale citation/policy
-- cannot pass, even if someone manually marked a promotion APPROVED.
-- The CURRENT #3682 receipt remains NOT PROMOTABLE; no auto-approval.
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
 RETURN jsonb_build_object('status','RETRY_REQUIRED',
   'blocking_code','RETRY_SEMANTIC_QUALITY_GATE_NOT_AUTHORIZED',
   'rule_snapshot_sha256',current_rule_sha,
   'cited_evidence_sha256',cite_result->>'cited_evidence_sha256',
   'semantic_verdict','PERMITIR','promotion_authorized',false,
   'semantic_independence_credited',false);
END $verify$;

REVOKE ALL ON FUNCTION public.lf_rule_promotion_bind_ig_semantic_v1(text,bigint,text,bigint,uuid,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_ig_semantic_verify_v1(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_bind_ig_semantic_v1(text,bigint,text,bigint,uuid,text)
 TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_ig_semantic_verify_v1(text)
 TO service_role;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_governed_decide_v1(
 p_promotion_id text,p_decider_actor text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions','lf_ops'
AS $governed$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 judgement jsonb;
 semantic_gate jsonb;
 v_sha text;
 actor constant text:='LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1';
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1
  WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.status<>'PENDING' THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING'); END IF;
 IF p_decider_actor IS DISTINCT FROM actor
    OR p_decider_actor=p.requested_by_profile
    OR p_decider_actor=p.request_execution_id
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','DECIDER_NOT_SEPARATE_FROM_REQUESTER'); END IF;

 judgement:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);
 v_sha:=encode(extensions.digest(convert_to(judgement::text,'UTF8'),'sha256'),'hex');
 UPDATE public.lf_rule_promotion_v1 SET judge_receipt=judgement,
   judge_receipt_sha256=v_sha,decision_route=judgement->>'classification'
 WHERE promotion_id=p_promotion_id;

 IF judgement->>'classification'<>'AUTO_APPROVABLE' THEN
   RETURN jsonb_build_object(
    'status',CASE WHEN judgement->>'classification'='HUMAN_DECISION_REQUIRED'
                  THEN 'HUMAN_DECISION_REQUIRED' ELSE 'BLOCKED' END,
    'blocking_codes',judgement->'blocking_codes','judge_receipt_sha256',v_sha,
    'promotion_id',p_promotion_id,'independent_semantic_judge_attested',false);
 END IF;

 semantic_gate:=public.lf_rule_promotion_ig_semantic_verify_v1(p_promotion_id);
 IF semantic_gate->>'status' IS DISTINCT FROM 'VERIFIED_PASS' THEN
   RETURN jsonb_build_object(
     'status',CASE WHEN semantic_gate->>'status'='RETRY_REQUIRED'
                   THEN 'RETRY_REQUIRED' ELSE 'BLOCKED' END,
     'blocking_code',coalesce(semantic_gate->>'blocking_code','BLOCK_EXISTING_IG_SEMANTIC_UNVERIFIED'),
     'judge_receipt_sha256',v_sha,'semantic_gate',semantic_gate,
     'promotion_id',p_promotion_id,'independent_semantic_judge_attested',false);
 END IF;

 -- Reserved for a future existing-Validator contract that explicitly attests
 -- promotion authority. Current #3682 contract can never reach this branch.
 UPDATE public.lf_rule_promotion_v1
 SET status='APPROVED',decided_by=actor,decided_at=now()
 WHERE promotion_id=p_promotion_id AND status='PENDING';
 RETURN jsonb_build_object('status','APPROVED','promotion_id',p_promotion_id,
   'decided_by',actor,'judge_receipt_sha256',v_sha,
   'independent_semantic_judge_attested',false);
END $governed$;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $apply$
DECLARE p record; semantic_gate jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.status<>'APPROVED' THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); END IF;

 semantic_gate:=public.lf_rule_promotion_ig_semantic_verify_v1(p_promotion_id);
 IF semantic_gate->>'status' IS DISTINCT FROM 'VERIFIED_PASS' THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','PROMOTION_IG_SEMANTIC_RECEIPT_NOT_CURRENT',
     'semantic_gate',semantic_gate);
 END IF;

 IF p.decided_by IS DISTINCT FROM 'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1'
    OR p.decision_route IS DISTINCT FROM 'AUTO_APPROVABLE'
    OR p.judge_receipt IS NULL
    OR p.judge_receipt_sha256 IS DISTINCT FROM encode(
         extensions.digest(convert_to(p.judge_receipt::text,'UTF8'),'sha256'),'hex')
    OR p.judge_receipt IS DISTINCT FROM public.lf_rule_promotion_quality_judge_v1(p_promotion_id)
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_JUDGE_RECEIPT_NOT_CURRENT'); END IF;

 IF public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) IS DISTINCT FROM p.request_snapshot_sha256 THEN
   UPDATE public.lf_rule_promotion_v1 SET status='STALE' WHERE promotion_id=p_promotion_id;
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE');
 END IF;

 UPDATE lf_ops.reglas SET estado='VIGENTE' WHERE codigo=p.rule_code AND estado='CANDIDATO';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_RULE_ROW_NOT_CANDIDATE'); END IF;
 UPDATE public.lf_rule_promotion_v1 SET status='APPLIED',applied_at=now() WHERE promotion_id=p_promotion_id;
 RETURN jsonb_build_object('status','APPLIED','rule_code',p.rule_code);
END $apply$;

COMMIT;
