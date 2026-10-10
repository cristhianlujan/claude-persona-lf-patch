-- D1/D2 DEVELOPMENT SMOKE: append real observations, preserve BLOCKED.
-- Source runner Git blob: d9b3c75e1c319dedb7d368edf152096a579b1bd8; PR #2208 merge 0e7e0edbc4a129e291679be64b46774be5e7ec62.
-- This is NOT a quality benchmark or runtime authorization proof.
DO $preimage$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_test_suite_runs
   WHERE suite_code='TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1'
   AND metadata->>'runner_git_blob'='d9b3c75e1c319dedb7d368edf152096a579b1bd8')
 THEN RAISE EXCEPTION 'D1D2_SMOKE_RUN_ALREADY_REGISTERED'; END IF;
 IF (SELECT count(*) FROM public.lf_test_suite_cases WHERE suite_code='TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1')<>12
 THEN RAISE EXCEPTION 'D1D2_SUITE_FIXTURE_DRIFT'; END IF;
END $preimage$;

WITH observed AS (
-- D1/D2 canonical smoke suite read-only runner (observation only).
-- Reads registered case inputs/expected separately; neither guides candidate
-- selection nor creates authority. Fixture catalog scope lf_ops, not runtime.
-- No production reads and no official run is written by this SQL.
WITH suite_cases AS (
 SELECT c.test_code,c.test_order,c.metadata->>'scenario_code' AS scenario,
        c.input_payload->>'objective' AS objective,
        c.expected_output->>'expected_state' AS expected_state,
        c.expected_output->>'expected_candidate_family' AS expected_family
 FROM public.lf_test_suite_cases c
 WHERE c.suite_code='TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1'
), currentness AS (
 SELECT count(*)::int AS active_versions,max(policy_sha) AS policy_sha
 FROM public.lf_policy_versions
 WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE'
), fixture_parameters AS (
 SELECT c.*, p.active_versions,p.policy_sha,
 CASE WHEN c.scenario='POLICY_DRIFT' THEN repeat('0',64)
      ELSE p.policy_sha END AS supplied_policy_sha,
 CASE WHEN c.scenario='SCHEMA_SCOPE_EMPTY' THEN ARRAY[]::text[]
      ELSE ARRAY['lf_ops']::text[] END AS supplied_metadata_schemas,
 CASE WHEN c.scenario='BUDGET_INVALID' THEN 0 ELSE 5 END AS supplied_budget
 FROM suite_cases c CROSS JOIN currentness p
), tokenized AS (
 SELECT f.*,
 (f.active_versions=1
  AND f.policy_sha IS NOT DISTINCT FROM f.supplied_policy_sha
  AND cardinality(f.supplied_metadata_schemas) BETWEEN 1 AND 16
  AND f.supplied_budget BETWEEN 1 AND 20) AS input_guard_pass,
 regexp_replace(plainto_tsquery('spanish',f.objective)::text,
                           ' +& +',' | ','g')::tsquery AS terms
 FROM fixture_parameters f
), metadata_probes AS (
 SELECT c.test_code,
 EXISTS(
   SELECT 1 FROM pg_catalog.pg_class obj
   JOIN pg_catalog.pg_namespace n ON n.oid=obj.relnamespace
   WHERE c.input_guard_pass AND n.nspname=ANY(c.supplied_metadata_schemas) AND obj.relkind IN ('r','p','v')
   AND NOT obj.relispartition
   AND ts_rank_cd(to_tsvector('spanish',replace(obj.relname,'_',' ')),c.terms)>0
 ) AS physical_hit,
 EXISTS(
   SELECT 1 FROM public.v_lf_fuente_operativa_busqueda a
   WHERE c.input_guard_pass AND ts_rank_cd(to_tsvector('spanish',coalesce(a.router_search_text,'')),c.terms)>0
 ) AS registered_asset_hit
 FROM tokenized c
), authorization_preconditions AS (
 SELECT count(*) FILTER(WHERE metadata->>'canonical_source_ref'='supabase://catalog/lf_ops/cargas_lotes'
                 AND metadata->>'admission_status'='VIGENTE')::int AS bound_sources
 FROM public.lf_activos WHERE archived_at IS NULL
), planner AS (
 SELECT public.lf_targeted_evidence_acquisition_plan_v1(
 jsonb_build_object('consumer_ref','synthetic://lf-d1d2-smoke-run',
  'unresolved_reasons',jsonb_build_array('SOURCE_AUTHORITY_UNVERIFIED'),
  'current_evidence',jsonb_build_array(),'candidates',jsonb_build_array())
 ) AS outcome
), observed AS (
 SELECT c.test_code,c.test_order,c.scenario,c.expected_state,c.expected_family,
   m.physical_hit,m.registered_asset_hit,
 CASE
 WHEN NOT c.input_guard_pass THEN 'ERROR_FAIL_CLOSED'
 WHEN c.scenario='NO_CANONICAL_BINDING'
    THEN CASE WHEN a.bound_sources=0 THEN 'BLOCK_CANONICAL_READ_BINDING_ABSENT'
      ELSE 'BINDING_PRESENT_REQUIRES_AUTH_CHECK' END
 WHEN c.scenario='NO_B2B_ACTOR'
    THEN CASE WHEN a.bound_sources=0 THEN 'BLOCKED_PRECONDITION_BINDING'
      WHEN auth.uid() IS NULL THEN 'BLOCK_ACTOR_NOT_AUTHENTICATED'
      ELSE 'ACTOR_PRESENT_NEEDS_REAL_SESSION_TEST' END
 WHEN c.scenario='TENANT_CROSS_SCOPE'
    THEN 'BLOCKED_NO_REAL_TENANT_FIXTURES'
 WHEN c.scenario='PLANNER_LOCAL_EXHAUSTION'
    THEN CASE WHEN (planner.outcome->>'state')='STOP'
         AND (planner.outcome->>'code')='STOP_NO_DECISION_CHANGING_EVIDENCE'
         AND (planner.outcome->>'effects_executed')='false'
      THEN 'RETURN_TO_SOURCE_DISCOVERY'
      ELSE 'PLANNER_CONTRACT_FAILED' END
 WHEN m.physical_hit OR m.registered_asset_hit THEN 'CANDIDATES_FOUND'
 ELSE 'NO_MATCH_IN_SCOPE'
 END AS observed_state
 FROM tokenized c JOIN metadata_probes m USING(test_code)
 CROSS JOIN authorization_preconditions a CROSS JOIN planner
), verdicts AS (
 SELECT *,
 CASE
   WHEN observed_state LIKE 'BLOCKED_%' THEN 'BLOCKED'
   WHEN observed_state=expected_state
      AND (expected_family='NONE'
        OR (expected_family='SCHEMA_METADATA' AND physical_hit)
        OR (expected_family='SOURCE_REGISTRY' AND registered_asset_hit))
       THEN 'PASS'
   ELSE 'FAIL'
 END AS result
 FROM observed
)
SELECT test_code,scenario,expected_state,observed_state,result,
       physical_hit,registered_asset_hit,
       false AS business_data_read_authorized,false AS global_discovery_exhausted
FROM verdicts ORDER BY test_order
), summary AS (
 SELECT count(*)::integer AS total,
 count(*) FILTER(WHERE result='PASS')::integer AS passed,
 count(*) FILTER(WHERE result='FAIL')::integer AS failed,
 count(*) FILTER(WHERE result='BLOCKED')::integer AS blocked,
 jsonb_agg(jsonb_build_object('test_code',test_code,'scenario',scenario,
       'expected_state',expected_state,'observed_state',observed_state,
       'status',result,'business_data_read_authorized',business_data_read_authorized,
       'global_discovery_exhausted',global_discovery_exhausted)
       ORDER BY test_code) AS cases
 FROM observed
), admitted AS (
 SELECT * FROM summary
 WHERE total=12 AND passed+failed+blocked=total
 AND blocked>0
)
INSERT INTO public.lf_test_suite_runs
(suite_code,execution_id,environment,application_version,commit_sha,
 executor_type,executor_name,status,started_at,completed_at,
 tests_total,tests_passed,tests_failed,tests_blocked,
 manifest,metadata,created_by_execution_id)
SELECT 'TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1',
 'EXEC-LF-D1D2-CANONICAL-SMOKE-20261010-001',
 'LF_SUPABASE_SANDBOX','D1_D2_DEV_SMOKE_V1',
 '0e7e0edbc4a129e291679be64b46774be5e7ec62',
 'SQL_READONLY_CANONICAL','LF_D1_D2_SMOKE_READER',
 CASE WHEN failed>0 THEN 'FAILED'
      WHEN blocked>0 THEN 'BLOCKED' ELSE 'PASSED' END,
 clock_timestamp(),clock_timestamp(),
 total,passed,failed,blocked,
 jsonb_build_object('schema_version','LF_D1D2_SMOKE_CASE_OBSERVATIONS_V1',
  'case_results',cases,'source_of_truth','SUPABASE',
  'metadata_only',true,'business_rows_read',false,
  'blind_holdout',false,'admission_authorized',false),
 jsonb_build_object('runner_git_blob','d9b3c75e1c319dedb7d368edf152096a579b1bd8',
  'runner_source_path','sandbox/lf_contract_gate_test/transversal_assets/source_candidate_discovery/canonical_smoke_readonly_runner_v1.sql',
  'source_pr',2208,'source_merge_sha','0e7e0edbc4a129e291679be64b46774be5e7ec62',
  'suite_kind','DEVELOPMENT_SMOKE','not_quality_benchmark',true,
  'cross_tenant_real_test_pending',true,'policy_from_supabase',true),
 'EXEC-LF-D1D2-CANONICAL-SMOKE-20261010-001'
FROM admitted;

DO $verify$
DECLARE v record;
BEGIN
 SELECT status,tests_total,tests_passed,tests_failed,tests_blocked INTO v
 FROM public.lf_test_suite_runs
 WHERE suite_code='TS-LF-D1-D2-SOURCE-DISCOVERY-SMOKE-V1'
 AND metadata->>'runner_git_blob'='d9b3c75e1c319dedb7d368edf152096a579b1bd8';
 IF NOT FOUND OR v.tests_total<>12 OR v.tests_passed+v.tests_failed+v.tests_blocked<>12
   OR v.status<>'BLOCKED' THEN
   RAISE EXCEPTION 'D1D2_OBSERVATIONS_NOT_REGISTERED_CONSISTENTLY';
 END IF;
END $verify$;
