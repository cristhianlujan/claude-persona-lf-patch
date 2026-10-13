-- M10.12 conditional ZERO_TARGET engineering closure, no physical retirement.
-- Uses executed provider-bound Python negative checkpoint test and signed M10.11
-- multi-source no-target suite. Physical DROP and operational release DENIED.
-- Only M10.12 CP3..CP6 transitions through canonical API and unit metadata.
-- No DROP, REVOKE, GRANT, live capability registry edits or runtime activation.
DO $m1012_close$
DECLARE
 v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_unit constant text := 'M10.12';
 v_actor constant text := 'IG_M1012_ZERO_TARGET_CONDITIONAL_CLOSURE_V1';
 v_work bigint;
 v_class bigint;
 v_historical_ready bigint;
 v_historical_unreferenced bigint;
 v_current_proof_count bigint;
 v_sql_acl_drift bigint;
 v_live_caller_count bigint;
 v_suite_prior public.lf_test_suite_runs%rowtype;
 v_suite_test public.lf_test_suite_runs%rowtype;
 v_bundle_prior jsonb;
 v_bundle_test jsonb;
 v_facades bigint;
 v_snapshot_before jsonb;
 v_snapshot_after jsonb;
 v_boot jsonb;
 v_result jsonb;
 v_states jsonb;
 v_progress numeric;
 v_ref_prior text;
 v_ref_test text;
BEGIN
 SELECT pu.work_item_id INTO STRICT v_work
 FROM programacion.engineering_plan_units pu
 JOIN programacion.engineering_work_items wi ON wi.id=pu.work_item_id
 WHERE pu.plan_code=v_plan AND pu.unit_code=v_unit AND wi.status='IN_PROGRESS';
 IF v_work IS DISTINCT FROM 198 THEN RAISE EXCEPTION 'M1012_CLOSURE_WRONG_WORK'; END IF;

 SELECT jsonb_agg(jsonb_build_object('cp',checkpoint_code,'status',status)
                  ORDER BY sequence_no) INTO v_states
 FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_work;
 IF v_states IS DISTINCT FROM
 '[{"cp":"RETIRE_SET_ASIS","status":"DONE"},
   {"cp":"REUSE_LEGACY_RETIREMENT","status":"DONE"},
   {"cp":"BATCH_DROP_NO_CASCADE","status":"PENDING"},
   {"cp":"SMOKE_M7_PER_BATCH","status":"PENDING"},
   {"cp":"NEG_CASCADE","status":"PENDING"},
   {"cp":"ZERO_RESIDUE_READBACK","status":"PENDING"}]'::jsonb
 THEN RAISE EXCEPTION 'M1012_CLOSURE_CP_PRESTATE_CHANGED'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_blockers
      WHERE work_item_id=v_work AND status='OPEN')<>0
 THEN RAISE EXCEPTION 'M1012_UNRESOLVED_BLOCKER'; END IF;

 IF (SELECT pu.unit_metadata#>>'{m1012_retirement_governance_v1,physical_retirement_authorized}'
     FROM programacion.engineering_plan_units pu
     WHERE pu.plan_code=v_plan AND pu.unit_code=v_unit) IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'M1012_PHYSICAL_RETIREMENT_FENCE_NOT_SET'; END IF;

 -- M10.10 classification is historical only. Its currentness comes from
 -- live PG source + grants AND an independently verified no-target suite.
 SELECT max(id) INTO v_class FROM public.lf_eventos e
 WHERE e.entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
 IF v_class IS NULL THEN RAISE EXCEPTION 'M1012_CLASSIFICATION_EVENT_MISSING'; END IF;
 SELECT count(*) FILTER(WHERE item->>'class'='REMOVE_READY'),
        count(*) FILTER(WHERE item->>'class'='LEGACY_UNREFERENCED')
   INTO v_historical_ready,v_historical_unreferenced
 FROM public.lf_eventos e
 CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(item)
 WHERE e.id=v_class;
 IF v_historical_ready IS DISTINCT FROM 0 THEN
   RAISE EXCEPTION 'M1012_RECLASSIFY_MATERIAL_TARGETS_FIRST';
 END IF;

 SELECT * INTO v_suite_prior
 FROM public.lf_test_suite_runs
 WHERE suite_code='IG_M1011_ZERO_TARGET_FINAL_V1'
 ORDER BY created_at DESC LIMIT 1;
 IF NOT FOUND OR v_suite_prior.status IS DISTINCT FROM 'PASSED'
   OR v_suite_prior.metadata->>'independently_verified' IS DISTINCT FROM 'true'
   OR v_suite_prior.metadata->>'remove_ready_count' IS DISTINCT FROM '0'
   OR v_suite_prior.metadata->>'dynamic_absence_proven' IS DISTINCT FROM 'false'
   OR v_suite_prior.metadata->>'acl_unchanged' IS DISTINCT FROM 'true'
   OR v_suite_prior.metadata->>'historical_classification_id' IS DISTINCT FROM v_class::text
   OR v_suite_prior.completed_at<clock_timestamp()-interval '24 hours' THEN
      RAISE EXCEPTION 'M1012_PRIOR_MULTI_SOURCE_NO_TARGET_SUITE_STALE';
 END IF;
 IF EXISTS (
   SELECT 1 FROM (VALUES('SQL'),('GIT'),('EDGE'),('ROUTER'),('CONTRACTS')) s(name)
   WHERE v_suite_prior.metadata#>>ARRAY['sources',s.name] IS DISTINCT FROM 'PASS'
 ) THEN RAISE EXCEPTION 'M1012_PRIOR_SOURCE_COVERAGE_INCOMPLETE'; END IF;
 v_bundle_prior:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite_prior.suite_run_id);
 IF v_bundle_prior->>'status' IS DISTINCT FROM 'VERIFIED'
   OR v_bundle_prior#>>'{verification,test_graph_complete}' IS DISTINCT FROM 'true'
   OR v_bundle_prior#>>'{verification,local_case_ownership_complete}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M1012_PRIOR_SUITE_BUNDLE_NOT_VERIFIED'; END IF;

 -- M10.11 signature-by-signature recheck, fail-closed on current SQL/ACL drift.
 WITH current_sql AS (
   SELECT x.item, pr.oid, pr.prosrc FROM programacion.engineering_plan_units pu
   CROSS JOIN LATERAL jsonb_array_elements(
     pu.unit_metadata#>'{m1011_live_sql_recheck_v2,functions}') x(item)
   LEFT JOIN pg_proc pr ON pr.oid=to_regprocedure(x.item->>'observed_signature')
   WHERE pu.plan_code=v_plan AND pu.unit_code='M10.11'
 )
 SELECT count(*), count(*) FILTER(WHERE oid IS NULL
   OR md5(prosrc) IS DISTINCT FROM item->>'function_source_md5'
   OR has_function_privilege('anon',oid,'EXECUTE') IS DISTINCT FROM
       (item#>>'{effective_execute,anon}')::boolean
   OR has_function_privilege('authenticated',oid,'EXECUTE') IS DISTINCT FROM
       (item#>>'{effective_execute,authenticated}')::boolean
   OR has_function_privilege('service_role',oid,'EXECUTE') IS DISTINCT FROM
       (item#>>'{effective_execute,service_role}')::boolean),
   count(*) FILTER(WHERE jsonb_array_length(item->'sql_callers')>0)
 INTO v_current_proof_count,v_sql_acl_drift,v_live_caller_count
 FROM current_sql;
 IF v_current_proof_count<>v_historical_unreferenced
   OR v_current_proof_count<1 OR v_sql_acl_drift<>0 OR v_live_caller_count<1 THEN
   RAISE EXCEPTION 'M1012_SQL_CALLER_OR_ACL_DRIFT_BLOCKS_CONDITIONAL_CLOSURE';
 END IF;

 -- CP5: an exact-source, externally executed local admission-oracle test.
 -- This tests sandbox construction, not a real physical DROP or Train enforcement.
 SELECT * INTO v_suite_test FROM public.lf_test_suite_runs
 WHERE suite_code='IG_M1012_NEG_CASCADE_BOUNDED_V1'
 ORDER BY created_at DESC LIMIT 1;
 IF NOT FOUND OR v_suite_test.status IS DISTINCT FROM 'PASSED'
   OR v_suite_test.tests_total<>1 OR v_suite_test.tests_passed<>1
   OR coalesce(v_suite_test.tests_failed,0)<>0
   OR coalesce(v_suite_test.tests_blocked,0)<>0
   OR coalesce(v_suite_test.tests_review_required,0)<>0
   OR v_suite_test.metadata->>'unit_code' IS DISTINCT FROM v_unit
   OR v_suite_test.metadata->>'checkpoint_code' IS DISTINCT FROM 'NEG_CASCADE'
   OR v_suite_test.metadata->>'case_owner' IS DISTINCT FROM v_unit
   OR v_suite_test.metadata->>'fixture_tests_run' IS DISTINCT FROM '9'
   OR v_suite_test.metadata->>'fixture_tests_passed' IS DISTINCT FROM '9'
   OR v_suite_test.metadata->>'provider_returncode' IS DISTINCT FROM '0'
   OR v_suite_test.metadata->>'negative_cases_executed' IS DISTINCT FROM 'true'
   OR v_suite_test.metadata->>'semantic_authority_bound' IS DISTINCT FROM 'true'
   OR v_suite_test.metadata->>'observed_zero_target_rejected' IS DISTINCT FROM 'true'
   OR v_suite_test.metadata->>'observed_no_target_code' IS DISTINCT FROM 'NO_REMOVE_READY'
   OR v_suite_test.metadata->>'real_db_drop_tested' IS DISTINCT FROM 'false'
   OR v_suite_test.metadata->>'train_gate_enforced' IS DISTINCT FROM 'false'
   OR v_suite_test.metadata->>'runtime_release_qualified' IS DISTINCT FROM 'false'
   OR v_suite_test.manifest->>'actual_execution' IS DISTINCT FROM 'true'
   OR v_suite_test.manifest->>'synthetic_pass' IS DISTINCT FROM 'false'
   OR v_suite_test.manifest->>'adversarial_case_executed' IS DISTINCT FROM 'true'
   OR v_suite_test.manifest->>'test_passed' IS DISTINCT FROM 'true'
   OR v_suite_test.manifest->>'test_exit_code' IS DISTINCT FROM '0'
   OR v_suite_test.completed_at<clock_timestamp()-interval '24 hours'
 THEN RAISE EXCEPTION 'M1012_BOUNDED_NEGATIVE_NOT_VERIFIED'; END IF;
 v_bundle_test:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite_test.suite_run_id);
 IF v_bundle_test->>'status' IS DISTINCT FROM 'VERIFIED'
   OR v_bundle_test#>>'{verification,test_graph_complete}' IS DISTINCT FROM 'true'
   OR v_bundle_test#>>'{verification,local_case_ownership_complete}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M1012_NEGATIVE_BUNDLE_NOT_VERIFIED'; END IF;

 SELECT count(distinct p.proname) INTO v_facades
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN (
   'fn_input_governance_execute',
   'fn_input_governance_validator_validate_v1',
   'fn_input_governance_curator_materialize_v1',
   'fn_input_governance_safe_autofix_v1',
   'fn_input_governance_validator_resume_context_v1');
 IF v_facades IS DISTINCT FROM 5 THEN
   RAISE EXCEPTION 'M1012_STABLE_FACADES_NOT_FIVE';
 END IF;

 -- Before/after physical baseline: all relevant function source+ACL,
 -- grant count, IG asset rows and asset relations. No full-history delete
 -- (current nonzero counts are valid; residual DELTA must be exactly zero).
 SELECT jsonb_build_object(
  'pg_proc_source_acl',(
   SELECT md5(coalesce(string_agg(n.nspname||'.'||p.oid::regprocedure::text
      ||':'||md5(p.prosrc)||':'||coalesce(p.proacl::text,'NULL'),
      ',' ORDER BY n.nspname,p.oid::regprocedure::text),''))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','programacion')
     AND (p.proname LIKE 'fn_input_governance%'
       OR p.proname LIKE 'fn_input_readiness%'
       OR p.proname LIKE 'fn_input_na_positive%'
       OR p.proname LIKE 'fn_input_bootstrap%'
       OR p.proname LIKE 'fn_guard_input_%')),
  'routine_privileges',(
   SELECT md5(coalesce(string_agg(concat_ws('|',routine_schema,routine_name,grantee,privilege_type),
     ',' ORDER BY routine_schema,routine_name,grantee,privilege_type),''))
   FROM information_schema.routine_privileges
   WHERE routine_schema IN ('public','programacion')
     AND (routine_name LIKE 'fn_input_governance%' OR routine_name LIKE 'fn_input_readiness%')),
  'asset_relations',(
   SELECT md5(coalesce(string_agg(concat_ws('|',codigo_activo,relacion_tipo,relacionado_codigo,fuente),
     ',' ORDER BY codigo_activo,relacion_tipo,relacionado_codigo,fuente),''))
   FROM public.lf_activo_relaciones
   WHERE codigo_activo LIKE '%INPUT_GOVERNANCE%'
      OR relacionado_codigo LIKE '%INPUT_GOVERNANCE%'),
  'assets',(
   SELECT md5(coalesce(string_agg(codigo_activo||':'||coalesce(estado_operativo,''),
     ',' ORDER BY codigo_activo),''))
   FROM public.lf_activos WHERE codigo_activo LIKE '%INPUT_GOVERNANCE%')
 ) INTO v_snapshot_before;

 v_ref_prior:='supabase://public.lf_test_suite_runs/'||v_suite_prior.suite_run_id::text
   ||'#VERIFIED;REMOVE_READY=0;NO_ACL_DELTA';
 v_ref_test:='supabase://public.lf_test_suite_runs/'||v_suite_test.suite_run_id::text
   ||'#VERIFIED;9of9;NO_REMOVE_READY;BOUNDED_ORACLE_ONLY';

 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
   OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'BATCH_DROP_NO_CASCADE'
 THEN RAISE EXCEPTION 'M1012_CP3_NOT_CURRENT'; END IF;
 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
   v_plan,v_unit,'BATCH_DROP_NO_CASCADE','NOT_APPLICABLE',
   v_ref_prior||';'||v_ref_test,v_actor,
   'Zero REMOVE_READY, independently VERIFIED no-target; negative 9/9 executed; no physical DROP batch eligible; retain future physical gate blocked');
 IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'M1012_CP3_NA_NOT_APPLIED'; END IF;

 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'SMOKE_M7_PER_BATCH'
 THEN RAISE EXCEPTION 'M1012_CP4_NOT_CURRENT'; END IF;
 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
   v_plan,v_unit,'SMOKE_M7_PER_BATCH','NOT_APPLICABLE',
   v_ref_prior||';supabase://pg_catalog/pg_proc#stable_facades=5',v_actor,
   'No M10.12 retirement batch therefore no post-batch smoke; five public IG facades preserved. No M7 tests rerun.');
 IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'M1012_CP4_NA_NOT_APPLIED'; END IF;

 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NEG_CASCADE'
 THEN RAISE EXCEPTION 'M1012_CP5_NOT_CURRENT'; END IF;
 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
   v_plan,v_unit,'NEG_CASCADE','DONE',v_ref_test,v_actor,
   'Bounded independent policy-oracle Python test 9/9 with CASCADE/dependent/caller adversarials, provenance exact Git; no real DB DROP and no runtime enforcement claim');
 IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'M1012_CP5_NOT_APPLIED'; END IF;

 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'ZERO_RESIDUE_READBACK'
 THEN RAISE EXCEPTION 'M1012_CP6_NOT_CURRENT'; END IF;
 v_result:=programacion.fn_engineering_checkpoint_transition_v1(
   v_plan,v_unit,'ZERO_RESIDUE_READBACK','DONE',
   v_ref_prior||';'||v_ref_test||';supabase://pg_catalog/pg_proc#delta=0',v_actor,
   'Terminal conditional zero-target: no physical batch, zero net changes to PG functions/grants/assets/relations; all existing history retained');
 IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'M1012_CP6_NOT_APPLIED'; END IF;

 -- Record truthful closure scope in the same M10.12 unit, not a release.
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{m1012_completion_v1}',
  jsonb_build_object(
    'status','ENGINEERING_ZERO_TARGET_CONDITIONAL_TERMINAL',
    'plan_code',v_plan,'unit_code',v_unit,
    'historical_classification_event_id',v_class,
    'approved_physical_target_count',v_historical_ready,
    'positive_sql_callers_retained',v_live_caller_count,
    'source_acl_drift',v_sql_acl_drift,
    'signed_no_target_suite_id',v_suite_prior.suite_run_id,
    'bounded_negative_suite_id',v_suite_test.suite_run_id,
    'negative_execution_scope','EXTERNAL_BOUNDED_POLICY_ORACLE_ONLY',
    'real_db_drop_tested',false,'physical_drop_executed',false,
    'physical_retirement_authorized',false,
    'runtime_release_qualified',false,'train_runtime_drop_guard_proven',false,
    'future_nonzero_candidate_requires_separate_fresh_admission',true,
    'terminal_mode','CP3_NA_CP4_NA_CP5_DONE_CP6_DONE',
    'snapshot_source','DYNAMIC_CURRENT_READBACK'
  ),true)
 WHERE plan_code=v_plan AND unit_code=v_unit;

 SELECT jsonb_build_object(
  'pg_proc_source_acl',(
   SELECT md5(coalesce(string_agg(n.nspname||'.'||p.oid::regprocedure::text
      ||':'||md5(p.prosrc)||':'||coalesce(p.proacl::text,'NULL'),
      ',' ORDER BY n.nspname,p.oid::regprocedure::text),''))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','programacion')
     AND (p.proname LIKE 'fn_input_governance%'
       OR p.proname LIKE 'fn_input_readiness%'
       OR p.proname LIKE 'fn_input_na_positive%'
       OR p.proname LIKE 'fn_input_bootstrap%'
       OR p.proname LIKE 'fn_guard_input_%')),
  'routine_privileges',(
   SELECT md5(coalesce(string_agg(concat_ws('|',routine_schema,routine_name,grantee,privilege_type),
     ',' ORDER BY routine_schema,routine_name,grantee,privilege_type),''))
   FROM information_schema.routine_privileges
   WHERE routine_schema IN ('public','programacion')
     AND (routine_name LIKE 'fn_input_governance%' OR routine_name LIKE 'fn_input_readiness%')),
  'asset_relations',(
   SELECT md5(coalesce(string_agg(concat_ws('|',codigo_activo,relacion_tipo,relacionado_codigo,fuente),
     ',' ORDER BY codigo_activo,relacion_tipo,relacionado_codigo,fuente),''))
   FROM public.lf_activo_relaciones
   WHERE codigo_activo LIKE '%INPUT_GOVERNANCE%'
      OR relacionado_codigo LIKE '%INPUT_GOVERNANCE%'),
  'assets',(
   SELECT md5(coalesce(string_agg(codigo_activo||':'||coalesce(estado_operativo,''),
     ',' ORDER BY codigo_activo),''))
   FROM public.lf_activos WHERE codigo_activo LIKE '%INPUT_GOVERNANCE%')
 ) INTO v_snapshot_after;
 IF v_snapshot_after IS DISTINCT FROM v_snapshot_before THEN
   RAISE EXCEPTION 'M1012_POST_CLOSURE_RESIDUE_DELTA_NONZERO';
 END IF;

 IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)
   IS DISTINCT FROM 'DONE' THEN RAISE EXCEPTION 'M1012_WORK_NOT_TERMINAL'; END IF;
 IF (SELECT jsonb_agg(jsonb_build_object('cp',checkpoint_code,'status',status)
       ORDER BY sequence_no)
     FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_work)
   IS DISTINCT FROM
 '[{"cp":"RETIRE_SET_ASIS","status":"DONE"},
   {"cp":"REUSE_LEGACY_RETIREMENT","status":"DONE"},
   {"cp":"BATCH_DROP_NO_CASCADE","status":"NOT_APPLICABLE"},
   {"cp":"SMOKE_M7_PER_BATCH","status":"NOT_APPLICABLE"},
   {"cp":"NEG_CASCADE","status":"DONE"},
   {"cp":"ZERO_RESIDUE_READBACK","status":"DONE"}]'::jsonb THEN
   RAISE EXCEPTION 'M1012_FINAL_CHECKPOINT_LEDGER_DRIFT';
 END IF;
 SELECT p.progress_pct INTO v_progress
 FROM programacion.v_engineering_work_progress p
 WHERE p.work_code='PAULO-096';
 IF v_progress IS DISTINCT FROM 100 THEN
   RAISE EXCEPTION 'M1012_FINAL_PROGRESS_NOT_100:%',v_progress;
 END IF;
 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
 IF v_boot->>'terminal_action' IS DISTINCT FROM 'STOP_TERMINAL_DONE'
   OR v_boot#>>'{state,status}' IS DISTINCT FROM 'DONE'
 THEN RAISE EXCEPTION 'M1012_TERMINAL_BOOTSTRAP_NOT_DONE'; END IF;
END;
$m1012_close$;
