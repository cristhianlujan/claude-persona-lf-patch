-- IG M10.13 CP3 - seven deployed IG RPC roots / adversarial negative guard
-- SOURCE: live Supabase pg_proc, Edge source entrypoints (2026-11-11)
-- NO EFFECTS: SELECT-only; injected dependency exists ONLY inside this query.
-- Tested result: ACTUAL=120 reachable, 0 legacy; MUTATED=124 reachable, both legacy nodes detected.
-- This does NOT prove zero dynamic/external invocations. Never use alone as CP3 terminal PASS.
WITH RECURSIVE
fn AS (
 SELECT n.nspname||'.'||p.proname AS name,p.prosrc
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','programacion','lf_ops')
),
tok AS (
 SELECT f.name AS caller,m[1] tok
 FROM fn f CROSS JOIN LATERAL regexp_matches(f.prosrc,
  '((?:(?:programacion|public|lf_ops)[.])?(?:fn_[a-z_0-9]+|lf_[a-z_0-9]+))[[:space:]]*[(]','g') m
),
base_edges AS (
 SELECT DISTINCT t.caller,f.name AS callee
 FROM tok t JOIN fn f ON CASE WHEN strpos(t.tok,'.')>0 THEN f.name=t.tok
                              ELSE split_part(f.name,'.',2)=t.tok END
),
cases(scenario) AS (VALUES ('ACTUAL'::text),('MUTATED_REINTRODUCTION'::text)),
edges AS (
 SELECT c.scenario,b.caller,b.callee FROM cases c CROSS JOIN base_edges b
 UNION ALL
 SELECT 'MUTATED_REINTRODUCTION',
 'public.fn_input_governance_curator_materialize_v1',
 'programacion.fn_input_run_semantic_revalidation_v1'
),
roots(root) AS (
 VALUES ('public.fn_input_governance_execute'::text),
        ('public.fn_input_governance_safe_autofix_v1'),
        ('public.fn_input_governance_curator_materialize_v1'),
        ('public.fn_input_governance_curator_handoff_receipt_v1'),
        ('public.fn_input_governance_validator_handoff_assert_v1'),
        ('public.fn_input_governance_validator_validate_handoff_v1'),
        ('public.fn_input_governance_validator_resume_context_v1')
),
reach(scenario,node) AS (
 SELECT c.scenario::text COLLATE "C",r.root::text COLLATE "C"
 FROM cases c CROSS JOIN roots r
 UNION
 SELECT r.scenario,e.callee FROM reach r
 JOIN edges e ON e.scenario=r.scenario AND e.caller=r.node
),
results AS (
 SELECT c.scenario,
        count(DISTINCT r.node) AS reachable_functions,
        count(DISTINCT r.node) FILTER (WHERE r.node=
          'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2') AS target_seen,
        count(DISTINCT r.node) FILTER (WHERE r.node=
          'programacion.fn_input_run_semantic_revalidation_v1') AS consumer_seen
 FROM cases c LEFT JOIN reach r ON c.scenario=r.scenario
 GROUP BY c.scenario
)
SELECT scenario,reachable_functions,target_seen,consumer_seen,
 CASE WHEN target_seen=0 AND consumer_seen=0
   THEN 'NO_ACTIVE_STATIC_PATHS_DETECTED' ELSE 'FAIL_LEGACY_PATH_DETECTED' END AS verdict,
 CASE WHEN scenario='ACTUAL' AND target_seen=0 AND consumer_seen=0 THEN true
      WHEN scenario='MUTATED_REINTRODUCTION' AND target_seen>0 AND consumer_seen>0 THEN true
      ELSE false END AS adversarial_test_pass
FROM results ORDER BY scenario;
