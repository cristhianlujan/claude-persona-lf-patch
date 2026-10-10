-- LF D3 synthetic contract fixtures only; NO business case executed.
WITH fixtures(code,phase,observation,expected_action,expected_preview) AS (VALUES
('NO_SOURCE','SOURCE_DISCOVERY','{"discovery_state":"NO_MATCH_IN_SCOPE","candidate_count":0}'::jsonb,'EXPAND_DISCOVERY_SCOPE_OR_OBTAIN_MORE_CONTEXT',NULL),
('ONE_SOURCE','SOURCE_DISCOVERY','{"discovery_state":"CANDIDATES_FOUND","candidate_count":1}'::jsonb,'RESOLVE_CANONICAL_BINDING_FOR_CANDIDATES',NULL),
('MANY_SOURCES','SOURCE_DISCOVERY','{"discovery_state":"CANDIDATES_FOUND","candidate_count":4}'::jsonb,'RESOLVE_CANONICAL_BINDING_FOR_CANDIDATES',NULL),
('SOURCE_ERROR','SOURCE_DISCOVERY','{"discovery_state":"ERROR_FAIL_CLOSED"}'::jsonb,'BLOCK_DISCOVERY_POLICY_OR_TECHNICAL_ERROR',NULL),
('SOURCE_INCONSISTENT','SOURCE_DISCOVERY','{"discovery_state":"CANDIDATES_FOUND","candidate_count":0}'::jsonb,'BLOCK_MALFORMED_PROCEDURE_INPUT',NULL),
('BINDING_MISSING','BINDING_READBACK','{"binding_decision":"BLOCK_BINDING_ABSENT_OR_AMBIGUOUS"}'::jsonb,'SEARCH_OTHER_CANDIDATES_OR_GOVERN_BINDING',NULL),
('BINDING_READY','BINDING_READBACK','{"binding_decision":"STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION"}'::jsonb,'REQUEST_REAL_IDENTITY_AND_TENANT_FACADE_ADMISSION',NULL),
('BINDING_STALE','BINDING_READBACK','{"binding_decision":"BLOCK_INVENTORY_SOURCE_NOT_UNIQUE_CURRENT"}'::jsonb,'RETURN_TO_CANONICAL_SOURCE_DISCOVERY',NULL),
('NO_ROWS','FACADE_OBSERVATION','{"record_count":0,"freshness_state":"CURRENT","search_scope_complete":true}'::jsonb,'VERIFY_AUTHORIZED_FACADE_RECEIPT_IN_SUPABASE','NO_MATCH_WITHIN_CHECKED_SCOPE_ONLY'),
('ONE_ROW','FACADE_OBSERVATION','{"record_count":1,"freshness_state":"CURRENT","search_scope_complete":true}'::jsonb,'VERIFY_AUTHORIZED_FACADE_RECEIPT_IN_SUPABASE','INVESTIGATE_SINGLE_RECORD_STATUS_AND_RELATED_EVIDENCE'),
('MANY_ROWS','FACADE_OBSERVATION','{"record_count":5,"freshness_state":"CURRENT","search_scope_complete":true}'::jsonb,'VERIFY_AUTHORIZED_FACADE_RECEIPT_IN_SUPABASE','REQUEST_MINIMUM_DISAMBIGUATOR_FOR_MULTIPLE_RECORDS'),
('STALE_ROWS','FACADE_OBSERVATION','{"record_count":5,"freshness_state":"STALE","search_scope_complete":true}'::jsonb,'VERIFY_AUTHORIZED_FACADE_RECEIPT_IN_SUPABASE','REFRESH_FACADE_EVIDENCE'),
('PARTIAL_SEARCH','FACADE_OBSERVATION','{"record_count":0,"freshness_state":"CURRENT","search_scope_complete":false}'::jsonb,'VERIFY_AUTHORIZED_FACADE_RECEIPT_IN_SUPABASE','CONTINUE_BOUNDED_SEARCH_OR_REQUEST_SCOPE'),
('MISSING_FRESHNESS','FACADE_OBSERVATION','{"record_count":1,"search_scope_complete":true}'::jsonb,'BLOCK_MALFORMED_PROCEDURE_INPUT',NULL),
('UNKNOWN_SCOPE','FACADE_OBSERVATION','{"record_count":1,"freshness_state":"CURRENT"}'::jsonb,'BLOCK_MALFORMED_PROCEDURE_INPUT',NULL),
('NEGATIVE_ROWS','FACADE_OBSERVATION','{"record_count":-1,"freshness_state":"CURRENT","search_scope_complete":true}'::jsonb,'BLOCK_MALFORMED_PROCEDURE_INPUT',NULL),
('TECHNICAL_FAILURE','TECHNICAL_FAILURE','{}'::jsonb,'RETURN_TO_TARGETED_EVIDENCE_ACQUISITION',NULL),
('BAD_PHASE','UNKNOWN','{}'::jsonb,'BLOCK_MALFORMED_PROCEDURE_INPUT',NULL)
), observed AS (
 SELECT code,expected_action,expected_preview,
 private.fn_lf_d3_investigation_decision_v1(phase,observation) v FROM fixtures
)
SELECT code,expected_action,v->>'next_action' actual_action,
expected_preview,v->>'provisional_after_verified_receipt' AS provisional,
CASE WHEN expected_action=v->>'next_action'
  AND expected_preview IS NOT DISTINCT FROM v->>'provisional_after_verified_receipt'
  AND v->>'final_business_answer_allowed'='false'
  AND v->>'business_data_read_authorized'='false'
  AND v->>'global_discovery_exhausted'='false'
  AND v->>'effects_executed'='false'
 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM observed ORDER BY code;