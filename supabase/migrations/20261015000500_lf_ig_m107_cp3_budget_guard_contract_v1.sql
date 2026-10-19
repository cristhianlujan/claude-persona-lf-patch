-- M10.7 CP3: fail-closed contract correction + EKB. NO CP3 completion.
-- One bounded engineering unit, Train only; no runtime/production/grants.
-- Read-only diagnosis: M9.11 cohort since 2026-10-07, 17 COMPLETED,
-- 6 validator_duration_ms > 150000, 5 duration=0, 0 explicit TIMEOUT.
-- This is NOT a frozen post-cutover observation window or qualifying PASS.
-- CP3 authored artifact in the same PR:
-- sandbox/lf_contract_gate_test/engineering_checkpoints/m10_7/no_false_pass.py
DO $ig_m107_cp3$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 u constant text := 'M10.7';
 w constant bigint := 478;
 v_before jsonb;
 v_after jsonb;
 v_current_exit text;
 v_old_spec jsonb;
 v_new_pass_when jsonb;
 v_new_spec jsonb;
 v_contract jsonb;
 v_trial integer;
 v_obs integer;
 v_over integer;
 v_unknown integer;
 v_explicit_timeout integer;
BEGIN
 SELECT unit_metadata,exit_criterion INTO STRICT v_before,v_current_exit
 FROM programacion.engineering_plan_units
 WHERE plan_code=p AND unit_code=u AND work_item_id=w AND disposition='ASSIGNED';
 v_old_spec:=v_before#>'{action_specs_v1,NO_FALSE_PASS}';
 IF v_old_spec->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
 OR (v_old_spec->>'requires_material_execution')::boolean IS DISTINCT FROM true
 OR v_old_spec#>>'{test_execution_contract,canonical_exit_criterion}'
    NOT LIKE 'Soak post-cutover con umbrales%'
 OR (v_before#>'{action_specs_v1,NO_FALSE_PASS,assertion_contract,pass_when}')
    IS DISTINCT FROM
    '{"test_passed":true,"test_exit_code":0,"semantic_authority_bound":true,"adversarial_case_executed":true}'::jsonb
 OR v_current_exit NOT LIKE 'Soak por suficiencia de observación conforme M9.11%'
 THEN RAISE EXCEPTION 'M107_CP3_EXPLICIT_CONTRACT_UNEXPECTED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=w)<>'IN_PROGRESS'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=w AND status='DONE')<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=w AND status='PENDING')<>3
 OR (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=w AND checkpoint_code='NO_FALSE_PASS')<>'PENDING'
 OR programacion.fn_engineering_effective_open_blocker_count_v1(w)<>0
 OR EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(w) d
           WHERE d.is_unmet)
 THEN RAISE EXCEPTION 'M107_CP3_EXPECTED_45_PERCENT_CHANGED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_router_action_registry
    WHERE operation_code='ACTUALIZACION_DB_LF' AND asset_type='MIGRATION'
      AND action_code='UPDATE' AND status='ACTIVE' AND write_allowed)
 THEN RAISE EXCEPTION 'M107_CP3_TRAIN_ROUTE_NOT_AUTHORIZED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.provenance_receipts
   WHERE id=38 AND receipt_kind='EVIDENCE_VERIFICATION'
     AND payload->>'schema_version'='SOAK_OBSERVATION_HISTORY_V2'
     AND payload->>'verification_status'='VERIFIED' AND payload->>'pass'='true')
 THEN RAISE EXCEPTION 'M107_CP3_HISTORICAL_RECEIPT_MISSING'; END IF;
 WITH cohort(id) AS (
   VALUES (1),(2),(3),(5),(43),(51),(52),(53),(54),(55),(56),(57),(58)
 ), observed AS (
   SELECT r.* FROM programacion.input_readiness_runs r
   JOIN cohort c ON c.id=r.pantalla_id
   WHERE r.created_at>='2026-10-07'::timestamptz
 ) SELECT count(*)::int,
          count(*) filter(where validator_duration_ms>150000)::int,
          count(*) filter(where validator_duration_ms is null or validator_duration_ms<=0)::int,
          count(*) filter(where status ilike '%timeout%'
              or coalesce(blocked_reason,'')~*'(timeout|57014|timed.out)')::int
 INTO v_obs,v_over,v_unknown,v_explicit_timeout FROM observed;
 IF v_obs<17 OR v_over<6 OR v_unknown<5
 THEN RAISE EXCEPTION 'M107_CP3_NEGATIVE_LIVE_DIAGNOSTIC_DRIFT: obs %,over %,missing %',v_obs,v_over,v_unknown; END IF;
 v_new_pass_when:=(v_old_spec#>'{assertion_contract,pass_when}')||
   jsonb_build_object('budget_breach_count',0,'unmeasured_duration_count',0,
     'timeout_signal_count',0,'known_false_pass_signals',0,
     'unresolved_d4',0,'frozen_window_verified',true);
 FOR v_trial IN 1..2 LOOP
   BEGIN
     UPDATE programacion.engineering_plan_units
     SET unit_metadata=jsonb_set(
          jsonb_set(
            jsonb_set(unit_metadata,
              '{action_specs_v1,NO_FALSE_PASS,assertion_contract,pass_when}',
              v_new_pass_when,true),
            '{action_specs_v1,NO_FALSE_PASS,test_execution_contract,canonical_exit_criterion}',
            to_jsonb(v_current_exit),true),
          '{m107_cp3_diagnostic_v1}',
          jsonb_build_object(
            'kind','NONTERMINAL_READ_ONLY_DIAGNOSTIC',
            'source','programacion.input_readiness_runs',
            'historical_receipt','supabase://programacion.provenance_receipts/38',
            'diagnostic_since','2026-10-07',
            'observed_runs',v_obs,'over_150s',v_over,'duration_unknown',v_unknown,
            'explicit_timeout_signals',v_explicit_timeout,
            'budget_guard','FAIL_CLOSED_WHEN_OVER_150S',
            'window_frozen',false,
            'material_checkpoint_pass',false),true)
     WHERE plan_code=p AND unit_code=u AND work_item_id=w
       AND unit_metadata=v_before;
     IF NOT FOUND THEN RAISE EXCEPTION 'M107_CP3_SCOPE_UPDATE_MISSED'; END IF;
     v_new_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(p,u,'NO_FALSE_PASS');
     v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
       p,u,'NO_FALSE_PASS',v_new_spec);
     IF v_new_spec->>'status' IS DISTINCT FROM 'READY'
      OR v_new_spec->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
      OR (v_new_spec->>'requires_material_execution')::boolean IS DISTINCT FROM true
      OR v_new_spec#>>'{test_execution_contract,canonical_exit_criterion}' IS DISTINCT FROM v_current_exit
      OR v_contract->>'status' IS DISTINCT FROM 'READY'
      OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
      OR v_contract->'pass_when' IS DISTINCT FROM v_new_pass_when
     THEN RAISE EXCEPTION 'M107_CP3_NEW_CONTRACT_FAILED_READBACK'; END IF;
     -- The observed live diagnostic MUST NOT match a passing machine assertion.
     IF (jsonb_build_object('test_passed',false,'test_exit_code',2,
          'semantic_authority_bound',true,'adversarial_case_executed',true,
          'budget_breach_count',v_over,'unmeasured_duration_count',v_unknown,
          'timeout_signal_count',v_explicit_timeout,'known_false_pass_signals',0,
          'unresolved_d4',0,'frozen_window_verified',false)
          @> (v_contract->'pass_when')) IS DISTINCT FROM false
     THEN RAISE EXCEPTION 'M107_CP3_NEGATIVE_WRONGLY_ADMITTED'; END IF;
     IF (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=w AND checkpoint_code='NO_FALSE_PASS')<>'PENDING'
       OR EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
                 WHERE work_item_id=w AND checkpoint_code='NO_FALSE_PASS'
                   AND assertion_receipt_sha256 IS NOT NULL)
     THEN RAISE EXCEPTION 'M107_CP3_FORGED_CHECKPOINT_PROGRESS'; END IF;
     IF v_trial=1 THEN
       RAISE EXCEPTION 'M107_CP3_ROLLBACK_SENTINEL' USING ERRCODE='PZ109';
     END IF;
   EXCEPTION WHEN SQLSTATE 'PZ109' THEN
     IF v_trial<>1 THEN RAISE; END IF;
   END;
   IF v_trial=1 AND (SELECT unit_metadata FROM programacion.engineering_plan_units
                      WHERE plan_code=p AND unit_code=u) IS DISTINCT FROM v_before
   THEN RAISE EXCEPTION 'M107_CP3_ROLLBACK_RESIDUE'; END IF;
 END LOOP;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=w AND status='DONE')<>2
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=w AND status='PENDING')<>3
 THEN RAISE EXCEPTION 'M107_CP3_STATE_MUST_STAY_45'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
           WHERE codigo='IG-M107-CP3-SOAK-TIMING-DRIFT-001')
 THEN RAISE EXCEPTION 'M107_CP3_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(
   id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
   validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
   estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
   detectability,source_context,source_ref)
 VALUES (
   gen_random_uuid(),'IG-M107-CP3-SOAK-TIMING-DRIFT-001','GOVERNANCE',
   'CP3 heredó criterio antiguo y confundía estado COMPLETED con presupuesto de tiempo',
   'En la cohorte M9.11 desde 2026-10-07 se observan 17 ejecuciones COMPLETED, 6 con validator_duration_ms>150000 (832-836,932) y 5 con duración 0; no hay TIMEOUT explícito. Recibo M9.11 histórico no certifica una nueva ventana live CP3. El contrato material aún apuntaba a exit_criterion anterior.',
   'Falta de vinculación de criterio de performance/currentness de CP3 con evidencia actual y regla de 150s; el campo status COMPLETED no implica presupuesto cumplido.',
   'SOAK_MATERIAL_PASS_FROM_STALE_EXIT_CRITERION_AND_UNMEASURED_TIMING',
   'Conservar el presupuesto <=150000 ms. Rechazar duraciones desconocidas, cualquier >150000 y timeout explícito, distinguir sus causas. Exigir ventana operativa congelada y aserción canónica derivada de ejecución real. No promover una muestra histórica ni dar PASS por pruebas locales.',
   'Read-only cohort 17 complete, 6 over budget, 5 zero, 0 timeout explicit. Prueba de 7 casos lógica positiva/negativa. Guard material ampliado para rechazar el estado actual. Checkpoint CP3 conserva PENDING y avance 45%.',
   'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
   'VALIDATED_TESTED','supabase://programacion.input_readiness_runs/932;github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/engineering_checkpoints/m10_7/no_false_pass.py',
   now(),now(),'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
   'M10.7 CP3 source-metadata version plus real bounded RO diagnostic',
   'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7'
 );
END
$ig_m107_cp3$;
