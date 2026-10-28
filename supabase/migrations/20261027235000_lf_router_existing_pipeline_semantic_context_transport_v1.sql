-- ACT-0001: continue transported read-only context using EXISTING pipeline functions.
-- No new Router entrypoints; no DB writes by read-only branches.
-- No privilege to execute handoff or effects.
BEGIN;

DO $patch$
DECLARE d text; anchor text; replacement text;
BEGIN
 d:=pg_get_functiondef('public.lf_router_pipeline_profile_semantic_prepare_v1(text)'::regprocedure);
 anchor:=E'  SELECT * INTO e\n';
 IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
   RAISE EXCEPTION 'ROUTER_SEMANTIC_PREPARE_ANCHOR_DRIFT';
 END IF;
 replacement:=$sql$  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_ctx jsonb; v_stage1 jsonb; v_route jsonb;
      v_trans jsonb; v_req jsonb; v_literal text;
    BEGIN
      IF left(coalesce(p_execution_id,''),6)<>'ROCTX:' THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      v_stage1:=v_ctx->'stage1_payload';
      v_route:=v_ctx->'stage2_route';
      v_trans:=v_ctx->'transition';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_READ_ONLY_CONTEXT_V1'
        OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
        OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
        OR v_stage1->>'texto_original' IS DISTINCT FROM v_literal
        OR coalesce((public.lf_router_stage1_validate_v2(v_stage1)->>'valid')::boolean,false) IS NOT TRUE
        OR v_route IS DISTINCT FROM public.lf_router_route_v1(v_stage1,'{}'::jsonb,false)
        OR v_trans IS DISTINCT FROM public.lf_router_route_transition_resolve_v1(v_route)
        OR v_trans->>'next_step'<>'profile_semantic_selection'
        OR v_trans->>'transition_code'<>'PROFILE_SELECTION_REQUIRED'
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_NOT_VERIFIED');
      END IF;
      v_req:=v_route->'profile_selection_request';
      IF jsonb_typeof(v_req)<>'object'
         OR v_req->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
         OR v_req->>'literal_request' IS DISTINCT FROM v_literal
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_PROFILE_REQUEST_INVALID');
      END IF;
      RETURN jsonb_build_object(
         'status','PROFILE_SEMANTIC_SELECTION_REQUIRED',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','READ_ONLY_CONTEXT',
         'transport_token',p_execution_id,
         'current_step','resolve_next_transition',
         'next_step','profile_semantic_selection',
         'profile_selection_request',v_req,
         'profile_selection_request_sha256',
             encode(extensions.digest(convert_to(v_req::text,'UTF8'),'sha256'),'hex'),
         'stage1_payload',v_stage1,
         'transition',v_trans,
         'trace_persistence','NONE',
         'effect_authority',false,
         'downstream_execution_allowed',false
      );
    END;
  END IF;
  SELECT * INTO e
$sql$;
 EXECUTE replace(d,anchor,replacement);
END $patch$;

DO $patch$
DECLARE d text; anchor text; replacement text;
BEGIN
 d:=pg_get_functiondef('public.lf_router_pipeline_profile_semantic_submit_v1(text,text)'::regprocedure);
 anchor:=E'  v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(\n';
 IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
   RAISE EXCEPTION 'ROUTER_SEMANTIC_SUBMIT_ANCHOR_DRIFT';
 END IF;
 replacement:=$sql$  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_prep jsonb; v_ctx jsonb; v_raw_result jsonb; v_sel jsonb;
      v_after jsonb; v_gate jsonb; v_literal text;
      v_sha text;
    BEGIN
      v_prep:=public.lf_router_pipeline_profile_semantic_prepare_v1(p_execution_id);
      IF v_prep->>'status'<>'PROFILE_SEMANTIC_SELECTION_REQUIRED' THEN
        RETURN v_prep;
      END IF;
      IF nullif(btrim(coalesce(p_raw,'')),'') IS NULL THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_RAW_REQUIRED');
      END IF;
      v_raw_result:=public.lf_profile_selector_semantic_consume_raw_v1(
        v_prep->'profile_selection_request',p_raw);
      IF v_raw_result->>'status'<>'VALID'
         OR jsonb_typeof(v_raw_result->'result')<>'object'
         OR jsonb_typeof(v_raw_result->'validation')<>'object'
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_INVALID',
         'semantic_consume_result',v_raw_result);
      END IF;
      v_sel:=v_raw_result->'result';
      IF v_sel->>'decision'<>'SELECTED' THEN
        RETURN jsonb_build_object(
          'status',CASE WHEN v_sel->>'decision'='AMBIGUOUS' THEN 'PROFILE_SELECTION_AMBIGUOUS' ELSE 'PROFILE_SELECTION_NO_MATCH' END,
          'current_step','profile_semantic_selection',
          'semantic_result',v_sel,
          'semantic_validation',v_raw_result->'validation',
          'trace_persistence','NONE','effect_authority',false,
          'downstream_execution_allowed',false);
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_after:=public.lf_router_profile_after_selection_v1(v_ctx->'stage1_payload',v_sel);
      IF v_after->>'status'<>'READY_FOR_GATE2' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code',coalesce(v_after->>'blocking_code','BLOCK_ROUTER_PROFILE_AFTER_SELECTION_NOT_READY'),
          'after_selection_result',v_after,'effect_authority',false);
      END IF;
      v_gate:=public.lf_router_profile_gate2_result_from_selection_v1(
          v_after->'gate2_request',v_sel);
      IF v_gate->>'status'<>'READY' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_GATE2_DERIVATION_FAILED',
          'gate2_derivation',v_gate,'effect_authority',false);
      END IF;
      RETURN jsonb_build_object(
         'status','READ_ONLY_GATE2_DERIVED_NOT_AUTHORIZED',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','READ_ONLY_CONTEXT',
         'current_step','profile_gate2',
         'next_step','GOVERNED_PROFILE_EXECUTION_REQUIRED',
         'stage1_payload',v_ctx->'stage1_payload',
         'route_result',v_ctx->'stage2_route',
         'transition',v_ctx->'transition',
         'semantic_result',v_sel,
         'semantic_validation',v_raw_result->'validation',
         'after_selection_result',v_after,
         'gate2_derivation',v_gate,
         'trace_persistence','NONE',
         'effect_authority',false,
         'downstream_execution_allowed',false,
         'handoff_authorized',false
      );
    END;
  END IF;
  v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(
$sql$;
 EXECUTE replace(d,anchor,replacement);
END $patch$;

-- Existing functions only; do not grant direct access to internal dispatchers.
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_profile_semantic_prepare_v1(text)
  TO supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_profile_semantic_submit_v1(text,text)
  TO supabase_read_only_user;

COMMIT;
