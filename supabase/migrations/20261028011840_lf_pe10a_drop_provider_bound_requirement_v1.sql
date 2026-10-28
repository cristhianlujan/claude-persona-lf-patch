-- Decision del dueño (2026-10-27): los perfiles se ejecutan como hasta ahora (ChatGPT o Claude en chat);
-- no se exige atestacion/recibo del proveedor del modelo en el trabajo nuevo.
-- Alcance: solo lo PENDIENTE del plan PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1, unidades PE10A_STRUCTURE y PE10A_READY:
--   1) checkpoint_inputs.provider_receipt_required: true -> false en ST01..ST12 (nadie lo lee; verificado en funciones y repo)
--   2) texto "provider-bound" de ST10 (positive_test y pass_when) y OP04 (positive_test y positive_evidence_required)
--      -> "ejecutado con el perfil real en ChatGPT o Claude (chat)".
-- No toca: nada DONE, CT01, estados, otros campos, evidence_mode (etiqueta de relectura real de la fuente, sin lectores en el plan).
DO $mig$
DECLARE
 c_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 st10_pre constant text := 'Cuatro casos representativos provider-bound con baseline congelado';
 op04_pre constant text := 'E2E provider-bound para tarea representativa y holdout';
 st10_old text; op04_old text; st10_new text; op04_new text;
 v_exec text; m_st jsonb; m_op jsonb; e_st jsonb; e_op jsonb; r_st jsonb; r_op jsonb; i int; cp text;
 v_cp_before text; v_cp_after text; v_other_before text; v_other_after text; v_n int;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10a_drop_provider_bound_requirement_v1' AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10A_DROP_PROVIDER_TRAIN_TRANSPORT_REQUIRED'; END IF;

 SELECT unit_metadata INTO m_st FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code='PE10A_STRUCTURE' FOR UPDATE;
 SELECT unit_metadata INTO m_op FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code='PE10A_READY' FOR UPDATE;
 IF m_st IS NULL OR m_op IS NULL THEN RAISE EXCEPTION 'PE10A_DROP_PROVIDER_UNITS_MISSING'; END IF;

 -- guardas de estado previo: spec y checkpoint_inputs llevan el mismo texto, con el prefijo esperado
 st10_old := m_st#>>'{action_specs_v1,PE10A_ST10,positive_test}';
 op04_old := m_op#>>'{action_specs_v1,PE10A_OP04,positive_test}';
 IF st10_old IS NULL OR op04_old IS NULL
    OR st10_old NOT LIKE st10_pre||'%' OR op04_old NOT LIKE op04_pre||'%'
    OR m_st#>>'{checkpoint_inputs,PE10A_ST10,pass_when}' IS DISTINCT FROM st10_old
    OR m_op#>>'{checkpoint_inputs,PE10A_OP04,positive_evidence_required}' IS DISTINCT FROM op04_old
 THEN RAISE EXCEPTION 'PE10A_DROP_PROVIDER_PRESTATE_TEXT_DRIFT'; END IF;
 st10_new := replace(replace(st10_old,'provider-bound','ejecutados con el perfil real en ChatGPT o Claude (chat),'),'registrar receipts','registrar la corrida y su resultado');
 op04_new := replace(op04_old,'provider-bound','ejecutado en ChatGPT o Claude (chat)');
 SELECT count(*) INTO v_n FROM jsonb_each(m_st->'checkpoint_inputs') e WHERE e.value->>'provider_receipt_required'='true';
 IF v_n<>12 THEN RAISE EXCEPTION 'PE10A_DROP_PROVIDER_PRESTATE_FLAGS:%',v_n; END IF;

 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_cp_before
  FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id WHERE u.plan_code=c_plan;
 SELECT md5(string_agg(u.unit_code||md5(u.unit_metadata::text),',' ORDER BY u.unit_code)) INTO v_other_before
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code NOT IN ('PE10A_STRUCTURE','PE10A_READY');

 -- resultado esperado (se construye una vez y se compara con lo persistido)
 e_st := jsonb_set(jsonb_set(m_st,'{action_specs_v1,PE10A_ST10,positive_test}',to_jsonb(st10_new)),'{checkpoint_inputs,PE10A_ST10,pass_when}',to_jsonb(st10_new));
 FOR i IN 1..12 LOOP
   cp := 'PE10A_ST'||lpad(i::text,2,'0');
   e_st := jsonb_set(e_st,ARRAY['checkpoint_inputs',cp,'provider_receipt_required'],'false'::jsonb);
 END LOOP;
 e_op := jsonb_set(jsonb_set(m_op,'{action_specs_v1,PE10A_OP04,positive_test}',to_jsonb(op04_new)),'{checkpoint_inputs,PE10A_OP04,positive_evidence_required}',to_jsonb(op04_new));

 UPDATE programacion.engineering_plan_units SET unit_metadata=e_st WHERE plan_code=c_plan AND unit_code='PE10A_STRUCTURE';
 UPDATE programacion.engineering_plan_units SET unit_metadata=e_op WHERE plan_code=c_plan AND unit_code='PE10A_READY';

 SELECT unit_metadata INTO r_st FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code='PE10A_STRUCTURE';
 SELECT unit_metadata INTO r_op FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code='PE10A_READY';
 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_cp_after
  FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id WHERE u.plan_code=c_plan;
 SELECT md5(string_agg(u.unit_code||md5(u.unit_metadata::text),',' ORDER BY u.unit_code)) INTO v_other_after
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code NOT IN ('PE10A_STRUCTURE','PE10A_READY');
 SELECT count(*) INTO v_n FROM jsonb_each(r_st->'checkpoint_inputs') e WHERE e.value->>'provider_receipt_required'='true';

 IF r_st IS DISTINCT FROM e_st OR r_op IS DISTINCT FROM e_op OR v_n<>0
    OR v_cp_before IS DISTINCT FROM v_cp_after OR v_other_before IS DISTINCT FROM v_other_after
    OR r_st::text ~* 'provider-bound' OR r_op::text ~* 'provider-bound'
 THEN RAISE EXCEPTION 'PE10A_DROP_PROVIDER_POSTSTATE_INVALID'; END IF;
END
$mig$;
