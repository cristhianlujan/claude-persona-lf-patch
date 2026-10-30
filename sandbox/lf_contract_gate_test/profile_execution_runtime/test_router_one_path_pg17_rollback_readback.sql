-- Isolated PostgreSQL rollback only. Run after exact candidate then exact guarded rollback.
DO $readback$
DECLARE
 mismatches int;
BEGIN
 SELECT count(*) INTO mismatches FROM (VALUES
  ('lf_profile_native_bridge_begin_v1','36a3bb6ea8a020c9b1f9cb94ee93b357'),
  ('lf_router_pipeline_begin_v1','1c4977c7f17e514cd5d32e9b7b693a00'),
  ('lf_router_pipeline_context_profile_admit_v2','d1bc9787de30980bdff8d4f48c58d438'),
  ('lf_router_pipeline_profile_handoff_continue_v1','51c05f2efc1d31c304f0126c20a14e8d'),
  ('lf_router_profile_after_selection_v1','754cf13fc6c7669763baa07a4031bc71'),
  ('lf_router_profile_execution_after_gate2_v1','94c468133a3961cc261ea312a0d23400')
 ) expected(fn,md5_expected)
 LEFT JOIN pg_proc p ON p.proname=expected.fn
 LEFT JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
 WHERE p.oid IS NULL OR n.oid IS NULL OR md5(pg_get_functiondef(p.oid))<>expected.md5_expected;
 IF mismatches<>0 THEN RAISE EXCEPTION 'ROLLBACK_NOT_ORIGINAL:%',mismatches; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_operation_execution)
 OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps)
 THEN RAISE EXCEPTION 'ROLLBACK_WROTE_EXECUTIONS'; END IF;
END;
$readback$;
SELECT 'PASS_ROUTER_ONE_PATH_PG17_ROLLBACK_READBACK' AS result;
