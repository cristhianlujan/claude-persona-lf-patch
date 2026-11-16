BEGIN;
-- Owner IG 22:40. CI 43799742923, attempt 2: R17 PG17.6+PG18.7 source-bound
-- behavior test successful on hardened schema. Only two previously FAIL registry
-- entries are changed; protected score/hash/approval gates remain enforced.
DO $proof$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n
 FROM pg_constraint c
 WHERE c.conrelid IN ('lf_ops.cargas_lotes'::regclass,'lf_ops.cargas_archivos'::regclass)
   AND c.conname IN ('cargas_lotes_valid_only_processed_chk','cargas_lotes_counts_sum_chk',
                     'cargas_archivos_ext_mime_chk','cargas_archivos_checksum_chk')
   AND c.convalidated;
 IF n<>4 THEN RAISE EXCEPTION 'LF_B2B_CARGA002_HARDENING_CONSTRAINTS_NOT_VALIDATED:%',n; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid='lf_ops.cargas_lotes'::regclass
     AND t.tgname='trg_cargas_lotes_block_unsafe_processing_v1'
     AND NOT t.tgisinternal AND t.tgenabled<>'D')
 THEN RAISE EXCEPTION 'LF_B2B_CARGA002_HARDENING_TRIGGER_NOT_ACTIVE'; END IF;
 SELECT count(*) INTO n FROM lf_ops.regla_behavior_tests
 WHERE regla_codigo IN ('B2B-RULE-VALIDATION-VALID-ONLY-001','B2B-RULE-STORAGE-002')
   AND test_ref='sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_carga002_behavior_pgdual_v1.py'
   AND pg17='FAIL' AND pg18='FAIL'
   AND ci_run='actions://cristhianlujan/claude-persona-lf-patch/runs/43797371776';
 IF n<>2 THEN RAISE EXCEPTION 'LF_B2B_CARGA002_PRIOR_FAILURE_ROWS_DRIFT:%',n; END IF;
END $proof$;

UPDATE lf_ops.regla_behavior_tests
 SET pg17='PASS',pg18='PASS',
     ci_run='actions://cristhianlujan/claude-persona-lf-patch/runs/43799742923'
 WHERE regla_codigo IN ('B2B-RULE-VALIDATION-VALID-ONLY-001','B2B-RULE-STORAGE-002')
   AND test_ref='sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_carga002_behavior_pgdual_v1.py'
   AND pg17='FAIL' AND pg18='FAIL';

DO $apply$
DECLARE r record; v_score jsonb; v_result jsonb;
 v_run CONSTANT text:='EXEC-PROFILE-GATE2-9DA4709670D5BDAEFB194CB0';
 n integer;
BEGIN
 SELECT count(*) INTO n FROM lf_ops.regla_behavior_tests
  WHERE regla_codigo IN ('B2B-RULE-VALIDATION-VALID-ONLY-001','B2B-RULE-STORAGE-002')
    AND test_ref='sandbox/lf_contract_gate_test/edge_function_operation/test_b2b_carga002_behavior_pgdual_v1.py'
    AND ci_run='actions://cristhianlujan/claude-persona-lf-patch/runs/43799742923'
    AND pg17='PASS' AND pg18='PASS';
 IF n<>2 THEN RAISE EXCEPTION 'LF_B2B_CARGA002_NEW_REGISTRY_ROWS_NOT_PROVEN:%',n; END IF;
 FOR r IN SELECT codigo FROM lf_ops.reglas
  WHERE codigo IN ('B2B-RULE-VALIDATION-VALID-ONLY-001','B2B-RULE-STORAGE-002')
  ORDER BY codigo LOOP
   v_score:=public.lf_rule_promotion_score_v1(v_run,r.codigo);
   IF v_score->>'decision'<>'AUTO'
      OR v_score->>'hard_block'<>'false'
      OR (v_score->>'score')::int<85
   THEN RAISE EXCEPTION 'LF_B2B_CARGA002_AUTO_SCORE_NOT_ADMITTED rule=% score=%',r.codigo,v_score; END IF;
   v_result:=public.lf_rule_promotion_auto_apply_v1(v_run,r.codigo);
   IF v_result->>'status'<>'APPLIED'
      OR v_result->>'written'<>'true'
      OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas
         WHERE codigo=r.codigo AND estado='VIGENTE')
      OR NOT EXISTS (SELECT 1 FROM public.lf_rule_promotion_v1
         WHERE rule_code=r.codigo AND request_execution_id=v_run
           AND status='APPLIED' AND decided_by='AUTO_SCORE_V1')
   THEN RAISE EXCEPTION 'LF_B2B_CARGA002_AUTO_APPLY_READBACK_FAILED rule=% result=%',r.codigo,v_result; END IF;
 END LOOP;
 IF (SELECT count(*) FROM lf_ops.reglas
     WHERE codigo IN ('B2B-RULE-VALIDATION-VALID-ONLY-001','B2B-RULE-STORAGE-002')
       AND estado='VIGENTE')<>2
 THEN RAISE EXCEPTION 'LF_B2B_CARGA002_FINAL_STATE_NOT_BOTH_VIGENTE'; END IF;
END $apply$;
COMMIT;
