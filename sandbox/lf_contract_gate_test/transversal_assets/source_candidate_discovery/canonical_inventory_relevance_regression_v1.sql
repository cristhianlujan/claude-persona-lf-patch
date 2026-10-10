-- LF D1 ranking regression over canonical inventory, metadata only.
-- Intent examples are fixtures: never embed source names into the actual router.
WITH fixtures(id,objective,budget,expected_state,expected_source,maximum_rank) AS (
 VALUES
 ('LOAD_CODE','Tengo un código de carga y no figura',12,'CANDIDATES_FOUND','db://lf_ops.cargas_lotes',2),
 ('LOAD_SINGLE','Subí una carga y no aparece',12,'CANDIDATES_FOUND','db://lf_ops.cargas_lotes',3),
 ('LOAD_MULTI','Subí dos cargas y una de las antiguas no aparece',12,'CANDIDATES_FOUND','db://lf_ops.cargas_lotes',3),
 ('LOAD_OLD','No encuentro las cargas antiguas del mes pasado',12,'CANDIDATES_FOUND','db://lf_ops.cargas_lotes',3),
 ('LOAD_FILE','Mi archivo de carga fue rechazado',12,'CANDIDATES_FOUND','db://lf_ops.cargas_archivos',2),
 ('LOAD_SYNONYM','El lote de cartera no se muestra',12,'CANDIDATES_FOUND','db://lf_ops.cargas_lotes',3),
 ('LOGIN','El acceso al backoffice B2B no funciona',12,'CANDIDATES_FOUND','db://lf_ops.v_b2b_backoffice_login_contract',3),
 ('UNKNOWN','nanoreactor cuántico',12,'NO_MATCH_IN_SCOPE',NULL,NULL),
 ('INVALID_BUDGET','Subí una carga y no aparece',0,'ERROR_FAIL_CLOSED',NULL,NULL)
), actual AS (
 SELECT f.*,private.fn_lf_d1_inventory_candidates_v1(f.objective,f.budget) AS result
 FROM fixtures f
), evidence AS (
 SELECT id,expected_state,expected_source,maximum_rank,
 result->>'discovery_state' AS observed_state,
 (SELECT MIN(ord)::integer FROM jsonb_array_elements(coalesce(result->'candidate_sources','[]'::jsonb))
 WITH ORDINALITY p(value,ord)
 WHERE p.value->>'source_ref'=expected_source) AS observed_source_rank,
 (result->>'data_access_granted')::boolean AS authorized,
 (result->>'discovery_exhausted')::boolean AS exhausted
 FROM actual
)
SELECT id,expected_state,observed_state,observed_source_rank,maximum_rank,
 CASE WHEN expected_state=observed_state
 AND NOT authorized AND NOT exhausted
 AND (expected_source IS NULL OR (observed_source_rank IS NOT NULL AND observed_source_rank<=maximum_rank))
 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM evidence ORDER BY id;