BEGIN;
CREATE TABLE IF NOT EXISTS lf_ops.regla_behavior_tests(regla_codigo text NOT NULL REFERENCES lf_ops.reglas(codigo), test_ref text NOT NULL, ci_run text NOT NULL, pg17 text NOT NULL CHECK (pg17 IN ('PASS','FAIL')), pg18 text NOT NULL CHECK (pg18 IN ('PASS','FAIL')), source_sha text, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (regla_codigo,test_ref));
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_score_v1(p_execution_id text,p_rule_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $score$
DECLARE
  r record; p40 record; p50 record; p60 record; p70 record;
  refs jsonb; is_bound boolean:=false; has_ref boolean:=false;
  a integer:=0; b integer:=0; c integer:=0; d integer:=0; total integer;
  hard_block boolean; decision text;
  blocked_categories CONSTANT text[]:=ARRAY['LEGAL','APPROVAL','OFERTAS_CUOTAS','AUTH','PRIVACY','PAGOS'];
BEGIN
  SELECT codigo,estado,categoria,pendiente_decision,updated_at INTO r FROM lf_ops.reglas WHERE codigo=p_rule_code;
  IF NOT FOUND THEN RETURN jsonb_build_object('score',0,'A',0,'B',0,'C',0,'D',0,'hard_block',true,
    'decision','BLOCKED','next_gate','RETURN_TO_ROUTER','reason','RULE_NOT_FOUND'); END IF;
  SELECT * INTO p40 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=40 AND step_id='input_validate';
  SELECT * INTO p50 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=50 AND step_id='execute_profile';
  SELECT * INTO p60 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=60 AND step_id='output_validate';
  SELECT * INTO p70 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id AND step_order=70 AND step_id='semantic_judge';
  is_bound:=p40.status='STEP_PASS_WITH_EVIDENCE'
    AND p50.status='STEP_PASS_WITH_EVIDENCE'
    AND p60.status='STEP_PASS_WITH_EVIDENCE'
    AND p70.status='STEP_PASS_WITH_EVIDENCE'
    AND p70.evidence_payload#>>'{semantic_judge_result,verdict}'
      IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
    AND p50.evidence_payload->>'raw_output_sha256' ~ '^[0-9a-f]{64}$'
    AND p50.evidence_payload->>'raw_output_sha256'=p60.evidence_payload->>'raw_output_sha256'
    AND p50.evidence_payload->>'raw_output_sha256'=p70.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
    AND p40.evidence_payload->>'scope_authority_packet_sha256'
      ='sha256:'||(p70.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}')
    AND jsonb_typeof(p70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')='array'
    AND jsonb_array_length(p70.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')=0;
  refs:=p50.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}';
  IF jsonb_typeof(refs)='array' THEN
    SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) x
      WHERE x->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code) INTO has_ref;
  END IF;
  IF is_bound AND has_ref THEN b:=30; END IF;
  IF r.pendiente_decision IS FALSE THEN c:=20; END IF;
  IF b>0 AND r.updated_at<p70.observed_at THEN d:=10; END IF;
  IF is_bound AND EXISTS (SELECT 1 FROM lf_ops.regla_behavior_tests bt WHERE bt.regla_codigo=p_rule_code AND bt.pg17='PASS' AND bt.pg18='PASS' AND bt.ci_run IS NOT NULL AND btrim(bt.ci_run)<>'') THEN a:=40; END IF;
  hard_block:=coalesce(r.pendiente_decision,true) OR r.categoria=ANY(blocked_categories)
    OR p_rule_code LIKE '%INSTALLMENT%';
  total:=a+b+c+d;
  -- Below 60 always returns Router; hard_block forces MANUAL at/above 60.
  IF r.estado<>'CANDIDATO' OR total<60 THEN decision:='BLOCKED';
  ELSIF hard_block THEN decision:='MANUAL';
  ELSIF total>=85 THEN decision:='AUTO';
  ELSE decision:='MANUAL'; END IF;
  RETURN jsonb_build_object('score',total,'A',a,'B',b,'C',c,'D',d,
    'hard_block',hard_block,'decision',decision,
    'next_gate',CASE WHEN decision='BLOCKED' THEN 'RETURN_TO_ROUTER' ELSE 'PROMOTION_REQUEST' END,
    'judge_independence',CASE
      WHEN p70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
       THEN 'NOT_PROVEN_OWNER_ACCEPTED'
      WHEN p70.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
       THEN 'INDEPENDENCE_ASSERTED_NOT_REVERIFIED'
      ELSE 'NO_VALID_JUDGE' END,
    'reason','A from lf_ops.regla_behavior_tests');
END $score$;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_auto_apply_v1(p_execution_id text,p_rule_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public','extensions' AS $aa$
DECLARE v_score jsonb; v_req jsonb;
BEGIN
  v_score:=public.lf_rule_promotion_score_v1(p_execution_id,p_rule_code);
  IF v_score->>'decision'<>'AUTO' OR v_score->>'hard_block'<>'false' THEN RETURN jsonb_build_object('status',v_score->>'decision','score',v_score,'written',false); END IF;
  v_req:=public.lf_rule_promotion_request_v1(p_execution_id,p_rule_code,'AUTO_SCORE_V1 score='||(v_score->>'score')||' no hard_block');
  IF v_req->>'status'<>'APPLIED' OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo=p_rule_code AND estado='VIGENTE') THEN RAISE EXCEPTION 'LF_AUTO_APPLY_READBACK_FAILED:%',v_req; END IF;
  RETURN jsonb_build_object('status','APPLIED','score',v_score,'request',v_req,'written',true);
END $aa$;
CREATE OR REPLACE FUNCTION public.lf_execution_mark_abandoned_v1(p_execution_id text,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $ab$
DECLARE n integer;
BEGIN
  UPDATE public.lf_operation_execution e SET status='ABANDONED', completed_at=now(), updated_at=now(), manifest=e.manifest||jsonb_build_object('abandoned_reason',p_reason,'abandoned_at',now())
  WHERE e.execution_id=p_execution_id AND e.status='IN_PROGRESS' AND e.updated_at<now()-interval '24 hours'
    AND NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s WHERE s.execution_id=e.execution_id AND s.observed_at>now()-interval '24 hours');
  GET DIAGNOSTICS n=ROW_COUNT;
  RETURN jsonb_build_object('execution_id',p_execution_id,'abandoned',n=1);
END $ab$;
INSERT INTO lf_ops.regla_behavior_tests(regla_codigo,test_ref,ci_run,pg17,pg18) VALUES ('B2B-RULE-LOAD-WIZARD-001','sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_wizard_three_step_pgdual_v1.py','actions://cristhianlujan/claude-persona-lf-patch/runs/43771883221','PASS','PASS');
COMMIT;
