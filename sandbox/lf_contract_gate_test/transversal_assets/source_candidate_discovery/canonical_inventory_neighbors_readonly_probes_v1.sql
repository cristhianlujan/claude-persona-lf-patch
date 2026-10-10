-- Canonical FK graph probes, metadata-only, no business rows.
WITH fixtures(test_code,source_ref,budget,expected_state) AS (VALUES
('LOAD_LOTS','db://lf_ops.cargas_lotes',12,'RELATED_CANDIDATES_FOUND'),
('LOAD_FILE','db://lf_ops.cargas_archivos',12,'RELATED_CANDIDATES_FOUND'),
('UNKNOWN','db://lf_ops.__nonexistent__',12,'ERROR_FAIL_CLOSED'),
('INVALID_BUDGET','db://lf_ops.cargas_lotes',0,'ERROR_FAIL_CLOSED')
), results AS (
SELECT test_code,expected_state,
 private.fn_lf_d1_inventory_neighbors_v1(source_ref,budget) AS result FROM fixtures
)
SELECT test_code,expected_state,result->>'discovery_state' AS actual_state,
coalesce((result->>'related_count')::int,0) AS neighbors,
CASE WHEN expected_state=result->>'discovery_state'
 AND (result->>'data_access_granted')::boolean IS FALSE
 AND (result->>'discovery_exhausted')::boolean IS FALSE
 AND (test_code<>'LOAD_LOTS' OR coalesce((result->>'related_count')::int,0)>=3)
 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM results ORDER BY test_code;