-- Decision del dueño (2026-10-27): el trabajo nuevo NO usa revisiones ni pruebas de independencia.
-- Alcance: solo lo PENDIENTE de las unidades PE10A_* del plan PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.
--   1) estado de las especificaciones de accion pendientes (excepto CT01, ya cerrado):
--      BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT -> BLOCK_PENDING_IMPLEMENTATION
--   2) texto de aceptacion de los work items: se quita "qualified independent receipt".
-- No toca: CT01 ni nada en DONE; ningun otro campo de las especificaciones; checkpoints, funciones, permisos.
-- No toca (decision pendiente del dueño): pruebas de producto sobre jueces independientes (JD02, JD04, ST12, OP08).
-- Hecho verificado: ninguna funcion de la base lee el texto de ese estado; el cierre solo compara status='READY'.
DO $mig$
DECLARE
 c_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 c_old  constant text := 'BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT';
 c_new  constant text := 'BLOCK_PENDING_IMPLEMENTATION';
 c_er_old constant text := 'Each atomic checkpoint has actual source/readback, positive and negative observation, qualified independent receipt; never self-attest completion';
 c_er_new constant text := 'Each atomic checkpoint has actual source/readback, positive and negative observation; never self-attest completion';
 c_expect_specs constant int := 62;
 c_expect_items constant int := 8;
 v_exec text; v_before int; v_after int; v_items int;
 v_ct01_before text; v_ct01_after text; v_rest_before text; v_rest_after text; v_cp_before text; v_cp_after text; v_done_before text; v_done_after text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10a_drop_independent_receipt_requirement_v1' AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10A_DROP_INDEP_TRAIN_TRANSPORT_REQUIRED'; END IF;

 PERFORM 1 FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code LIKE 'PE10A%' FOR UPDATE;

 SELECT count(*) INTO v_before FROM programacion.engineering_plan_units u, jsonb_each(u.unit_metadata->'action_specs_v1') s
  WHERE u.plan_code=c_plan AND u.unit_code LIKE 'PE10A%' AND s.key<>'PE10A_CT01' AND s.value->>'status'=c_old;
 IF v_before<>c_expect_specs THEN RAISE EXCEPTION 'PE10A_DROP_INDEP_PRESTATE_SPECS:%',v_before; END IF;

 SELECT md5((u.unit_metadata->'action_specs_v1'->'PE10A_CT01')::text) INTO v_ct01_before
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code='PE10A_CONTRACTS';
 -- huella de todo lo demas: metadata con el status de las especificaciones pendientes normalizado
 SELECT md5(string_agg(u.unit_code||md5((jsonb_set(u.unit_metadata,'{action_specs_v1}',
    (SELECT jsonb_object_agg(s.key, CASE WHEN s.value->>'status'=c_old THEN jsonb_set(s.value,'{status}',to_jsonb(c_new)) ELSE s.value END)
       FROM jsonb_each(u.unit_metadata->'action_specs_v1') s)))::text),',' ORDER BY u.unit_code))
   INTO v_rest_before FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code LIKE 'PE10A%';
 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_cp_before
  FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
  WHERE u.plan_code=c_plan AND u.unit_code LIKE 'PE10A%';
 SELECT md5(string_agg(u.unit_code||md5(u.unit_metadata::text),',' ORDER BY u.unit_code)) INTO v_done_before
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code NOT LIKE 'PE10A%';

 UPDATE programacion.engineering_plan_units u
    SET unit_metadata=jsonb_set(u.unit_metadata,'{action_specs_v1}',
      (SELECT jsonb_object_agg(s.key,
         CASE WHEN s.key<>'PE10A_CT01' AND s.value->>'status'=c_old THEN jsonb_set(s.value,'{status}',to_jsonb(c_new)) ELSE s.value END)
       FROM jsonb_each(u.unit_metadata->'action_specs_v1') s))
  WHERE u.plan_code=c_plan AND u.unit_code LIKE 'PE10A%'
    AND EXISTS (SELECT 1 FROM jsonb_each(u.unit_metadata->'action_specs_v1') s WHERE s.key<>'PE10A_CT01' AND s.value->>'status'=c_old);

 UPDATE programacion.engineering_work_items w SET expected_result=c_er_new
  WHERE w.expected_result=c_er_old
    AND w.id IN (SELECT work_item_id FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code LIKE 'PE10A%');
 GET DIAGNOSTICS v_items = ROW_COUNT;
 IF v_items<>c_expect_items THEN RAISE EXCEPTION 'PE10A_DROP_INDEP_ITEMS_UPDATED:%',v_items; END IF;

 SELECT count(*) INTO v_after FROM programacion.engineering_plan_units u, jsonb_each(u.unit_metadata->'action_specs_v1') s
  WHERE u.plan_code=c_plan AND u.unit_code LIKE 'PE10A%' AND s.key<>'PE10A_CT01' AND s.value->>'status'=c_old;
 SELECT md5((u.unit_metadata->'action_specs_v1'->'PE10A_CT01')::text) INTO v_ct01_after
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code='PE10A_CONTRACTS';
 SELECT md5(string_agg(u.unit_code||md5(u.unit_metadata::text),',' ORDER BY u.unit_code)) INTO v_rest_after
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code LIKE 'PE10A%';
 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_cp_after
  FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
  WHERE u.plan_code=c_plan AND u.unit_code LIKE 'PE10A%';
 SELECT md5(string_agg(u.unit_code||md5(u.unit_metadata::text),',' ORDER BY u.unit_code)) INTO v_done_after
  FROM programacion.engineering_plan_units u WHERE u.plan_code=c_plan AND u.unit_code NOT LIKE 'PE10A%';

 IF v_after<>0 OR v_ct01_before IS DISTINCT FROM v_ct01_after OR v_rest_before IS DISTINCT FROM v_rest_after
    OR v_cp_before IS DISTINCT FROM v_cp_after OR v_done_before IS DISTINCT FROM v_done_after
    OR (SELECT count(*) FROM programacion.engineering_plan_units u, jsonb_each(u.unit_metadata->'action_specs_v1') s
         WHERE u.plan_code=c_plan AND u.unit_code LIKE 'PE10A%' AND s.key<>'PE10A_CT01' AND s.value->>'status'=c_new)<>c_expect_specs
 THEN RAISE EXCEPTION 'PE10A_DROP_INDEP_POSTSTATE_INVALID'; END IF;
END
$mig$;
