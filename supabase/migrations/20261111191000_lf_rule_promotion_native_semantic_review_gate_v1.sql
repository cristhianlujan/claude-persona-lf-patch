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
 ADD COLUMN ig_semantic_rule_snapshot_sha256 text;

CREATE UNIQUE INDEX lf_rule_promotion_one_ig_run_v1
 ON public.lf_rule_promotion_v1(ig_semantic_run_id)
 WHERE ig_semantic_run_id IS NOT NULL;

-- Thin adapter: binds one promotion to one existing IG run and consumes the
-- existing Validator packet + external semantic receipt readback.
-- It never fabricates a verdict and never upgrades IG authority.
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

 packet_sha:=coalesce(packet->>'db_packet_sha256',
   encode(extensions.digest(convert_to(packet::text,'UTF8'),'sha256'),'hex'));

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

 UPDATE public.lf_rule_promotion_v1
 SET ig_semantic_run_id=p_run_id,
     ig_semantic_validator_identity=p_validator_identity,
     ig_semantic_handoff_receipt_id=p_handoff_receipt_id,
     ig_semantic_candidate_sha256=coalesce(receipt->>'candidate_sha256',p_candidate_sha256),
     ig_semantic_packet_sha256=packet_sha,
     ig_semantic_external_receipt=receipt,
     ig_semantic_external_receipt_sha256=receipt_sha,
     ig_semantic_rule_snapshot_sha256=rule_sha
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
   'promotion_authorized',false,
   'independent_semantic_judge_attested',false);
END $bind$;

-- Verification is intentionally fail-closed. The current #3682 readback is
-- explicitly NOT promotable, so this adapter cannot manufacture an approval.
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
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.ig_semantic_run_id IS NULL OR p.ig_semantic_external_receipt IS NULL THEN
   RETURN jsonb_build_object('status','RETRY_REQUIRED','blocking_code','RETRY_EXISTING_IG_SEMANTIC_REVIEW_REQUIRED');
 END IF;

 current_rule_sha:=public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code);
 current_receipt_sha:=encode(extensions.digest(
   convert_to(p.ig_semantic_external_receipt::text,'UTF8'),'sha256'),'hex');

 IF current_rule_sha IS DISTINCT FROM p.request_snapshot_sha256
    OR current_rule_sha IS DISTINCT FROM p.ig_semantic_rule_snapshot_sha256
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_SEMANTIC_RULE_SNAPSHOT_DRIFT'); END IF;

 IF current_receipt_sha IS DISTINCT FROM p.ig_semantic_external_receipt_sha256
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_IG_SEMANTIC_RECEIPT_HASH_DRIFT'); END IF;

 IF p.ig_semantic_external_receipt->>'status' IN (
      'SEMANTIC_CANDIDATE_VERIFICATION_REQUIRED',
      'INDEPENDENT_SEMANTIC_VERDICT_REQUIRED')
 THEN RETURN jsonb_build_object('status','RETRY_REQUIRED',
      'blocking_code','RETRY_EXISTING_IG_SEMANTIC_EVIDENCE_INCOMPLETE',
      'external_receipt_status',p.ig_semantic_external_receipt->>'status'); END IF;

 IF p.ig_semantic_external_receipt->>'status'='SEMANTIC_AUDIT_RECEIPT_VERIFIED_NOT_PROMOTABLE' THEN
   IF p.ig_semantic_external_receipt->>'audit_verdict' IN ('FAIL','BLOCKED') THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','BLOCK_EXISTING_IG_SEMANTIC_AUDIT',
        'audit_verdict',p.ig_semantic_external_receipt->>'audit_verdict');
   END IF;
   RETURN jsonb_build_object('status','RETRY_REQUIRED',
      'blocking_code','RETRY_SEMANTIC_QUALITY_GATE_NOT_AUTHORIZED',
      'audit_verdict',p.ig_semantic_external_receipt->>'audit_verdict',
      'promotion_authorized',false,
      'semantic_independence_credited',
        coalesce((p.ig_semantic_external_receipt->>'semantic_independence_credited')::boolean,false));
 END IF;

 RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','BLOCK_EXISTING_IG_SEMANTIC_RECEIPT_STATUS_UNSUPPORTED');
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
