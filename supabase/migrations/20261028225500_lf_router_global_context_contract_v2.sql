-- ACT-0001: neutral transport entrypoints without changing legacy V1 or effect authority.
-- One new migration; admission/execution remains governed and is NOT inferred from a token.
BEGIN;
DO $upgrade$
DECLARE
 old_name text;
 new_name text;
 signature text;
 src text;
 original_condition text;
 names text[][] := ARRAY[
  ARRAY['lf_router_pipeline_begin_v1','lf_router_pipeline_context_begin_v2','text'],
  ARRAY['lf_router_pipeline_stage1_submit_v1','lf_router_pipeline_context_stage1_submit_v2','text,jsonb'],
  ARRAY['lf_router_pipeline_profile_semantic_prepare_v1','lf_router_pipeline_context_profile_semantic_prepare_v2','text'],
  ARRAY['lf_router_pipeline_profile_semantic_submit_v1','lf_router_pipeline_context_profile_semantic_submit_v2','text,text']
 ];
 row_data text[];
 n int;
BEGIN
 FOREACH row_data SLICE 1 IN ARRAY names LOOP
  old_name:=row_data[1]; new_name:=row_data[2]; signature:=row_data[3];
  src:=pg_get_functiondef(('public.'||old_name||'('||signature||')')::regprocedure);
  original_condition:='session_user' || CASE WHEN old_name='lf_router_pipeline_begin_v1' THEN ' = ' ELSE '=' END || '''supabase_read_only_user''';
  IF position(original_condition IN src)=0 THEN
    RAISE EXCEPTION 'BLOCK_CONTEXT_V2_LEGACY_BRANCH_DRIFT:%',old_name;
  END IF;
  -- Context V2 always performs transport derivation, regardless of caller identity.
  -- The legacy persisted V1 entrypoints retain their behavior and permissions.
  src:=replace(src,'public.'||old_name||'(', 'public.'||new_name||'(');
  src:=replace(src,original_condition,'true');
  src:=replace(src,'LF_ROUTER_READ_ONLY_CONTEXT_V1','LF_ROUTER_EXECUTION_CONTEXT_V2');
  src:=replace(src,'READ_ONLY_CONTEXT','CONTEXT_TRANSPORT');
  src:=replace(src,'ROCTX:','RCTX2:');
  src:=replace(src,'transport_token','context_token');
  src:=replace(src,'BLOCK_READ_ONLY_','BLOCK_CONTEXT_');
  src:=replace(src,'READ_ONLY_GATE2_DERIVED_NOT_AUTHORIZED','GATE2_DERIVED_PENDING_GOVERNED_ADMISSION');
  src:=replace(src,'''trace_persistence'',''NONE''','''persistence_policy'',''CONTRACT_CONTROLLED''');
  IF old_name<>'lf_router_pipeline_begin_v1' THEN
    src:=replace(src,'p_execution_id','p_context_token');
  END IF;
  IF old_name='lf_router_pipeline_profile_semantic_submit_v1' THEN
    src:=replace(src,'public.lf_router_pipeline_profile_semantic_prepare_v1(', 'public.lf_router_pipeline_context_profile_semantic_prepare_v2(');
  END IF;
  -- These new entrypoints transport data only; they never certify authorization.
  EXECUTE src;
 END LOOP;
END $upgrade$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_context_begin_v2(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_router_pipeline_context_stage1_submit_v2(text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_router_pipeline_context_profile_semantic_prepare_v2(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_router_pipeline_context_profile_semantic_submit_v2(text,text) FROM PUBLIC;

-- Same explicitly authorized callers as existing transport, plus controlled service API.
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_context_begin_v2(text) TO supabase_read_only_user,service_role;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_context_stage1_submit_v2(text,jsonb) TO supabase_read_only_user,service_role;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_context_profile_semantic_prepare_v2(text) TO supabase_read_only_user,service_role;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_context_profile_semantic_submit_v2(text,text) TO supabase_read_only_user,service_role;
COMMIT;
