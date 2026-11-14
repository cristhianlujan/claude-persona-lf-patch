-- EKB evidence-only: bounded IG retry, read-only Step40 finding,
-- generic ticket vs legacy adapter, phrase-bound screen.
-- Evidence: real post-Train E2E5 Issue #3881; no RUN/ticket/status modification.
BEGIN;
DO $verified$
DECLARE
  v_execution constant text := 'EXEC-PROFILE-GATE2-E59574CD3BB5AAD2750092CC';
  v_codes text[] := ARRAY['LF-IG-BOUND-TICKET-SQL-20261114-001','LF-IG-SKILL-FAILED-STEP40-FINDING-20261114-001','LF-IG-GENERIC-TICKET-READBACK-20261114-001','LF-NATIVE-PHRASE-SCREEN-CANONICAL-20261114-001'];
  v_count integer;
  v_record record;
BEGIN
  IF (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id=v_execution
        AND step_order IN (0,10,20,30,40,45,47)
        AND status='STEP_PASS_WITH_EVIDENCE')<>7
  THEN RAISE EXCEPTION 'LF_EKB_E2E5_SEVEN_STEPS_NOT_VERIFIED'; END IF;
  IF NOT EXISTS(
      SELECT 1 FROM public.lf_operation_execution_steps
      WHERE execution_id=v_execution AND step_order=40
        AND status='STEP_PASS_WITH_EVIDENCE'
        AND evidence_payload->>'analysis_scope'='READ_ONLY_WITH_IG_FINDINGS'
        AND evidence_payload#>>'{input_governance,screen_code}'='B2B-CARGA-002'
        AND evidence_payload#>>'{skill_findings,0,status}'='SKILL_FAILED_AS_FINDING'
        AND evidence_payload#>>'{skill_findings,0,blocking_code}'=
           'SKILL_IG_RUNTIME_ATTEMPTS_EXHAUSTED_AS_FINDING'
  ) THEN RAISE EXCEPTION 'LF_EKB_E2E5_STEP40_NOT_VERIFIED'; END IF;
  IF (SELECT count(*) FROM private.lf_profile_skill_runtime_ticket_v1
        WHERE execution_id=v_execution)<>2
     OR (SELECT count(*) FROM private.lf_profile_skill_runtime_ticket_v1
        WHERE execution_id=v_execution AND consumed_at IS NOT NULL)<>2
     OR (SELECT count(*) FROM private.lf_profile_input_governance_runtime_ticket_v1
        WHERE execution_id=v_execution)<>2
     OR (SELECT count(*) FROM private.lf_profile_input_governance_runtime_ticket_v1
        WHERE execution_id=v_execution AND consumed_at IS NOT NULL)<>2
  THEN RAISE EXCEPTION 'LF_EKB_E2E5_TICKETS_NOT_2_OF_2'; END IF;
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes))
  THEN RAISE EXCEPTION 'LF_EKB_CODE_DUPLICATED'; END IF;
  FOR v_record IN
    SELECT * FROM (VALUES
    ('LF-IG-BOUND-TICKET-SQL-20261114-001','INPUT_GOVERNANCE','Limitar retries con contador SQL por RUN/skill','En E2E5, tras dos respuestas HTTP 409 del IG Validator, el contrato SQL devolvio bloqueo semantico y no emitio tercer ticket.','El bucle nativo de 64 iteraciones podia generar tickets one-use sin limite persistente; un limite solo en Python no evita doble emision concurrente.','IG_RUNTIME_RETRY_UNBOUNDED_WITHOUT_DB_CAP','Contar tickets emitidos por (execution_id,skill_code) en tabla privada; limitar a 2 bajo advisory_xact_lock y impedir tercera emision sin redefinir la autoridad OIDC.','Issue #3881, RUN E59574CD: SELECT generic emitted=2, consumed=2; PG17.6/18.7 rollback cap PASS; PR #3880 Train #43597093434.','ACTIVO'),
    ('LF-IG-SKILL-FAILED-STEP40-FINDING-20261114-001','PROFILE_EXECUTION','Skill IG fallida se registra como hallazgo y paso 40 sigue','E2E5: Input Governance no llego a READY, pero paso 40 fue STEP_PASS_WITH_EVIDENCE con SKILL_FAILED_AS_FINDING y analysis_scope READ_ONLY_WITH_IG_FINDINGS; 45 y 47 PASS.','Un fallo de dependencia READ_ONLY no debe cancelar el registro del paso 40 ni inventar un READY.','IG_FAILURE_SHOULD_NOT_BLOCK_PROFILE_READONLY_STEP40','Usar handler oficial que devuelve BLOCKED, invocador normaliza SKILL_FAILED_AS_FINDING y recorder oficial graba evidencia; bloquear promocion y produccion, continuar 45/47.','Issue #3881, SELECT steps 0/10/20/30/40/45/47 PASS; Step40 finding; 50/60/70/80 ausentes.','ACTIVO'),
    ('LF-IG-GENERIC-TICKET-READBACK-20261114-001','INPUT_GOVERNANCE','Ticket generico y adaptador legacy deben consumirse 1:1','E2E5 registro 2 tickets privados de skill y 2 del adaptador IG, todos consumidos, para el mismo execution_id; ambos son una representacion del mismo despacho autorizado.','La contabilidad de tickets por tabla puede duplicar aparente numero de invocaciones si se confunde generico con adaptador.','GENERIC_TICKET_AND_LEGACY_ADAPTER_DOUBLE_COUNT','Relacionar ticket_id y execution_id entre tablas; reportar emitidos/consumidos por cada tabla sin sumarlos; verificar no hay tercer ticket.','Issue #3881, SELECT private.lf_profile_skill_runtime_ticket_v1 2/2 y private.lf_profile_input_governance_runtime_ticket_v1 2/2.','ACTIVO'),
    ('LF-NATIVE-PHRASE-SCREEN-CANONICAL-20261114-001','PROFILE_EXECUTION','Pantalla de frase se resuelve por Router/perfil y se lee en IG','El mismo texto B2B-CARGA-002 fue conservado en Issue #3881 sin Gate2 manual y paso 40 refirio pantalla codigo B2B-CARGA-002; 0 a 47 PASS.','Redescubrir pantalla desde frase en cada dependencia crea ambiguedad de contexto y desvia identidad de pantalla.','PHRASE_SELECTED_SCREEN_NOT_CONSISTENTLY_REUSED','Usar contexto seleccionado y recibido de Router; resolver pantalla una vez por perfil, ligarla a step40 y demostrar coincidencia por SELECT; sin forzar PASS/decisiones.','Issue #3881, SELECT step40 input_governance.screen_code=B2B-CARGA-002; E2E5 7/11; PR #3875 product context binding.','ACTIVO')
    ) AS item(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,estado)
  LOOP
    INSERT INTO public.lf_error_knowledge(
      id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
      validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
      pr,estado,evidencia,created_at,updated_at,lifecycle_phase,
      consumer_role,root_cause_family,detectability,source_context,source_ref)
    VALUES(
      gen_random_uuid(),v_record.codigo,v_record.categoria,
      v_record.titulo,v_record.descripcion,v_record.causa_raiz,
      v_record.patron,v_record.prevencion,v_record.validacion,
      'HIGH',1,clock_timestamp(),clock_timestamp(),
      'LF_NATIVE_PROFILE_STEP40_E2E5/ISSUE_3881',
      '#3880',v_record.estado,
      'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3881; supabase://public.lf_operation_execution_steps/'||v_execution,
      clock_timestamp(),clock_timestamp(),'PROFILE_EXECUTION',
      ARRAY['PROFILE_EXECUTOR','INPUT_GOVERNANCE_VALIDATOR','ENGINEERING'],
      'R5_EROSION_PROCESO','LOUD_EARLY',
      'Readback E2E5; 7/11 steps; 2/2 generic+adapter; no READY or production authorization',
      'https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3881'
    );
  END LOOP;
  SELECT count(*) INTO v_count FROM public.lf_error_knowledge
  WHERE codigo=ANY(v_codes) AND estado='ACTIVO'
    AND lote_origen='LF_NATIVE_PROFILE_STEP40_E2E5/ISSUE_3881';
  IF v_count<>4 THEN RAISE EXCEPTION 'LF_EKB_E2E5_READBACK_NOT_FOUR:%',v_count; END IF;
END $verified$;
COMMIT;
