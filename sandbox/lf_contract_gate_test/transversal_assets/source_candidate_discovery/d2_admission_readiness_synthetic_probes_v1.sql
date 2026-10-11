-- D2 diagnostic contract tests: metadata only, no B2B records read.
WITH fixtures(case_code,source_ref,expected,expect_physical,expect_policy_false) AS (
 VALUES
 ('LOAD','db://lf_ops.cargas_lotes','REQUIRES_GOVERNED_SOURCE_AND_ACTOR_ADMISSION',1,true),
 ('LOAD_FILES','db://lf_ops.cargas_archivos','REQUIRES_GOVERNED_SOURCE_AND_ACTOR_ADMISSION',1,true),
 ('UNRELATED','db://public.lf_activos','REQUIRES_GOVERNED_SOURCE_AND_ACTOR_ADMISSION',1,false),
 ('NOT_FOUND','db://lf_ops.d2_probe_object_absent','BLOCK_EXACT_PHYSICAL_SOURCE_NOT_IN_CURRENT_CATALOG',0,false),
 ('BAD_REF','supabase://catalog/lf_ops/cargas_lotes','BLOCK_INVALID_CANONICAL_SOURCE_REF',0,false),
 ('NULL_REF',NULL::text,'BLOCK_INVALID_CANONICAL_SOURCE_REF',0,false)
), measured AS (
 SELECT case_code,source_ref,expected,expect_physical,expect_policy_false,
        private.fn_lf_d2_admission_readiness_v1(source_ref) AS result
 FROM fixtures
)
SELECT case_code,expected,result->>'decision' observed,
 CASE WHEN result->>'decision'=expected
   AND result->>'business_data_access_authorized'='false'
   AND result->>'business_rows_accessed'='false'
   AND result->>'runtime_enabled'='false'
   AND result->>'effects_executed'='false'
   AND result->>'global_discovery_exhausted'='false'
   AND pg_catalog.jsonb_typeof(result->'blocking_requirements')='array'
   AND (result->>'physical_source_count')::int=expect_physical
   AND (NOT expect_policy_false OR (
     result->'blocking_requirements' ? 'NO_PERMISSIVE_CLIENT_SELECT_RLS_POLICY'
     AND (result->>'authenticated_static_false_select_policies')::int>0
     AND result->>'authenticated_direct_select_granted'='false'))
  THEN 'PASS' ELSE 'FAIL' END verdict
FROM measured ORDER BY case_code;
