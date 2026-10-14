-- Execute ONLY after the candidate migration is installed on an isolated
-- authorized sandbox. Every assertion is a read; the transaction rolls back.
BEGIN TRANSACTION READ ONLY;
DO $test$
DECLARE
  v_route jsonb;
  v_migration text;
  v_role text;
  v_principal regprocedure :=
    'public.lf_operational_executor_assert_principal_v1(text)'::regprocedure;
  v_admit regprocedure :=
    'public.lf_operational_executor_admit_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure;
  v_begin regprocedure :=
    'public.lf_operational_executor_begin_v1(text,text,text,text,text,text,text,text,text)'::regprocedure;
  v_finish regprocedure :=
    'public.lf_operational_executor_finish_v1(text,text,bigint,text,jsonb,text)'::regprocedure;
  v_close regprocedure :=
    'public.lf_close_operational_execution_v1(text,text,bigint,jsonb,text)'::regprocedure;
  v_decision regprocedure :=
    'public.lf_operational_executor_assert_decision_current_v1(text)'::regprocedure;
  v_facade regprocedure;
  v_api_role text;
BEGIN
 SELECT operation_code INTO v_migration FROM public.lf_router_action_registry
 WHERE asset_type='DB' AND action_code='UPDATE';
 IF v_migration IS DISTINCT FROM 'ACTUALIZACION_DB_LF' THEN
   RAISE EXCEPTION 'TEST_MIGRATION_TRAIN_ROUTE_CHANGED';
 END IF;
 v_route:=public.lf_router_resolve_v1(
   'Governed operational handler',NULL,'OPERATION_EXECUTE','OPERATIONAL_DB','ROUTER'
 );
 IF v_route->>'status' IS DISTINCT FROM 'READY_TO_EXECUTE'
    OR v_route->>'operation_code' IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF'
    OR v_route->>'downstream_execution_allowed' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'TEST_OPERATIONAL_ROUTE_UNRESOLVED';
 END IF;
 IF (SELECT count(*) FROM public.lf_operation_steps
     WHERE operation_code='EJECUCION_OPERATIVA_LF' AND required AND active)<>3 THEN
   RAISE EXCEPTION 'TEST_REQUIRED_STEPS_NOT_EXACT';
 END IF;
 IF NOT public.lf_router_downstream_authority_consumer_v1('EJECUCION_OPERATIVA_LF') THEN
   RAISE EXCEPTION 'TEST_AUTHORITY_CONSUMER_NOT_BOUND';
 END IF;
 FOREACH v_role IN ARRAY ARRAY['lf_operational_admission_authority','lf_operation_executor_runtime'] LOOP
   IF NOT EXISTS(
      SELECT 1 FROM pg_roles WHERE rolname=v_role AND NOT rolcanlogin AND NOT rolinherit
       AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
       AND NOT rolreplication AND NOT rolbypassrls
   ) THEN RAISE EXCEPTION 'TEST_ROLE_NOT_MINIMAL:%',v_role; END IF;
   IF has_table_privilege(v_role,'public.lf_operation_execution','INSERT')
      OR has_table_privilege(v_role,'public.lf_operation_execution','UPDATE')
      OR has_table_privilege(v_role,'public.lf_operation_effect_guard','INSERT')
      OR has_table_privilege(v_role,'public.lf_operation_effect_guard','UPDATE') THEN
     RAISE EXCEPTION 'TEST_DIRECT_GOVERNANCE_TABLE_WRITE_GRANT:%',v_role;
   END IF;
 END LOOP;
 IF NOT has_function_privilege('lf_operational_admission_authority',v_principal,'EXECUTE')
    OR NOT has_function_privilege('lf_operation_executor_runtime',v_principal,'EXECUTE') THEN
   RAISE EXCEPTION 'TEST_PRINCIPAL_GUARD_EXECUTE_GRANTS_INVALID';
 END IF;
 IF NOT has_function_privilege('lf_operational_admission_authority',v_admit,'EXECUTE')
    OR has_function_privilege('lf_operation_executor_runtime',v_admit,'EXECUTE')
    OR has_function_privilege('lf_operational_admission_authority',v_begin,'EXECUTE')
    OR has_function_privilege('lf_operational_admission_authority',v_finish,'EXECUTE')
    OR NOT has_function_privilege('lf_operation_executor_runtime',v_begin,'EXECUTE')
    OR NOT has_function_privilege('lf_operation_executor_runtime',v_finish,'EXECUTE') THEN
   RAISE EXCEPTION 'TEST_ADMISSION_RUNTIME_EXECUTE_BOUNDARY_BROKEN';
 END IF;
 IF EXISTS(
   SELECT 1 FROM pg_proc p
   CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
   WHERE p.oid IN (v_principal::oid,v_admit::oid,v_begin::oid,v_finish::oid)
     AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
 ) THEN
   RAISE EXCEPTION 'TEST_OPERATIONAL_FACADE_EXPOSED_TO_PUBLIC';
 END IF;
 -- Verify the exact six new facades against effective grants, not just PUBLIC ACL.
 -- Supabase creates functions with additional explicit default EXECUTE grants
 -- for anon, authenticated, and service_role.
 FOR v_facade IN SELECT unnest(ARRAY[
   v_principal,v_admit,v_begin,v_finish,v_close,v_decision
 ]) LOOP
   FOREACH v_api_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
     IF has_function_privilege(v_api_role,v_facade,'EXECUTE') THEN
       RAISE EXCEPTION 'TEST_OPERATIONAL_FACADE_EFFECTIVE_API_EXECUTE:%:%',
         v_facade::text,v_api_role;
     END IF;
   END LOOP;
 END LOOP;
 IF has_function_privilege('lf_operation_executor_runtime',v_close,'EXECUTE')
    OR has_function_privilege('lf_operational_admission_authority',v_close,'EXECUTE')
    OR has_function_privilege('lf_operation_executor_runtime',v_decision,'EXECUTE')
    OR has_function_privilege('lf_operational_admission_authority',v_decision,'EXECUTE') THEN
   RAISE EXCEPTION 'TEST_INTERNAL_CLOSE_OR_DECISION_EXPOSED_TO_GROUP_ROLES';
 END IF;
END $test$;
ROLLBACK;
