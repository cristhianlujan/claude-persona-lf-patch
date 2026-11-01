-- LF EKB closeout: only canonical profile-owned evidence is required.
-- No new chat, external browser, altered Router, new secrets or additional independent judge.
-- Applied only via protected LF Migration Merge Train.
DO $lf$
DECLARE
  v_code text := 'LF-PROFILE-HANDOFF-DIRECT-42501-OLD-RUN-SUBSTITUTION-001';
  v_runs text[] := ARRAY[
    'EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00',
    'EXEC-PROFILE-GATE2-93CEF1403D252A61F5EC2AC8',
    'EXEC-PROFILE-GATE2-1B544082A880C107E66BCBD1'
  ];
  v_run text;
  v_count integer;
BEGIN
  IF (SELECT count(*) FROM transversal.error_knowledge
      WHERE codigo=v_code AND estado IN ('ACTIVE_REMEDIATION','VERIFICADO')) <> 1
  THEN RAISE EXCEPTION 'LF_EKB_HANDOFF_PRESTATE_INVALID'; END IF;

  IF has_function_privilege('supabase_read_only_user',
     'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)','EXECUTE')
     OR NOT has_function_privilege('service_role',
     'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)','EXECUTE')
  THEN RAISE EXCEPTION 'LF_HANDOFF_ACL_ISOLATION_DRIFT'; END IF;

  FOREACH v_run IN ARRAY v_runs LOOP
    IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
                   WHERE e.execution_id=v_run AND e.status='COMPLETED')
      OR (SELECT count(*) FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=v_run AND s.status='STEP_PASS_WITH_EVIDENCE') <> 11
      OR (SELECT count(*) FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=v_run) <> 11
      OR (SELECT count(*) FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=v_run
            AND s.step_id IN ('semantic_judge','report_output')
            AND s.status='STEP_PASS_WITH_EVIDENCE'
            AND s.evidence_payload#>>'{trust_validation,valid}'='true') <> 2
      OR (public.lf_profile_execution_terminal_authority_receipt_v1(v_run)->>'status') IS DISTINCT FROM 'READY'
    THEN RAISE EXCEPTION 'LF_PROFILE_HANDOFF_CANONICAL_E2E_NOT_CERTIFIED: %',v_run; END IF;
  END LOOP;

  UPDATE transversal.error_knowledge
  SET estado='VERIFICADO',
      validacion='EKB closeout por recorrido canónico EXISTENTE de LF, sin navegador externo ni requisito de otro chat: (1) Router ACT-0001 sólo entrega contexto Gate2 y nunca service_role; (2) nuevo execution_id distinto por cada invocación; (3) BEGIN de perfil mediante Issue LF_PROFILE_NATIVE_BEGIN_REQUEST_V1 / GitHub OIDC -> Edge con service_role interno -> RPC restringido; (4) continuación en mismo ID con pantalla, RAW y V3 real, sin simular independencia; (5) Supabase step70 y step80 validos, 11/11 STEP_PASS_WITH_EVIDENCE, run COMPLETED, recibo terminal READY. Evidencia POSITIVA verificada en tres runs distintos: EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00; EXEC-PROFILE-GATE2-93CEF1403D252A61F5EC2AC8; EXEC-PROFILE-GATE2-1B544082A880C107E66BCBD1. NEGATIVO ACL vigente: supabase_read_only_user NO puede ejecutar lf_router_pipeline_context_profile_admit_v2 y service_role SI puede. La restricción es intencional; no llamar desde lectura ni ampliar permisos. No se exige otra conversación, otra ruta, otro dictamen o navegador. Este cierre acredita el recorrido técnico, no garantiza conducta de todos los chats futuros ni acredita ajustes de negocio.',
      evidencia='github://cristhianlujan/claude-persona-lf-patch/issues/3449;github://cristhianlujan/claude-persona-lf-patch/issues/3452;github://cristhianlujan/claude-persona-lf-patch/issues/3455;github://cristhianlujan/claude-persona-lf-patch/issues/3458;github://cristhianlujan/claude-persona-lf-patch/issues/3459;github://cristhianlujan/claude-persona-lf-patch/issues/3462;github-actions://cristhianlujan/claude-persona-lf-patch/actions/runs/41293887404;github-actions://cristhianlujan/claude-persona-lf-patch/actions/runs/41296096617;github-actions://cristhianlujan/claude-persona-lf-patch/actions/runs/41296832156;supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00;supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-93CEF1403D252A61F5EC2AC8;supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-1B544082A880C107E66BCBD1'
  WHERE codigo=v_code;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN RAISE EXCEPTION 'LF_EKB_HANDOFF_CLOSEOUT_NOT_EXACTLY_ONE'; END IF;
END $lf$;
