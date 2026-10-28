-- Router ACT-0001 candidate: read-only transport through EXISTING pipeline functions.
-- No new public Router function. Existing governed persisted branch remains unchanged.
-- Must be acceptance tested before deployment / cutover.
BEGIN;

DO $patch$
DECLARE
 d text;
 anchor text;
 replacement text;
BEGIN
 d:=pg_get_functiondef('public.lf_router_pipeline_begin_v1(text)'::regprocedure);
 anchor:=E'  v_request_sha:=encode(\n';
 IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'ROUTER_BEGIN_TRANSPORT_ANCHOR_DRIFT';
 END IF;
 replacement:=$sql$  -- Pure read-only derivation: no execution row, step row or manifest update.
  -- Explicit governed effects continue through the existing writer, opted in
  -- only by its already-authorized service-role entrypoint.
  IF session_user = 'supabase_read_only_user' THEN
    v_begin:=jsonb_build_object(
         'schema_version','LF_ROUTER_READ_ONLY_CONTEXT_V1',
         'original_request_text',v_request,
         'request_sha256',encode(extensions.digest(convert_to(v_request,'UTF8'),'sha256'),'hex'),
         'next_step','stage1_seal',
         'effect_authority',false
    );
    RETURN jsonb_build_object(
      'status','STAGE1_REQUIRED',
      'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
      'transport_mode','READ_ONLY_CONTEXT',
      'request_context',v_begin,
      'transport_token','ROCTX:'||encode(convert_to(v_begin::text,'UTF8'),'base64'),
      'current_step','request_intake',
      'next_step','stage1_seal',
      'stage1_contract','LF_ROUTER_STAGE1_V2',
      'effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;
  v_request_sha:=encode(
$sql$;
 EXECUTE replace(d,anchor,replacement);
END $patch$;

DO $patch$
DECLARE d text; anchor text; replacement text;
BEGIN
 d:=pg_get_functiondef('public.lf_router_pipeline_stage1_submit_v1(text,jsonb)'::regprocedure);
 anchor:=E'  SELECT * INTO e\n';
 IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'ROUTER_STAGE1_TRANSPORT_ANCHOR_DRIFT';
 END IF;
 replacement:=$sql$  -- The read-only user supplies an encoded JSON envelope in the existing
  -- execution-id parameter. It does not qualify as an execution id or receipt.
  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_ctx jsonb;
      v_route jsonb;
      v_transition jsonb;
      v_literal text;
    BEGIN
      IF left(coalesce(p_execution_id,''),6)<>'ROCTX:' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_READ_ONLY_CONTEXT_V1'
         OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
         OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
         OR p_stage1->>'texto_original' IS DISTINCT FROM v_literal
         OR p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
      THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUEST_MISMATCH');
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
        'transport_mode','READ_ONLY_CONTEXT',
        'current_step','resolve_next_transition',
        'next_step',v_transition->>'next_step',
        'stage1_validation',v_validation,
        'stage1_payload',p_stage1,
        'route_result',v_route,
        'transition',v_transition,
        'profile_selection_request',v_route->'profile_selection_request',
        'transport_token','ROCTX:'||encode(convert_to(jsonb_build_object(
           'schema_version','LF_ROUTER_READ_ONLY_CONTEXT_V1',
           'original_request_text',v_literal,
           'request_sha256',v_ctx->>'request_sha256',
           'stage1_payload',p_stage1,
           'stage2_route',v_route,
           'transition',v_transition,
           'next_step',v_transition->>'next_step',
           'effect_authority',false
        )::text,'UTF8'),'base64'),
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

-- No blanket grant to internal functions. Read-only can use only the
-- guarded existing beginning and Stage1 continuation.
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_begin_v1(text) TO supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_stage1_submit_v1(text,jsonb) TO supabase_read_only_user;

COMMIT;
