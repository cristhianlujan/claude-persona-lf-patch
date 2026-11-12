-- LF #3779 L7 CANDIDATE ONLY. Exact citations are untrusted text.
-- PG18 disposable rollback tests only; no IG/Router/new judge/model changes.
BEGIN;
DO $guard7$
BEGIN
 IF md5(pg_get_functiondef('public.lf_rule_promotion_blind_verdict_verify_v1(text)'::regprocedure))
     IS DISTINCT FROM '5dcdf7d9ebe4fc53cb80c80514f5c44f'
    OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
     IS DISTINCT FROM 'bc5d3b6b39e755915d61a99a9cb4926d'
 THEN RAISE EXCEPTION 'BLOCK_L7_UPSTREAM_SQL_MD5_DRIFT'; END IF;
END $guard7$;

-- L7 roles are NOLOGIN and have NO membership in service_role/IG.
-- Promotion caller is not the recording identity.
DO $roles$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lf_rule_citation_source_custodian') THEN
   CREATE ROLE lf_rule_citation_source_custodian NOLOGIN;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lf_rule_citation_step70_bridge') THEN
   CREATE ROLE lf_rule_citation_step70_bridge NOLOGIN;
 END IF;
END $roles$;

CREATE TABLE public.lf_rule_promotion_citation_source_v1(
 promotion_id text NOT NULL REFERENCES public.lf_rule_promotion_v1(promotion_id),
 case_id text NOT NULL UNIQUE CHECK(case_id ~ '^K[A-F0-9]{8,32}$'),
 rule_code text NOT NULL,
 base_rule jsonb NOT NULL,
 proposal jsonb NOT NULL,
 frozen_case_sha256 text NOT NULL CHECK(frozen_case_sha256 ~ '^[a-f0-9]{64}$'),
 rule_snapshot_sha256 text NOT NULL CHECK(rule_snapshot_sha256 ~ '^[a-f0-9]{64}$'),
 packet_sha256 text NOT NULL CHECK(packet_sha256 ~ '^[a-f0-9]{64}$'),
 ig_external_receipt_sha256 text NOT NULL CHECK(ig_external_receipt_sha256 ~ '^[a-f0-9]{64}$'),
 source_artifact_sha256 text NOT NULL CHECK(source_artifact_sha256 ~ '^[a-f0-9]{64}$'),
 source_artifact_ref text NOT NULL CHECK(length(source_artifact_ref)>=12),
 PRIMARY KEY(promotion_id,case_id)
);
CREATE TABLE public.lf_rule_promotion_citation_capture_v1(
 promotion_id text NOT NULL,
 case_id text NOT NULL,
 verdict text NOT NULL CHECK(verdict IN ('ALLOW','BLOCK')),
 capture_line text NOT NULL,
 literal_excerpt text NOT NULL,
 literal_origin text NOT NULL CHECK(literal_origin IN ('BASE_RULE','PROPOSAL')),
 quote_sha256 text NOT NULL UNIQUE CHECK(quote_sha256 ~ '^[a-f0-9]{64}$'),
 capture_line_sha256 text NOT NULL CHECK(capture_line_sha256 ~ '^[a-f0-9]{64}$'),
 frozen_case_sha256 text NOT NULL CHECK(frozen_case_sha256 ~ '^[a-f0-9]{64}$'),
 capture_binding_sha256 text NOT NULL CHECK(capture_binding_sha256 ~ '^[a-f0-9]{64}$'),
 capture_run_id text NOT NULL,
 step70_evidence_ref text NOT NULL,
 source_provenance text NOT NULL,
 PRIMARY KEY(promotion_id,case_id),
 FOREIGN KEY(promotion_id,case_id) REFERENCES public.lf_rule_promotion_citation_source_v1(promotion_id,case_id)
);
CREATE FUNCTION public.lf_rule_citation_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public' AS $immut$
BEGIN RAISE EXCEPTION 'BLOCK_L7_CITATION_IMMUTABLE_NO_UPDATE_DELETE'; END $immut$;
CREATE TRIGGER trg_l7_source_immut BEFORE UPDATE OR DELETE ON public.lf_rule_promotion_citation_source_v1
 FOR EACH ROW EXECUTE FUNCTION public.lf_rule_citation_immutable_v1();
CREATE TRIGGER trg_l7_capture_immut BEFORE UPDATE OR DELETE ON public.lf_rule_promotion_citation_capture_v1
 FOR EACH ROW EXECUTE FUNCTION public.lf_rule_citation_immutable_v1();
REVOKE ALL ON public.lf_rule_promotion_citation_source_v1,
 public.lf_rule_promotion_citation_capture_v1
 FROM PUBLIC,anon,authenticated,service_role,lf_rule_citation_source_custodian,lf_rule_citation_step70_bridge;
REVOKE ALL ON FUNCTION public.lf_rule_citation_immutable_v1() FROM PUBLIC,anon,authenticated,service_role;

-- Immutable source publication, only by governed source custodian.
-- Source hash binds the FULL original base rule + proposal, not a mutable quote.
CREATE FUNCTION public.lf_rule_promotion_citation_source_publish_v1(
 p_promotion_id text,p_case_id text,p_base_rule jsonb,p_proposal jsonb,
 p_artifact_sha256 text,p_artifact_ref text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $publish$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE; v_sha text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND OR p.status<>'PENDING' THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','L7_PROMOTION_NOT_PENDING'); END IF;
 IF p_case_id !~ '^K[A-F0-9]{8,32}$'
    OR jsonb_typeof(p_base_rule)<>'object'
    OR jsonb_typeof(p_proposal)<>'object'
    OR p_base_rule->>'code' IS DISTINCT FROM p.rule_code
    OR p_proposal->>'rule_code' IS DISTINCT FROM p.rule_code
    OR nullif(btrim(p_base_rule->>'description'),'') IS NULL
    OR nullif(btrim(p_proposal->>'description'),'') IS NULL
    OR p_artifact_sha256 !~ '^[a-f0-9]{64}$'
    OR length(coalesce(p_artifact_ref,''))<12
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','L7_SOURCE_OR_RULE_MISMATCH'); END IF;
 IF public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) IS DISTINCT FROM p.request_snapshot_sha256
    OR p.ig_semantic_packet_sha256 IS NULL
    OR p.ig_semantic_external_receipt_sha256 IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','L7_SOURCE_CURRENTNESS_NOT_READY'); END IF;
 v_sha:=encode(extensions.digest(convert_to(
   jsonb_build_object('case_id',p_case_id,'base_rule',p_base_rule,'proposal',p_proposal)::text,'UTF8'),'sha256'),'hex');
 BEGIN
  INSERT INTO public.lf_rule_promotion_citation_source_v1(
   promotion_id,case_id,rule_code,base_rule,proposal,frozen_case_sha256,
   rule_snapshot_sha256,packet_sha256,ig_external_receipt_sha256,source_artifact_sha256,source_artifact_ref)
  VALUES(p_promotion_id,p_case_id,p.rule_code,p_base_rule,p_proposal,v_sha,
   p.request_snapshot_sha256,p.ig_semantic_packet_sha256,p.ig_semantic_external_receipt_sha256,
   p_artifact_sha256,p_artifact_ref);
 EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','L7_SOURCE_CASE_ALREADY_BOUND'); END;
 RETURN jsonb_build_object('status','SOURCE_FROZEN','case_id',p_case_id,
   'case_sha256',v_sha,'source_artifact_sha256',p_artifact_sha256);
END $publish$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_citation_source_publish_v1(text,text,jsonb,jsonb,text,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_citation_source_publish_v1(text,text,jsonb,jsonb,text,text)
 TO lf_rule_citation_source_custodian;

-- Pure structural check: exact one-line ID|VERDICT|LITERAL.
-- >=40 Unicode characters AND >=6 whitespace-delimited words.
CREATE FUNCTION public.lf_rule_promotion_citation_line_check_v1(
 p_promotion_id text,p_line text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $check$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE;
 s public.lf_rule_promotion_citation_source_v1%ROWTYPE;
 v_id text; v_verdict text; v_quote text; v_origin text; v_case_sha text;
 v_count integer;
BEGIN
 IF p_line IS NULL OR length(p_line)>1400
    OR position(E'\n' IN p_line)>0 OR position(E'\r' IN p_line)>0
    OR length(p_line)-length(replace(p_line,'|',''))<>2 THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_LINE_FORMAT_INVALID'); END IF;
 v_id:=split_part(p_line,'|',1);
 v_verdict:=split_part(p_line,'|',2);
 v_quote:=split_part(p_line,'|',3);
 IF v_id !~ '^K[A-F0-9]{8,32}$' OR v_verdict NOT IN ('ALLOW','BLOCK') THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_ID_OR_VERDICT_INVALID'); END IF;
 IF length(v_quote)<40 OR btrim(v_quote)<>v_quote
    OR cardinality(regexp_split_to_array(v_quote,E'\\s+'))<6 THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_QUOTE_EMPTY_OR_TRIVIAL'); END IF;
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 SELECT * INTO s FROM public.lf_rule_promotion_citation_source_v1
  WHERE promotion_id=p_promotion_id AND case_id=v_id;
 IF NOT FOUND OR p.promotion_id IS NULL THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_CASE_NOT_FROZEN'); END IF;
 IF s.rule_code IS DISTINCT FROM p.rule_code
    OR s.base_rule->>'code' IS DISTINCT FROM p.rule_code
    OR s.proposal->>'rule_code' IS DISTINCT FROM p.rule_code THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_QUOTE_OTHER_RULE'); END IF;
 v_case_sha:=encode(extensions.digest(convert_to(
    jsonb_build_object('case_id',v_id,'base_rule',s.base_rule,'proposal',s.proposal)::text,'UTF8'),'sha256'),'hex');
 IF v_case_sha IS DISTINCT FROM s.frozen_case_sha256
    OR s.rule_snapshot_sha256 IS DISTINCT FROM p.request_snapshot_sha256
    OR s.packet_sha256 IS DISTINCT FROM p.ig_semantic_packet_sha256
    OR s.ig_external_receipt_sha256 IS DISTINCT FROM p.ig_semantic_external_receipt_sha256
    OR public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) IS DISTINCT FROM s.rule_snapshot_sha256 THEN
  RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_CASE_SNAPSHOT_OR_RECEIPT_DRIFT'); END IF;
 IF position(v_quote IN s.base_rule->>'description')>0 THEN v_origin:='BASE_RULE';
 ELSIF position(v_quote IN s.proposal->>'description')>0 THEN v_origin:='PROPOSAL';
 ELSE RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_QUOTE_NOT_LITERAL_IN_FROZEN_TEXT'); END IF;
 RETURN jsonb_build_object('status','LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE',
    'case_id',v_id,'verdict',v_verdict,'exact_excerpt',v_quote,
    'literal_origin',v_origin,'case_sha256',v_case_sha,
    'quote_sha256',encode(extensions.digest(convert_to(v_quote,'UTF8'),'sha256'),'hex'),
    'capture_line_sha256',encode(extensions.digest(convert_to(p_line,'UTF8'),'sha256'),'hex'),
    'source_snapshot_sha256',s.rule_snapshot_sha256,
    'packet_sha256',s.packet_sha256,
    'ig_external_receipt_sha256',s.ig_external_receipt_sha256);
END $check$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_citation_line_check_v1(text,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_citation_line_check_v1(text,text)
 TO lf_rule_citation_step70_bridge;

-- Only existing recorder with separate NOLOGIN credential may record;
-- the raw line MUST already exist verbatim inside the trusted same-RUN Step70.
CREATE FUNCTION public.lf_rule_promotion_citation_record_v1(
 p_promotion_id text,p_line text,p_capture_execution_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $record$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE;
 x jsonb; s public.lf_rule_promotion_citation_source_v1%ROWTYPE;
 e public.lf_operation_execution%ROWTYPE;
 st public.lf_operation_execution_steps%ROWTYPE;
 v_binding jsonb; v_sha text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND OR p.status<>'PENDING' THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','L7_PROMOTION_NOT_PENDING'); END IF;
 x:=public.lf_rule_promotion_citation_line_check_v1(p_promotion_id,p_line);
 IF x->>'status'<>'LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE' THEN RETURN x; END IF;
 SELECT * INTO s FROM public.lf_rule_promotion_citation_source_v1
    WHERE promotion_id=p_promotion_id AND case_id=x->>'case_id';
 SELECT * INTO e FROM public.lf_operation_execution
    WHERE execution_id=p_capture_execution_id AND operation_code='EJECUCION_PERFIL_LF'
       AND target_code=p.requested_by_profile AND execution_id=p.request_execution_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_CAPTURE_RUN_AUTHORITY_MISMATCH'); END IF;
 SELECT * INTO st FROM public.lf_operation_execution_steps
    WHERE execution_id=e.execution_id AND step_id='semantic_judge'
      AND status='STEP_PASS_WITH_EVIDENCE';
 IF NOT FOUND OR nullif(st.evidence_ref,'') IS NULL
    OR st.created_by_execution_id IS DISTINCT FROM e.execution_id
    OR st.evidence_payload->>'test_only_synthetic'='true'
    OR st.evidence_payload#>>'{semantic_judge_result,test_only_synthetic}'='true'
    OR st.evidence_payload->>'rule_promotion_citation_line' IS DISTINCT FROM p_line
    OR st.evidence_payload->>'rule_promotion_citation_case_id' IS DISTINCT FROM x->>'case_id'
    OR st.evidence_payload->>'rule_promotion_citation_source_sha256' IS DISTINCT FROM s.frozen_case_sha256
    OR st.evidence_payload->>'rule_promotion_citation_ig_receipt_sha256'
        IS DISTINCT FROM p.ig_semantic_external_receipt_sha256
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_STEP70_VERBATIM_CAPTURE_NOT_ATTESTED'); END IF;
 IF p.ig_semantic_external_receipt->'l5_blind_case_verdict'->>'id' IS DISTINCT FROM x->>'case_id'
    OR p.ig_semantic_external_receipt->'l5_blind_case_verdict'->>'verdict' IS DISTINCT FROM x->>'verdict'
    OR p.ig_semantic_external_receipt->'l5_blind_case_verdict'->>'exact_excerpt' IS DISTINCT FROM x->>'exact_excerpt'
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_IG_RECEIPT_DISAGREES_WITH_CAPTURE'); END IF;
 v_binding:=jsonb_build_object('promotion_id',p_promotion_id,'rule_code',p.rule_code,
    'case_id',x->>'case_id','verdict',x->>'verdict',
    'line_sha256',x->>'capture_line_sha256','quote_sha256',x->>'quote_sha256',
    'case_sha256',s.frozen_case_sha256,
    'rule_snapshot_sha256',p.request_snapshot_sha256,
    'packet_sha256',p.ig_semantic_packet_sha256,
    'ig_receipt_sha256',p.ig_semantic_external_receipt_sha256,
    'ig_binding_sha256',p.ig_semantic_binding_sha256,
    'capture_execution_id',e.execution_id,'step70_evidence_ref',st.evidence_ref);
 v_sha:=encode(extensions.digest(convert_to(v_binding::text,'UTF8'),'sha256'),'hex');
 BEGIN
  INSERT INTO public.lf_rule_promotion_citation_capture_v1(
      promotion_id,case_id,verdict,capture_line,literal_excerpt,literal_origin,
      quote_sha256,capture_line_sha256,frozen_case_sha256,capture_binding_sha256,
      capture_run_id,step70_evidence_ref,source_provenance)
  VALUES(p_promotion_id,x->>'case_id',x->>'verdict',p_line,x->>'exact_excerpt',
      x->>'literal_origin',x->>'quote_sha256',x->>'capture_line_sha256',
      s.frozen_case_sha256,v_sha,e.execution_id,st.evidence_ref,
      coalesce(st.evidence_payload->>'rule_promotion_citation_provenance','UNVERIFIED_NOT_CAPTURED'));
 EXCEPTION WHEN unique_violation THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_QUOTE_OR_CASE_REUSED'); END;
 RETURN jsonb_build_object('status','CAPTURED_FOR_GATE_VERIFICATION','case_id',x->>'case_id',
    'verdict',x->>'verdict','capture_binding_sha256',v_sha,
    'source_provenance',coalesce(st.evidence_payload->>'rule_promotion_citation_provenance','UNVERIFIED_NOT_CAPTURED'));
END $record$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_citation_record_v1(text,text,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_citation_record_v1(text,text,text)
 TO lf_rule_citation_step70_bridge;

-- Gate verify is read-only and re-run at decide + apply. No caller line input.
CREATE FUNCTION public.lf_rule_promotion_citation_verify_v1(p_promotion_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $verify7$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE;
 x public.lf_rule_promotion_citation_capture_v1%ROWTYPE;
 s public.lf_rule_promotion_citation_source_v1%ROWTYPE;
 v jsonb; v_binding jsonb; v_sha text; st public.lf_operation_execution_steps%ROWTYPE;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 SELECT * INTO x FROM public.lf_rule_promotion_citation_capture_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND OR p.promotion_id IS NULL THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_CITATION_MISSING_NO_AUTO_PROMOTION'); END IF;
 SELECT * INTO s FROM public.lf_rule_promotion_citation_source_v1
  WHERE promotion_id=p_promotion_id AND case_id=x.case_id;
 v:=public.lf_rule_promotion_citation_line_check_v1(p_promotion_id,x.capture_line);
 IF v->>'status'<>'LITERAL_STRUCTURE_VERIFIED_FOR_CAPTURE'
    OR x.case_id IS DISTINCT FROM v->>'case_id'
    OR x.verdict IS DISTINCT FROM v->>'verdict'
    OR x.literal_excerpt IS DISTINCT FROM v->>'exact_excerpt'
    OR x.literal_origin IS DISTINCT FROM v->>'literal_origin'
    OR x.quote_sha256 IS DISTINCT FROM v->>'quote_sha256'
    OR x.capture_line_sha256 IS DISTINCT FROM v->>'capture_line_sha256'
    OR x.frozen_case_sha256 IS DISTINCT FROM s.frozen_case_sha256 THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_CAPTURE_CONTENT_OR_SOURCE_DRIFT','line_gate',v); END IF;
 SELECT * INTO st FROM public.lf_operation_execution_steps
    WHERE execution_id=x.capture_run_id AND step_id='semantic_judge'
      AND status='STEP_PASS_WITH_EVIDENCE';
 IF NOT FOUND OR st.evidence_ref IS DISTINCT FROM x.step70_evidence_ref
    OR st.created_by_execution_id IS DISTINCT FROM x.capture_run_id
    OR st.evidence_payload->>'rule_promotion_citation_line' IS DISTINCT FROM x.capture_line
    OR st.evidence_payload->>'rule_promotion_citation_source_sha256' IS DISTINCT FROM s.frozen_case_sha256
    OR st.evidence_payload->>'rule_promotion_citation_ig_receipt_sha256'
      IS DISTINCT FROM p.ig_semantic_external_receipt_sha256
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
      'blocking_code','L7_STEP70_READBACK_OR_HASH_DRIFT'); END IF;
 IF p.ig_semantic_external_receipt->'l5_blind_case_verdict'->>'id' IS DISTINCT FROM x.case_id
    OR p.ig_semantic_external_receipt->'l5_blind_case_verdict'->>'verdict' IS DISTINCT FROM x.verdict
    OR p.ig_semantic_external_receipt->'l5_blind_case_verdict'->>'exact_excerpt' IS DISTINCT FROM x.literal_excerpt
 THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_NATIVE_IG_RECEIPT_BINDING_DRIFT'); END IF;
 v_binding:=jsonb_build_object('promotion_id',p_promotion_id,'rule_code',p.rule_code,
    'case_id',x.case_id,'verdict',x.verdict,
    'line_sha256',x.capture_line_sha256,'quote_sha256',x.quote_sha256,
    'case_sha256',s.frozen_case_sha256,
    'rule_snapshot_sha256',p.request_snapshot_sha256,
    'packet_sha256',p.ig_semantic_packet_sha256,
    'ig_receipt_sha256',p.ig_semantic_external_receipt_sha256,
    'ig_binding_sha256',p.ig_semantic_binding_sha256,
    'capture_execution_id',x.capture_run_id,'step70_evidence_ref',x.step70_evidence_ref);
 v_sha:=encode(extensions.digest(convert_to(v_binding::text,'UTF8'),'sha256'),'hex');
 IF v_sha IS DISTINCT FROM x.capture_binding_sha256 THEN
  RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_CAPTURE_SHA256_TAMPER'); END IF;
 IF x.verdict='BLOCK' THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code','L7_BLOCK_QUOTE_VERIFIED_NO_PROMOTION',
    'case_id',x.case_id,'binding_sha256',v_sha,'promotable',false); END IF;
 IF x.source_provenance IN ('UNVERIFIED_NOT_FROM_REAL_REVIEW','UNVERIFIED_NOT_CAPTURED') THEN
   RETURN jsonb_build_object('status','PROFILE_OWNER_REVIEW_ONLY',
      'blocking_code','L7_CAPTURED_QUOTE_NOT_REAL_REVIEW_ATTESTED',
      'case_id',x.case_id,'verdict',x.verdict,'promotable',false,
      'next_actor','PROFILE_OWNER','binding_sha256',v_sha); END IF;
 IF x.source_provenance IS DISTINCT FROM 'OFFICIAL_STEP70_VERIFIED_NATIVE_IG' THEN
  RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED','blocking_code','L7_SOURCE_PROVENANCE_UNTRUSTED'); END IF;
 IF x.verdict='BLOCK' THEN RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
    'blocking_code','L7_BLOCK_QUOTE_VERIFIED_NO_PROMOTION',
    'case_id',x.case_id,'binding_sha256',v_sha,'promotable',false); END IF;
 RETURN jsonb_build_object('status','VERIFIED_CAPTURE_BINDING','case_id',x.case_id,
    'verdict','ALLOW','literal_origin',x.literal_origin,
    'binding_sha256',v_sha,'promotable',false,
    'next_actor','PROFILE_OWNER','independence_attested',false);
END $verify7$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_citation_verify_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_citation_verify_v1(text) TO service_role;

-- Old L5 checks are preserved, plus REQUIRED L7 pin: no quote, no promotion.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_blind_verdict_verify_v1(
 p_promotion_id text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $real_verify$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE;
 c jsonb; r lf_ops.reglas%ROWTYPE; actual_sha text;
 v_case_sha text; v_binding_sha text; v_expected_bind jsonb; l7 jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.ig_semantic_external_receipt IS NULL OR p.ig_semantic_run_id IS NULL THEN
   RETURN jsonb_build_object('status','RETRY_REQUIRED','blocking_code','L5_IG_RECEIPT_REQUIRED'); END IF;
 IF p.ig_semantic_external_receipt_sha256 IS DISTINCT FROM
  encode(extensions.digest(convert_to(p.ig_semantic_external_receipt::text,'UTF8'),'sha256'),'hex') THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
      'blocking_code','L5_EXTERNAL_RECEIPT_SHA_DRIFT'); END IF;
 l7:=public.lf_rule_promotion_citation_verify_v1(p_promotion_id);
 IF l7->>'status' IS DISTINCT FROM 'VERIFIED_CAPTURE_BINDING' THEN
   RETURN jsonb_build_object('status','HUMAN_DECISION_REQUIRED',
      'blocking_code','L7_EXACT_CITATION_CAPTURE_NOT_VERIFIED',
      'citation_gate',l7); END IF;
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
 THEN
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
   'case_binding_sha256',v_binding_sha,
   'exact_citation_capture_binding_sha256',l7->>'binding_sha256',
   'independence_attested',false);
END $real_verify$;
-- L7 fail-closed apply guard: always re-read original capture, source and Step70.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $apply$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE; gate jsonb; owner_gate jsonb;
   real_gate jsonb; rb jsonb; v_expected text; v_after text; v_error text; l7 jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 -- L7 citation hash/Step70/source currentness before any status gate or write.
 l7:=public.lf_rule_promotion_citation_verify_v1(p_promotion_id);
 IF l7->>'status' IS DISTINCT FROM 'VERIFIED_CAPTURE_BINDING' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','L7_EXACT_CITATION_NOT_CURRENT',
     'citation_gate',l7,'apply_authorized',false); END IF;
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
COMMIT;
