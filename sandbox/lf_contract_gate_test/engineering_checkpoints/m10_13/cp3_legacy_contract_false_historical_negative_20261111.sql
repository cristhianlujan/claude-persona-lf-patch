-- LF IG / M10.13 CP3 | Contract interpretation negative test
-- No mutations: entirely SELECT, no changes to M10.4 freeze, ACLs, Router or runtime.
-- Full checkpoint ZERO_LEGACY_CALLERS is NOT passed by this test.
-- EKB: GOV-ASSET-RETIREMENT-GOVERNANCE-V1-001
--      IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001
--      IG-M104-LEGACY-ACTIVE-FREEZE-SCOPE-001
WITH
target AS (
 SELECT p.oid,p.oid::regprocedure::text AS signature,md5(p.prosrc) AS md5
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion'
 AND p.proname='fn_input_governance_bootstrap_classify_v2_cached_v2'
),
actual AS (
 SELECT count(DISTINCT p.oid)::int AS executable_sql_callers,
 count(DISTINCT p.oid) FILTER(WHERE p.proname='fn_input_run_semantic_revalidation_v1')::int AS legacy_runtime_callers
 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
 WHERE n.nspname IN ('public','programacion','lf_ops')
 AND p.proname <> 'fn_input_governance_bootstrap_classify_v2_cached_v2'
 AND p.prosrc ~* 'fn_input_governance_bootstrap_classify_v2_cached_v2[[:space:]]*[(]'
),
frozen AS (
 SELECT t.signature,t.md5,
 EXISTS(
  SELECT 1 FROM programacion.engineering_plan_units u
  CROSS JOIN LATERAL jsonb_array_elements(u.unit_metadata#>'{m104_freeze_baseline_v1,legacy_functions}') x
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND u.unit_code='M10.4'
  AND split_part(x->>'identity','(',1)='programacion.fn_input_governance_bootstrap_classify_v2_cached_v2'
  AND x->>'prosrc_md5'=t.md5
 ) AS frozen_hash_matches
 FROM target t
),
cases(scenario,executable_callers,permitted_archival_mentions) AS (
 SELECT 'CURRENT'::text,a.executable_sql_callers,1 FROM actual a
 UNION ALL
 SELECT 'FALSE_HISTORICAL_ONLY_CLAIM',a.executable_sql_callers,1 FROM actual a
 UNION ALL
 SELECT 'HYPOTHETICAL_ARCHIVAL_ONLY',0,1
)
SELECT c.scenario,c.executable_callers,c.permitted_archival_mentions,
 f.frozen_hash_matches,
 CASE
 WHEN c.executable_callers<>0 THEN 'BLOCK_SQL_CALLER_PRESENT'
 WHEN c.scenario='HYPOTHETICAL_ARCHIVAL_ONLY' THEN 'SQL_COMPONENT_CANDIDATE_ONLY_MORE_GATES_REQUIRED'
 ELSE 'NO_MATCH' END AS verdict,
 CASE
 WHEN c.scenario='CURRENT' THEN c.executable_callers=1 AND f.frozen_hash_matches
 WHEN c.scenario='FALSE_HISTORICAL_ONLY_CLAIM' THEN c.executable_callers>0
 WHEN c.scenario='HYPOTHETICAL_ARCHIVAL_ONLY' THEN c.executable_callers=0
 ELSE false END AS expected_test_pass
FROM cases c CROSS JOIN frozen f
ORDER BY c.scenario;
