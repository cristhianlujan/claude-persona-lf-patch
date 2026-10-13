-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.12 ONLY.
-- Contract + local governance + checkpoint validator readback alignment.
-- This migration performs NO checkpoint transition, REVOKE, DROP, or runtime cutover.
-- A positive REMOVE_READY requires separate current source admission and a new batch migration.
-- EKB: IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001,
--      IG-M1011-NONMATERIAL-READBACK-MISSING-QUERY-001,
--      IG-M99-REPETITIVE-SYMPTOM-PATCHING-001.
DO $ig_m1012$
DECLARE
  v_id bigint;
  v_upstream_status text;
  v_action_status text;
  v_cp_status text;
  v_ready bigint;
  v_event bigint;
  v_cap_version text;
  v_suite public.lf_test_suite_runs%rowtype;
  v_reclass jsonb;
  v_after jsonb;
BEGIN
  SELECT pu.work_item_id,
         pu.unit_metadata#>>'{action_specs_v1,REUSE_LEGACY_RETIREMENT,status}'
    INTO v_id,v_action_status
  FROM programacion.engineering_plan_units pu
  WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND pu.unit_code='M10.12'
  FOR UPDATE;

  IF v_id IS NULL OR v_action_status IS DISTINCT FROM 'BLOCK_MATERIALIZATION_CONTRACT_REQUIRED' THEN
    RAISE EXCEPTION 'M1012_UNIT_OR_ACTION_DRIFT';
  END IF;

  SELECT status INTO v_cp_status
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=v_id AND checkpoint_code='REUSE_LEGACY_RETIREMENT';
  IF v_cp_status IS DISTINCT FROM 'PENDING' THEN
    RAISE EXCEPTION 'M1012_CP2_NOT_PENDING';
  END IF;

  SELECT wi.status INTO v_upstream_status
  FROM programacion.engineering_plan_units pu
  JOIN programacion.engineering_work_items wi ON wi.id=pu.work_item_id
  WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND pu.unit_code='M10.11';
  IF v_upstream_status IS DISTINCT FROM 'DONE' THEN
    RAISE EXCEPTION 'M1012_M1011_NOT_CLOSED';
  END IF;

  SELECT max(id) INTO v_event
  FROM public.lf_eventos
  WHERE entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
  IF v_event IS NULL THEN RAISE EXCEPTION 'M1012_NO_CLASSIFICATION_RECEIPT'; END IF;

  SELECT count(*) INTO v_ready
  FROM public.lf_eventos e
  CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') item
  WHERE e.id=v_event AND item->>'class'='REMOVE_READY';
  IF v_ready <> 0 THEN
    RAISE EXCEPTION 'M1012_MATERIAL_BRANCH_REQUIRES_EXACT_FRESH_ALLOWLIST';
  END IF;

  SELECT * INTO v_suite
  FROM public.lf_test_suite_runs
  WHERE suite_code='IG_M1011_ZERO_TARGET_FINAL_V1'
  ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND OR v_suite.status IS DISTINCT FROM 'PASSED'
     OR v_suite.tests_total<1
     OR v_suite.tests_passed IS DISTINCT FROM v_suite.tests_total
     OR coalesce(v_suite.tests_failed,0)<>0
     OR coalesce(v_suite.tests_blocked,0)<>0
     OR coalesce(v_suite.tests_review_required,0)<>0
     OR v_suite.metadata->>'independently_verified' IS DISTINCT FROM 'true'
     OR v_suite.metadata->>'acl_unchanged' IS DISTINCT FROM 'true'
     OR v_suite.metadata->>'remove_ready_count' IS DISTINCT FROM '0'
     OR v_suite.metadata->>'historical_classification_id' IS DISTINCT FROM v_event::text
  THEN
    RAISE EXCEPTION 'M1012_SIGNED_ZERO_TARGET_SUITE_MISSING_OR_STALE';
  END IF;

  SELECT c.version INTO v_cap_version
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c ON c.capability_code=r.capability_code
  JOIN public.lf_capability_version_registry v ON v.capability_code=c.capability_code
                                           AND v.version=c.version
  WHERE r.capability_code='ASSET_RETIREMENT_GOVERNANCE'
    AND r.status='ACTIVE' AND v.release_state='RELEASED';
  IF v_cap_version IS NULL THEN
    RAISE EXCEPTION 'M1012_RETIREMENT_GOVERNANCE_NOT_CURRENT';
  END IF;

  -- CP2 consumes a CURRENT shared capability: this is a readback, not materialization.
  -- The canonical helper compiles real verification_queries from the existing source pack.
  SELECT programacion.fn_engineering_checkpoint_reclassify_readback_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.12','REUSE_LEGACY_RETIREMENT',
    'ASSET_RETIREMENT_GOVERNANCE must be ACTIVE and current RELEASED, the eight declared SADM-PP artifacts stay reference-only; do not create a parallel retirement engine or infer physical removal.',
    'IG_M1012_CONDITIONAL_CONTRACT_V1'
  ) INTO v_reclass;
  IF v_reclass->>'status' IS DISTINCT FROM 'RECLASSIFIED_READBACK'
     OR (v_reclass->>'query_count')::integer < 1 THEN
    RAISE EXCEPTION 'M1012_CP2_READBACK_RECLASSIFY_FAILED';
  END IF;

  UPDATE programacion.engineering_plan_units pu
  SET exit_criterion=
       'ZERO_TARGET: independently verified 0 current REMOVE_READY => no DROP/REVOKE; candidate-only material checkpoints may be NOT_APPLICABLE only with signed fresh zero-target and no-delta readback; CP5 safety negative remains independently testable. NONZERO: exact allowlist, no CASCADE, owned post-batch facade smoke, zero candidate residual deltas.',
      unit_metadata =
        jsonb_set(
          jsonb_set(
            jsonb_set(
              pu.unit_metadata,
              '{action_specs_v1,BATCH_DROP_NO_CASCADE,retirement_guard}',
              jsonb_build_object(
                'zero_target_route','NOT_APPLICABLE_ONLY_AFTER_CURRENT_SIGNED_ZERO_AND_NEGATIVE',
                'positive_target_route','EXACT_ALLOWLIST_CURRENT_SQL_GIT_EDGE_ROUTER_CONTRACTS',
                'forbid_drop_without_current_remove_ready',true,
                'forbid_cascade',true,
                'no_op_is_not_physical_retirement',true
              ),true
            ),
            '{action_specs_v1,SMOKE_M7_PER_BATCH,no_batch_policy}',
            jsonb_build_object(
              'zero_target_route','NOT_APPLICABLE_AFTER_EVIDENCED_NO_BATCH',
              'nonzero_route','OWN_M1012_FIVE_PUBLIC_FACADES_READBACK',
              'reuse_M7_foreign_tests',false
            ),true
          ),
          '{m1012_retirement_governance_v1}',
          jsonb_build_object(
            'schema_version','IG_M1012_CONDITIONAL_RETIREMENT_V1',
            'scope','IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.12_ONLY',
            'governed_capability','ASSET_RETIREMENT_GOVERNANCE',
            'capability_current_version',v_cap_version,
            'M1010_event_id',v_event,
            'M1011_suite_run_id',v_suite.suite_run_id,
            'historical_remove_ready_count',v_ready,
            'admission','ZERO_TARGET_CONDITIONAL_NO_DELETE',
            'currentness_requires_fresh_source_recheck',true,
            'physical_retirement_authorized',false,
            'negative_cascade_test_required',true,
            'zero_residue_means_delta_from_baseline',true,
            'must_use_canonical_checkpoint_transition',true,
            'status_transition_executed_by_this_migration',false
          ),true
        )
  WHERE pu.work_item_id=v_id;

  UPDATE programacion.engineering_work_items
  SET acceptance_criteria=jsonb_build_array(
       'ZERO_TARGET: zero physical deletion; current no-target evidence, independent negative and baseline-delta readback; no cross-project release',
       'NONZERO: current exact REMOVE_READY list, per-batch DROP WITHOUT CASCADE plus own smoke and exact poststate'
  )
  WHERE id=v_id;

  SELECT pu.unit_metadata#>'{action_specs_v1,REUSE_LEGACY_RETIREMENT}' INTO v_after
  FROM programacion.engineering_plan_units pu WHERE pu.work_item_id=v_id;
  IF v_after->>'status' IS DISTINCT FROM 'READY'
     OR v_after->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
     OR jsonb_array_length(v_after->'verification_queries') < 1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_id AND status IN ('DONE','NOT_APPLICABLE'))<>0 THEN
    RAISE EXCEPTION 'M1012_POSTCHECK_CONTRACT_OR_CHECKPOINT_DRIFT';
  END IF;
END
$ig_m1012$;
