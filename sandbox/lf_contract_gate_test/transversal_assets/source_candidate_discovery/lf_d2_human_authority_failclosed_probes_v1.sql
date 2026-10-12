-- Source binding authority: fail-closed probes, executed only between BEGIN/ROLLBACK
-- after the exact migration is loaded. No business data or human approvals written.
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
SELECT case_code,expected,v->>'decision' observed,
 CASE WHEN v->>'decision'=expected
 AND v->>'authority_receipt_reverified'='false'
 AND v->>'business_data_read_authorized'='false'
 AND v->>'business_rows_accessed'='false'
 AND v->>'runtime_dispatched'='false'
 AND v->>'effects_executed'='false'
 THEN 'PASS' ELSE 'FAIL' END verdict
FROM result ORDER BY case_code;

SELECT CASE WHEN
    NOT has_function_privilege('authenticated','private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)','EXECUTE')
    AND has_function_privilege('service_role','private.fn_lf_d2_source_binding_authority_gate_v1(text,jsonb)','EXECUTE')
  THEN 'PASS' ELSE 'FAIL' END AS privileges_verdict;

SELECT
 CASE WHEN private.fn_lf_d2_binding_readback_v1('db://lf_ops.cargas_lotes')->>'decision'
       NOT IN ('STRUCTURAL_MATCH_REQUIRES_REAL_ACTOR_FACADE_AUTHORIZATION')
 THEN 'PASS' ELSE 'FAIL' END AS no_unapproved_structural_binding_verdict;
