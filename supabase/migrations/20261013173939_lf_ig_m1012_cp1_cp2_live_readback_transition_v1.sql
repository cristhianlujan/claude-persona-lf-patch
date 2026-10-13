-- IG M10.12 (PAULO-096): exact 2-checkpoint observational microlot.
-- EKB preflight: IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001,
-- IG-M1011-NONMATERIAL-READBACK-MISSING-QUERY-001,
-- IG-M99-REPETITIVE-SYMPTOM-PATCHING-001.
-- Only canonical CP1/CP2 transitions. ZERO destructive SQL/ACL/current pointers.
-- CP3..CP6 remain pending; no physical retirement or runtime approval.
DO $m1012_cp1_cp2$
DECLARE
  v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit constant text := 'M10.12';
  v_actor constant text := 'IG_M1012_CP1_CP2_LIVE_READBACK_V1';
  v_work bigint;
  v_e bigint;
  v_ready bigint;
  v_legacy bigint;
  v_acl bigint;
  v_dep bigint;
  v_sql_caller bigint;
  v_cap text;
  v_sadm_done int;
  v_sadm_total int;
  v_suite public.lf_test_suite_runs%rowtype;
  v_bundle jsonb;
  v_boot jsonb;
  v_result jsonb;
  v_counts jsonb;
  v_ref text;
  v_before_facades bigint;
  v_after_facades bigint;
BEGIN
  SELECT u.work_item_id INTO STRICT v_work
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code=v_plan AND u.unit_code=v_unit AND w.status='BACKLOG';

  IF v_work IS DISTINCT FROM 198 THEN RAISE EXCEPTION 'M1012_WORK_ID_DRIFT'; END IF;
  SELECT jsonb_agg(jsonb_build_object('code',c.checkpoint_code,'status',c.status)
                   ORDER BY c.sequence_no) INTO v_counts
  FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_work;
  IF v_counts IS DISTINCT FROM
    '[{"code":"RETIRE_SET_ASIS","status":"PENDING"},
      {"code":"REUSE_LEGACY_RETIREMENT","status":"PENDING"},
      {"code":"BATCH_DROP_NO_CASCADE","status":"PENDING"},
      {"code":"SMOKE_M7_PER_BATCH","status":"PENDING"},
      {"code":"NEG_CASCADE","status":"PENDING"},
      {"code":"ZERO_RESIDUE_READBACK","status":"PENDING"}]'::jsonb THEN
    RAISE EXCEPTION 'M1012_CHECKPOINT_PRESTATE_CHANGED';
  END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_blockers
      WHERE work_item_id=v_work AND status='OPEN')<>0 THEN
    RAISE EXCEPTION 'M1012_BLOCKER_REOPENED';
  END IF;

  -- Classification from previous checkpoint is historical, never asserted current.
  SELECT max(e.id) INTO v_e FROM public.lf_eventos e
  WHERE e.entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
  IF v_e IS NULL THEN RAISE EXCEPTION 'M1012_CLASSIFICATION_MISSING'; END IF;
  SELECT count(*) FILTER(WHERE x.item->>'class'='REMOVE_READY'),
         count(*) FILTER(WHERE x.item->>'class'='LEGACY_UNREFERENCED')
  INTO v_ready,v_legacy
  FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(item)
  WHERE e.id=v_e;
  IF v_ready IS DISTINCT FROM 0 OR v_legacy IS DISTINCT FROM 14 THEN
    RAISE EXCEPTION 'M1012_CLASSIFICATION_CHANGED_RECHECK_REQUIRED';
  END IF;

  -- Reuse independent verified M10.11 evidence; do not turn it into proof
  -- that all consumers are absent (it explicitly reports the opposite).
  SELECT * INTO v_suite
  FROM public.lf_test_suite_runs t
  WHERE t.suite_code='IG_M1011_ZERO_TARGET_FINAL_V1'
  ORDER BY t.created_at DESC LIMIT 1;
  IF NOT FOUND OR v_suite.status IS DISTINCT FROM 'PASSED'
    OR v_suite.tests_total < 1
    OR v_suite.tests_passed IS DISTINCT FROM v_suite.tests_total
    OR coalesce(v_suite.tests_failed,0)<>0
    OR coalesce(v_suite.tests_blocked,0)<>0
    OR coalesce(v_suite.tests_review_required,0)<>0
    OR v_suite.metadata->>'plan_code' IS DISTINCT FROM v_plan
    OR v_suite.metadata->>'unit_code' IS DISTINCT FROM 'M10.11'
    OR v_suite.metadata->>'independently_verified' IS DISTINCT FROM 'true'
    OR v_suite.metadata->>'acl_unchanged' IS DISTINCT FROM 'true'
    OR v_suite.metadata->>'remove_ready_count' IS DISTINCT FROM '0'
    OR v_suite.metadata->>'dynamic_absence_proven' IS DISTINCT FROM 'false'
    OR v_suite.metadata->>'historical_classification_id' IS DISTINCT FROM v_e::text
    OR v_suite.completed_at<clock_timestamp()-interval '24 hours' THEN
      RAISE EXCEPTION 'M1012_INDEPENDENT_RECEIPT_STALE_OR_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1 FROM (VALUES('SQL'),('GIT'),('EDGE'),('ROUTER'),('CONTRACTS')) s(k)
    WHERE v_suite.metadata#>>ARRAY['sources',s.k] IS DISTINCT FROM 'PASS'
  ) THEN RAISE EXCEPTION 'M1012_SOURCES_NOT_VERIFIED'; END IF;
  v_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite.suite_run_id);
  IF v_bundle->>'status' IS DISTINCT FROM 'VERIFIED'
    OR v_bundle#>>'{verification,test_graph_complete}' IS DISTINCT FROM 'true'
    OR v_bundle#>>'{verification,local_case_ownership_complete}' IS DISTINCT FROM 'true' THEN
     RAISE EXCEPTION 'M1012_INDEPENDENT_BUNDLE_UNVERIFIED';
  END IF;

  -- Actual CP1 preferred-input readback: privilege rows and pg_depend.
  -- pg_depend=0 NEVER implies no callers; inspect active SQL body separately.
  SELECT count(*) INTO v_acl FROM information_schema.routine_privileges
  WHERE routine_schema IN ('programacion','public')
    AND (routine_name LIKE 'fn_input_governance%' OR routine_name LIKE 'fn_input_readiness%');
  SELECT count(*) INTO v_dep FROM pg_depend d
  JOIN pg_proc p ON p.oid=d.refobjid
  WHERE d.refclassid='pg_proc'::regclass
    AND p.proname LIKE 'fn_input_governance%' AND d.deptype<>'i';
  SELECT count(*) INTO v_sql_caller FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion'
    AND p.proname='fn_input_gov_gold_b_prepare_review_v1'
    AND p.prosrc ILIKE '%fn_input_readiness_run_is_current_cached_v2%';
  IF v_acl<1 OR v_sql_caller<1 THEN
    RAISE EXCEPTION 'M1012_LIVE_SOURCE_CURRENTNESS_CHANGED';
  END IF;

  SELECT count(distinct p.proname) INTO v_before_facades
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (
    'fn_input_governance_execute','fn_input_governance_validator_validate_v1',
    'fn_input_governance_curator_materialize_v1',
    'fn_input_governance_safe_autofix_v1',
    'fn_input_governance_validator_resume_context_v1');
  IF v_before_facades IS DISTINCT FROM 5 THEN
     RAISE EXCEPTION 'M1012_STABLE_PUBLIC_FACADE_NOT_INTACT';
  END IF;

  -- CP2 observes reusable transversal governance, not materializing it.
  SELECT c.version INTO v_cap
  FROM public.lf_capability_registry r
  JOIN public.lf_capability_current c USING (capability_code)
  JOIN public.lf_capability_version_registry v
      ON v.capability_code=c.capability_code AND v.version=c.version
  WHERE r.capability_code='ASSET_RETIREMENT_GOVERNANCE'
    AND r.status='ACTIVE' AND v.release_state='RELEASED';
  IF v_cap IS DISTINCT FROM '1.0.0' THEN
     RAISE EXCEPTION 'M1012_GOVERNED_RETIREMENT_CAPABILITY_DRIFT';
  END IF;

  SELECT count(*),count(*) FILTER(WHERE wi.status='DONE')
    INTO v_sadm_total,v_sadm_done
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items wi ON wi.id=u.work_item_id
  WHERE u.plan_code='LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1'
    AND u.unit_code IN ('SADM-PP-L3-017','SADM-PP-L4-019',
      'SADM-PP-L4-020','SADM-PP-L4-021','SADM-PP-L5-022',
      'SADM-PP-L5-023','SADM-PP-L6-024','SADM-PP-L6-025');
  IF v_sadm_total IS DISTINCT FROM 8 OR v_sadm_done IS DISTINCT FROM 8 THEN
    RAISE EXCEPTION 'M1012_EXISTING_RETIREMENT_REFERENCES_UNAVAILABLE';
  END IF;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'RETIRE_SET_ASIS'
    OR v_boot#>>'{action_spec,status}' IS DISTINCT FROM 'READY'
    OR (SELECT programacion.fn_engineering_checkpoint_execution_readiness_v1(
      v_plan,v_unit,'RETIRE_SET_ASIS')->>'status') IS DISTINCT FROM 'READY' THEN
      RAISE EXCEPTION 'M1012_CP1_NOT_READBACK_READY';
  END IF;

  v_ref:='supabase://public.lf_eventos/'||v_e::text
    ||';supabase://public.lf_test_suite_runs/'||v_suite.suite_run_id::text
    ||';supabase://pg_catalog/pg_depend'
    ||';supabase://information_schema/routine_privileges';
  v_result:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,'RETIRE_SET_ASIS','DONE',v_ref,v_actor,
    format('Current readback ACL rows=%s; pg_depend rows=%s; SQL caller positive=%s; REMOVE_READY=%s; previous legacy unreferenced=%s; no deletion eligible',
      v_acl,v_dep,v_sql_caller,v_ready,v_legacy));
  IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN
    RAISE EXCEPTION 'M1012_CP1_TRANSITION_NOT_APPLIED';
  END IF;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'REUSE_LEGACY_RETIREMENT'
    OR v_boot#>>'{action_spec,action_kind}' IS DISTINCT FROM 'READBACK_ONCE'
    OR v_boot#>>'{action_spec,status}' IS DISTINCT FROM 'READY'
    OR (SELECT programacion.fn_engineering_checkpoint_execution_readiness_v1(
      v_plan,v_unit,'REUSE_LEGACY_RETIREMENT')->>'status') IS DISTINCT FROM 'READY' THEN
      RAISE EXCEPTION 'M1012_CP2_NOT_READBACK_READY';
  END IF;
  v_result:=programacion.fn_engineering_checkpoint_transition_v1(
    v_plan,v_unit,'REUSE_LEGACY_RETIREMENT','DONE',
    'supabase://public.lf_capability_current/ASSET_RETIREMENT_GOVERNANCE@1.0.0',
    v_actor,
    'Reuse ACTIVE/RELEASED capability v1.0.0; 8/8 SADM references already DONE; no new implementation and no external project mutation');
  IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN
    RAISE EXCEPTION 'M1012_CP2_TRANSITION_NOT_APPLIED';
  END IF;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'BATCH_DROP_NO_CASCADE'
    OR v_boot#>>'{state,done_checkpoint_count}' IS DISTINCT FROM '2'
    OR v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT' THEN
      RAISE EXCEPTION 'M1012_AFTER_CP2_NEXT_IS_NOT_CP3';
  END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_work AND c.status='DONE') IS DISTINCT FROM 2
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_work AND c.status<>'PENDING'
        AND c.checkpoint_code IN ('BATCH_DROP_NO_CASCADE',
          'SMOKE_M7_PER_BATCH','NEG_CASCADE','ZERO_RESIDUE_READBACK'))<>0 THEN
      RAISE EXCEPTION 'M1012_CP3_CP6_UNEXPECTEDLY_CHANGED';
  END IF;

  SELECT count(distinct p.proname) INTO v_after_facades
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (
    'fn_input_governance_execute','fn_input_governance_validator_validate_v1',
    'fn_input_governance_curator_materialize_v1',
    'fn_input_governance_safe_autofix_v1',
    'fn_input_governance_validator_resume_context_v1');
  IF v_after_facades IS DISTINCT FROM v_before_facades THEN
    RAISE EXCEPTION 'M1012_FACADE_DRIFT_AFTER_READBACK_TRANSITIONS';
  END IF;
  IF (SELECT status FROM programacion.engineering_work_items
      WHERE id=v_work) IS DISTINCT FROM 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'M1012_WORK_STATUS_NOT_IN_PROGRESS';
  END IF;
END;
$m1012_cp1_cp2$;
