-- Generic metadata-only candidate spec tests. No binding is written or authorized.
WITH input(case_code,src,expected) AS(VALUES
 ('LOAD_TABLE','db://lf_ops.cargas_lotes','CANDIDATE_ONLY_REQUIRES_GOVERNED_BINDING_AND_FACADE'),
 ('LOAD_FILE_TABLE','db://lf_ops.cargas_archivos','CANDIDATE_ONLY_REQUIRES_GOVERNED_BINDING_AND_FACADE'),
 ('UNKNOWN_TABLE','db://lf_ops.not_in_inventory','BLOCK_NOT_IN_CANONICAL_INVENTORY'),
 ('BAD_SCHEME','supabase://catalog/lf_ops/cargas_lotes','BLOCK_INVALID_SOURCE_REF'),
 ('EMPTY_REF',NULL::text,'BLOCK_INVALID_SOURCE_REF')
), outputs AS(
 SELECT case_code,expected,private.fn_lf_d2_source_binding_candidate_v1(src) AS result FROM input
)
SELECT case_code,expected,result->>'decision' observed,
  CASE WHEN result->>'decision'=expected
   AND result->>'binding_written'='false'
   AND result->>'business_rows_accessed'='false'
   AND result->>'business_read_authorized'='false'
   AND result->>'runtime_dispatched'='false'
   AND result->>'effects_executed'='false'
   AND (
     expected<>'CANDIDATE_ONLY_REQUIRES_GOVERNED_BINDING_AND_FACADE'
     OR (
       result->'proposed_binding'->>'admission_status'='CANDIDATO'
       AND result->'proposed_binding'->>'read_facade_ref' IS NULL
       AND result->'proposed_binding'->>'required_permission_code' IS NULL
       AND result->'proposed_binding'->>'governance_approval_required'='true'
       AND result->>'source_schema_fingerprint' ~ '^[0-9a-f]{64}$'
       AND jsonb_array_length(result->'proposed_binding'->'permitted_columns')=0
       AND jsonb_array_length(result->'proposed_binding'->'allowed_filter_fields')=0
     )
   )
  THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM outputs ORDER BY case_code;
