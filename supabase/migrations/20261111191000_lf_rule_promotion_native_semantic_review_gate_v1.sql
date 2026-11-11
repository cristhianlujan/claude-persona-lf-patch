-- LF #3779 Lote4. NO deploy, source-first isolated PG18 candidate.
-- Reuse the parent Step70 native review, NOT a new LLM/IG/Router.
BEGIN;
DO $guard$
BEGIN
 IF md5(pg_get_functiondef(
   'public.lf_rule_promotion_governed_decide_v1(text,text)'::regprocedure))
    IS DISTINCT FROM '451864b7f9a49d9dc64b2780a4556774'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
    IS DISTINCT FROM '83660185fd06fa3905864fdb73f178e2'
 THEN RAISE EXCEPTION 'BLOCK_RULE_NATIVE_SEMANTIC_GATE_UPSTREAM_MD5_DRIFT'; END IF;
END $guard$;
ALTER TABLE public.lf_rule_promotion_v1
 ADD COLUMN semantic_receipt jsonb,
 ADD COLUMN semantic_receipt_sha256 text,
 ADD COLUMN semantic_reviewer_execution_id text;


-- Packet for native GPT review; all source text is UNTRUSTED DATA.
-- No second LLM/IG. Any reviewer must cite actual compared source.
CREATE FUNCTION public.lf_rule_promotion_semantic_packet_v1(p_promotion_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $packet$
DECLARE
 p record;r record;d jsonb;v_payload jsonb;v_sha text;
 v_candidates jsonb;v_global_catalog jsonb;v_count integer;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 SELECT * INTO r FROM lf_ops.reglas WHERE codigo=p.rule_code;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_FOUND'); END IF;
 d:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);
 -- Include the complete VIGENTE catalogue (titles/descriptions) and
 -- full same-category config. No silent top-N truncation.
 SELECT count(*) INTO v_count FROM lf_ops.reglas x
 WHERE x.codigo<>r.codigo AND x.estado='VIGENTE' AND x.categoria=r.categoria;
 SELECT coalesce(jsonb_agg(jsonb_build_object('codigo',q.codigo,'titulo',q.titulo,
       'descripcion',q.descripcion,'estado',q.estado,'valor_config',q.valor_config,
       'source_sha256',public.lf_asset_snapshot_sha_v1('REGLA',q.codigo))
       ORDER BY q.codigo),'[]'::jsonb) INTO v_candidates
 FROM (SELECT x.codigo,x.titulo,x.descripcion,x.estado,x.valor_config
       FROM lf_ops.reglas x
       WHERE x.codigo<>r.codigo AND x.estado='VIGENTE' AND x.categoria=r.categoria
       ORDER BY x.codigo) q;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
       'codigo',g.codigo,'categoria',g.categoria,'titulo',g.titulo,
       'descripcion',g.descripcion,'estado',g.estado,
       'source_sha256',public.lf_asset_snapshot_sha_v1('REGLA',g.codigo))
       ORDER BY g.codigo),'[]'::jsonb) INTO v_global_catalog
 FROM lf_ops.reglas g WHERE g.codigo<>r.codigo AND g.estado='VIGENTE';
 v_payload:=jsonb_build_object(
   'schema_version','LF_RULE_PROMOTION_NATIVE_SEMANTIC_PACKET_V1',
   'promotion_id',p.promotion_id,
   'request_execution_id',p.request_execution_id,
   'candidate_code',r.codigo,
   'candidate_source_sha256',public.lf_asset_snapshot_sha_v1('REGLA',r.codigo),
   'request_snapshot_sha256',p.request_snapshot_sha256,
   'candidate_rule',jsonb_build_object('codigo',r.codigo,'titulo',r.titulo,
      'descripcion',r.descripcion,'categoria',r.categoria,'valor_config',r.valor_config),
   'deterministic_classification',d->>'classification',
   'deterministic_blocking_codes',d->'blocking_codes',
   'source_decision_sha256',d->>'source_decision_sha256',
   'security_policy_sha256',d->>'security_policy_set_sha256',
   'dependency_sha256',d->>'dependency_sha256',
   'vigente_security_policies',coalesce((
      SELECT jsonb_agg(jsonb_build_object('code',s.policy_code,
              'status',s.status,'config',s.policy_config) ORDER BY s.policy_code)
      FROM lf_ops.politicas_seguridad s WHERE s.status='VIGENTE'),'[]'::jsonb),
   'same_category_rules',v_candidates,
   'same_category_total_count',v_count,
   'same_category_coverage_complete',true,
   'global_vigente_catalog',v_global_catalog,
   'global_catalog_coverage_complete',true,
   'requester_profile',p.requested_by_profile,
   'input_is_untrusted_data',true,
   'ground_truth_label_in_packet',false,
   'model_invocation_receipt_present',false);
 v_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
 RETURN jsonb_build_object('status','READY','packet',v_payload,
   'packet_sha256',v_sha,'review_required',true,
   'review_mode','NOT_EXECUTED');
END $packet$;

REVOKE ALL ON FUNCTION public.lf_rule_promotion_semantic_packet_v1(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_semantic_packet_v1(text) TO service_role;

-- Only reads a Step70 result previously recorded by the EXISTING official
-- native bridge, in a distinct reviewer RUN. No caller-supplied verdict JSON.
CREATE FUNCTION public.lf_rule_promotion_semantic_record_v1(
 p_promotion_id text,p_review_execution_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $record$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 reviewer public.lf_operation_execution%ROWTYPE;
 st public.lf_operation_execution_steps%ROWTYPE;
 packet jsonb;v_review jsonb;v_hash text;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1
   WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND OR p.status<>'PENDING' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING'); END IF;
 IF p_review_execution_id IS NULL OR p_review_execution_id=p.request_execution_id THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','REVIEWER_MUST_BE_DISTINCT_RUN'); END IF;
 SELECT * INTO reviewer FROM public.lf_operation_execution
  WHERE execution_id=p_review_execution_id
    AND operation_code='EJECUCION_PERFIL_LF'
    AND status='COMPLETED';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','REVIEWER_GOVERNED_RUN_NOT_FOUND'); END IF;
 IF reviewer.manifest#>>'{semantic_review,subject_promotion_id}' IS DISTINCT FROM p_promotion_id
    OR reviewer.manifest#>>'{semantic_review,review_mode}' IS DISTINCT FROM 'SEPARATE_NATIVE_CONTEXT'
    OR reviewer.manifest->>'executor_mode' IS DISTINCT FROM 'GPT_NATIVE'
    OR reviewer.manifest->>'executor_provider' IS DISTINCT FROM 'OPENAI_CHATGPT_NATIVE'
    OR reviewer.manifest->>'read_only' IS DISTINCT FROM 'true'
    OR reviewer.manifest->>'no_write' IS DISTINCT FROM 'true'
    OR reviewer.manifest->>'no_promotion' IS DISTINCT FROM 'true'
    OR reviewer.manifest ? 'queue_request_id'
    OR nullif(reviewer.manifest->>'runtime_target','') IS NOT NULL
    OR reviewer.target_code=p.requested_by_profile
 THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','REVIEWER_ROLE_OR_SCOPE_NOT_ATTESTED'); END IF;
 SELECT * INTO st FROM public.lf_operation_execution_steps
  WHERE execution_id=p_review_execution_id AND step_id='semantic_judge'
    AND status='STEP_PASS_WITH_EVIDENCE';
 IF NOT FOUND OR nullif(st.evidence_ref,'') IS NULL
    OR nullif(st.created_by_execution_id,'') IS NULL
    OR st.evidence_payload->>'test_only_synthetic'='true'
    OR st.evidence_payload#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
    OR st.evidence_payload#>>'{semantic_judge_result,validator_status}' IS DISTINCT FROM 'PASS'
    OR NOT (
      (st.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
       AND st.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
       AND st.evidence_payload#>>'{semantic_judge_result,reviewer_is_producer}'='true'
       AND st.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='false'
       AND st.evidence_payload#>>'{semantic_judge_result,model_call_count}'='0')
      OR
      (st.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
       AND st.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='true'
       AND st.evidence_payload#>>'{semantic_judge_result,model_call_count}'='1')
    )
    OR st.evidence_payload#>'{semantic_judge_result,result,blocking_codes}' IS DISTINCT FROM '[]'::jsonb
    OR st.evidence_payload#>'{semantic_judge_result,result,unsupported_claims}' IS DISTINCT FROM '[]'::jsonb
 THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','REVIEWER_STEP70_RECEIPT_NOT_ATTESTED'); END IF;
 v_review:=st.evidence_payload#>'{semantic_judge_result,result,promotion_semantic_review}';
 packet:=public.lf_rule_promotion_semantic_packet_v1(p_promotion_id);
 IF v_review IS NULL OR v_review->>'schema_version' IS DISTINCT FROM 'LF_RULE_PROMOTION_NATIVE_SEMANTIC_REVIEW_V1'
    OR v_review->>'reviewer_execution_id' IS DISTINCT FROM p_review_execution_id
    OR v_review->>'promotion_id' IS DISTINCT FROM p_promotion_id
    OR v_review->>'request_execution_id' IS DISTINCT FROM p.request_execution_id
    OR v_review->>'review_mode' IS DISTINCT FROM 'SEPARATE_NATIVE_CONTEXT'
    OR v_review->>'packet_sha256' IS DISTINCT FROM packet->>'packet_sha256'
    OR v_review->>'candidate_source_sha256' IS DISTINCT FROM
          packet#>>'{packet,candidate_source_sha256}'
    OR v_review->>'security_policy_sha256' IS DISTINCT FROM
          packet#>>'{packet,security_policy_sha256}'
    OR v_review->>'dependency_sha256' IS DISTINCT FROM
          packet#>>'{packet,dependency_sha256}'
    OR v_review->>'verdict' NOT IN ('PASS','BLOCK','INCONCLUSIVE')
    OR jsonb_typeof(v_review->'cited_evidence') IS DISTINCT FROM 'array'
    OR jsonb_array_length(coalesce(v_review->'cited_evidence','[]'::jsonb))<1
    OR packet#>>'{packet,same_category_coverage_complete}' IS DISTINCT FROM 'true'
    OR EXISTS(
       SELECT 1 FROM jsonb_array_elements(coalesce(v_review->'cited_evidence','[]'::jsonb)) cite(item)
       WHERE jsonb_typeof(cite.item)<>'object'
         OR nullif(btrim(coalesce(cite.item->>'exact_excerpt','')),'') IS NULL
         OR nullif(btrim(coalesce(cite.item->>'implication','')),'') IS NULL
         OR nullif(btrim(coalesce(cite.item->>'claim_type','')),'') IS NULL
         OR NOT (
            EXISTS(
              SELECT 1 FROM lf_ops.reglas rr
              WHERE rr.codigo=cite.item->>'source_code'
                AND public.lf_asset_snapshot_sha_v1('REGLA',rr.codigo)=
                   cite.item->>'source_sha256'
                AND position(cite.item->>'exact_excerpt' IN rr.descripcion)>0
            )
            OR EXISTS(
              SELECT 1 FROM lf_ops.politicas_seguridad pp
              WHERE pp.policy_code=cite.item->>'source_code'
                AND pp.status='VIGENTE'
                AND cite.item->>'source_sha256'=
                    packet#>>'{packet,security_policy_sha256}'
                AND position(cite.item->>'exact_excerpt' IN pp.policy_config::text)>0
            )
         )
    )
    OR v_review->'unsupported_claims' IS DISTINCT FROM '[]'::jsonb
 THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','SEMANTIC_REVIEW_SOURCE_PACKET_MISMATCH'); END IF;
 v_hash:=encode(extensions.digest(convert_to(v_review::text,'UTF8'),'sha256'),'hex');
 UPDATE public.lf_rule_promotion_v1 SET semantic_receipt=v_review,
   semantic_receipt_sha256=v_hash,semantic_reviewer_execution_id=p_review_execution_id
 WHERE promotion_id=p_promotion_id;
 RETURN jsonb_build_object('status','RECORDED','semantic_receipt_sha256',v_hash,
   'review_mode','SEPARATE_NATIVE_CONTEXT',
   'independent_semantic_judge_attested',false);
END $record$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_semantic_record_v1(text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_semantic_record_v1(text,text) TO service_role;

CREATE FUNCTION public.lf_rule_promotion_semantic_verify_v1(p_promotion_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $verify$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 reviewer public.lf_operation_execution%ROWTYPE;
 st public.lf_operation_execution_steps%ROWTYPE;
 packet jsonb;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND OR p.semantic_receipt IS NULL
 THEN RETURN jsonb_build_object('status','RETRY_REQUIRED',
 'blocking_code','RETRY_SEMANTIC_REVIEW_REQUIRED'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge k
    WHERE k.codigo='PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001'
      AND k.estado IN ('RESOLVED','VALIDATED_TESTED'))
 THEN RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code','BLOCK_SEMANTIC_JUDGE_ENFORCEMENT_NOT_RESOLVED'); END IF;
 SELECT * INTO reviewer FROM public.lf_operation_execution
  WHERE execution_id=p.semantic_reviewer_execution_id
    AND operation_code='EJECUCION_PERFIL_LF' AND status='COMPLETED'
    AND execution_id<>p.request_execution_id;
 IF NOT FOUND OR reviewer.manifest->>'executor_mode' IS DISTINCT FROM 'GPT_NATIVE'
    OR reviewer.manifest->>'executor_provider' IS DISTINCT FROM 'OPENAI_CHATGPT_NATIVE'
    OR reviewer.manifest->>'read_only' IS DISTINCT FROM 'true'
    OR reviewer.manifest->>'no_write' IS DISTINCT FROM 'true'
    OR reviewer.manifest->>'no_promotion' IS DISTINCT FROM 'true'
    OR reviewer.manifest ? 'queue_request_id'
    OR nullif(reviewer.manifest->>'runtime_target','') IS NOT NULL
    OR reviewer.target_code=p.requested_by_profile
    OR reviewer.manifest#>>'{semantic_review,subject_promotion_id}' IS DISTINCT FROM p.promotion_id
 THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','BLOCK_SEMANTIC_REVIEWER_NOT_DISTINCT'); END IF;
 SELECT * INTO st FROM public.lf_operation_execution_steps
  WHERE execution_id=reviewer.execution_id AND step_id='semantic_judge'
   AND status='STEP_PASS_WITH_EVIDENCE';
 IF NOT FOUND OR nullif(st.evidence_ref,'') IS NULL
  OR nullif(st.created_by_execution_id,'') IS NULL
  OR st.evidence_payload->>'test_only_synthetic'='true'
  OR st.evidence_payload#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
  OR st.evidence_payload#>>'{semantic_judge_result,validator_status}' IS DISTINCT FROM 'PASS'
  OR NOT (
     (st.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
      AND st.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
      AND st.evidence_payload#>>'{semantic_judge_result,reviewer_is_producer}'='true'
      AND st.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='false'
      AND st.evidence_payload#>>'{semantic_judge_result,model_call_count}'='0')
     OR
     (st.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
      AND st.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='true'
      AND st.evidence_payload#>>'{semantic_judge_result,model_call_count}'='1')
  )
  OR st.evidence_payload#>'{semantic_judge_result,result,blocking_codes}' IS DISTINCT FROM '[]'::jsonb
  OR st.evidence_payload#>'{semantic_judge_result,result,unsupported_claims}' IS DISTINCT FROM '[]'::jsonb
  OR st.evidence_payload#>'{semantic_judge_result,result,promotion_semantic_review}' IS DISTINCT FROM p.semantic_receipt
 THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','BLOCK_SEMANTIC_REVIEWER_RECEIPT_CHANGED'); END IF;
 packet:=public.lf_rule_promotion_semantic_packet_v1(p_promotion_id);
 IF p.semantic_receipt_sha256 IS DISTINCT FROM
      encode(extensions.digest(convert_to(p.semantic_receipt::text,'UTF8'),'sha256'),'hex')
    OR p.semantic_receipt->>'packet_sha256' IS DISTINCT FROM packet->>'packet_sha256'
    OR p.semantic_receipt->>'candidate_source_sha256' IS DISTINCT FROM
        packet#>>'{packet,candidate_source_sha256}'
    OR p.semantic_receipt->>'security_policy_sha256' IS DISTINCT FROM
        packet#>>'{packet,security_policy_sha256}'
    OR p.semantic_receipt->>'dependency_sha256' IS DISTINCT FROM
        packet#>>'{packet,dependency_sha256}'
 THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','BLOCK_SEMANTIC_SOURCE_OR_RECEIPT_DRIFT'); END IF;
 IF p.semantic_receipt->>'review_mode' IS DISTINCT FROM 'SEPARATE_NATIVE_CONTEXT'
    OR p.semantic_receipt->>'reviewer_execution_id' IS DISTINCT FROM reviewer.execution_id
    OR p.semantic_receipt->'unsupported_claims' IS DISTINCT FROM '[]'::jsonb
 THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','BLOCK_SEMANTIC_REVIEW_MODE_UNATTESTED'); END IF;
 IF p.semantic_receipt->>'verdict'='INCONCLUSIVE'
 THEN RETURN jsonb_build_object('status','RETRY_REQUIRED',
 'blocking_code','RETRY_SEMANTIC_INCONCLUSIVE'); END IF;
 IF p.semantic_receipt->>'verdict'='BLOCK'
 THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','BLOCK_SEMANTIC_CONTRADICTION'); END IF;
 IF p.semantic_receipt->>'verdict' IS DISTINCT FROM 'PASS'
 THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','BLOCK_SEMANTIC_VERDICT_UNSUPPORTED'); END IF;
 RETURN jsonb_build_object('status','VERIFIED_PASS',
 'reviewer_execution_id',reviewer.execution_id,'semantic_receipt_sha256',p.semantic_receipt_sha256,
 'review_mode','SEPARATE_NATIVE_CONTEXT',
 'independent_semantic_judge_attested',false);
END $verify$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_semantic_verify_v1(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_semantic_verify_v1(text) TO service_role;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_governed_decide_v1(
 p_promotion_id text,p_decider_actor text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions','lf_ops'
AS $governed$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE;
  judgement jsonb; semantic_gate jsonb; v_sha text; actor constant text:='LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1';
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1
  WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.status<>'PENDING' THEN RETURN jsonb_build_object(
  'status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING'); END IF;
 IF p_decider_actor IS DISTINCT FROM actor
    OR p_decider_actor=p.requested_by_profile
    OR p_decider_actor=p.request_execution_id
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','DECIDER_NOT_SEPARATE_FROM_REQUESTER'); END IF;
 judgement:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);
 v_sha:=encode(extensions.digest(convert_to(judgement::text,'UTF8'),'sha256'),'hex');
 UPDATE public.lf_rule_promotion_v1 SET judge_receipt=judgement,
   judge_receipt_sha256=v_sha,
   decision_route=judgement->>'classification'
 WHERE promotion_id=p_promotion_id;
 IF judgement->>'classification'<>'AUTO_APPROVABLE' THEN
   RETURN jsonb_build_object('status',CASE WHEN judgement->>'classification'=
    'HUMAN_DECISION_REQUIRED' THEN 'HUMAN_DECISION_REQUIRED' ELSE 'BLOCKED' END,
    'blocking_codes',judgement->'blocking_codes',
    'judge_receipt_sha256',v_sha,'promotion_id',p_promotion_id,
    'independent_semantic_judge_attested',false);
 END IF;
 semantic_gate:=public.lf_rule_promotion_semantic_verify_v1(p_promotion_id);
 IF semantic_gate->>'status' IS DISTINCT FROM 'VERIFIED_PASS' THEN
   RETURN jsonb_build_object(
     'status',CASE WHEN semantic_gate->>'status'='RETRY_REQUIRED'
                   THEN 'RETRY_REQUIRED' ELSE 'BLOCKED' END,
     'blocking_code', coalesce(semantic_gate->>'blocking_code','BLOCK_SEMANTIC_REVIEW_UNVERIFIED'),
     'judge_receipt_sha256',v_sha,
     'semantic_gate',semantic_gate,
     'promotion_id',p_promotion_id,
     'independent_semantic_judge_attested',false);
 END IF;
 UPDATE public.lf_rule_promotion_v1
 SET status='APPROVED',decided_by=actor,decided_at=now()
 WHERE promotion_id=p_promotion_id AND status='PENDING';
 RETURN jsonb_build_object('status','APPROVED',
   'promotion_id',p_promotion_id,'decided_by',actor,
   'judge_receipt_sha256',v_sha,
   'independent_semantic_judge_attested',false);
END $governed$;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'APPROVED' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); end if;
 if public.lf_rule_promotion_semantic_verify_v1(p_promotion_id)->>'status'
    IS DISTINCT FROM 'VERIFIED_PASS' THEN
    return jsonb_build_object('status','BLOCKED',
      'blocking_code','PROMOTION_SEMANTIC_RECEIPT_NOT_CURRENT');
 end if;
 if p.decided_by IS DISTINCT FROM 'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1'
    OR p.decision_route IS DISTINCT FROM 'AUTO_APPROVABLE'
    OR p.judge_receipt IS NULL
    OR p.judge_receipt_sha256 IS DISTINCT FROM encode(
         extensions.digest(convert_to(p.judge_receipt::text,'UTF8'),'sha256'),'hex')
    OR p.judge_receipt IS DISTINCT FROM
         public.lf_rule_promotion_quality_judge_v1(p_promotion_id)
 THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','PROMOTION_JUDGE_RECEIPT_NOT_CURRENT'); END IF;
 if public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update lf_ops.reglas set estado='VIGENTE' where codigo=p.rule_code and estado='CANDIDATO';
 if NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','PROMOTION_RULE_ROW_NOT_CANDIDATE'); END IF;
 update public.lf_rule_promotion_v1 set status='APPLIED', applied_at=now() where promotion_id=p_promotion_id;
 return jsonb_build_object('status','APPLIED','rule_code',p.rule_code);
end $function$
;
COMMIT;
