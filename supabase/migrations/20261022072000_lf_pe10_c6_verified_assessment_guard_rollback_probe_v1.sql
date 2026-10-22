-- PE10: material verification of the real PROFILE_ASSESSMENT receipt at step 35.
-- NO DURABLE v0.2 activation, NO method qualification or C6 PASS.
-- The temporary execution is a TRANSACTIONAL TEST FIXTURE, not an authority
-- receipt, certified provider execution, or production invocation.
-- DB apply exclusively via ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;
DO $pe10_c6$
DECLARE
  v_operation constant text := 'ACTUALIZACION_PERFIL_LF';
  v_exec constant text := 'EXEC-PE10-C6-REAL-RECEIPT-SUBTX-20261022-V1';
  v_actor constant text := 'EXEC-PE10-C6-TRANSACTIONAL-PROBE-NONAUTHORITY-V1';
  v_event_code constant text := 'PE10_C6.REAL_ASSESSMENT_GUARD_ROLLBACK_PROBE.V1';
  v_slug constant text := 'systemic_root_cause_repair_lf';
  v_receipt_id constant text := '9f758577-c9f6-4744-852b-a03827b466f6';
  v_subject_sha constant text := '692618756e551011b52487bc7091ed5f14f166c66f99f9ecea95619c0f5634fc';
  v_source_head constant text := '8dabb3a1bfd68dc90b78b09233000bce92d35ee9';
  v_policy jsonb;
  v_selector text;
  v_payload jsonb;
  v_reply jsonb;
  v_route jsonb;
  v_result text;
  v_count integer;
  v_event_id bigint;
  v_audit jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_event_code)
    OR EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_exec)
  THEN RAISE EXCEPTION 'PE10_C6_PROBE_DUPLICATE'; END IF;
  IF (SELECT version FROM public.lf_operation_registry WHERE operation_code=v_operation)
       IS DISTINCT FROM 'v0.1'
    OR (SELECT count(*) FROM public.lf_operation_steps
        WHERE operation_code=v_operation AND active)<>15
    OR (SELECT count(*) FROM public.lf_operation_steps
        WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
          AND required AND NOT active)<>2
    OR (SELECT c.status
        FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
        WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
          AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C6') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'PE10_C6_PRESTATE_CHANGED'; END IF;
  SELECT policy_payload INTO v_policy FROM public.lf_policy_versions
    WHERE policy_code='POL-PROFILE-UPDATE-PASS'
      AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE';
  IF v_policy IS NULL
    OR jsonb_array_length(v_policy->'required_steps')<>17
    OR jsonb_array_length(v_policy#>'{required_steps_by_outcome,NO_CHANGE}')<>10
    OR coalesce((v_policy->>'activation_authorized')::boolean,true)
  THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_POLICY_NOT_CURRENT'; END IF;
  SELECT version INTO v_selector FROM public.lf_capability_current
    WHERE capability_code='CAPABILITY_SELECTOR';
  IF v_selector IS DISTINCT FROM '1.0.0'
    OR NOT EXISTS (
      SELECT 1 FROM private.lf_evidence_ledger_v1
      WHERE receipt_id=v_receipt_id::uuid
        AND subject_type='PROFILE_ASSESSMENT'
        AND subject_ref=v_slug AND subject_sha256=v_subject_sha
        AND source_head_sha=v_source_head AND verification_state='VERIFIED'
    )
    OR NOT public.lf_profile_update_verified_receipt_v1(
      'PROFILE_ASSESSMENT',v_slug,v_receipt_id,v_subject_sha,v_source_head)
  THEN RAISE EXCEPTION 'PE10_C6_REAL_ASSESSMENT_NOT_VERIFIED'; END IF;
  v_payload := jsonb_build_object(
    'profile_slug',v_slug,'source_head_sha',v_source_head,
    'profile_assessment_receipt_id',v_receipt_id,
    'profile_assessment_sha256',v_subject_sha,
    'selector_version',v_selector,'selected_methods','[]'::jsonb,
    'no_additional_method_needed',true,
    'empty_selection_reason','S26_STRUCTURAL_BINDINGS_PATCH',
    'method_execution_permitted',false
  );

  -- PostgreSQL PL/pgSQL exception subtransaction rolls back ALL actor and
  -- init-step effects after the actual deployed begin RPC and guard calls.
  BEGIN
    -- A fully isolated subtransaction temporarily stages the candidate state.
    -- Other sessions never see this uncommitted state; the intentional
    -- exception below reverses all policy, step and execution changes.
    UPDATE public.lf_policy_versions SET status='CANDIDATE'
      WHERE policy_code='POL-PROFILE-UPDATE-PASS'
        AND policy_version='v1.1' AND status='ACTIVE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'PE10_C6_ACTIVE_POLICY_NOT_UNIQUE'; END IF;
    UPDATE public.lf_policy_versions SET status='ACTIVE'
      WHERE policy_code='POL-PROFILE-UPDATE-PASS'
        AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_POLICY_NOT_UNIQUE'; END IF;
    UPDATE public.lf_operation_steps SET active=true
      WHERE operation_code=v_operation
        AND step_id IN ('method_selection','evolution_decision')
        AND required AND NOT active;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_STAGED_STEPS_NOT_EXACT'; END IF;
    UPDATE public.lf_operation_step_contracts SET status='ACTIVE_ENFORCEMENT'
      WHERE operation_code=v_operation
        AND step_id IN ('method_selection','evolution_decision')
        AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_STAGED_CONTRACTS_NOT_EXACT'; END IF;
    UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT'
      WHERE operation_code=v_operation
        AND step_id IN ('method_selection','evolution_decision')
        AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_STAGED_BINDINGS_NOT_EXACT'; END IF;

    SELECT public.lf_profile_update_begin_v1(
      v_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'cristhianlujan/claude-persona-lf-patch',
      'profiles/systemic_root_cause_repair_lf',
      repeat('c',64),'pe10-c6-real-assessment-subtx-20261022-v1',
      v_actor,
      jsonb_build_object(
        'transactional_probe_only',true,
        'production_authorized',false,
        'initial_main_revision',v_source_head,
        'operation_policy_snapshots',jsonb_build_object(
          'PASS_POLICY',jsonb_build_object('policy_payload',v_policy)
        )
      )
    ) INTO v_reply;
    IF v_reply->>'init_step' IS DISTINCT FROM 'RECORDED'
      OR (SELECT status FROM public.lf_operation_execution
          WHERE execution_id=v_exec) IS DISTINCT FROM 'IN_PROGRESS'
      OR NOT EXISTS (
        SELECT 1 FROM public.lf_operation_execution_steps
        WHERE execution_id=v_exec AND step_id='init_execution'
      )
    THEN RAISE EXCEPTION 'PE10_C6_ACTUAL_BEGIN_RPC_FAILED:%',v_reply; END IF;

    SELECT public.lf_profile_update_evolution_step_guard_v1(
      v_exec,'method_selection',v_payload) INTO v_result;
    IF v_result IS NOT NULL
    THEN RAISE EXCEPTION 'PE10_C6_REAL_RECEIPT_POSITIVE_GUARD_FAILED:%',v_result; END IF;

    SELECT public.lf_profile_update_evolution_step_guard_v1(
      v_exec,'method_selection',v_payload-'empty_selection_reason') INTO v_result;
    IF v_result IS DISTINCT FROM 'EVOLUTION_EMPTY_METHOD_UNJUSTIFIED'
    THEN RAISE EXCEPTION 'PE10_C6_MISSING_EMPTY_REASON_NOT_REJECTED:%',v_result; END IF;
    SELECT public.lf_profile_update_evolution_step_guard_v1(
      v_exec,'method_selection',v_payload||jsonb_build_object(
        'method_execution_permitted',true)) INTO v_result;
    IF v_result IS DISTINCT FROM 'EVOLUTION_SELECTION_ILLEGAL_EXECUTION_PERMISSION'
    THEN RAISE EXCEPTION 'PE10_C6_ILLEGAL_METHOD_AUTH_NOT_REJECTED:%',v_result; END IF;
    SELECT public.lf_profile_update_evolution_step_guard_v1(
      v_exec,'method_selection',v_payload||jsonb_build_object(
        'source_head_sha',repeat('0',40))) INTO v_result;
    IF v_result IS DISTINCT FROM 'EVOLUTION_SOURCE_REVISION_MISMATCH'
    THEN RAISE EXCEPTION 'PE10_C6_STALE_SOURCE_NOT_REJECTED:%',v_result; END IF;
    SELECT public.lf_profile_update_evolution_step_guard_v1(
      v_exec,'method_selection',v_payload||jsonb_build_object(
        'profile_assessment_receipt_id','00000000-0000-0000-0000-000000000000')) INTO v_result;
    IF v_result IS DISTINCT FROM 'EVOLUTION_PROFILE_ASSESSMENT_NOT_VERIFIED'
    THEN RAISE EXCEPTION 'PE10_C6_INVALID_RECEIPT_NOT_REJECTED:%',v_result; END IF;
    SELECT public.lf_profile_update_evolution_step_guard_v1(
      v_exec,'evolution_decision',v_payload||jsonb_build_object(
        'decision','UPDATE','evolution_mode','PATCH',
        'decision_evidence_ref','github://case/pe10-c6-test',
        'github_write_permitted',false)) INTO v_result;
    IF v_result IS DISTINCT FROM 'EVOLUTION_SELECTION_STEP_NOT_CLEAN'
    THEN RAISE EXCEPTION 'PE10_C6_UNRECORDED_SELECTION_NOT_REJECTED:%',v_result; END IF;
    SELECT public.lf_profile_update_effective_route_v1(v_exec) INTO v_route;
    IF v_route->>'outcome' IS DISTINCT FROM 'AWAITING_EVOLUTION_DECISION'
      OR jsonb_array_length(v_route->'effective_steps')<>6
    THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_PREFIX_ROUTE_INVALID:%',v_route; END IF;
    RAISE EXCEPTION 'PE10_C6_EXPECTED_SUBTRANSACTION_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'PE10_C6_EXPECTED_SUBTRANSACTION_ROLLBACK' THEN RAISE; END IF;
  END;

  IF EXISTS (SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_exec)
     OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps WHERE execution_id=v_exec)
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
           AND NOT active)<>2
     OR (SELECT count(*) FROM public.lf_operation_execution
         WHERE operation_code=v_operation AND status='IN_PROGRESS')<>0
     OR (SELECT count(*) FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS'
           AND policy_version='v1.1' AND status='ACTIVE')<>1
     OR (SELECT count(*) FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS'
           AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE')<>1
     OR (SELECT count(*) FROM public.lf_operation_step_contracts
         WHERE operation_code=v_operation
           AND step_id IN ('method_selection','evolution_decision')
           AND status='CANDIDATE')<>2
     OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings
         WHERE operation_code=v_operation
           AND step_id IN ('method_selection','evolution_decision')
           AND status='CANDIDATE')<>2
  THEN RAISE EXCEPTION 'PE10_C6_TRANSACTIONAL_RESIDUE'; END IF;

  -- Durable evidence of a bounded guard test ONLY. Not a C6 acceptance receipt.
  v_audit := jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'acceptance_declared',false,
    'execution_id',v_actor,
    'producer','LF_MIGRATION_TRAIN_PE10_C6_GUARD_PROBE',
    'occurred_at',clock_timestamp(),
    'plan_code','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1',
    'checkpoint_code','PE10_C6',
    'profile_slug',v_slug,
    'profile_assessment_receipt_id',v_receipt_id,
    'profile_assessment_sha256',v_subject_sha,
    'source_head_sha',v_source_head,
    'guard_real_receipt_empty_selection_pass',true,
    'negative_guard_cases',jsonb_build_array(
      'EMPTY_REASON','METHOD_PERMISSION','STALE_SOURCE','UNVERIFIED_RECEIPT',
      'DECISION_WITHOUT_RECORDED_SELECTION','AWAITING_EVOLUTION_DECISION_PREFIX'),
    'temporary_candidate_policy_and_steps_staged',true,
    'transactional_rollback_verified',true,
    'positive_recorder_and_route_verified',false,
    'checkpoint_pass',false,
    'cutover_admitted',false,'production_activation',false
  );
  IF private.fn_lf_event_acceptance_signal_v2(
    'ARTIFACT_RECONCILED',v_event_code,
    'PE10_C6 real receipt guard rollback rehearsal; no v0.2 cutover',v_audit
  ) IS NOT NULL
  THEN RAISE EXCEPTION 'PE10_C6_FALSE_CLOSURE_SIGNAL'; END IF;
  INSERT INTO public.lf_eventos (
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
    origen,created_by_execution_id,payload
  ) VALUES (
    'ARTIFACT_RECONCILED','PROGRAM_PLAN',v_event_code,
    'PE10_C6 real assessment guard positive/negative and rollback; route/recorder still pending',
    'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_audit
  ) RETURNING id INTO v_event_id;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_eventos
    WHERE id=v_event_id AND payload->>'checkpoint_pass'='false'
      AND payload->>'transactional_rollback_verified'='true'
      AND payload->>'positive_recorder_and_route_verified'='false'
  )
    OR (SELECT version FROM public.lf_operation_registry
        WHERE operation_code=v_operation)<>'v0.1'
    OR (SELECT status FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
        WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
          AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C6')<>'PENDING'
  THEN RAISE EXCEPTION 'PE10_C6_POSTPROBE_READBACK_FAILED'; END IF;
END $pe10_c6$;
COMMIT;
