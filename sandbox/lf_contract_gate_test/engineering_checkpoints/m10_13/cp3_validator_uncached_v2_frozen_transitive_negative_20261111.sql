-- LF M10.13 CP3 | adversarial guard for transitive frozen M10.4 dependencies
-- Pure SELECT; adds only hypothetical call edges inside a CTE.
WITH RECURSIVE
fn AS (
 SELECT n.nspname||'.'||p.proname AS name,p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','programacion','lf_ops')
),tokens AS (
 SELECT f.name caller,m[1] token FROM fn f CROSS JOIN LATERAL regexp_matches(f.prosrc,'((?:(?:programacion|public|lf_ops)[.])?(?:fn_[a-z_0-9]+|lf_[a-z_0-9]+))[[:space:]]*[(]','g') m
),base_edges AS (
 SELECT DISTINCT t.caller,f.name AS callee FROM tokens t JOIN fn f ON CASE WHEN strpos(t.token,'.')>0 THEN f.name=t.token ELSE split_part(f.name,'.',2)=t.token END
),cases(scenario,added_classifier,expected_frozen_count) AS (
 VALUES
 ('CURRENT_VALIDATOR'::text,NULL::text,0),
 ('CANDIDATE_UNCACHED_V2','programacion.fn_input_governance_bootstrap_classify_v2',0),
 ('REJECTED_CACHED_CTX','programacion.fn_input_governance_bootstrap_classify_v2_ctx',3)
),edges AS (
 SELECT c.scenario,e.caller,e.callee FROM cases c CROSS JOIN base_edges e
 UNION ALL SELECT scenario,'programacion.fn_input_governance_validate_v2',added_classifier
 FROM cases WHERE added_classifier IS NOT NULL
),reachable(scenario,node) AS (
 SELECT scenario::text COLLATE "C",'programacion.fn_input_governance_validate_v2'::text COLLATE "C" FROM cases
 UNION SELECT r.scenario,e.callee FROM reachable r JOIN edges e ON e.scenario=r.scenario AND e.caller=r.node
),frozen AS (
 SELECT split_part(x->>'identity','(',1) AS name
 FROM programacion.engineering_plan_units u CROSS JOIN LATERAL jsonb_array_elements(u.unit_metadata#>'{m104_freeze_baseline_v1,legacy_functions}') x
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.4'
),outcomes AS (
 SELECT c.scenario,c.added_classifier,c.expected_frozen_count,count(DISTINCT r.node)::int reachable_functions,
 count(DISTINCT f.name)::int reached_frozen_count,coalesce(jsonb_agg(DISTINCT f.name) FILTER(WHERE f.name IS NOT NULL),'[]'::jsonb) reached_frozen
 FROM cases c LEFT JOIN reachable r ON r.scenario=c.scenario LEFT JOIN frozen f ON f.name=r.node
 GROUP BY c.scenario,c.added_classifier,c.expected_frozen_count
)
SELECT *, (reached_frozen_count=expected_frozen_count) AS negative_guard_test_pass,
 CASE WHEN reached_frozen_count=0 THEN 'NO_STATIC_FROZEN_PATHS'
      ELSE 'BLOCK_FROZEN_DEPENDENCY_REINTRODUCTION' END AS verdict,
 'STATIC_REACHABILITY_NOT_RUNTIME_EXECUTION'::text AS proof_scope
FROM outcomes ORDER BY scenario;