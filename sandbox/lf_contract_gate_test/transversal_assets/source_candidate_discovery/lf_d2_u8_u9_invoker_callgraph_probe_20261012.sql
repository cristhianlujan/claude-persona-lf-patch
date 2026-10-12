-- LF Reparador D2 U8/U9. Read-only falsification of the *physical* actor call graph.
-- DO NOT simulate auth.uid, actor, company, permission, JWT, or receipt.
-- Expected 9/9 PASS documents fail-closed observations, NOT business acceptance.
BEGIN;
WITH checks AS (
 SELECT 'F01_U8_FACADE_IS_INVOKER' code,
  (SELECT NOT prosecdef FROM pg_proc WHERE oid='private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)'::regprocedure) ok
 UNION ALL SELECT 'F02_NO_AUTH_SCHEMA_PRIVATE',
  NOT has_schema_privilege('authenticated','private','USAGE')
 UNION ALL SELECT 'F03_PLANNER_NOT_CALLABLE_BY_ACTOR',
  NOT has_function_privilege('authenticated','private.fn_lf_d2_facade_request_plan_v1(text,jsonb,jsonb,integer)','EXECUTE')
 UNION ALL SELECT 'F04_BINDING_READER_NOT_CALLABLE_BY_ACTOR',
  NOT has_function_privilege('authenticated','private.fn_lf_d2_binding_readback_v1(text)','EXECUTE')
 UNION ALL SELECT 'F05_POLICY_CATALOG_NOT_CLIENT_READABLE',
  NOT has_table_privilege('authenticated','public.lf_policy_versions','SELECT')
 UNION ALL SELECT 'F06_FACADE_NOT_GRANTED',
  NOT has_function_privilege('authenticated','private.fn_lf_d2_cargas_lotes_read_v1(text,jsonb,jsonb,integer)','EXECUTE')
 UNION ALL SELECT 'F07_SOURCE_BINDING_NOT_ADMITTED',
  (private.fn_lf_d2_binding_readback_v1('db://lf_ops.cargas_lotes')->>'decision')='BLOCK_BINDING_ABSENT_OR_AMBIGUOUS'
 UNION ALL SELECT 'F08_U9_NULL_RECEIPT_REJECTED',
  (private.fn_lf_d2_facade_receipt_readback_v1(NULL::uuid,'db://lf_ops.cargas_lotes','EXEC-LF-U9-NEGATIVE-20261012')->>'decision')='BLOCK_RECEIPT_LOOKUP_PARAMETERS_INVALID'
 UNION ALL SELECT 'F09_U9_NO_BUSINESS_ADMISSION',
  (private.fn_lf_d2_facade_receipt_readback_v1(NULL::uuid,'db://lf_ops.cargas_lotes','EXEC-LF-U9-NEGATIVE-20261012')->>'business_answer_authorized')='false'
)
SELECT count(*) total,count(*) FILTER (WHERE ok) passed,
 jsonb_agg(jsonb_build_object('code',code,'passed',ok) ORDER BY code) checks
FROM checks;
ROLLBACK;
