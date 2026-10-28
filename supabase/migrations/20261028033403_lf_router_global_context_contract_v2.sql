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

-- Governed bridge: a context carries evidence, never authorization by itself.
-- Only the authenticated service runtime may request admission/materialization.
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_profile_admit_v2(
  p_context jsonb, p_executor_mode text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $bridge$
DECLARE
 v_stage jsonb;
 v_route jsonb;
 v_transition jsonb;
 v_request jsonb;
 v_selection jsonb;
 v_validation jsonb;
 v_after jsonb;
 v_gate jsonb;
 v_literal text;
 v_mode text;
 v_action_count integer;
BEGIN
 IF jsonb_typeof(p_context)<>'object'
    OR p_context->>'schema_version'<>'LF_ROUTER_EXECUTION_PIPELINE_V1'
    OR p_context->>'status'<>'GATE2_DERIVED_PENDING_GOVERNED_ADMISSION'
    OR p_context->>'transport_mode'<>'CONTEXT_TRANSPORT'
    OR p_context->'effect_authority' IS DISTINCT FROM 'false'::jsonb
    OR p_context->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_ENVELOPE_INVALID');
 END IF;
 v_stage:=p_context->'stage1_payload';
 v_literal:=v_stage->>'texto_original';
 IF nullif(btrim(coalesce(v_literal,'')),'') IS NULL
    OR coalesce((public.lf_router_stage1_validate_v2(v_stage)->>'valid')::boolean,false) IS NOT TRUE
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_STAGE1_INVALID');
 END IF;
 v_route:=public.lf_router_route_v1(v_stage,'{}'::jsonb,false);
 v_transition:=public.lf_router_route_transition_resolve_v1(v_route);
 IF v_route IS DISTINCT FROM p_context->'route_result'
    OR v_transition IS DISTINCT FROM p_context->'transition'
    OR v_transition->>'status'<>'RESOLVED'
    OR v_transition->>'transition_code'<>'PROFILE_SELECTION_REQUIRED'
    OR v_transition->>'next_step'<>'profile_semantic_selection'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_ROUTE_INVALID');
 END IF;
 v_request:=v_route->'profile_selection_request';
 v_selection:=p_context->'semantic_result';
 v_validation:=public.lf_profile_selector_semantic_validate_v1(v_request,v_selection);
 IF v_validation->>'status'<>'VALID'
    OR v_selection->>'decision'<>'SELECTED'
    OR v_validation IS DISTINCT FROM p_context->'semantic_validation'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_SELECTION_INVALID');
 END IF;
 v_after:=public.lf_router_profile_after_selection_v1(v_stage,v_selection);
 IF v_after->>'status'<>'READY_FOR_GATE2'
    OR v_after IS DISTINCT FROM p_context->'after_selection_result'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_AFTER_SELECTION_INVALID');
 END IF;
 v_gate:=public.lf_router_profile_gate2_result_from_selection_v1(
   v_after->'gate2_request',v_selection);
 IF v_gate->>'status'<>'READY'
    OR v_gate IS DISTINCT FROM p_context->'gate2_derivation'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_GATE2_INVALID');
 END IF;
 SELECT count(*) INTO v_action_count
 FROM public.lf_router_action_registry
 WHERE asset_type='PERFIL'
   AND action_code='PROFILE_EXECUTION'
   AND operation_code='EJECUCION_PERFIL_LF'
   AND status='ACTIVE'
   AND write_allowed=false
   AND requires_existing_target=true;
 IF v_action_count<>1 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_OPERATION_UNAVAILABLE');
 END IF;
 v_mode:=upper(nullif(btrim(coalesce(p_executor_mode,'')),''));
 IF v_mode IS NULL OR v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_EXECUTOR_INVALID');
 END IF;
 -- Reuses existing governed profile begin and its idempotency/provenance checks.
 -- It must not reenter Stage1/Stage2 or authorize unrelated asset mutations.
 RETURN public.lf_router_profile_execution_after_gate2_v1(
   v_after->'gate2_request',v_gate->'gate2_result',
   v_stage->>'canal_candidato',v_stage->>'negocio_codigo',
   v_stage->'alcance',v_mode,NULL,NULL
 );
END;
$bridge$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_context_profile_admit_v2(jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_context_profile_admit_v2(jsonb,text) TO service_role;

COMMIT;
