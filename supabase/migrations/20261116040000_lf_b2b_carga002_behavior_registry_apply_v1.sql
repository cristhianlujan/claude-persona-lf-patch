BEGIN;
-- Owner 22:08: tested physical DB constraints in PG17.6/PG18.7, CI SUCCESS 43797371776.
-- A passing diagnostic test does not certify a failing business contract.
-- Full VALID_ONLY and STORAGE-002 contract checks FAIL; uniqueness-based idempotency check PASS.
INSERT INTO lf_ops.regla_behavior_tests(regla_codigo,test_ref,ci_run,pg17,pg18)
VALUES
('B2B-RULE-VALIDATION-VALID-ONLY-001','sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_carga002_behavior_pgdual_v1.py','actions://cristhianlujan/claude-persona-lf-patch/runs/43797371776','FAIL','FAIL'),
('B2B-RULE-STORAGE-002','sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_carga002_behavior_pgdual_v1.py','actions://cristhianlujan/claude-persona-lf-patch/runs/43797371776','FAIL','FAIL'),
('B2B-RULE-IDEMP-001','sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_carga002_behavior_pgdual_v1.py','actions://cristhianlujan/claude-persona-lf-patch/runs/43797371776','PASS','PASS');

DO $owner$
DECLARE p jsonb; x jsonb; v_ok text:='B2B-RULE-IDEMP-001'; v_val text:='B2B-RULE-VALIDATION-VALID-ONLY-001'; v_store text:='B2B-RULE-STORAGE-002';
 v_run text:='EXEC-PROFILE-GATE2-9DA4709670D5BDAEFB194CB0';
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
   WHERE e.execution_id=v_run AND e.status='COMPLETED' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF')
 THEN RAISE EXCEPTION 'LF_IDEMP_SOURCE_RUN_NOT_COMPLETED_OR_WRONG_PROFILE'; END IF;
 p:=public.lf_rule_promotion_score_v1(v_run,v_ok);
 IF p->>'score'<>'100' OR p->>'decision'<>'AUTO' OR p->>'hard_block'<>'false'
 THEN RAISE EXCEPTION 'LF_IDEMP_POSITIVE_SCORE_MISMATCH:%',p; END IF;
 p:=public.lf_rule_promotion_score_v1(v_run,v_val);
 IF p->>'score'<>'60' OR p->>'decision'<>'MANUAL' OR p->>'A'<>'0'
 THEN RAISE EXCEPTION 'LF_VALID_ONLY_MUST_NOT_AUTO:%',p; END IF;
 p:=public.lf_rule_promotion_score_v1(v_run,v_store);
 IF p->>'score'<>'60' OR p->>'decision'<>'MANUAL' OR p->>'A'<>'0'
 THEN RAISE EXCEPTION 'LF_STORAGE_MUST_NOT_AUTO:%',p; END IF;
 x:=public.lf_rule_promotion_auto_apply_v1(v_run,v_ok);
 IF x->>'status'<>'APPLIED' OR x->>'written'<>'true'
    OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_ok AND estado='VIGENTE')
    OR NOT EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1
         WHERE rule_code=v_ok AND request_execution_id=v_run AND status='APPLIED'
         AND decided_by='AUTO_SCORE_V1')
 THEN RAISE EXCEPTION 'LF_IDEMP_AUTO_APPLY_READBACK_MISMATCH:%',x; END IF;
 x:=public.lf_rule_promotion_auto_apply_v1(v_run,v_val);
 IF x->>'status'<>'MANUAL' OR x->>'written'<>'false'
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_val AND estado='CANDIDATO')
 THEN RAISE EXCEPTION 'LF_VALID_ONLY_SHOULD_STAY_CANDIDATO:%',x; END IF;
 x:=public.lf_rule_promotion_auto_apply_v1(v_run,v_store);
 IF x->>'status'<>'MANUAL' OR x->>'written'<>'false'
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_store AND estado='CANDIDATO')
 THEN RAISE EXCEPTION 'LF_STORAGE_SHOULD_STAY_CANDIDATO:%',x; END IF;
END $owner$;
COMMIT;
