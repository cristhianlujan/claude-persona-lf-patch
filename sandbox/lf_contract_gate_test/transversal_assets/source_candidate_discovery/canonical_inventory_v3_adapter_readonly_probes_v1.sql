-- LF D1 canonical inventory adapter contract test: no operational data reads.
-- Run after candidate migration in a ROLLBACK transaction or after installation.
WITH cases(code,objective,budget,expected) AS (
 VALUES ('LOAD','Subí una carga y no aparece',12,'CANDIDATES_FOUND'),
        ('LOGIN','Revisar reglas de login B2B',12,'CANDIDATES_FOUND'),
        ('UNKNOWN','nanoreactor cuántico',12,'NO_MATCH_IN_SCOPE'),
        ('BAD_BUDGET','Subí una carga y no aparece',0,'ERROR_FAIL_CLOSED')
), results AS (
 SELECT code,expected,private.fn_lf_d1_inventory_candidates_v1(objective,budget) AS result
 FROM cases
), evaluated AS (
 SELECT code,expected,result->>'discovery_state' AS observed,
  result->>'inventory_status' AS inventory_status,
  coalesce((result->>'candidate_count')::int,0) AS candidates,
  CASE WHEN code='LOAD' THEN
     (SELECT count(*)::int FROM pg_catalog.jsonb_array_elements(result->'candidate_sources') s
      WHERE s->>'source_ref' IN ('db://lf_ops.cargas_lotes','db://lf_ops.cargas_archivos'))
     ELSE NULL END AS load_refs,
  (result->>'data_access_granted')::boolean AS authorized,
  (result->>'discovery_exhausted')::boolean AS exhausted
 FROM results
)
SELECT code,expected,observed,candidates,load_refs,inventory_status,
 CASE WHEN observed=expected AND NOT authorized AND NOT exhausted
       AND (code<>'LOAD' OR load_refs=2)
       AND (code<>'LOGIN' OR candidates>0)
       AND (code<>'UNKNOWN' OR candidates=0)
      THEN 'PASS' ELSE 'FAIL' END AS result
FROM evaluated ORDER BY code;
-- Test fixtures may name known business sources; adapter code must not.
