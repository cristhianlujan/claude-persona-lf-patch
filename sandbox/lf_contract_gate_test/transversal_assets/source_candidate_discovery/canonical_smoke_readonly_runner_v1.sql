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
), tokenized AS (
 SELECT c.*,regexp_replace(plainto_tsquery('spanish',c.objective)::text,
                           ' +& +',' | ','g')::tsquery AS terms
 FROM suite_cases c
), metadata_probes AS (
 SELECT c.test_code,
 EXISTS(
   SELECT 1 FROM pg_catalog.pg_class obj
   JOIN pg_catalog.pg_namespace n ON n.oid=obj.relnamespace
   WHERE n.nspname='lf_ops' AND obj.relkind IN ('r','p','v')
   AND NOT obj.relispartition
   AND ts_rank_cd(to_tsvector('spanish',replace(obj.relname,'_',' ')),c.terms)>0
 ) AS physical_hit,
 EXISTS(
   SELECT 1 FROM public.v_lf_fuente_operativa_busqueda a
   WHERE ts_rank_cd(to_tsvector('spanish',coalesce(a.router_search_text,'')),c.terms)>0
 ) AS registered_asset_hit
 FROM tokenized c
), currentness AS (
 SELECT count(*)::int AS active_versions,max(policy_sha) AS policy_sha
 FROM public.lf_policy_versions
 WHERE policy_code='POL-LF-SOURCE-RESOLUTION' AND status='ACTIVE'
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
 WHEN c.scenario='POLICY_DRIFT'
    THEN CASE WHEN p.active_versions=1 AND p.policy_sha IS DISTINCT FROM repeat('0',64)
      THEN 'ERROR_FAIL_CLOSED' ELSE 'ERROR_POLICY_FIXTURE_INVALID' END
 WHEN c.scenario='SCHEMA_SCOPE_EMPTY' THEN 'ERROR_FAIL_CLOSED'
 WHEN c.scenario='BUDGET_INVALID' THEN 'ERROR_FAIL_CLOSED'
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
 CROSS JOIN currentness p CROSS JOIN authorization_preconditions a CROSS JOIN planner
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
FROM verdicts ORDER BY test_order;
-- Fail and blocked are preserved; no case is silently called PASS.
