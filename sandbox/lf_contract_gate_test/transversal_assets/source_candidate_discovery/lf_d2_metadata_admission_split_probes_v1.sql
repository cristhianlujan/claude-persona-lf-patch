-- Validate source metadata independent of enterprise admission.
-- All cases are intent metadata, no business reads or runtime execution.
WITH fixtures(case_code,objective,budget,expect_metadata,expect_action) AS (
 VALUES
 ('SOURCE_METADATA','carga lote archivo plantilla',12,true,'SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING'),
 ('BACKOFFICE_METADATA','El acceso al backoffice B2B no funciona',12,true,'SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING'),
 ('ABSENT_IN_SCOPE','nanoreactor cuántico',12,false,'EXPAND_DISCOVERY_SCOPE_OR_OBTAIN_MORE_CONTEXT'),
 ('INVALID_BUDGET','carga lote archivo plantilla',0,false,'BLOCK_DISCOVERY_POLICY_OR_TECHNICAL_ERROR')
), observed AS (
 SELECT case_code,expect_metadata,expect_action,
 private.fn_lf_source_investigation_prepare_v1(objective,budget) result
 FROM fixtures
), verdicts AS (
 SELECT case_code,
 CASE WHEN
 result->>'next_action'=expect_action
 AND (CASE WHEN expect_metadata
   THEN (result->>'metadata_technically_verified_count')::integer>0
   ELSE coalesce((result->>'metadata_technically_verified_count')::integer,0)=0 END)
 AND NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements(coalesce(result->'binding_checks','[]'::jsonb)) b
   WHERE b->>'access_authorized'<>'false'
      OR b->>'rows_accessed'<>'false')
 AND result->>'business_data_read_authorized'='false'
 AND result->>'final_business_answer_allowed'='false'
 AND result->>'runtime_dispatched'='false'
 AND result->>'global_discovery_exhausted'='false'
 AND result->>'effects_executed'='false'
 THEN 'PASS' ELSE 'FAIL' END verdict
 FROM observed
)
SELECT count(*)::int AS total,
count(*) FILTER(WHERE verdict='PASS')::int AS passed,
jsonb_agg(jsonb_build_object('case',case_code,'verdict',verdict) ORDER BY case_code) AS cases
FROM verdicts;

-- Independent direct candidate rejection: unknown or forged route is never
-- technically admitted by metadata tools.
SELECT
 CASE WHEN private.fn_lf_d2_source_binding_candidate_v1('db://lf_ops.nonexistent_source')->>'decision'
   ='BLOCK_NOT_IN_CANONICAL_INVENTORY'
 AND private.fn_lf_d2_source_binding_candidate_v1('external://not-a-source')->>'decision'
   ='BLOCK_INVALID_SOURCE_REF'
 THEN 'PASS' ELSE 'FAIL' END AS invalid_ref_rejection;
