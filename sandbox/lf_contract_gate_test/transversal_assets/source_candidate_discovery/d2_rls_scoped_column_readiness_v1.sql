-- Technical metadata readback only: column GRANT counts for both B2B sources.
WITH decisions AS (
 SELECT src,private.fn_lf_d2_admission_readiness_v1(src) r
 FROM (VALUES
  ('db://lf_ops.cargas_lotes'),
  ('db://lf_ops.cargas_archivos')
 ) t(src)
)
SELECT src,
 CASE WHEN r->>'authenticated_direct_select_granted'='false'
 AND r->>'authenticated_column_select_granted'='true'
 AND NOT (r->'blocking_requirements' ? 'DIRECT_CLIENT_TABLE_READ_UNAVAILABLE_USE_GOVERNED_FACADE')
 AND r->>'business_data_access_authorized'='false'
 AND r->>'business_rows_accessed'='false'
 THEN 'PASS' ELSE 'FAIL' END verdict
FROM decisions ORDER BY src;
