-- LF Router ACT-0001 Context V2: remove ONLY unreachable V1 fallback branches.
-- Preserve current output, signature, permissions, identity checks and downstream admission.
-- Verified against exact live source function MD5; migration is fail-closed on drift.
-- NO DROP FUNCTION, NO REVOKE, NO ALTER of Input Governance / profiles / V1 compatibility.

-- lf_router_pipeline_context_begin_v2 (observed source MD5 ace0425eeea3c818fd8dbd9e86c93796)
DO $precheck$
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_pipeline_context_begin_v2(text)'::regprocedure)) <> 'ace0425eeea3c818fd8dbd9e86c93796' THEN
    RAISE EXCEPTION 'LF_CONTEXT_V2_SOURCE_DRIFT: lf_router_pipeline_context_begin_v2';
  END IF;
END
$precheck$;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_begin_v2(p_request_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_request text:=btrim(coalesce(p_request_text,''));
  v_begin jsonb;
BEGIN
  IF v_request='' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_REQUEST_REQUIRED'
    );
  END IF;

  -- Pure read-only derivation: no execution row, step row or manifest update.
  -- Explicit governed effects continue through the existing writer, opted in
  -- only by its already-authorized service-role entrypoint.
    v_begin:=jsonb_build_object(
         'schema_version','LF_ROUTER_EXECUTION_CONTEXT_V2',
         'original_request_text',v_request,
         'request_sha256',encode(extensions.digest(convert_to(v_request,'UTF8'),'sha256'),'hex'),
         'next_step','stage1_seal',
         'effect_authority',false
    );
    RETURN jsonb_build_object(
      'status','STAGE1_REQUIRED',
      'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
      'transport_mode','CONTEXT_TRANSPORT',
      'request_context',v_begin,
      'context_token','RCTX2:'||encode(convert_to(v_begin::text,'UTF8'),'base64'),
      'current_step','request_intake',
      'next_step','stage1_seal',
      'stage1_contract','LF_ROUTER_STAGE1_V2',
      'effect_authority',false,
      'downstream_execution_allowed',false
    );
END
$function$;

-- lf_router_pipeline_context_profile_semantic_prepare_v2 (observed source MD5 de1ad7bbe366c1b4ce358788ac6745bd)
DO $precheck$
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_pipeline_context_profile_semantic_prepare_v2(text)'::regprocedure)) <> 'de1ad7bbe366c1b4ce358788ac6745bd' THEN
    RAISE EXCEPTION 'LF_CONTEXT_V2_SOURCE_DRIFT: lf_router_pipeline_context_profile_semantic_prepare_v2';
  END IF;
END
$precheck$;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_profile_semantic_prepare_v2(p_context_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
BEGIN
    DECLARE
      v_ctx jsonb; v_stage1 jsonb; v_route jsonb;
      v_trans jsonb; v_req jsonb; v_literal text;
    BEGIN
      IF left(coalesce(p_context_token,''),6)<>'RCTX2:' THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_TRANSPORT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_context_token,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_TRANSPORT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      v_stage1:=v_ctx->'stage1_payload';
      v_route:=v_ctx->'stage2_route';
      v_trans:=v_ctx->'transition';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_EXECUTION_CONTEXT_V2'
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
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_TRANSPORT_NOT_VERIFIED');
      END IF;
      v_req:=v_route->'profile_selection_request';
      IF jsonb_typeof(v_req)<>'object'
         OR v_req->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
         OR v_req->>'literal_request' IS DISTINCT FROM v_literal
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_PROFILE_REQUEST_INVALID');
      END IF;
      RETURN jsonb_build_object(
         'status','PROFILE_SEMANTIC_SELECTION_REQUIRED',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','CONTEXT_TRANSPORT',
         'context_token',p_context_token,
         'current_step','resolve_next_transition',
         'next_step','profile_semantic_selection',
         'profile_selection_request',v_req,
         'profile_selection_request_sha256',
             encode(extensions.digest(convert_to(v_req::text,'UTF8'),'sha256'),'hex'),
         'stage1_payload',v_stage1,
         'transition',v_trans,
         'persistence_policy','CONTRACT_CONTROLLED',
         'effect_authority',false,
         'downstream_execution_allowed',false
      );
    END;
END
$function$;

-- lf_router_pipeline_context_profile_semantic_submit_v2 (observed source MD5 ddd7d7ccacebb0abea8e146482ab5433)
DO $precheck$
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_pipeline_context_profile_semantic_submit_v2(text,text)'::regprocedure)) <> 'ddd7d7ccacebb0abea8e146482ab5433' THEN
    RAISE EXCEPTION 'LF_CONTEXT_V2_SOURCE_DRIFT: lf_router_pipeline_context_profile_semantic_submit_v2';
  END IF;
END
$precheck$;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_profile_semantic_submit_v2(p_context_token text, p_raw text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
BEGIN
    DECLARE
      v_prep jsonb; v_ctx jsonb; v_raw_result jsonb; v_sel jsonb;
      v_after jsonb; v_gate jsonb; v_literal text;
      v_sha text;
    BEGIN
      v_prep:=public.lf_router_pipeline_context_profile_semantic_prepare_v2(p_context_token);
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
          'persistence_policy','CONTRACT_CONTROLLED','effect_authority',false,
          'downstream_execution_allowed',false);
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_context_token,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_TRANSPORT_INVALID');
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
         'status','GATE2_DERIVED_PENDING_GOVERNED_ADMISSION',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','CONTEXT_TRANSPORT',
         'current_step','profile_gate2',
         'next_step','GOVERNED_PROFILE_EXECUTION_REQUIRED',
         'stage1_payload',v_ctx->'stage1_payload',
         'route_result',v_ctx->'stage2_route',
         'transition',v_ctx->'transition',
         'semantic_result',v_sel,
         'semantic_validation',v_raw_result->'validation',
         'after_selection_result',v_after,
         'gate2_derivation',v_gate,
         'persistence_policy','CONTRACT_CONTROLLED',
         'effect_authority',false,
         'downstream_execution_allowed',false,
         'handoff_authorized',false
      );
    END;
END
$function$;

-- lf_router_pipeline_context_stage1_submit_v2 (observed source MD5 46f314bef29bf95ac930fefb49d3eba9)
DO $precheck$
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_pipeline_context_stage1_submit_v2(text,jsonb)'::regprocedure)) <> '46f314bef29bf95ac930fefb49d3eba9' THEN
    RAISE EXCEPTION 'LF_CONTEXT_V2_SOURCE_DRIFT: lf_router_pipeline_context_stage1_submit_v2';
  END IF;
END
$precheck$;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_stage1_submit_v2(p_context_token text, p_stage1 jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_validation jsonb;
BEGIN
  -- The read-only user supplies an encoded JSON envelope in the existing
  -- execution-id parameter. It does not qualify as an execution id or receipt.
    DECLARE
      v_ctx jsonb;
      v_route jsonb;
      v_transition jsonb;
      v_literal text;
    BEGIN
      IF left(coalesce(p_context_token,''),6)<>'RCTX2:' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_CONTEXT_TRANSPORT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_context_token,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_CONTEXT_TRANSPORT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_EXECUTION_CONTEXT_V2'
         OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
         OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
         OR p_stage1->>'texto_original' IS DISTINCT FROM v_literal
         OR p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
      THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_CONTEXT_TRANSPORT_REQUEST_MISMATCH');
      END IF;
      v_validation:=public.lf_router_stage1_validate_v2(p_stage1);
      IF v_validation->>'valid'<>'true' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_ROUTER_STAGE1_INVALID',
          'stage1_validation',v_validation);
      END IF;
      v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);
      v_transition:=public.lf_router_route_transition_resolve_v1(v_route);
      IF v_transition->>'status'<>'RESOLVED' THEN
        RETURN jsonb_build_object('status','BLOCKED',
           'blocking_code','BLOCK_ROUTER_TRANSITION_INVALID',
           'stage1_validation',v_validation,
           'route_result',v_route,'transition',v_transition);
      END IF;
      RETURN jsonb_build_object(
        'status','NEXT_TRANSITION_READY',
        'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
        'transport_mode','CONTEXT_TRANSPORT',
        'current_step','resolve_next_transition',
        'next_step',v_transition->>'next_step',
        'stage1_validation',v_validation,
        'stage1_payload',p_stage1,
        'route_result',v_route,
        'transition',v_transition,
        'profile_selection_request',v_route->'profile_selection_request',
        'context_token','RCTX2:'||encode(convert_to(jsonb_build_object(
           'schema_version','LF_ROUTER_EXECUTION_CONTEXT_V2',
           'original_request_text',v_literal,
           'request_sha256',v_ctx->>'request_sha256',
           'stage1_payload',p_stage1,
           'stage2_route',v_route,
           'transition',v_transition,
           'next_step',v_transition->>'next_step',
           'effect_authority',false
        )::text,'UTF8'),'base64'),
        'persistence_policy','CONTRACT_CONTROLLED',
        'effect_authority',false,
        'downstream_execution_allowed',false
      );
    END;
END
$function$;

-- Cross-function safety check: transport remains read-only and no abandoned V1 writers remain.
DO $postcheck$
DECLARE v_name text; v_def text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'lf_router_pipeline_context_begin_v2',
    'lf_router_pipeline_context_stage1_submit_v2',
    'lf_router_pipeline_context_profile_semantic_prepare_v2',
    'lf_router_pipeline_context_profile_semantic_submit_v2'
  ] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname=v_name;
    IF v_def IS NULL OR position('IF true THEN' IN v_def)>0 OR
       position('lf_record_router_execution_step_v1' IN v_def)>0 OR
       position('UPDATE public.lf_operation_execution' IN v_def)>0 OR
       position('fn_lf_operation_reserve_execution_v1' IN v_def)>0 OR
       position('effect_authority' IN v_def)=0 THEN
      RAISE EXCEPTION 'LF_CONTEXT_V2_POSTCHECK_FAILED: %', v_name;
    END IF;
  END LOOP;
END
$postcheck$;
