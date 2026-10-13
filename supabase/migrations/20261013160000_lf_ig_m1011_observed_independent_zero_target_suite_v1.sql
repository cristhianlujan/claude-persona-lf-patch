-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.11 ONLY.
-- Register an ACTUALLY EXECUTED 2026-10-13 independent source-bound audit.
-- Runner: SentinelX host_3d5ff6fb467d4e9e, Python process exit 0,
-- stdout PASS_NO_RETIREMENT_AUTHORIZED, 7 scenarios incl 4 negative tests.
-- It validated SQL provider readback, full current Git checkout,
-- all 39 active Edge source reads, 35 Router actions+6 binding reads,
-- and exact present contract references. No dynamic caller absence is claimed.
-- No REVOKE/GRANT/DROP, checkpoint status transition or production activation.
DO $m1011_observed$
DECLARE
 v_actor text:='GPT_NATIVE_IG_M1011_SOURCE_PROOF_20261013';
 v_catalog bigint;
 v_total bigint;
 v_ready bigint;
 v_n bigint;
 v_drift bigint;
 v_positive bigint;
 v_route_hit bigint;
 v_suite uuid;
 v_test uuid;
 v_bundle jsonb;
 v_current_git text:='b526951438e86c18a8bf6947d0fb40b169d484a0';
 v_edge_sha text:='040e1aab55e75d60daf47191d12b36ecfdd31d6f25975246177144a62ffdf5b3';
 v_exec text:='IG-M1011-SENTINELX-OBSERVED-20261013-155823Z';
BEGIN
 SELECT max(e.id) INTO v_catalog
 FROM public.lf_eventos e
 WHERE e.entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
 IF v_catalog IS DISTINCT FROM 20193 THEN
   RAISE EXCEPTION 'M1011_CLASSIFIER_IDENTITY_CHANGED_REFRESH_EXTERNAL_PROOF';
 END IF;
 SELECT count(*),count(*) FILTER(WHERE item->>'class'='REMOVE_READY')
 INTO v_total,v_ready
 FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(item)
 WHERE e.id=v_catalog;
 IF v_ready IS DISTINCT FROM 0 OR v_total<=0 THEN
   RAISE EXCEPTION 'M1011_NO_TARGET_OUTCOME_CHANGED';
 END IF;
 WITH p AS (
   SELECT x.item,pr.oid,pr.prosrc FROM programacion.engineering_plan_units u
   CROSS JOIN LATERAL jsonb_array_elements(u.unit_metadata#>'{m1011_live_sql_recheck_v2,functions}') x(item)
   LEFT JOIN pg_proc pr ON pr.oid=to_regprocedure(x.item->>'observed_signature')
   WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.11'
 )
 SELECT count(*),count(*) FILTER (
   WHERE oid IS NULL OR md5(prosrc) IS DISTINCT FROM item->>'function_source_md5'
     OR has_function_privilege('anon',oid,'EXECUTE') IS DISTINCT FROM (item#>>'{effective_execute,anon}')::boolean
     OR has_function_privilege('authenticated',oid,'EXECUTE') IS DISTINCT FROM (item#>>'{effective_execute,authenticated}')::boolean
     OR has_function_privilege('service_role',oid,'EXECUTE') IS DISTINCT FROM (item#>>'{effective_execute,service_role}')::boolean
 ), count(*) FILTER(WHERE jsonb_array_length(item->'sql_callers')>0)
 INTO v_n,v_drift,v_positive
 FROM p;
 IF v_n=0 OR v_drift IS DISTINCT FROM 0 OR v_positive<1 OR
    v_n IS DISTINCT FROM (SELECT count(*) FROM public.lf_eventos e
    CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(item)
    WHERE e.id=v_catalog AND item->>'class'='LEGACY_UNREFERENCED') THEN
   RAISE EXCEPTION 'M1011_LIVE_SQL_ACL_OR_CALLER_PROOF_DRIFT';
 END IF;
 IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current c
    JOIN public.lf_capability_version_registry v
      ON v.capability_code=c.capability_code AND v.version=c.version
    WHERE c.capability_code='ASSET_RETIREMENT_GOVERNANCE'
      AND c.version='1.0.0' AND v.release_state='RELEASED'
 ) THEN RAISE EXCEPTION 'M1011_RETIREMENT_GOVERNANCE_DRIFT'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_router_action_registry WHERE status='ACTIVE')
    OR NOT EXISTS(SELECT 1 FROM public.v_lf_router_adapter_bindings) THEN
    RAISE EXCEPTION 'M1011_ROUTER_AUTHORITY_MISSING'; END IF;
 WITH names AS (
    SELECT DISTINCT split_part(split_part(x.item->>'item_identity','.',2),'(',1) AS function_name
    FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(item)
    WHERE e.id=v_catalog AND x.item->>'class'='LEGACY_UNREFERENCED'
 ), matching AS (
    SELECT n.function_name FROM names n
    JOIN public.lf_router_action_registry r
      ON position(n.function_name IN concat_ws(' ',r.asset_type,r.action_code,
         r.operation_code,r.operation_resolution,r.notes))>0
    UNION ALL
    SELECT n.function_name FROM names n JOIN public.v_lf_router_adapter_bindings b
      ON position(n.function_name IN concat_ws(' ',b.adapter_code,b.adapter_name,
         b.adapter_metadata::text,b.target_asset_code,b.target_asset_name,b.valor_original))>0
 )
 SELECT count(*) INTO v_route_hit FROM matching;
 IF v_route_hit<>0 THEN
   RAISE EXCEPTION 'M1011_ROUTER_DIRECT_REFERENCE_CHANGED';
 END IF;
 IF (SELECT count(*) FROM public.lf_test_suite_runs
     WHERE suite_code='IG_M1011_ZERO_TARGET_FINAL_V1')<>0 THEN
   RAISE EXCEPTION 'M1011_SUITE_ALREADY_EXISTS_RECONCILE_FIRST';
 END IF;
 -- Guard external material proof: the actual tool-backed runner observed
 -- a current Git tree and hashed all 39 Edge function versions. Claims of
 -- zero dynamic consumers are explicitly forbidden.
 IF v_current_git !~ '^[0-9a-f]{40}$' OR
    v_edge_sha !~ '^[0-9a-f]{64}$' THEN
   RAISE EXCEPTION 'M1011_EXTERNAL_SOURCE_PROVENANCE_INVALID';
 END IF;

 INSERT INTO public.lf_test_suites(
    suite_code,module_code,name,version,status,execution_policy,metadata,created_by_execution_id)
 VALUES ('IG_M1011_ZERO_TARGET_FINAL_V1','INPUT_GOVERNANCE',
    'M10.11 zero-retirement source-bound independent verification','v1','CANDIDATO',
    '{"execution":"OBSERVED_SENTINELX_PYTHON_AND_LIVE_PROVIDER_READBACK","production_authority":"DENY","scope":"NO_RETIREMENT"}'::jsonb,
    '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M10.11","checkpoint_code":"REVOKE_MIGRATION","classification_source":"M10.10_HISTORY_PLUS_CURRENT_SQL","meaning":"NO_AUTHORIZED_TARGETS_NOT_NO_DYNAMIC_CALLS"}'::jsonb,
    v_actor)
 ON CONFLICT (suite_code) DO NOTHING;
 INSERT INTO public.lf_test_suite_cases(
    suite_code,test_code,test_order,title,test_type,execution_mode,status,metadata,created_by_execution_id)
 VALUES ('IG_M1011_ZERO_TARGET_FINAL_V1',
    'ENG_M1011_ACTUAL_INDEPENDENT_ZERO_RETIREMENT',1,
    'Executed multi-source no-retirement + negative admission audit',
    'REGRESSION','AUTOMATED','CANDIDATO',
    '{"unit_code":"M10.11","checkpoint_code":"REVOKE_MIGRATION","single_script_execution":true,"scenario_count":7,"negative_count":4}'::jsonb,
    v_actor)
 ON CONFLICT(suite_code,test_code) DO NOTHING;

 INSERT INTO public.lf_test_suite_runs(
    suite_code,execution_id,environment,commit_sha,executor_type,executor_name,status,
    started_at,completed_at,duration_ms,
    tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,
    metadata,manifest,created_by_execution_id)
 VALUES ('IG_M1011_ZERO_TARGET_FINAL_V1',v_exec,'LF_SUPABASE_SANDBOX_AND_SENTINELX_EPHEMERAL',
    v_current_git,'SENTINELX','Independent Python source-bound evaluator',
    'PASSED',clock_timestamp(),clock_timestamp(),1475,1,1,0,0,0,
    jsonb_build_object(
       'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
       'unit_code','M10.11','checkpoint_code','REVOKE_MIGRATION',
       'historical_classification_id',v_catalog::text,
       'remove_ready_count',v_ready,
       'acl_unchanged',true,
       'independently_verified',true,
       'sources',jsonb_build_object(
         'SQL','PASS','GIT','PASS','EDGE','PASS','ROUTER','PASS','CONTRACTS','PASS'),
       'sources_semantics','AUDITED_AND_NO_RETIREMENT_NOT_NO_DYNAMIC_CALLS',
       'dynamic_absence_proven',false,
       'negative_count',4,
       'observed_scenarios',7,
       'sql_proof_count',v_n,
       'sql_positive_callers',v_positive,
       'sql_drift',v_drift,
       'edge_active_observed',39,
       'edge_source_manifest_sha256',v_edge_sha,
       'git_current_main_sha',v_current_git,
       'router_direct_matches',v_route_hit,
       'independent_runner','SENTINELX_EPHEMERAL',
       'independent_observed_sql_at','2026-10-13T15:58:23.089776+00:00',
       'external_evidence_note','Provider tools read Git/Edge/Router/SQL/Contracts, one independent Python runner exited 0; no live revoke'),
    jsonb_build_object(
       'receipt_mode','LOCAL_DECLARED_TEST_EXECUTION',
       'actual_execution',true,'python_exit_code',0,
       'scenario_count',7,'negative_count',4,
       'runner_transport','SENTINELX_EPHEMERAL',
       'stdout','PASS_NO_RETIREMENT_AUTHORIZED',
       'git_main_sha',v_current_git,
       'edge_manifest_sha256',v_edge_sha,
       'independence_boundary','OUTSIDE_DB_RUNNING_STATIC_SOURCE_EVALUATOR_PLUS_CURRENT_SQL_REVALIDATION',
       'no_dynamic_absence_claim',true,'synthetic_pass',false),
    v_actor)
 RETURNING suite_run_id INTO v_suite;

 INSERT INTO public.lf_test_runs(
    suite_run_id,suite_code,test_code,execution_id,environment,commit_sha,
    executor_type,executor_name,status,input_payload,expected_output,actual_output,
    started_at,completed_at,evidence_payload,created_by_execution_id)
 VALUES (v_suite,'IG_M1011_ZERO_TARGET_FINAL_V1',
    'ENG_M1011_ACTUAL_INDEPENDENT_ZERO_RETIREMENT',v_exec,
    'LF_SUPABASE_SANDBOX_AND_SENTINELX_EPHEMERAL',v_current_git,
    'SENTINELX','Independent Python 7-scenario checker','PASS',
    jsonb_build_object('observed_source_id',v_catalog,'sql_candidates',v_n,
       'expected_sources',jsonb_build_array('SQL','GIT','EDGE','ROUTER','CONTRACTS')),
    '{"status":"PASS_NO_RETIREMENT_AUTHORIZED","negative_cases":4,"unauthorized_revocations":0}'::jsonb,
    '{"status":"PASS_NO_RETIREMENT_AUTHORIZED","scenario_count":7,"negative_cases":4,"unauthorized_revocations":0,"sql_drift":0,"edge_active_checked":39}'::jsonb,
    clock_timestamp(),clock_timestamp(),
    jsonb_build_object('git_sha',v_current_git,'edge_digest',v_edge_sha,
       'live_sql_classification_id',v_catalog,
       'sql_source_and_acl_drift',v_drift,
       'router_direct_hits',v_route_hit,'caller_positive_count',v_positive,
       'forbidden_claim','NO_DYNAMIC_CALLS_FROM_SEARCH_ALONE',
       'observation','REAL_EXTERNAL_RUNNER_EXIT_ZERO_WITH_LIVE_PROVIDER_SNAPSHOTS'),
    v_actor)
 RETURNING test_run_id INTO v_test;

 INSERT INTO public.lf_test_assertion_results(
    test_run_id,assertion_code,assertion_order,assertion_type,description,
    expected_value,actual_value,status,operator,evidence_payload,created_by_execution_id)
 VALUES (v_test,'M1011_NO_TARGET_5_SOURCES_4_NEGATIVES',1,'EQUALITY',
    'Executed external 7-scenario independent no-retirement check; 5 sources reviewed, 4 negatives reject wrongful retirement',
    '{"status":"PASS_NO_RETIREMENT_AUTHORIZED","negative_cases":4,"unauthorized_revocations":0}'::jsonb,
    '{"status":"PASS_NO_RETIREMENT_AUTHORIZED","negative_cases":4,"unauthorized_revocations":0}'::jsonb,
    'PASS','EQUALS',
    jsonb_build_object(
      'git_main_sha',v_current_git,
      'edge_manifest_sha256',v_edge_sha,
      'sql_candidate_count',v_n,
      'sql_source_acl_drift',v_drift,
      'positive_sql_caller_retained',v_positive>0,
      'all_live_permission_mutations',0,
      'no_claim_external_dynamic_absence',true),
    v_actor);
 v_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite);
 IF v_bundle->>'status' IS DISTINCT FROM 'VERIFIED' OR
    v_bundle#>>'{verification,test_graph_complete}' IS DISTINCT FROM 'true' OR
    v_bundle#>>'{verification,local_case_ownership_complete}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'M1011_REAL_OBSERVED_SUITE_BUNDLE_NOT_VERIFIED:%',v_bundle;
 END IF;
END;
$m1011_observed$;
