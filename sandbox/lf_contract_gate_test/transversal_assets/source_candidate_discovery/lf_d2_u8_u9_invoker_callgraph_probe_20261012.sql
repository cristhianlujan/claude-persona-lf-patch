-- LF Reparador D2 U8/U9. Read-only falsification of the *physical* actor call graph.
-- DO NOT simulate auth.uid, actor, company, permission, JWT, or receipt.
-- Expected 14/14 PASS documents fail-closed observations, NOT business acceptance.
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
 UNION ALL SELECT 'F10_SOURCE_SELECT_DENIED_AUTHENTICATED',
  NOT has_table_privilege('authenticated','lf_ops.cargas_lotes','SELECT')
 UNION ALL SELECT 'F11_DENY_POLICY_IS_PERMISSIVE',
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='lf_ops' AND tablename='cargas_lotes'
    AND policyname='deny_direct_client_access' AND permissive='PERMISSIVE' AND qual='false')
 UNION ALL SELECT 'F12_SCOPED_POLICY_IS_PERMISSIVE',
  EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='lf_ops' AND tablename='cargas_lotes'
    AND policyname='lf_b2b_load_scoped_read_v1' AND permissive='PERMISSIVE' AND cmd='SELECT')
 UNION ALL SELECT 'F13_SOURCE_FORCE_RLS',
  EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='lf_ops' AND c.relname='cargas_lotes'
      AND c.relrowsecurity AND c.relforcerowsecurity)
 UNION ALL SELECT 'F14_U9_LEDGER_SERVICE_SELECT_DENIED',
  NOT has_table_privilege('service_role','private.lf_evidence_ledger_v1','SELECT')
)
SELECT count(*) total,count(*) FILTER (WHERE ok) passed,
 jsonb_agg(jsonb_build_object('code',code,'passed',ok) ORDER BY code) checks
FROM checks;
ROLLBACK;
