-- Negative matrix: raise on any failure instead of returning only the last SELECT.
DO $checks$
DECLARE failures integer;
BEGIN
WITH checks(case_code,source_ref,payload,expected) AS (
 VALUES
 ('NO_APPROVAL','db://lf_ops.cargas_lotes','{"admission_status":"VIGENTE"}'::jsonb,'BLOCK_SOURCE_BINDING_AUTHORITY_RECEIPT_MISSING'),
 ('FAKE_UUIDS','db://lf_ops.cargas_lotes','{"admission_status":"VIGENTE","human_decision_request_id":"11111111-1111-4111-8111-111111111111","human_decision_receipt_id":"22222222-2222-4222-8222-222222222222"}'::jsonb,'BLOCK_SOURCE_BINDING_AUTHORITY_REQUEST_NOT_CURRENT'),
 ('FAKE_APPROVER','db://lf_ops.cargas_lotes','{"admission_status":"VIGENTE","approved_by_ref":"SYNTHETIC_SELF_ASSERTED"}'::jsonb,'BLOCK_SOURCE_BINDING_AUTHORITY_RECEIPT_MISSING'),
 ('NOT_VIGENTE','db://lf_ops.cargas_lotes','{"admission_status":"CANDIDATO"}'::jsonb,'BLOCK_SOURCE_BINDING_AUTHORITY_INPUT_INVALID'),
 ('INVALID_OBJECT','db://lf_ops.cargas_lotes','[]'::jsonb,'BLOCK_SOURCE_BINDING_AUTHORITY_INPUT_INVALID'),
 ('BAD_REF','supabase://fake/source','{"admission_status":"VIGENTE"}'::jsonb,'BLOCK_SOURCE_BINDING_AUTHORITY_INPUT_INVALID'),
 ('NULL_REF',NULL::text,'{"admission_status":"VIGENTE"}'::jsonb,'BLOCK_SOURCE_BINDING_AUTHORITY_INPUT_INVALID'),
 ('INVALID_UUID_TEXT','db://lf_ops.cargas_lotes','{"admission_status":"VIGENTE","human_decision_request_id":"forged","human_decision_receipt_id":"forged"}'::jsonb,'BLOCK_SOURCE_BINDING_AUTHORITY_RECEIPT_MISSING')
),
result AS (
 SELECT case_code,expected,private.fn_lf_d2_source_binding_authority_gate_v1(source_ref,payload) v FROM checks
)

SELECT count(*) FILTER(WHERE NOT(
 v->>'decision'=expected
 AND v->>'authority_receipt_reverified'='false'
 AND v->>'business_data_read_authorized'='false'
 AND v->>'business_rows_accessed'='false'
 AND v->>'runtime_dispatched'='false'
 AND v->>'effects_executed'='false'
))::integer INTO failures
FROM result;
IF failures<>0 THEN
  RAISE EXCEPTION 'LF_D2_HUMAN_PROOF_NEGATIVE_MATRIX_FAILURES_%',failures;
END IF;
END $checks$;

DO $privileges$
BEGIN
 IF has_function_privilege('authenticated','private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)','EXECUTE')
  OR has_function_privilege('anon','private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)','EXECUTE')
  OR NOT has_function_privilege('service_role','private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'LF_D2_AUTHORITY_PRIVILEGE_FAILURE'; END IF;
 IF private.fn_lf_d2_binding_readback_v1('db://lf_ops.cargas_lotes')->>'decision' =
      'STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION' THEN
 RAISE EXCEPTION 'LF_D2_UNADMITTED_SOURCE_WAS_DECLARED_VALID'; END IF;
END $privileges$;
SELECT 'PASS' AS overall_verdict,8 AS negative_cases,1 AS acl_assertion,1 AS integration_assertion;
