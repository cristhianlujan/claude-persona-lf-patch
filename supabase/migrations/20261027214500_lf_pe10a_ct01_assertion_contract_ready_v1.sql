-- PE10A_CT01: condicion de cierre verificable (assertion_contract) y estado de especificacion READY.
--
-- Hecho verificado en produccion (solo lectura, 2026-10-27): la especificacion de CT01 esta en
-- BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT y no tiene assertion_contract, por lo que
-- fn_engineering_action_spec_assertion_contract_v1 devuelve BLOCK_ACTION_SPEC_NOT_READY y el cierre
-- gobernado de CT01 no puede evaluarse.
--
-- Cambio (solo datos, un unico checkpoint):
--   * action_specs_v1['PE10A_CT01'].status -> READY
--   * action_specs_v1['PE10A_CT01'].assertion_contract -> pass_when con 6 condiciones, entre ellas
--     independent_receipt_bound=true: pasar a READY NO cierra CT01; el cierre exige el recibo de otro agente.
-- No toca: el estado del checkpoint (sigue PENDING), otras especificaciones, funciones, permisos ni otras tablas.
-- No activa Profile Updater v0.2.

DO $mig$
DECLARE
 c_spec_before constant text := '5e33d3cc30bc6b829b4b3b00df3cee87';  -- md5(action_specs_v1->PE10A_CT01) vigente
 c_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 c_unit constant text := 'PE10A_CONTRACTS';
 c_cp   constant text := 'PE10A_CT01';
 v_exec text;
 v_wid bigint;
 v_meta jsonb;
 v_spec jsonb;
 v_rest_before text;
 v_rest_after text;
 v_contract jsonb;
 v_new_spec jsonb;
 v_status text;
 v_res jsonb;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10a_ct01_assertion_contract_ready_v1'
  AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10A_CT01_ASSERTION_TRAIN_TRANSPORT_REQUIRED'; END IF;

 SELECT u.work_item_id, u.unit_metadata INTO v_wid, v_meta
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code=c_plan AND u.unit_code=c_unit
 FOR UPDATE;
 IF v_wid IS NULL THEN RAISE EXCEPTION 'PE10A_CT01_ASSERTION_UNIT_MISSING'; END IF;

 v_spec := v_meta->'action_specs_v1'->c_cp;
 IF v_spec IS NULL OR md5(v_spec::text) <> c_spec_before
  THEN RAISE EXCEPTION 'PE10A_CT01_ASSERTION_PRESTATE_DRIFT_OR_ALREADY_APPLIED'; END IF;
 IF v_spec ? 'assertion_contract' THEN RAISE EXCEPTION 'PE10A_CT01_ASSERTION_ALREADY_PRESENT'; END IF;

 SELECT c.status INTO v_status FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_wid AND c.checkpoint_code=c_cp;
 IF v_status IS DISTINCT FROM 'PENDING' THEN RAISE EXCEPTION 'PE10A_CT01_ASSERTION_CHECKPOINT_NOT_PENDING'; END IF;

 -- huella de todo el plan de la unidad salvo la especificacion de CT01
 v_rest_before := md5((v_meta #- ARRAY['action_specs_v1',c_cp])::text);

 v_contract := jsonb_build_object(
   'mode','EXPLICIT_PASS_WHEN_SUBSET',
   'pass_when', jsonb_build_object(
     'frozen_inventory_matches_production', true,
     'falsifier_positive_passed', true,
     'falsifier_negative_executed', true,
     'independent_receipt_bound', true,
     'git_merged', true,
     'readback_passed', true));
 v_new_spec := jsonb_set(v_spec,'{status}','"READY"') || jsonb_build_object('assertion_contract',v_contract);

 UPDATE programacion.engineering_plan_units
    SET unit_metadata = jsonb_set(v_meta, ARRAY['action_specs_v1',c_cp], v_new_spec)
  WHERE plan_code=c_plan AND unit_code=c_unit;

 -- post-estado
 SELECT unit_metadata INTO v_meta FROM programacion.engineering_plan_units WHERE plan_code=c_plan AND unit_code=c_unit;
 v_rest_after := md5((v_meta #- ARRAY['action_specs_v1',c_cp])::text);
 IF v_rest_after <> v_rest_before THEN RAISE EXCEPTION 'PE10A_CT01_ASSERTION_OTHER_METADATA_CHANGED'; END IF;

 v_res := programacion.fn_engineering_action_spec_assertion_contract_v1(c_plan,c_unit,c_cp,v_meta->'action_specs_v1'->c_cp);
 -- La funcion oficial devuelve READY aunque falte pass_when (verificado: pass_when=null); por eso se exige aqui
 -- explicitamente que pass_when sea un objeto con las 6 condiciones, todas true.
 IF v_res->>'status' IS DISTINCT FROM 'READY' OR v_res->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
  OR jsonb_typeof(v_res->'pass_when') IS DISTINCT FROM 'object'
  OR (SELECT count(*) FROM jsonb_each(v_res->'pass_when')) <> 6
  OR EXISTS (SELECT 1 FROM jsonb_each(v_res->'pass_when') e WHERE e.value IS DISTINCT FROM 'true'::jsonb)
  THEN RAISE EXCEPTION 'PE10A_CT01_ASSERTION_POSTSTATE_CONTRACT_NOT_READY'; END IF;

 SELECT c.status INTO v_status FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_wid AND c.checkpoint_code=c_cp;
 IF v_status IS DISTINCT FROM 'PENDING' THEN RAISE EXCEPTION 'PE10A_CT01_ASSERTION_POSTSTATE_CHECKPOINT_CHANGED'; END IF;
END
$mig$;
