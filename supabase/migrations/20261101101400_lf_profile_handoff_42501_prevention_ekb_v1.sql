-- LF runtime EKB preventive record. No Router function/grant/operation altered.
-- Source first, apply ONLY by canonical LF Migration Merge Train.
-- The profile, not ACT-0001, is responsible for BEGIN via existing GitHub OIDC/Edge.
DO $ekb$
BEGIN
  IF to_regprocedure('public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)') IS NULL
     OR has_function_privilege('supabase_read_only_user',
          'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)','EXECUTE')
     OR NOT has_function_privilege('service_role',
          'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)','EXECUTE')
     OR NOT EXISTS(
       SELECT 1 FROM public.lf_operation_execution e
       WHERE e.execution_id='EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00'
         AND e.status='COMPLETED'
         AND (SELECT count(*) FROM public.lf_operation_execution_steps s
              WHERE s.execution_id=e.execution_id AND s.status='STEP_PASS_WITH_EVIDENCE')=11
     )
  THEN
    RAISE EXCEPTION 'LF_PROFILE_HANDOFF_EKB_SOURCE_PRESTATE_DRIFT';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM transversal.error_knowledge WHERE codigo='LF-PROFILE-HANDOFF-DIRECT-42501-OLD-RUN-SUBSTITUTION-001') THEN
    INSERT INTO transversal.error_knowledge
      (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
       severidad,lote_origen,estado,evidencia,lifecycle_phase,root_cause_family,
       detectability,source_context,source_ref,consumer_role)
    VALUES
      ('LF-PROFILE-HANDOFF-DIRECT-42501-OLD-RUN-SUBSTITUTION-001',
       'PROFILE_RUNTIME_GOVERNANCE',
       'Router entrega Gate2 READY pero agente intenta SQL read-only, obtiene 42501 y reutiliza run antiguo',
       'Recurrente 2026-11-01: Router ACT-0001 selecciona product_director_lf con HANDOFF_CONTEXT_TO_SELECTED_PROFILE, pero el agente llama lf_router_pipeline_context_profile_admit_v2 desde supabase_read_only_user; la ACL intencional devuelve 42501. No hay nuevo run y se presenta un resultado COMPLETED historico. La causa no es un permiso faltante ni un fallo del perfil.',
       'El consumer ignora el inicio OIDC/Edge propio de EJECUCION_PERFIL_LF; CLAUDE.md mezclaba el contrato legacy independiente con el modo V3 CURRENT_CONTEXT_REVIEW y no explicitaba BEGIN desde el handoff.',
       'READ_ONLY_DIRECT_PROFILE_ADMISSION_AND_HISTORICAL_EXECUTION_SUBSTITUTION',
       'Leer EKB y el runbook de perfiles. Un Gate2 GATE2_DERIVED_PENDING_GOVERNED_ADMISSION/HANDOFF_CONTEXT_TO_SELECTED_PROFILE obliga al agente a generar LF_PROFILE_NATIVE_BEGIN_REQUEST_V1 con router_context sin cambios y executor_mode GPT_NATIVE, crear Issue Github con label lf-profile-resume-governed y dejar que el workflow use GitHub OIDC->Edge->service_role->RPC canónico. No llamar el admit RPC desde supabase_read_only_user, no ampliar ACL, no mover secrets al Router, no crear dispatcher o ruta directa al perfil. Comprobar nuevo execution_id antes de afirmar recepcion; si no existe, NOT_EXECUTED, nunca reutilizar run previo. Continuar con mismo ID y evidencia real por LF_PROFILE_NATIVE_RESUME_REQUEST_V1 (screen/RAW/V3) hasta 11/11 COMPLETED READY, sin repetir autorización dentro del mismo alcance. CURRENT_CONTEXT_REVIEW es solo read_only/no_write/no_promotion, sin independencia simulada.',
       'Negativo: 42501 de supabase_read_only_user en admit RPC no bloquea OIDC gobernado; los retired actions dan 410 y cero backend calls. Positivo comprobado: Issues 3449->3450->3451->3452, Actions 41293887404, execution EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00 11/11 COMPLETED y terminal READY. Prevención futura: canary fresco de un nuevo chat en el mismo alcance debe crear un ID distinto y no detenerse en Gate2.',
       'HIGH',
       'LF_PROFILE_HANDOFF_E2E_20261101',
       'ACTIVE_REMEDIATION',
       'github://cristhianlujan/claude-persona-lf-patch/issues/3449;github://cristhianlujan/claude-persona-lf-patch/issues/3452;github-actions://cristhianlujan/claude-persona-lf-patch/actions/runs/41293887404;supabase://public.lf_operation_execution/EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00',
       'RUNTIME_LIVE_REVERIFY',
       'R5_EROSION_PROCESO',
       'LOUD_LATE',
       'Repeated LF Login B2B profile handoff 2026-11-01',
       'github://cristhianlujan/claude-persona-lf-patch/ops/runbook-profiles-lf.md',
       ARRAY['Architect','Builder','Judge','Auditor']::text[]);
  END IF;
  IF (SELECT count(*) FROM transversal.error_knowledge WHERE codigo='LF-PROFILE-HANDOFF-DIRECT-42501-OLD-RUN-SUBSTITUTION-001') <> 1
  THEN RAISE EXCEPTION 'LF_PROFILE_HANDOFF_EKB_NOT_UNIQUE'; END IF;
END $ekb$;
