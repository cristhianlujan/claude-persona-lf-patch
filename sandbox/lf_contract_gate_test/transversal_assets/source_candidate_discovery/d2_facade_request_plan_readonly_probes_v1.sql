-- D2 metadata-only facade planning: invalid input and unbound source probes.
WITH cases(code,source_ref,projection,filters,row_budget,expected) AS(VALUES
('UNBOUND','db://lf_ops.cargas_lotes','["status"]'::jsonb,'{}'::jsonb,5,'BLOCK_SOURCE_NOT_STRUCTURALLY_ADMITTED'),
('UNKNOWN','db://lf_ops.not_in_registry','["status"]'::jsonb,'{}'::jsonb,5,'BLOCK_SOURCE_NOT_STRUCTURALLY_ADMITTED'),
('EMPTY_SOURCE',NULL::text,'["status"]'::jsonb,'{}'::jsonb,5,'BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST'),
('ZERO_BUDGET','db://lf_ops.cargas_lotes','["status"]'::jsonb,'{}'::jsonb,0,'BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST'),
('EXCESS_BUDGET','db://lf_ops.cargas_lotes','["status"]'::jsonb,'{}'::jsonb,1001,'BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST'),
('EMPTY_FIELDS','db://lf_ops.cargas_lotes','[]'::jsonb,'{}'::jsonb,5,'BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST'),
('NOT_ARRAY','db://lf_ops.cargas_lotes','{}'::jsonb,'{}'::jsonb,5,'BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST'),
('NOT_OBJECT','db://lf_ops.cargas_lotes','["status"]'::jsonb,'[]'::jsonb,5,'BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST'),
('NO_FILTERS','db://lf_ops.cargas_lotes','["status"]'::jsonb,NULL::jsonb,5,'BLOCK_UNBOUNDED_OR_INVALID_FACADE_REQUEST')
), results AS(
SELECT code,expected,private.fn_lf_d2_facade_request_plan_v1(source_ref,projection,filters,row_budget) AS result FROM cases
)
SELECT code,expected,result->>'decision' observed,
CASE WHEN result->>'decision'=expected
AND result->>'execution_authorized'='false'
AND result->>'business_rows_accessed'='false'
AND result->>'receipt_verified'='false'
AND result->>'runtime_dispatch_authorized'='false'
AND result->>'effects_executed'='false'
THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM results ORDER BY code;
