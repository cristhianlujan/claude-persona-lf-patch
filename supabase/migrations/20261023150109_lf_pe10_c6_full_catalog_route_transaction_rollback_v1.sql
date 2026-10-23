-- LF PE10_C6: real registry v0.2 + frozen conditional routing rehearsed
-- in PostgreSQL and reverted without production cutover.
-- This extends proven 35/37 recorder tests from migration 20261022094354;
-- every temporary write occurs inside EXCEPTION subtransaction.
-- The prefix router/profile/baseline steps remain explicitly synthetic
-- rollback-only fixtures; NO provider E2E receipt and NO C6 closure claimed.
-- Database writes only via ACTUALIZACION_DB_LF -> Merge Train.
BEGIN;
DO $pe10_c6_recorder$
DECLARE
  v_operation constant text := 'ACTUALIZACION_PERFIL_LF';
  v_actor constant text := 'EXEC-PE10-C6-FULL-V02-CATALOG-SUBTX-V1';
  v_event_code constant text := 'PE10_C6.FULL_CATALOG_ROUTE_REVERSIBLE_V02.V1';
  v_slug constant text := 'systemic_root_cause_repair_lf';
  v_receipt constant text := '9f758577-c9f6-4744-852b-a03827b466f6';
  v_subject_sha constant text := '692618756e551011b52487bc7091ed5f14f166c66f99f9ecea95619c0f5634fc';
  v_head constant text := '8dabb3a1bfd68dc90b78b09233000bce92d35ee9';
  v_selector text;
  v_policy jsonb;
  v_exec text;
  v_mode text;
  v_payload jsonb;
  v_decision jsonb;
  v_result jsonb;
  v_route jsonb;
  v_audit jsonb;
  v_count integer;
  v_event_id bigint;
  v_expected_error text;
  v_expected_count integer;
  v_guard_error text;
BEGIN
  IF position('lf_profile_update_evolution_step_guard_v1' in
      pg_get_functiondef('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure))=0
    OR position('lf_profile_update_effective_route_v1' in
      pg_get_functiondef('public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text)'::regprocedure))=0
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_INTEGRATION_NOT_MATERIAL'; END IF;

  SELECT policy_payload INTO v_policy FROM public.lf_policy_versions
    WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.4-evolved-routing-candidate'
      AND status='CANDIDATE';
  SELECT version INTO v_selector FROM public.lf_capability_current
    WHERE capability_code='CAPABILITY_SELECTOR';
  IF v_policy IS NULL OR v_selector<>'1.0.0'
     OR jsonb_array_length(v_policy->'required_steps')<>17
     OR jsonb_array_length(v_policy#>'{required_steps_by_outcome,NO_CHANGE}')<>10
     OR NOT public.lf_profile_update_verified_receipt_v1('PROFILE_ASSESSMENT',v_slug,v_receipt,v_subject_sha,v_head)
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_POLICY_OR_RECEIPT_STALE'; END IF;

  -- Registry, policy, step status, and physical routing are test-only.
  -- The nested EXCEPTION SUBTRANSACTION must restore ALL originals.
  BEGIN
    UPDATE public.lf_operation_registry SET version='v0.2'
      WHERE operation_code=v_operation AND version='v0.1'
        AND status='PRODUCCION_CONTROLADA';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'PE10_C6_TEMP_V02_REGISTRY_NOT_EXACT'; END IF;
    UPDATE public.lf_operation_step_contracts SET next_if_pass='method_selection'
      WHERE operation_code=v_operation AND step_id='baseline_read'
        AND status='ACTIVE_ENFORCEMENT' AND next_if_pass='change_scope';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'PE10_C6_TEMP_30_TO_35_WIRING_NOT_EXACT'; END IF;
    -- The step-37 physical next_if_pass remains NULL by DESIGN.
    -- Its UPDATE next=40 and NO_CHANGE stop are resolved by the
    -- frozen policy + lf_profile_update_effective_route_v1, never by
    -- unconditional 37->40 wiring (which would break NO_CHANGE).
    IF NOT EXISTS (
      SELECT 1 FROM public.lf_operation_step_contracts
      WHERE operation_code=v_operation AND step_id='method_selection'
        AND next_if_pass='evolution_decision'
    ) OR NOT EXISTS (
      SELECT 1 FROM public.lf_operation_step_contracts
      WHERE operation_code=v_operation AND step_id='evolution_decision'
        AND next_if_pass IS NULL
    ) THEN RAISE EXCEPTION 'PE10_C6_35_37_PHYSICAL_WIRING_DRIFT'; END IF;
    UPDATE public.lf_policy_versions SET status='CANDIDATE'
     WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND policy_version='v1.1' AND status='ACTIVE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'PE10_C6_ACTIVE_POLICY_NOT_UNIQUE'; END IF;
    UPDATE public.lf_policy_versions SET status='ACTIVE'
     WHERE policy_code='POL-PROFILE-UPDATE-PASS'
       AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_POLICY_NOT_UNIQUE'; END IF;
    UPDATE public.lf_operation_steps SET active=true
     WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
       AND required AND NOT active;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_STEPS_NOT_EXACT'; END IF;
    UPDATE public.lf_operation_step_contracts SET status='ACTIVE_ENFORCEMENT'
     WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
       AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_CONTRACTS_NOT_EXACT'; END IF;
    UPDATE public.lf_operation_step_judge_bindings SET status='ACTIVE_ENFORCEMENT'
     WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
       AND status='CANDIDATE';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_BINDINGS_NOT_EXACT'; END IF;
    -- The step enforcement trigger requires ACTIVE_ENFORCEMENT judges,
    -- not merely active bindings. This activation is rollback-only.
    UPDATE public.lf_operation_judges SET status='ACTIVE_ENFORCEMENT'
     WHERE operation_code=v_operation
       AND judge_code IN ('JUDGE-PE10-V02-METHOD-SELECTION',
                          'JUDGE-PE10-V02-EVOLUTION-DECISION')
       AND status='CANDIDATO_READ_ONLY';
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>2 THEN RAISE EXCEPTION 'PE10_C6_CANDIDATE_JUDGES_NOT_EXACT'; END IF;

    FOREACH v_mode IN ARRAY ARRAY['UPDATE','NO_CHANGE'] LOOP
      v_exec := 'EXEC-PE10-C6-FULL-V02-SUBTX-'||v_mode||'-20261023-V1';
      SELECT public.lf_profile_update_begin_v1(
         v_exec,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
         'cristhianlujan/claude-persona-lf-patch',
         'profiles/systemic_root_cause_repair_lf',
         repeat('e',64),'pe10-c6-full-route-'||lower(v_mode)||'-20261022-v1',
         v_actor,
         jsonb_build_object('transactional_probe_only',true,
           'production_authorized',false,'initial_main_revision',v_head)
      ) INTO v_result;
      IF v_result->>'init_step' IS DISTINCT FROM 'RECORDED' THEN
        RAISE EXCEPTION 'PE10_C6_BEGIN_NOT_RECORDED:%',v_result; END IF;

      -- Fixture ONLY: prior three prefix steps are structurally clean within
      -- the rollback scope. This is NOT a real Router/provider pass receipt.
      INSERT INTO public.lf_operation_execution_steps(
        execution_id,step_order,step_id,status,evidence_ref,evidence_payload,
        notes,created_by_execution_id
      )
      SELECT v_exec,s.step_order,s.step_id,b.clean_result_value,
        'pe10-c6://rollback-only-prefix-fixture',
        CASE s.step_id
         WHEN 'router' THEN
           jsonb_build_object('router_read',true,'action','PROFILE_UPDATE')
         WHEN 'profile_resolve' THEN
           jsonb_build_object('codigo_activo','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
             'profile_slug',v_slug,'repo_path','profiles/'||v_slug,'exact_profile_resolved',true)
         WHEN 'baseline_read' THEN
           jsonb_build_object('baseline_revision',v_head,
             'baseline_files',jsonb_build_array('profiles/'||v_slug),
             'before_evidence',jsonb_build_object('fixture_only',true))
        END || jsonb_build_object(
          'assertions_checked','[]'::jsonb,'hard_fails_checked','[]'::jsonb,
          'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb,
          'mini_judge_result',b.clean_result_value,'recorded_by_rpc','PE10_C6_ROLLBACK_ONLY_FIXTURE',
          'fixture_not_provider_attestation',true),
        'Rollback-only synthetic prefix; no operational certification',v_actor
      FROM public.lf_operation_steps s
      JOIN public.lf_operation_step_judge_bindings b ON b.operation_code=s.operation_code
        AND b.step_id=s.step_id AND b.status='ACTIVE_ENFORCEMENT'
      WHERE s.operation_code=v_operation AND s.step_id IN ('router','profile_resolve','baseline_read');
      GET DIAGNOSTICS v_count=ROW_COUNT;
      IF v_count<>3 THEN RAISE EXCEPTION 'PE10_C6_PREFIX_FIXTURE_NOT_EXACT'; END IF;

      v_payload := jsonb_build_object(
        'profile_slug',v_slug,'source_head_sha',v_head,
        'profile_assessment_receipt_id',v_receipt,
        'profile_assessment_sha256',v_subject_sha,
        'selector_version',v_selector,'selected_methods','[]'::jsonb,
        'no_additional_method_needed',true,
        'empty_selection_reason','STRUCTURAL_BINDING_NO_METHOD_EXECUTION',
        'method_execution_permitted',false,
        'assertions_checked',jsonb_build_array(
          'verified_assessment','qualified_method_receipts_or_reasoned_empty',
          'current_selector','method_execution_permitted_false'),
        'hard_fails_checked','[]'::jsonb);

      -- Negative purity check: call the deterministic guard directly.
      -- A synthetic BLOCKED row would dispatch PRE_EKB_GATE as a real
      -- remediation and is not valid within this isolated test fixture.
      SELECT public.lf_profile_update_evolution_step_guard_v1(
         v_exec,'method_selection',v_payload-'empty_selection_reason')
         INTO v_guard_error;
      IF v_guard_error IS DISTINCT FROM 'EVOLUTION_EMPTY_METHOD_UNJUSTIFIED'
      THEN RAISE EXCEPTION 'PE10_C6_GUARD_MISSING_REASON_ACCEPTED:%',v_guard_error; END IF;
      SELECT public.lf_profile_update_evolution_step_guard_v1(
         v_exec,'method_selection',v_payload||jsonb_build_object(
           'profile_assessment_receipt_id','00000000-0000-0000-0000-000000000000'))
         INTO v_guard_error;
      IF v_guard_error IS DISTINCT FROM 'EVOLUTION_PROFILE_ASSESSMENT_NOT_VERIFIED'
      THEN RAISE EXCEPTION 'PE10_C6_GUARD_FALSE_ASSESSMENT_ACCEPTED:%',v_guard_error; END IF;

      SELECT public.lf_record_profile_operation_step_v1(
         v_exec,'method_selection','supabase://private/lf_evidence_ledger_v1/'||v_receipt,
         v_payload,v_actor) INTO v_result;
      IF v_result->>'outcome' <> 'STEP_RECORDED'
         OR v_result->>'status' <> 'STEP_PASS_WITH_EVIDENCE'
         OR v_result->>'resumed_from_blocked' <> 'false'
      THEN RAISE EXCEPTION 'PE10_C6_RECORDER_SELECTION_NOT_CLEAN:%',v_result; END IF;

      IF NOT EXISTS (
        SELECT 1 FROM public.lf_operation_execution_steps
        WHERE execution_id=v_exec AND step_id='method_selection'
          AND status='STEP_PASS_WITH_EVIDENCE'
          AND evidence_payload->>'recorded_by_rpc'='lf_record_profile_operation_step_v1'
          AND jsonb_array_length(evidence_payload->'attempt_history')=0
      ) THEN RAISE EXCEPTION 'PE10_C6_SELECTION_READBACK_FAILED'; END IF;

      v_decision := jsonb_build_object(
         'profile_slug',v_slug,'source_head_sha',v_head,
         'profile_assessment_receipt_id',v_receipt,
         'profile_assessment_sha256',v_subject_sha,
         'decision',v_mode,
         'evolution_mode',CASE WHEN v_mode='UPDATE' THEN 'PATCH' ELSE 'NO_CHANGE' END,
         'decision_evidence_ref','pe10-c6://rollback-only-decision-fixture',
         'github_write_permitted',false,
         'assertions_checked',jsonb_build_array('verified_assessment',
            'clean_method_selection','typed_decision_mode','frozen_route_consistency'),
         'hard_fails_checked','[]'::jsonb
      );
      v_expected_error := CASE WHEN v_mode='UPDATE'
        THEN 'EVOLUTION_UPDATE_MODE_INVALID' ELSE 'EVOLUTION_NO_CHANGE_MODE_INVALID' END;
      SELECT public.lf_profile_update_evolution_step_guard_v1(
        v_exec,'evolution_decision',
        v_decision||jsonb_build_object(
          'evolution_mode',CASE WHEN v_mode='UPDATE' THEN 'NO_CHANGE' ELSE 'PATCH' END))
        INTO v_guard_error;
      IF v_guard_error IS DISTINCT FROM v_expected_error
      THEN RAISE EXCEPTION 'PE10_C6_GUARD_DECISION_MISMATCH_ACCEPTED:%',v_guard_error; END IF;

      SELECT public.lf_record_profile_operation_step_v1(
        v_exec,'evolution_decision','pe10-c6://rollback-only-decision-fixture',
        v_decision,v_actor) INTO v_result;
      IF v_result->>'outcome' <> 'STEP_RECORDED'
         OR v_result->>'status' <> 'STEP_PASS_WITH_EVIDENCE'
         OR v_result->>'resumed_from_blocked'<>'false'
      THEN RAISE EXCEPTION 'PE10_C6_RECORDER_DECISION_NOT_CLEAN:%',v_result; END IF;

      SELECT public.lf_profile_update_effective_route_v1(v_exec) INTO v_route;
      IF NOT EXISTS(SELECT 1 FROM public.lf_operation_registry
          WHERE operation_code=v_operation AND version='v0.2')
        OR NOT EXISTS(SELECT 1 FROM public.lf_operation_step_contracts
          WHERE operation_code=v_operation AND step_id='baseline_read'
            AND next_if_pass='method_selection')
      THEN RAISE EXCEPTION 'PE10_C6_ROUTING_NOT_TESTED_AT_V02'; END IF;
      v_expected_count := CASE WHEN v_mode='UPDATE' THEN 17 ELSE 10 END;
      IF v_route->>'outcome' <> v_mode
         OR jsonb_array_length(v_route->'effective_steps') <> v_expected_count
      THEN RAISE EXCEPTION 'PE10_C6_EFFECTIVE_ROUTE_NOT_FROZEN:%',v_route; END IF;

      IF v_mode='UPDATE' AND NOT (v_route->'effective_steps' ? 'change_scope')
        THEN RAISE EXCEPTION 'PE10_C6_UPDATE_ROUTE_40_MISSING'; END IF;
      IF v_mode='NO_CHANGE' AND (v_route->'effective_steps' ? 'change_scope')
        THEN RAISE EXCEPTION 'PE10_C6_NO_CHANGE_ROUTE_40_LEAK'; END IF;
      IF v_mode='NO_CHANGE' THEN
        SELECT public.lf_record_profile_operation_step_v1(
          v_exec,'github_write','pe10-c6://forbidden-route-fixture',
          '{}'::jsonb,v_actor) INTO v_result;
        IF v_result->>'code'<>'PROFILE_UPDATE_STEP_NOT_ON_FROZEN_ROUTE'
           OR v_result->>'durable'<>'false'
        THEN RAISE EXCEPTION 'PE10_C6_NO_CHANGE_WRITE_ADMITTED:%',v_result; END IF;
      ELSE
        IF NOT (v_route->'effective_steps' ? 'github_write')
        THEN RAISE EXCEPTION 'PE10_C6_UPDATE_ROUTE_MISSING_GITHUB_WRITE'; END IF;
      END IF;
    END LOOP;
    RAISE EXCEPTION 'PE10_C6_EXPECTED_FULL_CATALOG_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'PE10_C6_EXPECTED_FULL_CATALOG_ROLLBACK' THEN RAISE; END IF;
  END;

  IF (SELECT version FROM public.lf_operation_registry
        WHERE operation_code=v_operation) IS DISTINCT FROM 'v0.1'
    OR (SELECT count(*) FROM public.lf_operation_step_contracts
        WHERE operation_code=v_operation AND step_id='baseline_read'
          AND next_if_pass='change_scope' AND status='ACTIVE_ENFORCEMENT')<>1
    OR EXISTS (SELECT 1 FROM public.lf_operation_execution
       WHERE execution_id LIKE 'EXEC-PE10-C6-FULL-V02-SUBTX-%-20261023-V1')
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code=v_operation AND active)<>15
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
           AND NOT active)<>2
     OR (SELECT count(*) FROM public.lf_operation_step_contracts
         WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
           AND status='CANDIDATE')<>2
     OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings
         WHERE operation_code=v_operation AND step_id IN ('method_selection','evolution_decision')
           AND status='CANDIDATE')<>2
     OR (SELECT count(*) FROM public.lf_operation_judges
         WHERE operation_code=v_operation AND judge_code IN
           ('JUDGE-PE10-V02-METHOD-SELECTION','JUDGE-PE10-V02-EVOLUTION-DECISION')
           AND status='CANDIDATO_READ_ONLY')<>2
     OR (SELECT count(*) FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS'
           AND policy_version='v1.1' AND status='ACTIVE')<>1
     OR (SELECT count(*) FROM public.lf_policy_versions
         WHERE policy_code='POL-PROFILE-UPDATE-PASS'
           AND policy_version='v1.4-evolved-routing-candidate' AND status='CANDIDATE')<>1
  THEN RAISE EXCEPTION 'PE10_C6_FULL_CATALOG_TRANSACTION_RESIDUE'; END IF;

  v_audit := jsonb_build_object(
     'evidence_schema_version','operational-event/v2',
     'producer','LF_MIGRATION_TRAIN_PE10_C6_FULL_CATALOG_PROBE',
     'purpose','Verify real v0.2 catalog and conditional step route in rollback-only Postgres trial',
     'execution_id',v_actor,'occurred_at',clock_timestamp(),
     'checkpoint_code','PE10_C6',
     'profile_slug',v_slug,
     'profile_assessment_receipt_id',v_receipt,
     'recorder_guard_integrated',true,
     'recorder_transactional_fixture_pass',true,
     'temporary_v02_registry_tested',true,
     'physical_30_to_35_wiring_tested',true,
     'step_37_conditional_40_update_tested',true,
     'no_change_skips_40_tested',true,
     'recorder_fixture_synthetic_prefix',true,
     'decision_paths_tested',jsonb_build_array('UPDATE','NO_CHANGE'),
     'negative_guard_cases_tested',jsonb_build_array('MISSING_EMPTY_REASON',
        'FALSE_ASSESSMENT_RECEIPT','DECISION_MODE_MISMATCH'),
     'negative_non_durable_route_cases',jsonb_build_array('NO_CHANGE_FORBIDS_GITHUB_WRITE'),
     'blocked_step_retry_fixture_excluded_due_to_ekb_autopersist',true,
     'transactional_rollback_verified',true,
     'legacy_v01_kept_active',true,
     'checkpoint_pass',false,'production_activation',false,
     'positive_provider_end_to_end_verified',false,
     'acceptance_declared',false
  );
  IF private.fn_lf_event_acceptance_signal_v2(
       'ARTIFACT_RECONCILED',v_event_code,
       'PE10_C6 recorder rollback-only validation, checkpoint remains pending',
       v_audit) IS NOT NULL
  THEN RAISE EXCEPTION 'PE10_C6_EVENT_FALSE_ACCEPTANCE'; END IF;
  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,
    severidad,origen,created_by_execution_id,payload)
  VALUES('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_event_code,
    'PE10 C6 recorder tested in transaction; provider E2E and activation still pending',
    'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_audit)
  RETURNING id INTO v_event_id;
  IF NOT EXISTS (SELECT 1 FROM public.lf_eventos
      WHERE id=v_event_id AND payload->>'checkpoint_pass'='false'
        AND payload->>'transactional_rollback_verified'='true')
      OR (SELECT status FROM programacion.engineering_work_checkpoints c
          JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
          WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
          AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C6') <> 'PENDING'
      OR (SELECT version FROM public.lf_operation_registry
          WHERE operation_code=v_operation) <> 'v0.1'
  THEN RAISE EXCEPTION 'PE10_C6_RECORDER_POSTCOMMIT_EVIDENCE_UNVERIFIED'; END IF;
END $pe10_c6_recorder$;
COMMIT;
