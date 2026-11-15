-- LF EKB lesson through existing lf_error_knowledge contract; sandbox only.
-- Prerequisites observed: PR #4000 merged at 2551d002d883fbe949cddbb61ad62d399f70fbd9;
-- exact-head R17 #43767955490 SUCCESS 379 tests; PASE #43767954580 SUCCESS.
-- R17 PG17.6 / PG18.7: PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED, BEGIN/ROLLBACK.
-- Strictly one EKB INSERT; no tables, functions, promotions or RUN changes.
BEGIN;
DO $ekb$
DECLARE
  v_code text := 'LF-QUALITY-CURRENT-CONTEXT-TECHNICAL-PASS-NOT-APPROVAL-20261115-001';
  v_n integer;
BEGIN
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
    RAISE EXCEPTION 'LF_QUALITY_STEP70_EKB_DUPLICATE_CODE';
  END IF;
  IF NOT EXISTS(
    SELECT 1
    FROM public.lf_operation_execution e
    JOIN public.lf_operation_execution_steps s ON s.execution_id=e.execution_id
    WHERE e.execution_id='EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C'
      AND e.status='COMPLETED'
      AND e.target_code='PERFIL-QUALITY-PACK'
      AND s.step_order=70 AND s.step_id='semantic_judge'
      AND s.status='STEP_PASS_WITH_EVIDENCE'
      AND s.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
      AND s.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
      AND s.evidence_payload#>>'{semantic_judge_result,reviewer_is_producer}'='true'
      AND s.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='false'
      AND s.evidence_payload#>>'{semantic_judge_result,model_call_count}'='0'
      AND s.evidence_payload->>'judge_independence_status'='NOT_PROVEN'
  ) THEN
    RAISE EXCEPTION 'LF_QUALITY_STEP70_EKB_SOURCE_CURRENTNESS_MISSING';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.lf_operation_execution_steps s
    WHERE s.execution_id='EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C'
      AND s.step_order=50 AND s.status='STEP_PASS_WITH_EVIDENCE'
      AND s.evidence_payload#>>'{profile_output,verdict}'='RETURN_TO_ORCHESTRATOR'
  ) OR NOT EXISTS(
    SELECT 1 FROM public.lf_operation_execution_steps s
    WHERE s.execution_id='EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C'
      AND s.step_order=80 AND s.status='STEP_PASS_WITH_EVIDENCE'
      AND s.evidence_payload->>'result'='PASS_REVIEWED_CURRENT_CONTEXT'
      AND s.evidence_payload->>'next_gate'='RETURN_TO_ROUTER'
  ) THEN
    RAISE EXCEPTION 'LF_QUALITY_STEP70_EKB_STEP50_OR_STEP80_INCONSISTENT';
  END IF;
  IF position('PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED' IN
       pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure))=0
     OR position('NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE' IN
       pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure))=0
  THEN
    RAISE EXCEPTION 'LF_QUALITY_STEP70_EKB_PROMOTION_SOURCE_GUARD_MISSING';
  END IF;

  INSERT INTO public.lf_error_knowledge
  (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
   severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
   lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref,
   created_at,updated_at)
  VALUES
  (gen_random_uuid(),v_code,'PROFILE_EXECUTION',
   'Quality: cierre técnico CURRENT_CONTEXT no es Quality aprobado',
   'Quality RUN EXEC-PROFILE-GATE2-497B6E82FA5593B0F03CB10C cerró técnicamente 11/11 con Step70 CURRENT_CONTEXT_REVIEW, reviewer_is_producer=true e independence NOT_PROVEN; Step50 retornó 19/25 RETURN_TO_ORCHESTRATOR con QUALITY_SEMANTIC_INDEPENDENCE_NOT_PROVEN y QUALITY_GOV037_FULL_RESOLVER_GATE_NOT_EXECUTED. Se buscaba erróneamente forzar un PASS pleno del juez aun sin candidatos elegibles.',
   'Confusión entre EXECUTION_PASS de la corrida técnica de solo lectura y QUALITY_APPROVED, que exige un juez semántico independiente y evidencia de GOV-037.',
   'TECHNICAL_COMPLETION_MISTAKEN_FOR_QUALITY_APPROVAL',
   'No forzar Quality PASS. CURRENT_CONTEXT_REVIEW con read_only/no_write/no_promotion puede cerrar paso 70 y 80 como ejecución técnica EXECUTION_PASS pero nunca es QUALITY_APPROVED. La promoción requiere PASS_INDEPENDENT_SEMANTIC, producer_independence_proven=true y judge_invocation_kind=NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE por public.lf_rule_promotion_request_v1 (migración 20261114163200). Quality PASS pleno solo cuando exista una regla CANDIDATO elegible con pruebas suficientes y cinco compuertas GOV-037 y juez limpio en chat nuevo ejecutado por el dueño. No modificar el bridge existente del Product Director; no fabricar recibos ni identidad.',
   'PR #4000 merge 2551d002d883fbe949cddbb61ad62d399f70fbd9, R17 SUCCESS #43767955490 (379 tests, PG17.6 y PG18.7 bajo BEGIN/ROLLBACK) con PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED; PASE SUCCESS #43767954580; SELECT público Step50/70/80 del RUN 497B6E82; SELECT función promoción muestra guards activos. Migraciones 20261101050034 y 20261114163200.',
   'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_QUALITY_STEP70_20261115',
   '#4000','ACTIVO',
   'PG17.6 PASS_QUALITY_497B_STEP70_PG17.6_PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED_ROLLBACK; PG18.7 PASS_QUALITY_497B_STEP70_PG18.7_PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED_ROLLBACK; CI run 43767955490; SELECT Quality RUN COMPLETED, same context NOT_PROVEN.',
   'PROFILE_EXECUTION',ARRAY['QUALITY','PRODUCT_DIRECTOR','ROUTER','RULE_GOVERNANCE']::text[],
   'R5_EROSION_PROCESO','LOUD_EARLY',
   'B2B-CARGA-002 / Quality 497B6E82; 0 eligible candidate evidenced; governed read-only current context.',
   'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4000',
   clock_timestamp(),clock_timestamp());
  SELECT count(*) INTO v_n FROM public.lf_error_knowledge WHERE codigo=v_code AND estado='ACTIVO';
  IF v_n<>1 THEN
    RAISE EXCEPTION 'LF_QUALITY_STEP70_EKB_INSERT_NOT_UNIQUE:%',v_n;
  END IF;
END
$ekb$;
COMMIT;
