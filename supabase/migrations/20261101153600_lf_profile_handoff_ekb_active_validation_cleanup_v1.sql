-- LF EKB active-rule wording correction.
-- Readback of the existing governed execution is the sole terminal certificate.
-- Existing migration records remain immutable; no Router, role or RPC changes.
DO $lf$
DECLARE
  v_code constant text := 'LF-PROFILE-HANDOFF-DIRECT-42501-OLD-RUN-SUBSTITUTION-001';
  v_run text;
  v_runs text[] := ARRAY[
    'EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00',
    'EXEC-PROFILE-GATE2-93CEF1403D252A61F5EC2AC8',
    'EXEC-PROFILE-GATE2-1B544082A880C107E66BCBD1'
  ];
  v_count integer;
BEGIN
  IF (SELECT count(*) FROM transversal.error_knowledge
      WHERE codigo = v_code AND estado = 'VERIFICADO') <> 1
  THEN RAISE EXCEPTION 'LF_HANDOFF_EKB_ACTIVE_SOURCE_DRIFT'; END IF;

  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)',
       'EXECUTE'
     )
  THEN RAISE EXCEPTION 'LF_HANDOFF_ACL_DRIFT'; END IF;

  FOREACH v_run IN ARRAY v_runs LOOP
    IF NOT EXISTS(
        SELECT 1 FROM public.lf_operation_execution e
        WHERE e.execution_id = v_run AND e.status = 'COMPLETED'
      )
      OR (SELECT count(*) FROM public.lf_operation_execution_steps s
          WHERE s.execution_id = v_run) <> 11
      OR (SELECT count(*) FROM public.lf_operation_execution_steps s
          WHERE s.execution_id = v_run
            AND s.status = 'STEP_PASS_WITH_EVIDENCE') <> 11
      OR (SELECT count(*) FROM public.lf_operation_execution_steps s
          WHERE s.execution_id = v_run AND s.step_id IN ('semantic_judge','report_output')
            AND s.status = 'STEP_PASS_WITH_EVIDENCE'
            AND s.evidence_payload#>>'{trust_validation,valid}' = 'true') <> 2
      OR public.lf_profile_execution_terminal_authority_receipt_v1(v_run)->>'status' IS DISTINCT FROM 'READY'
    THEN RAISE EXCEPTION 'LF_HANDOFF_CANONICAL_EVIDENCE_INCOMPLETE: %',v_run; END IF;
  END LOOP;

  UPDATE transversal.error_knowledge
  SET validacion =
    'Criterio canónico LF: Router ACT-0001 entrega Gate2 VALID, sin ejecutar el perfil ni transportar credenciales. '
    || 'El perfil inicia una ejecución distinta mediante LF_PROFILE_NATIVE_BEGIN_REQUEST_V1 en GitHub OIDC -> Edge -> RPC autorizado, '
    || 'con service_role exclusivamente dentro de Edge. Las etapas posteriores reutilizan el mismo execution_id y '
    || 'registran screen_selection, RAW real, output_validate y dictamen V3 con procedencia verificable. '
    || 'El cierre requiere exactamente 11/11 STEP_PASS_WITH_EVIDENCE, semantic_judge 70 y report_output 80 '
    || 'con trust_validation válido, ejecución COMPLETED y terminal READY en Supabase. '
    || 'Controles de permisos: supabase_read_only_user sin EXECUTE para admit_v2; service_role con EXECUTE. '
    || 'Evidencia positiva: tres ejecuciones distintas, EXEC-PROFILE-GATE2-31340B34D5B0E320E3B83C00, '
    || 'EXEC-PROFILE-GATE2-93CEF1403D252A61F5EC2AC8 y '
    || 'EXEC-PROFILE-GATE2-1B544082A880C107E66BCBD1; '
    || 'GitHub Actions 41293887404, 41296096617 y 41296832156. '
    || 'Este certificado acredita el transporte y cierre de los perfiles, no modifica reglas de negocio ni acredita producción.'
  WHERE codigo = v_code AND estado = 'VERIFICADO';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1 THEN RAISE EXCEPTION 'LF_HANDOFF_EKB_ACTIVE_UPDATE_NOT_EXACTLY_ONE'; END IF;
END $lf$;
