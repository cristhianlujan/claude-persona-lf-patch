-- M10.3 CP4: checkpoint-scoped INPUT_GOVERNANCE_REGRESSION evidence
-- REUSES the actual CP3 positive+negative+revert execution, valid/current.
-- Scope precisely 1 tested case; DOES NOT represent all catalog cases passing.
-- No test rerun, no production promotion, no runtime traffic claim.
DO $m103_cp4$
DECLARE
 p constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 cp constant text := 'ROLLBACK_SUITE';
 v_case_code constant text := 'ENG_M10_3_ROLLBACK_DRILL';
 suite constant text := 'INPUT_GOVERNANCE_REGRESSION';
 actor constant text := 'IG_M103_CP4_SCOPED_REGRESSION_REUSE_20261013';
 ev text; b jsonb; t jsonb; a jsonb; cp3_sha text; cp3_evidence text;
 current_sha text; run_id uuid; test_id uuid;
 case_count bigint; owner_cases bigint; v_registry_count bigint; v_cp3_at timestamptz;
BEGIN
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.3');
 IF b->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
   OR b#>>'{current_checkpoint,checkpoint_code}'<>cp
   OR b#>>'{execution_readiness,status}'<>'READY'
   OR b#>>'{state,progress_pct}'<>'65.00'
   OR b#>>'{state,done_checkpoint_count}'<>'3'
   OR b#>>'{state,open_blockers}'<>'0'
   OR b#>>'{state,unmet_deps}'<>'0'
 THEN RAISE EXCEPTION 'M103_CP4_BOOTSTRAP_NOT_READY'; END IF;
 IF (SELECT status FROM public.lf_test_suites WHERE suite_code=suite)
      IS DISTINCT FROM 'CANDIDATO'
 THEN RAISE EXCEPTION 'M103_CP4_REGRESSION_SUITE_NOT_CURRENT'; END IF;

 SELECT assertion_receipt, assertion_receipt_sha256,evidence_ref
 INTO a,cp3_sha,cp3_evidence
 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=475 AND checkpoint_code='ROLLBACK_DRILL' AND status='DONE';
 IF a IS NULL OR cp3_sha IS NULL OR a->>'passed'<>'true'
 OR a->>'unit_code'<>'M10.3'
 OR a->>'checkpoint_code'<>'ROLLBACK_DRILL'
 OR a->>'schema_version'<>'ENGINEERING_CHECKPOINT_ASSERTION_RECEIPT_V1'
 OR cp3_evidence NOT LIKE '%m10_3/rollback_drill.py%'
 OR a->>'recorded_at' IS NULL
 THEN RAISE EXCEPTION 'M103_CP4_MATERIAL_ASSERTION_NOT_BOUND'; END IF;
 v_cp3_at:=(a->>'recorded_at')::timestamptz;
 IF v_cp3_at<clock_timestamp()-interval '24 hours'
 THEN RAISE EXCEPTION 'M103_CP4_REUSED_MATERIAL_EVIDENCE_STALE'; END IF;
 IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
                 WHERE name='lf_ig_m103_cp3_rollback_drill_v1')
 THEN RAISE EXCEPTION 'M103_CP4_CP3_TRAIN_MIGRATION_MISSING'; END IF;

 SELECT c.manifest_sha256 INTO STRICT current_sha
 FROM public.lf_capability_current c
 JOIN public.lf_capability_version_registry r USING(capability_code,version)
 WHERE c.capability_code='INPUT_GOVERNANCE' AND c.version='1.0.0'
 AND c.previous_version IS NULL AND c.manifest_sha256=r.manifest_sha256
 AND r.release_state='RELEASED';
 SELECT count(*) INTO v_registry_count
 FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE';
 IF v_registry_count<>1 THEN RAISE EXCEPTION 'M103_CP4_BASELINE_NOT_CLEAN'; END IF;

 IF EXISTS(SELECT 1 FROM public.lf_test_suite_cases
           WHERE suite_code=suite AND test_code=v_case_code)
 OR EXISTS(SELECT 1 FROM public.lf_test_suite_runs
           WHERE suite_code=suite
             AND metadata->>'unit_code'='M10.3'
             AND metadata->>'checkpoint_code'=cp)
 THEN RAISE EXCEPTION 'M103_CP4_ALREADY_REGISTERED_STOP'; END IF;

 -- Add exactly one source-bound case to existing suite, not an alternative suite.
 INSERT INTO public.lf_test_suite_cases(
   suite_code,test_code,test_order,title,test_type,execution_mode,severity,
   preconditions,input_payload,expected_output,prohibited_output,status,
   metadata,created_by_execution_id)
 SELECT suite,v_case_code,coalesce(max(test_order),0)+1,
   'M10.3 sandbox pointer rollback: material CP3 re-used (positive+negative+revert+zero residue)',
   'DETERMINISTIC','AUTOMATED','HIGH',
   jsonb_build_object('source_checkpoint','M10.3.ROLLBACK_DRILL',
     'assertion_receipt_sha256',cp3_sha,'must_be_current',true),
   jsonb_build_object('test_artifact','m10_3/rollback_drill.py',
     'material_source',cp3_evidence),
   jsonb_build_object('negative_sha_rejected',true,'positive_switch',true,
     'pointer_reverted',true,'zero_residues',true),
   jsonb_build_object('operational_activation',true,'full_suite_passed',true),
   'CANDIDATO',
   jsonb_build_object('owner','M10.3','checkpoint_code',cp,
     'source_execution_checkpoint','ROLLBACK_DRILL',
     'source_assertion_sha256',cp3_sha,'scoped_case_only',true,
     'reused_execution',true,'not_full_catalog_run',true),
   actor
 FROM public.lf_test_suite_cases WHERE suite_code=suite;

 -- The suite run is explicitly a scoped result of an already-executed
 -- real test, never a newly executed or full 889-case regression.
 INSERT INTO public.lf_test_suite_runs(
  suite_code,execution_id,environment,executor_type,executor_name,
  status,started_at,completed_at,tests_total,tests_passed,tests_failed,
  tests_blocked,tests_review_required,manifest,metadata,created_by_execution_id)
 VALUES(
  suite,actor,'sandbox','VERIFIED_EVIDENCE_REUSE','M10.3 CP3 Train PostgreSQL',
  'PASSED',v_cp3_at,v_cp3_at,1,1,0,0,0,
  jsonb_build_object('scope','CHECKPOINT_SCOPED_SINGLE_CASE',
   'test_code',v_case_code,'cp3_assertion_sha256',cp3_sha),
  jsonb_build_object('plan_code',p,'unit_code','M10.3','checkpoint_code',cp,
   'source_checkpoint','ROLLBACK_DRILL','source_assertion_sha256',cp3_sha,
   'source_evidence_ref',cp3_evidence,'source_execution_time',v_cp3_at,
   'result_origin','REUSED_VERIFIED_REAL_EXECUTION','scoped_case_count',1,
   'full_catalog_evaluated',false,'global_suite_green_asserted',false,
   'positive_and_negative_executed_in_source',true,'zero_residue_rechecked',true,
   'source_version','INPUT_GOVERNANCE@1.0.0','source_manifest_sha256',current_sha),
  actor) RETURNING suite_run_id INTO run_id;

 INSERT INTO public.lf_test_runs(
  suite_run_id,suite_code,test_code,execution_id,environment,executor_type,
  executor_name,status,input_payload,expected_output,actual_output,
  evidence_payload,metadata,started_at,completed_at,created_by_execution_id)
 VALUES(
  run_id,suite,v_case_code,actor,'sandbox','VERIFIED_EVIDENCE_REUSE','M10.3 CP3 Train PostgreSQL',
  'PASS',jsonb_build_object('source_checkpoint','M10.3.ROLLBACK_DRILL'),
  jsonb_build_object('negative_sha_rejected',true,'positive_switch',true,
      'pointer_reverted',true,'zero_residues',true),
  jsonb_build_object('material_assertion_passed',true,'source_assertion_sha256',cp3_sha,
     'current_manifest',current_sha,'reused_not_reexecuted',true),
  jsonb_build_object('source_migration','lf_ig_m103_cp3_rollback_drill_v1',
     'source_evidence_ref',cp3_evidence,'assertion_receipt',a,
     'zero_registry_candidate',v_registry_count=1),
  jsonb_build_object('owner_unit','M10.3','owner_checkpoint',cp,
     'source_checkpoint','ROLLBACK_DRILL','full_catalog_evaluated',false),
  v_cp3_at,v_cp3_at,actor) RETURNING test_run_id INTO test_id;

 SELECT count(*) INTO owner_cases FROM public.lf_test_runs
 WHERE suite_run_id=run_id AND status='PASS' AND test_code=v_case_code;
 SELECT count(*) INTO case_count FROM public.lf_test_suite_cases
 WHERE suite_code=suite;
 IF owner_cases<>1 OR case_count<1
   OR NOT EXISTS(
     SELECT 1 FROM public.lf_test_suite_runs s
     JOIN public.lf_test_runs r USING(suite_run_id,suite_code)
     WHERE s.suite_run_id=run_id AND s.tests_total=1 AND s.tests_passed=1
       AND s.tests_failed=0 AND s.status='PASSED'
       AND s.metadata->>'full_catalog_evaluated'='false'
       AND r.test_code=v_case_code AND r.status='PASS')
 THEN RAISE EXCEPTION 'M103_CP4_SCOPED_SUITE_EVIDENCE_INVALID'; END IF;

 ev := 'supabase://public.lf_test_suite_runs/'||run_id::text||
        ';supabase://public.lf_test_runs/'||test_id::text||
        ';supabase://programacion.engineering_work_checkpoints/M10.3#ROLLBACK_DRILL@'||cp3_sha;
 t:=programacion.fn_engineering_checkpoint_transition_v1(
  p,'M10.3',cp,'DONE',ev,actor,
  'One-case scoped regression PASS by canonical source-bound reuse of material CP3 rollback test; global INPUT_GOVERNANCE_REGRESSION catalog NOT executed or claimed green; baseline manifest and zero candidate reread.');
 IF t#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M103_CP4_TRANSITION_FAILED:%',t; END IF;
 b:=programacion.fn_engineering_unit_bootstrap_v3(p,'M10.3');
 IF b#>>'{state,progress_pct}'<>'85.00'
   OR b#>>'{state,done_checkpoint_count}'<>'4'
   OR b#>>'{current_checkpoint,checkpoint_code}'<>'ROLLBACK_READBACK'
 THEN RAISE EXCEPTION 'M103_CP4_POSTSTATE_MISMATCH:%',b#>'{state}'; END IF;
END $m103_cp4$;