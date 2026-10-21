-- IG M10.13 / GIT_RUNTIME_PARITY: correct a derived phantom test-repair policy.
-- Only per-checkpoint source specification is changed. CP2 stays PENDING.
-- The actual MIGRATION_SOURCE_PARITY capability and live Edge readback remain mandatory.
BEGIN;
DO $m1013_parity_spec$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_packet jsonb;
  v_status text;
  v_progress numeric;
BEGIN
  SELECT status INTO v_status FROM programacion.engineering_work_items WHERE id=474 FOR UPDATE;
  SELECT progress_pct INTO v_progress FROM programacion.v_engineering_work_progress WHERE id=474;
  IF v_status IS DISTINCT FROM 'IN_PROGRESS' OR v_progress <> 15
    OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
                  WHERE work_item_id=474 AND checkpoint_code='PLAN_STATE_ASIS' AND status='DONE')
    OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
                  WHERE work_item_id=474 AND checkpoint_code='GIT_RUNTIME_PARITY'
                    AND status='PENDING' AND evidence_ref IS NULL)
    OR EXISTS(SELECT 1 FROM programacion.engineering_plan_units
              WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13'
                AND unit_metadata#>'{action_specs_v1,GIT_RUNTIME_PARITY}' IS NOT NULL)
  THEN
    RAISE EXCEPTION 'IG_M1013_PARITY_CONTRACT_PRESTATE_DRIFT status=% progress=%',v_status,v_progress;
  END IF;

  v_before:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.13','GIT_RUNTIME_PARITY');

  IF v_before->>'status' IS DISTINCT FROM 'READY'
    OR v_before->>'action_kind' IS DISTINCT FROM 'TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION'
    OR v_before#>>'{repair_policy,mode}' IS DISTINCT FROM 'REPAIR_DECLARED_TARGET_THEN_RETEST'
    OR v_before->>'transversal_capability_code' IS DISTINCT FROM 'MIGRATION_SOURCE_PARITY'
  THEN
    RAISE EXCEPTION 'IG_M1013_PARITY_UNEXPECTED_COMPILER_PRESTATE:%',v_before;
  END IF;

  -- Explicit action classification avoids the legacy VERIFY_QUERY_ONCE repair
  -- heuristic. Dynamic capability release/currentness remains owned by V3.
  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(
    unit_metadata,
    '{action_specs_v1,GIT_RUNTIME_PARITY}',
    jsonb_build_object(
      'status','READY',
      'action_kind','TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION',
      'recipe_mode','EXECUTE_REPOSITORY_CAPABILITY',
      'requires_material_execution',true,
      'mutation_policy','CAPABILITY_CONTRACT_ONLY',
      'precision','IG_M1013_EXPLICIT_TRANSVERSAL_PARITY_BASE_V1',
      'expected','Run current released MIGRATION_SOURCE_PARITY capability with actual Git and Supabase snapshots, then compare all three deployed Edge functions to current main. Never accept synthetic or source-only PASS.',
      'target',jsonb_build_object(
        'checkpoint','GIT_RUNTIME_PARITY',
        'declared_objects',jsonb_build_array('supabase_migrations.schema_migrations','public.lf_capability_registry'),
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'declared_artifacts',jsonb_build_array(
          jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch/supabase/functions/input-governance-agent-v1/index.ts','verified',true),
          jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch/supabase/functions/input-governance-curator-v1/index.ts','verified',true),
          jsonb_build_object('path','cristhianlujan/claude-persona-lf-patch/supabase/functions/input-governance-validator-v1/index.ts','verified',true)
        )
      ),
      'forbidden',jsonb_build_array('SYNTHETIC_PASS_WITHOUT_CAPABILITY_EXECUTION','EXECUTE_NON_CURRENT_CAPABILITY_SOURCE','PRODUCTION_ACTIVATION_BY_THIS_CHECKPOINT'),
      'fallback_only_on',jsonb_build_array('MISSING_CANONICAL_OBJECT','CONTRADICTION','STALE_CURRENTNESS','DEMONSTRATED_DRIFT','MATERIAL_FINGERPRINT_CHANGE')
    ),
    true
  )
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code='M10.13' AND disposition='ASSIGNED';

  v_after:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.13','GIT_RUNTIME_PARITY');

  IF v_after->>'status' IS DISTINCT FROM 'READY'
    OR v_after->>'action_kind' IS DISTINCT FROM 'TRANSVERSAL_REPOSITORY_CAPABILITY_EXECUTION'
    OR v_after#>>'{repair_policy,mode}' IS DISTINCT FROM 'NONE'
    OR v_after->>'transversal_capability_code' IS DISTINCT FROM 'MIGRATION_SOURCE_PARITY'
    OR v_after#>>'{capability_execution,execution_input,execution_mode}' IS DISTINCT FROM 'FULL_CURRENT_STATE'
    OR v_after->>'transversal_gate' IS DISTINCT FROM 'PASS_CURRENT_ITEM'
  THEN
    RAISE EXCEPTION 'IG_M1013_PARITY_DERIVED_SPEC_REGRESSION:%',v_after;
  END IF;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.13','GIT_RUNTIME_PARITY',
    v_after,'{}'::jsonb
  );

  IF v_packet->>'status' IS DISTINCT FROM 'READY'
    OR v_packet->>'execution_capability' IS DISTINCT FROM 'RUN_TEST'
    OR v_packet->>'capability_mode' IS DISTINCT FROM 'REPOSITORY_CAPABILITY'
  THEN
    RAISE EXCEPTION 'IG_M1013_PARITY_PACKET_NOT_READY:%',v_packet;
  END IF;

  IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
            WHERE work_item_id=474 AND checkpoint_code='GIT_RUNTIME_PARITY'
              AND (status<>'PENDING' OR evidence_ref IS NOT NULL))
  THEN RAISE EXCEPTION 'IG_M1013_PARITY_CP2_WAS_MUTATED'; END IF;
END
$m1013_parity_spec$;
COMMIT;