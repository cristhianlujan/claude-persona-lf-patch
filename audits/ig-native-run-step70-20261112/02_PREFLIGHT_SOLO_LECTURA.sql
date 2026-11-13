-- LF / RUN + STEP70 + AUTH + OWNERS / preflight 2026-11-12.
-- TEST DE SOLO LECTURA. NO toca RUN existentes ni llama a escritores.
-- Usar conexion readonly y conservar stdout con fecha/proyecto/commit.
BEGIN TRANSACTION READ ONLY;

SELECT
  current_user AS sql_role,
  auth.uid() IS NOT NULL AS supabase_auth_claim_present,
  (SELECT count(*)::int FROM auth.users) AS auth_user_count,
  (SELECT count(*)::int FROM auth.identities) AS auth_identity_count,
  (SELECT count(*)::int FROM auth.mfa_factors WHERE status::text='verified') AS verified_mfa_factor_count;

SELECT status,count(*)::int AS run_count
FROM public.lf_operation_execution
WHERE operation_code='EJECUCION_PERFIL_LF'
GROUP BY status ORDER BY status;

SELECT s.status,count(*)::int AS step70_count
FROM public.lf_operation_execution_steps s
JOIN public.lf_operation_execution e USING (execution_id)
WHERE e.operation_code='EJECUCION_PERFIL_LF'
  AND s.step_id='semantic_judge'
GROUP BY s.status ORDER BY s.status;

SELECT operation_code,count(*)::int AS declared_steps
FROM public.lf_operation_steps
WHERE operation_code='EJECUCION_PERFIL_LF'
GROUP BY operation_code;

SELECT
  p.proname AS function_name,
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') AS preimage_sha256,
  position('hmac' in lower(pg_get_functiondef(p.oid)))>0 AS hmac_in_current_definition,
  position('auth.uid' in lower(pg_get_functiondef(p.oid)))>0 AS auth_uid_in_current_definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('lf_profile_execution_begin_from_handoff_v1',
  'lf_profile_native_bridge_record_semantic_v1',
  'lf_profile_native_bridge_record_report_v1',
  'lf_record_profile_execution_step_v1')
ORDER BY p.proname;

SELECT
  has_function_privilege('authenticated',
    'public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)','EXECUTE')
      AS authenticated_may_call_step70_rpc,
  has_function_privilege('service_role',
    'public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)','EXECUTE')
      AS service_role_may_call_step70_rpc,
  position('DUPLICATE_NATIVE_BRIDGE_ENTRY_RETIRED' IN
    pg_get_functiondef('public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)'::regprocedure))>0
      AS duplicate_begin_retired;

SELECT
  (SELECT count(*)::int FROM private.lf_human_decision_authority_policies_v1 WHERE status='ACTIVE')
    AS human_owner_policies_active,
  (SELECT count(*)::int FROM programacion.authority_attestations)
    AS attestations,
  (SELECT count(*)::int FROM programacion.human_decisions)
    AS human_decisions,
  (SELECT count(*)::int FROM public.lf_profile_write_authority_v1 WHERE status='ACTIVE')
    AS profile_write_policy_rows_not_human_owners;

SELECT
  (SELECT count(*)::int FROM public.lf_operation_execution) AS operation_runs,
  (SELECT count(*)::int FROM public.lf_operation_execution_steps) AS operation_steps,
  (SELECT count(*)::int FROM lf_ops.reglas) AS rules,
  (SELECT count(*)::int FROM storage.buckets) AS storage_buckets,
  (SELECT count(*)::int FROM storage.objects) AS storage_objects;

-- No se puede probar un token Auth humano ni OIDC externo por conexión admin.
-- NO simular JWT con set_config('request.jwt.claims',...) ni falsificar auth.uid().
ROLLBACK;
