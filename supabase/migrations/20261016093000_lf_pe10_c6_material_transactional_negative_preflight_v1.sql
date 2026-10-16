-- PE10_C6: material DB transactional preflight via LF Migration Merge Train.
-- Tests the real candidate row/readback, guard's negative path, and exact
-- rollback of a test audit insert. DOES NOT fabricate the missing positive
-- provider-qualified execution, transition PE10_C6, or activate v0.2.
BEGIN;
DO $pe10_c6$
DECLARE
 v_op constant text := 'ACTUALIZACION_PERFIL_LF';
 v_actor constant text := 'EXEC-PE10C6-MATERIAL-TX-PROBE-20261016-V1';
 v_audit constant text := 'PE10_C6.MATERIAL_TX_PREFLIGHT_PREACTIVATION.V1';
 v_rollback constant text := 'PE10_C6.MATERIAL_TX_ROLLBACK_SENTINEL.V1';
 v_missing constant text := 'PE10-C6-NONEXISTENT-EXECUTION-NEGATIVE-20261016';
 v_policy jsonb;
 v_policy_sha text;
 v_negative_guard text;
 v_negative_route jsonb;
 v_negative_receipt boolean;
 v_steps int;
 v_contracts int;
 v_bindings int;
 v_judges int;
 v_count int;
 v_payload jsonb;
 v_event bigint;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_eventos WHERE entidad_codigo IN(v_audit,v_rollback))
 THEN RAISE EXCEPTION 'PE10_C6_PREFLIGHT_REPLAY_CONFLICT'; END IF;
 IF (SELECT version FROM public.lf_operation_registry WHERE operation_code=v_op)
    IS DISTINCT FROM 'v0.1'
 OR (SELECT status FROM programacion.engineering_work_checkpoints c
   JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
   WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
     AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C6') IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'PE10_C6_AUTHORITY_PRESTATE_CHANGED'; END IF;
 IF (SELECT count(*) FROM private.lf_event_type_contracts_v2
     WHERE event_type='ARTIFACT_RECONCILED' AND active AND contract_mode='OPERATIONAL')<>1
 THEN RAISE EXCEPTION 'PE10_C6_AUDIT_CONTRACT_NOT_GOVERNED'; END IF;
 SELECT policy_payload,policy_sha INTO v_policy,v_policy_sha
 FROM public.lf_policy_versions
 WHERE policy_code='POL-PROFILE-UPDATE-PASS'
 AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE';
 IF v_policy IS NULL OR v_policy_sha !~ '^[0-9a-f]{64}$'
    OR v_policy->'required_steps_before_decision' IS DISTINCT FROM
      '["init_execution","router","profile_resolve","baseline_read","method_selection","evolution_decision"]'::jsonb
    OR jsonb_array_length(v_policy#>'{required_steps_by_outcome,UPDATE}')<>17
    OR jsonb_array_length(v_policy#>'{required_steps_by_outcome,NO_CHANGE}')<>10
    OR coalesce((v_policy->>'activation_authorized')::boolean,true)
 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_POLICY_NOT_FROZEN'; END IF;
 SELECT count(*)::int INTO v_steps FROM public.lf_operation_steps
 WHERE operation_code=v_op AND step_id IN('method_selection','evolution_decision')
 AND required AND NOT active;
 SELECT count(*)::int INTO v_contracts FROM public.lf_operation_step_contracts
 WHERE operation_code=v_op AND step_id IN('method_selection','evolution_decision')
 AND status='CANDIDATE';
 SELECT count(*)::int INTO v_bindings FROM public.lf_operation_step_judge_bindings
 WHERE operation_code=v_op AND step_id IN('method_selection','evolution_decision')
 AND status='CANDIDATE';
 SELECT count(*)::int INTO v_judges FROM public.lf_operation_judges
 WHERE operation_code=v_op
 AND judge_code IN('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION')
 AND status='CANDIDATO_READ_ONLY';
 IF v_steps<>2 OR v_contracts<>2 OR v_bindings<>2 OR v_judges<>2
 THEN RAISE EXCEPTION 'PE10_C6_STAGED_COMPONENTS_NOT_EXACT:%,%,%,%',
 v_steps,v_contracts,v_bindings,v_judges; END IF;

 -- Negative probes are executed by the real deployed functions, not mocks.
 SELECT public.lf_profile_update_evolution_step_guard_v1(
 v_missing,'method_selection','{}'::jsonb) INTO v_negative_guard;
 IF v_negative_guard IS DISTINCT FROM 'EVOLUTION_OPERATION_CONTEXT_INVALID'
 THEN RAISE EXCEPTION 'PE10_C6_NEGATIVE_GUARD_FAILED:%',v_negative_guard; END IF;
 SELECT public.lf_profile_update_effective_route_v1(v_missing)
 INTO v_negative_route;
 IF v_negative_route->>'outcome' IS DISTINCT FROM 'BLOCKED'
    OR v_negative_route->>'code' IS DISTINCT FROM 'PROFILE_UPDATE_EXECUTION_UNRESOLVED'
 THEN RAISE EXCEPTION 'PE10_C6_NEGATIVE_ROUTE_FAILED:%',v_negative_route; END IF;
 SELECT public.lf_profile_update_verified_receipt_v1(
  'PROFILE_ASSESSMENT','systemic_root_cause_repair_lf',
  'PE10-C6-MISSING-RECEIPT-NEGATIVE',repeat('0',64),repeat('0',40))
 INTO v_negative_receipt;
 IF v_negative_receipt IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'PE10_C6_UNVERIFIED_RECEIPT_ACCEPTED'; END IF;

 v_payload:=jsonb_build_object(
  'evidence_schema_version','operational-event/v2',
  'acceptance_declared',false,
  'execution_id',v_actor,'producer','LF_MIGRATION_TRAIN_PE10_C6_MATERIAL',
  'occurred_at',clock_timestamp(),
  'purpose','Material v0.2 candidate readback, negative guard verification and rollback test',
  'plan_code','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1',
  'checkpoint_code','PE10_C6',
  'candidate_policy_sha256',v_policy_sha,
  'positive_candidate_structure_verified',true,
  'candidate_steps_inactive_count',v_steps,
  'candidate_contracts_count',v_contracts,
  'candidate_judge_bindings_count',v_bindings,
  'candidate_judges_count',v_judges,
  'negative_guard_rejections_observed',jsonb_build_array('CONTEXT_INVALID','ROUTE_BLOCKED','RECEIPT_UNVERIFIED'),
  'negative_guard_observed',v_negative_guard,
  'negative_route_observed',v_negative_route,
  'invalid_receipt_rejected',true,
  'source_test_receipt_sha256','2847cb4d960135b0e490180fa5e50dbefae1236f9cb04bf992c385dd284f2f22',
  'source_test_count',55,
  'material_gpt_capture_sha256','944eaa1ce1d7c10ccd80f2f6e1153d657a523ecba875284a8b51a20d4644795a',
  'transactional_rollback_verified',true,
  'positive_provider_qualified_execution_verified',false,
  'checkpoint_pass',false,
  'cutover_admitted',false,
  'production_activation',false);

 -- Exercise the same event write used for durable proof; force rollback of
 -- the nested subtransaction, inspect absence, then write only audit proof.
 BEGIN
   INSERT INTO public.lf_eventos
    (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
     origen,created_by_execution_id,payload)
   VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_rollback,
     'PE10_C6_EXPECTED_ROLLBACK_ONLY','INFO','DERIVE_FROM_EXECUTION_ID',
     v_actor,v_payload);
   IF (SELECT count(*) FROM public.lf_eventos WHERE entidad_codigo=v_rollback)<>1
   THEN RAISE EXCEPTION 'PE10_C6_PROBE_WRITE_NOT_SEEN'; END IF;
   RAISE EXCEPTION 'PE10_C6_EXPECTED_NESTED_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   IF SQLERRM<>'PE10_C6_EXPECTED_NESTED_ROLLBACK' THEN RAISE; END IF;
 END;
 SELECT count(*)::int INTO v_count FROM public.lf_eventos
 WHERE entidad_codigo=v_rollback;
 IF v_count<>0 THEN RAISE EXCEPTION 'PE10_C6_ROLLBACK_RESIDUE'; END IF;

 IF private.fn_lf_event_acceptance_signal_v2(
   'ARTIFACT_RECONCILED',v_audit,
   'PE10_C6 scoped transaction preflight, cutover not admitted',v_payload)
   IS NOT NULL
 THEN RAISE EXCEPTION 'PE10_C6_FALSE_ADMISSION_SIGNAL'; END IF;
 INSERT INTO public.lf_eventos
 (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
 origen,created_by_execution_id,payload)
 VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_audit,
 'PE10_C6: material transactional readback, negative gates, rollback PASS; execution gate still pending',
 'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload)
 RETURNING id INTO v_event;
 IF NOT EXISTS(
 SELECT 1 FROM public.lf_eventos WHERE id=v_event
 AND payload->>'transactional_rollback_verified'='true'
 AND payload->>'positive_provider_qualified_execution_verified'='false'
 AND payload->>'checkpoint_pass'='false'
 AND payload->>'cutover_admitted'='false')
 OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_rollback)
 OR (SELECT status FROM programacion.engineering_work_checkpoints c
   JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
   WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
     AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C6')<>'PENDING'
 OR (SELECT version FROM public.lf_operation_registry
     WHERE operation_code=v_op)<>'v0.1'
 THEN RAISE EXCEPTION 'PE10_C6_DURABLE_AUDIT_READBACK_FAILED'; END IF;
END $pe10_c6$;
COMMIT;
