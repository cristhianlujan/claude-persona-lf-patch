-- RW1-05_C2 executor-mode scoping correction.
-- Forward-only correction: preserves the three canonical EJECUCION_PERFIL_LF modes
-- and removes REMOTE_API host availability as a global C2 blocker.
-- Does not close C2, does not enable REMOTE_API, does not activate T3, and does not alter runtime code.
BEGIN;

DO $rw105_c2_executor_scope_fix$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C2';
  v_wi constant bigint := 1131;
  v_prior_md5 constant text := '758f4c9fb2273941c593c6817b539906';

  v_modes constant jsonb := '["GPT_NATIVE","CLAUDE_NATIVE","REMOTE_API"]'::jsonb;
  v_c2_admitted_modes constant jsonb := '["GPT_NATIVE","CLAUDE_NATIVE"]'::jsonb;

  v_old jsonb;
  v_new jsonb;
  v_spec jsonb;
  v_source jsonb;
  v_missing_typed jsonb;
  v_count integer;
BEGIN
  SELECT unit_metadata
    INTO STRICT v_old
  FROM programacion.engineering_plan_units
  WHERE plan_code = v_plan
    AND unit_code = v_unit
    AND work_item_id = v_wi
    AND disposition = 'ASSIGNED'
    AND md5(unit_metadata::text) = v_prior_md5
  FOR UPDATE;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id = v_wi)
       IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id = v_wi AND checkpoint_code = 'RW1-05_C1')
       IS DISTINCT FROM 'DONE'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id = v_wi AND checkpoint_code = v_cp)
       IS DISTINCT FROM 'PENDING'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id = v_wi AND checkpoint_code = 'RW1-05_C3')
       IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_EXECUTOR_SCOPE_LIFECYCLE_DRIFT';
  END IF;

  v_spec := v_old #> '{action_specs_v1,RW1-05_C2}';
  v_source := v_old #> '{source_pack_v2,checkpoint_inputs,RW1-05_C2}';

  IF v_spec IS NULL OR v_source IS NULL
  THEN
    RAISE EXCEPTION 'RW105_C2_EXECUTOR_SCOPE_CONTRACT_MISSING';
  END IF;

  IF v_spec #>> '{assertion_contract,pass_when,runtime_host_available_for_material_run}'
       IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION 'RW105_C2_EXECUTOR_SCOPE_PRIOR_ASSERTION_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(coalesce(v_source->'missing_typed','[]'::jsonb)) AS x(item)
    WHERE x.item->>'code' = 'PROFILE_RUNTIME_HOST_OFFLINE'
      AND coalesce((x.item->>'blocking')::boolean,false) = true
      AND x.item->>'host_label' = 'scalora-vps'
  )
  THEN
    RAISE EXCEPTION 'RW105_C2_EXECUTOR_SCOPE_PRIOR_BLOCKER_DRIFT';
  END IF;

  -- The canonical execution-mode universe is exactly three modes.
  -- RW1-05_C2 admits native execution only; REMOTE_API remains part of the
  -- operation contract but is not admitted/required for this checkpoint.
  v_spec := v_spec #- '{assertion_contract,pass_when,runtime_host_available_for_material_run}';

  v_spec := jsonb_set(
    v_spec,
    '{executor_mode_contract}',
    jsonb_build_object(
      'operation_code','EJECUCION_PERFIL_LF',
      'canonical_executor_modes',v_modes,
      'c2_admitted_executor_modes',v_c2_admitted_modes,
      'remote_api_c2_state','DISABLED_NOT_ADMITTED',
      'remote_api_host_required_only_when_selected',true,
      'native_modes_require_remote_api_host',false,
      'additional_executor_modes_forbidden',true,
      'mode_substitution_forbidden',true,
      'source_contract_path','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_execution_contract.py',
      'source_contract_blob','558f05415dd78590fd83298263151fffa28c5e4e',
      'source_runtime_readme_path','sandbox/lf_contract_gate_test/profile_execution_runtime/README.md',
      'source_runtime_readme_blob','75e4dbd29470f3bfa8f983dcf922d7c36db2ce57'
    ),
    true
  );

  v_spec := jsonb_set(
    v_spec,
    '{assertion_contract,pass_when,profile_canary_executor_mode_admitted}',
    'true'::jsonb,
    true
  );

  v_spec := jsonb_set(
    v_spec,
    '{assertion_contract,pass_when,remote_api_required_for_c2}',
    'false'::jsonb,
    true
  );

  v_spec := jsonb_set(
    v_spec,
    '{expected}',
    to_jsonb(
      'Materialize the shared T2 semantic consumer and caller-interaction boundary, preserve ACT-0001 as resume/rederivation authority, compose the canonical EJECUCION_PERFIL_LF terminal authority receipt, reconcile terminal failures, and close only after real semantic-shadow plus a real zero-cost read-only profile canary using an admitted native executor mode. REMOTE_API remains a canonical executor mode but is not admitted or required for RW1-05_C2.'::text
    ),
    false
  );

  v_spec := jsonb_set(
    v_spec,
    '{authoring_contract,executor_mode_universe}',
    v_modes,
    true
  );
  v_spec := jsonb_set(
    v_spec,
    '{authoring_contract,c2_admitted_executor_modes}',
    v_c2_admitted_modes,
    true
  );
  v_spec := jsonb_set(
    v_spec,
    '{authoring_contract,remote_api_c2_state}',
    to_jsonb('DISABLED_NOT_ADMITTED'::text),
    true
  );

  SELECT coalesce(jsonb_agg(x.item ORDER BY x.ord),'[]'::jsonb)
    INTO v_missing_typed
  FROM jsonb_array_elements(coalesce(v_source->'missing_typed','[]'::jsonb))
       WITH ORDINALITY AS x(item,ord)
  WHERE x.item->>'code' <> 'PROFILE_RUNTIME_HOST_OFFLINE';

  v_source := jsonb_set(v_source,'{missing_typed}',v_missing_typed,true);

  v_source := jsonb_set(
    v_source,
    '{executor_mode_contract}',
    jsonb_build_object(
      'operation_code','EJECUCION_PERFIL_LF',
      'canonical_executor_modes',v_modes,
      'c2_admitted_executor_modes',v_c2_admitted_modes,
      'remote_api_c2_state','DISABLED_NOT_ADMITTED',
      'profile_canary_requirement','REAL_ZERO_COST_READ_ONLY_CANARY_USING_ADMITTED_EXECUTOR_MODE',
      'remote_api_host_availability_blocking',false,
      'native_host_dependency',false,
      'source_contract_blob','558f05415dd78590fd83298263151fffa28c5e4e',
      'source_runtime_readme_blob','75e4dbd29470f3bfa8f983dcf922d7c36db2ce57'
    ),
    true
  );

  v_source := jsonb_set(
    v_source,
    '{runtime_availability_at_bind,relevance}',
    to_jsonb('REMOTE_API_ONLY_NON_BLOCKING_FOR_RW1_05_C2'::text),
    true
  );

  v_source := jsonb_set(
    v_source,
    '{expected_result}',
    to_jsonb(
      'T2 semantic consumer plus Profile Runtime receipt/reconciliation support materialized in Git/DB, followed by a real semantic shadow run and a real zero-cost read-only EJECUCION_PERFIL_LF canary using GPT_NATIVE or CLAUDE_NATIVE. REMOTE_API is canonical but disabled/not admitted for this checkpoint, so scalora-vps availability is not a C2 closure condition.'::text
    ),
    false
  );

  v_source := jsonb_set(
    v_source,
    '{verification_boundary}',
    to_jsonb('RW105_C2_NATIVE_EXECUTOR_CANARY_REQUIRED_REMOTE_API_NOT_ADMITTED_NOT_T3_CUTOVER'::text),
    false
  );

  v_new := jsonb_set(
    v_old,
    '{action_specs_v1,RW1-05_C2}',
    v_spec,
    false
  );

  v_new := jsonb_set(
    v_new,
    '{source_pack_v2,checkpoint_inputs,RW1-05_C2}',
    v_source,
    false
  );

  IF v_new #>> '{action_specs_v1,RW1-05_C2,assertion_contract,pass_when,runtime_host_available_for_material_run}'
       IS NOT NULL
     OR v_new #>> '{action_specs_v1,RW1-05_C2,assertion_contract,pass_when,remote_api_required_for_c2}'
       IS DISTINCT FROM 'false'
     OR v_new #>> '{action_specs_v1,RW1-05_C2,executor_mode_contract,remote_api_c2_state}'
       IS DISTINCT FROM 'DISABLED_NOT_ADMITTED'
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements(
         coalesce(v_new #> '{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}','[]'::jsonb)
       ) AS y(item)
       WHERE y.item->>'code' = 'PROFILE_RUNTIME_HOST_OFFLINE'
     )
  THEN
    RAISE EXCEPTION 'RW105_C2_EXECUTOR_SCOPE_POSTCONDITION_FAILED';
  END IF;

  UPDATE programacion.engineering_plan_units
     SET unit_metadata = v_new
   WHERE plan_code = v_plan
     AND unit_code = v_unit
     AND work_item_id = v_wi
     AND disposition = 'ASSIGNED'
     AND md5(unit_metadata::text) = v_prior_md5;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> 1
  THEN
    RAISE EXCEPTION 'RW105_C2_EXECUTOR_SCOPE_UPDATE_COUNT:%',v_count;
  END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id = v_wi AND checkpoint_code = v_cp)
       IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'RW105_C2_EXECUTOR_SCOPE_CHANGED_CHECKPOINT';
  END IF;
END
$rw105_c2_executor_scope_fix$;

COMMIT;
