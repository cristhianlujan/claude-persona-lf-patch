-- Executed only after the LF D2 U8 facade migration; never simulates JWT/tenant.
-- Technical negative proof != business admission. All checks are read-only and reversible.
BEGIN;
WITH checks AS (
 SELECT 'C01_INVOKER' code,
   (SELECT NOT p.prosecdef FROM pg_proc p
    WHERE p.oid='private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)'::regprocedure) ok
 UNION ALL SELECT 'C02_AUTH_GRANT_REVOKED',
   NOT has_function_privilege('authenticated','private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)','EXECUTE')
 UNION ALL SELECT 'C03_ANON_GRANT_REVOKED',
   NOT has_function_privilege('anon','private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)','EXECUTE')
 UNION ALL SELECT 'C04_SERVICE_GRANT_REVOKED',
   NOT has_function_privilege('service_role','private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)','EXECUTE')
 UNION ALL SELECT 'C05_NO_REAL_ACTOR',
   (private.fn_lf_d2_cargas_lotes_read_v1('db://lf_ops.cargas_lotes','["load_code"]','{}',5)->>'decision')='BLOCK_REAL_AUTHENTICATED_ACTOR_REQUIRED'
 UNION ALL SELECT 'C06_PROJECTION_DENIED',
   (private.fn_lf_d2_cargas_lotes_read_v1('db://lf_ops.cargas_lotes','["policy_snapshot"]','{}',5)->>'decision')='BLOCK_UNGOVERNED_PROJECTION_OR_FILTER'
 UNION ALL SELECT 'C07_FILTER_DENIED',
   (private.fn_lf_d2_cargas_lotes_read_v1('db://lf_ops.cargas_lotes','["load_code"]','{"private_field":"x"}',5)->>'decision')='BLOCK_UNGOVERNED_PROJECTION_OR_FILTER'
 UNION ALL SELECT 'C08_FILTER_TYPE_DENIED',
   (private.fn_lf_d2_cargas_lotes_read_v1('db://lf_ops.cargas_lotes','["load_code"]','{"status":[]}',5)->>'decision')='BLOCK_UNGOVERNED_PROJECTION_OR_FILTER'
 UNION ALL SELECT 'C09_ROW_CAP',
   (private.fn_lf_d2_cargas_lotes_read_v1('db://lf_ops.cargas_lotes','["load_code"]','{}',101)->>'decision')='BLOCK_FACADE_REQUEST_INVALID'
 UNION ALL SELECT 'C10_SOURCE_EXACT',
   (private.fn_lf_d2_cargas_lotes_read_v1('db://lf_ops.cargas_archivos','["load_code"]','{}',5)->>'decision')='BLOCK_FACADE_REQUEST_INVALID'
 UNION ALL SELECT 'C11_UNAUTHORIZED_RETURN_FALSE',
   (private.fn_lf_d2_cargas_lotes_read_v1('db://lf_ops.cargas_lotes','["load_code"]','{}',5)->>'business_answer_admitted')='false'
)
SELECT count(*) total,count(*) FILTER (WHERE ok) passed,
  jsonb_agg(jsonb_build_object('code',code,'passed',ok) ORDER BY code) checks
FROM checks;
ROLLBACK;
