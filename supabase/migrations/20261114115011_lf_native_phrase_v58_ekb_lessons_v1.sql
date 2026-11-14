-- LF EKB-only: observed native profile phrase blocker + candidate V58 recuration gap.
-- Source evidence: Issue #3871, Actions #43590839238, PR #3867 (2026-11-14).
-- No profile RUN or IG RUN mutation; no runtime/production/promotion changes.
BEGIN;
DO $ekb$
DECLARE
  v_codes text[] := ARRAY[
    'LF-NATIVE-PHRASE-SCREEN-SELECTION-HALT-20261114-001',
    'LF-IG-V58-RECURATION-NOT-DISPATCHED-20261114-001'
  ];
  v_count integer;
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM public.lf_operation_execution e
    WHERE e.execution_id='EXEC-PROFILE-GATE2-597CEBD8C99ECE4C0A4FEC47'
      AND e.operation_code='EJECUCION_PERFIL_LF'
      AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
  ) THEN RAISE EXCEPTION 'LF_EKB_SOURCE_RUN_NOT_FOUND'; END IF;
  IF (SELECT count(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id='EXEC-PROFILE-GATE2-597CEBD8C99ECE4C0A4FEC47'
        AND s.step_order IN (0,10,20,30)
        AND s.status='STEP_PASS_WITH_EVIDENCE')<>4
  THEN RAISE EXCEPTION 'LF_EKB_FIRST_FOUR_STEPS_NOT_VERIFIED'; END IF;
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes))
  THEN RAISE EXCEPTION 'LF_EKB_DUPLICATE_CODE_RECONCILE'; END IF;

  INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    pr,estado,evidencia,created_at,updated_at,lifecycle_phase,consumer_role,
    root_cause_family,detectability,source_context,source_ref
  ) VALUES (
    gen_random_uuid(),v_codes[1],'PROFILE_EXECUTION',
    'Frase ACT-0001 crea RUN pero se detiene en selección semántica de pantalla',
    'El Issue #3871, con LF_PROFILE_RUN_FROM_PHRASE_V1 y la frase B2B-CARGA-002, abrió el RUN EXEC-PROFILE-GATE2-597CEBD8C99ECE4C0A4FEC47. SELECT acreditó solo pasos 0/10/20/30. El bridge devolvió SCREEN_SELECTION_REQUIRED y REQUIRED_INPUT=AUTHORIZED_SCREEN_SELECTION. Los pasos 40 a 80 no se registraron y no hubo ticket genérico de skill.',
    'La integración frase→Router→BEGIN no resuelve la selección de pantalla requerida por el perfil antes del paso 40 sin una continuación semántica adicional.',
    'PHRASE_BEGIN_CREATES_RUN_BUT_REQUIRES_UNDISPATCHED_SCREEN_SELECTION',
    'Resolver selección de pantalla por el perfil en la misma ruta nativa; mantener el mismo RUN y prohibir Gate2 o STEP_PASS manual. Verificar 11/11 por SELECT y recibo terminal READY antes de declarar E2E.',
    'Issue #3871; Actions run 43590839238: exit 1 SCREEN_SELECTION_REQUIRED. SELECT public.lf_operation_execution_steps: 4/11; private.lf_profile_skill_runtime_ticket_v1: 0; private.lf_profile_input_governance_runtime_ticket_v1: 0; public.lf_skill_invocation_v1: 0.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_NATIVE_PROFILE_0_80/ISSUE_3871',
    '#3871','ACTIVO',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43590839238; supabase://public.lf_operation_execution_steps/EXEC-PROFILE-GATE2-597CEBD8C99ECE4C0A4FEC47',
    clock_timestamp(),clock_timestamp(),'PROFILE_EXECUTION',
    ARRAY['PROFILE_EXECUTOR','ROUTER_OWNER'], 'R2_NO_VE','LOUD_EARLY',
    'LF native phrase entry; 2026-11-14 11:37 UTC; no production authorization',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3871'
  ), (
    gen_random_uuid(),v_codes[2],'INPUT_GOVERNANCE',
    'V58 NEEDS_RECURATION propuesta sin despacho probado de sucesor Curator',
    'PR #3867 propone transformar rebind fallido en NEEDS_RECURATION y bloquear PASS con CURATOR_REEVALUATION_REQUIRED, pero el propio PR declara ausente el despacho automático del orquestador Edge. En el preflight GitHub, mergeable_state=dirty; tres workflows exitosos no demuestran pruebas PG17/18 ni cascada E2E. Es una brecha del candidato, no un incidente desplegado.',
    'El contrato de bloqueo del validador y la creación automática del Curator sucesor permanecen separados; falta integración y prueba de la transición.',
    'VALIDATOR_RECURATION_FINDING_WITHOUT_VERIFIED_CURATOR_DISPATCH',
    'No promover PR B ni alegar recuración automática por solo emitir NEEDS_RECURATION. Resolver conflictos con main; implementar despacho al Curator sucesor por ruta gobernada y acreditar PG17/18 E2E, casos negativos, readback y exact HEAD CI antes del Train.',
    'PR #3867 HEAD 4ccb72837322bf29e99fd0bd1a79b39a1376f612: draft, mergeable_state=dirty; comment 6876721184. PASE 43586919639 PASS, migration name 43586919681 PASS y Router Level2 43586919515 PASS, no evidencia de cascada.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_IG_V58/PR_3867',
    '#3867','CANDIDATO',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3867',
    clock_timestamp(),clock_timestamp(),'CODE_REVIEW',
    ARRAY['INPUT_GOVERNANCE_CURATOR','VALIDATOR_OWNER','ENGINEERING'],
    'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
    'V58 PR B candidate as inspected 2026-11-14; not deployed, no production authority',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3867'
  );
  SELECT count(*) INTO v_count FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes);
  IF v_count<>2 THEN RAISE EXCEPTION 'LF_EKB_READBACK_COUNT_NOT_TWO:%',v_count; END IF;
  IF (SELECT count(*) FROM public.lf_error_knowledge
      WHERE (codigo=v_codes[1] AND estado='ACTIVO')
         OR (codigo=v_codes[2] AND estado='CANDIDATO'))<>2
  THEN RAISE EXCEPTION 'LF_EKB_READBACK_STATUS_MISMATCH'; END IF;
END $ekb$;
COMMIT;
