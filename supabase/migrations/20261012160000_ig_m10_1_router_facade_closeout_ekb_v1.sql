-- IG M10.1 CP4-CP6 verified learnings; append-only EKB.
-- No checkpoint rewrites, runtime switches, grants, or production change.
DO $ekb$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN
 ('IG-M101-SUPABASE-PUBLIC-DEFAULT-RPC-GRANTS-001',
  'IG-M101-EXTERNAL-PRIVATE-CALL-SEMANTIC-SCOPE-001'))
 THEN RAISE EXCEPTION 'M101_EKB_PRESTATE_COLLISION'; END IF;
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
  created_at,updated_at,source_context,source_ref)
 VALUES
 (gen_random_uuid(),
 'IG-M101-SUPABASE-PUBLIC-DEFAULT-RPC-GRANTS-001',
 'IG_SECURITY_FACADE',
 'Supabase public schema default EXECUTE grants must be explicitly revoked for new facades',
 'Router facade migration initially failed its exact-source reversible security test: new public SQL wrappers unexpectedly allowed anon/authenticated execution despite an explicit REVOKE FROM PUBLIC.',
 'postgres pg_default_acl for public functions grants EXECUTE directly to anon, authenticated and service_role. Revoking PUBLIC alone does not remove those explicit default privileges.',
 'Schema-level default grants can silently expose a SECURITY INVOKER wrapper even when its runtime authority is intended to remain restricted.',
 'For each new public facade, query pg_default_acl first; REVOKE specifically from anon and authenticated, and service_role for owner-only dependencies. Verify has_function_privilege across roles in a ROLLBACK transaction, keep SECURITY INVOKER and reuse original function, then Git PR merge, exact migration ledger and DB readback. Do not add SECURITY DEFINER to bypass privilege errors.',
 'Initial source rollback failed M101_NEW_FACADE_PUBLIC_ROLE_EXPOSURE. Corrected in PR #2301 and verified: anon/authenticated EXECUTE=false on both new facades; service_role only worker_spec=true, currentness=false. Positive and negative router behavior parity in rollback, no residues. PR#2301 merged main b02cd6cf9d9944d82fc072e1746eecd2bc2d9519; migration 20261012153000 exact Git blob f0855085cdae425d5a742541702cfa56ac0d9d34. CP4 DONE, no production/runtime activation.',
 'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.1','#2301','VERIFICADO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2301;supabase://supabase_migrations.schema_migrations/20261012153000;supabase://pg_catalog.pg_default_acl',
 now(),now(),'M10.1 CP4 role-restricted public facade, sandbox source migration',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2301'),
 (gen_random_uuid(),
 'IG-M101-EXTERNAL-PRIVATE-CALL-SEMANTIC-SCOPE-001',
 'IG_VALIDATOR_SEMANTICS',
 'External consumer scan must distinguish public facades and IG-private implementations',
 'Original CP5 raw pg_proc regex matches public façade implementations and IG backend/core helpers; these are not external consumers and raw matching can produce false failures. Terminal SQL-only query also omits Edge sources despite CP6 SQL+Edge criterion.',
 'The scan conflated a function implementation calling its private backend with an external consumer bypassing the public façade. Terminal evidence source contract did not enumerate deployed Edge code for live readback.',
 'Unscoped regex that checks every pg_proc occurrence, or SQL-only terminal evidence for a SQL+Edge requirement, does not prove zero unauthorized external consumers.',
 'Derive external SQL entrypoint scope from public/lf_ops non-facades plus Router integration entrypoint; only match fully-qualified programacion.fn_input_(governance|readiness)_ calls. Use exact live pg_proc snapshot with test from merged Git and adversarial injected direct call. Independently read actual deployed Edge source versions, detect private schema override/direct programacion.fn_input_* references, verify Git worker uses governed Router. Keep engineering sandbox proof distinct from runtime cutover and do not broaden user permissions.',
 'PR #2302 merged main f9c43a6fb3eba05a323607f60ee0493055c5f7e2, Python test source blob 451b0c320c58302c1ba85284d0093d9efe54090b. SentinelX host_3d5ff6fb467d4e9e job script_job_38f2f73ec20d48f0ad806efe27a88879 PASS: 325 SQL entrypoints scanned, 13 public IG facades, 0 forbidden private refs, adversarial injected call rejected. Edge readback: input-governance-agent-v1 deployed v17 sha256=95977bfd7be64aef68a4c18c2e7fe15914aa510bcc1c1ee668863068cc5e656c and lf-profiles-governance-caller-v1 deployed v23 sha256=3abb3a19e09db6902f65ab89ffd3f2617ab113b62da3977825aca79b6817a979, private IG direct calls=0. Profiles worker Git blob 9ea498d372203207f2bd6ae1880c227749e257cb calls governed Router, not private IG. CP5 and CP6 DONE; M10.1 DONE 6/6 100%.',
 'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.1','#2302','VERIFICADO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2302;supabase://pg_catalog.pg_proc;supabase://edge_functions/input-governance-agent-v1;supabase://edge_functions/lf-profiles-governance-caller-v1',
 now(),now(),'M10.1 CP5/CP6 SQL+Edge engineering readback, no production activation',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2302');
END $ekb$;
