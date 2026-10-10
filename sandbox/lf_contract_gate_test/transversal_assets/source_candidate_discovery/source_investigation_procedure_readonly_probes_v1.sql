-- D1-D2-D3 metadata-only orchestration; fixtures are intent strings only.
-- NEVER an enterprise data lookup, auth impersonation or end-to-end runtime test.
WITH fixture(code,objective,budget,expected_action) AS (VALUES
('DISCOVER_METADATA','Subí una carga y no aparece',12,'SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING'),
('DIFFERENT_DOMAIN','El acceso al backoffice B2B no funciona',12,'SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING'),
('ABSENT_IN_SCOPE','nanoreactor cuántico',12,'EXPAND_DISCOVERY_SCOPE_OR_OBTAIN_MORE_CONTEXT'),
('BAD_BUDGET','Subí una carga y no aparece',0,'BLOCK_DISCOVERY_POLICY_OR_TECHNICAL_ERROR')
), observed AS (
 SELECT code,expected_action,
 private.fn_lf_source_investigation_prepare_v1(objective,budget) result
 FROM fixture
)
SELECT code,expected_action,result->>'next_action' observed_action,
 result->>'binding_checks_count' AS bindings_checked,
 result->>'planner_code' AS planner_code,
 result->'discovery'->>'discovery_state' discovery_state,
 CASE WHEN result->>'next_action'=expected_action
  AND result->>'business_data_read_authorized'='false'
  AND result->>'final_business_answer_allowed'='false'
  AND result->>'global_discovery_exhausted'='false'
  AND result->>'runtime_dispatched'='false'
  AND result->>'effects_executed'='false'
  AND result->>'planner_stop_is_local_only'='true'
 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM observed ORDER BY code;