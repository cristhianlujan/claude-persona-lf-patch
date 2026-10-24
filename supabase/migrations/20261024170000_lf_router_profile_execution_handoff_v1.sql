-- ACT-0001 / EJECUCION_PERFIL_LF: consume one Router decision without re-routing it.
-- A semantic Gate 2 produces a signed profile-execution handoff. The execution
-- validates that handoff, hydrates channel-specific context, and only returns to
-- ACT-0001 after the profile result exists.
BEGIN;

ALTER TABLE private.lf_profile_runtime_queue_v1
  ADD COLUMN IF NOT EXISTS router_profile_handoff jsonb;

COMMENT ON COLUMN private.lf_profile_runtime_queue_v1.router_profile_handoff IS
'Optional LF_ROUTER_PROFILE_EXECUTION_HANDOFF_V1. When present, consumers validate it and MUST NOT re-run ACT-0001 for the same decision.';

CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_v1(
  p_request jsonb,
  p_result jsonb,
  p_channel text,
  p_business text,
  p_scope jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  v_validation jsonb;
  v_resume jsonb;
  v_route jsonb;
  v_profile text;
  v_slug text;
  v_router_md5 text;
  v_operation_revision text;
  v_body jsonb;
  v_fp text;
BEGIN
  IF upper(coalesce(p_channel,'')) NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR upper(coalesce(p_business,'')) <> 'LF' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_CHANNEL_OR_BUSINESS_INVALID',
      'downstream_execution_allowed',false
    );
  END IF;

  v_validation:=public.lf_router_semantic_resume_validate_v1(p_request,p_result);
  IF v_validation->>'status' IS DISTINCT FROM 'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_GATE2_INVALID',
      'resume_validation',v_validation,
      'downstream_execution_allowed',false
    );
  END IF;

  -- Gate 2 re-derives ACT-0001 once. The resulting handoff is what travels.
  v_resume:=public.lf_router_semantic_resume_route_v1(p_request,p_result);
  v_route:=v_resume->'router_result';

  IF v_resume->>'status' IS DISTINCT FROM 'ROUTER_REDERIVED'
     OR v_route->>'status' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_route->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR coalesce((v_route->>'downstream_execution_allowed')::boolean,false) IS NOT TRUE
     OR v_route#>>'{asset,tipo_activo}' IS DISTINCT FROM 'PERFIL' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_ROUTER_NOT_READY',
      'resume_route',v_resume,
      'downstream_execution_allowed',false
    );
  END IF;

  v_profile:=v_route#>>'{asset,codigo_activo}';
  SELECT metadata->>'profile_slug'
    INTO v_slug
  FROM public.lf_activos
  WHERE codigo_activo=v_profile
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL
  LIMIT 1;

  IF nullif(v_profile,'') IS NULL OR nullif(v_slug,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_PROFILE_BINDING_UNRESOLVED',
      'downstream_execution_allowed',false
    );
  END IF;

  v_router_md5:=md5(pg_get_functiondef(
    'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
  ));
  v_operation_revision:=public.lf_operation_revision_sha256_v1('EJECUCION_PERFIL_LF');

  v_body:=jsonb_build_object(
    'schema_version','LF_ROUTER_PROFILE_EXECUTION_HANDOFF_V1',
    'router','ACT-0001',
    'channel',upper(p_channel),
    'business',upper(p_business),
    'scope',p_scope,
    'literal_request',p_request->>'literal_request',
    'request_sha256',p_request->>'request_sha256',
    'profile_code',v_profile,
    'profile_slug',v_slug,
    'operation_code','EJECUCION_PERFIL_LF',
    'semantic_request',p_request,
    'semantic_result',p_result,
    'router_result',v_route,
    'router_source_md5',v_router_md5,
    'operation_revision_sha256',v_operation_revision,
    'profile_execution_allowed',true,
    'effect_authority',false,
    'reenter_router_before_execution',false,
    'return_to_router_after_profile_result',true,
    'issued_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );

  v_fp:=encode(
    extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'handoff',v_body||jsonb_build_object('fingerprint_sha256',v_fp),
    'downstream_execution_allowed',true
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)
  TO service_role,supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(
  p_handoff jsonb,
  p_literal_request text DEFAULT NULL,
  p_profile_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  v_core jsonb;
  v_expected_fp text;
  v_validation jsonb;
  v_binding jsonb;
  v_current_md5 text;
  v_current_operation_revision text;
  v_route jsonb;
BEGIN
  IF jsonb_typeof(coalesce(p_handoff,'null'::jsonb))<>'object'
     OR p_handoff->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_PROFILE_EXECUTION_HANDOFF_V1'
     OR p_handoff->>'router' IS DISTINCT FROM 'ACT-0001'
     OR p_handoff->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR p_handoff->>'business' IS DISTINCT FROM 'LF'
     OR p_handoff->>'channel' NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR coalesce((p_handoff->>'profile_execution_allowed')::boolean,false) IS NOT TRUE
     OR coalesce((p_handoff->>'effect_authority')::boolean,true) IS NOT FALSE
     OR coalesce((p_handoff->>'reenter_router_before_execution')::boolean,true) IS NOT FALSE
     OR coalesce((p_handoff->>'return_to_router_after_profile_result')::boolean,false) IS NOT TRUE
  THEN
    RETURN jsonb_build_object('valid',false,'code','PROFILE_HANDOFF_SHAPE_INVALID');
  END IF;

  IF p_literal_request IS NOT NULL
     AND p_handoff->>'literal_request' IS DISTINCT FROM p_literal_request THEN
    RETURN jsonb_build_object('valid',false,'code','PROFILE_HANDOFF_LITERAL_MISMATCH');
  END IF;
  IF p_profile_code IS NOT NULL
     AND p_handoff->>'profile_code' IS DISTINCT FROM p_profile_code THEN
    RETURN jsonb_build_object('valid',false,'code','PROFILE_HANDOFF_PROFILE_MISMATCH');
  END IF;

  IF encode(
       extensions.digest(convert_to(coalesce(p_handoff->>'literal_request',''),'UTF8'),'sha256'),
       'hex'
     ) IS DISTINCT FROM p_handoff->>'request_sha256' THEN
    RETURN jsonb_build_object('valid',false,'code','PROFILE_HANDOFF_REQUEST_SHA_INVALID');
  END IF;

  v_core:=p_handoff-'fingerprint_sha256';
  v_expected_fp:=encode(
    extensions.digest(convert_to(v_core::text,'UTF8'),'sha256'),
    'hex'
  );
  IF coalesce(p_handoff->>'fingerprint_sha256','') !~ '^[0-9a-f]{64}$'
     OR p_handoff->>'fingerprint_sha256' IS DISTINCT FROM v_expected_fp THEN
    RETURN jsonb_build_object('valid',false,'code','PROFILE_HANDOFF_FINGERPRINT_INVALID');
  END IF;

  v_validation:=public.lf_router_semantic_resume_validate_v1(
    p_handoff->'semantic_request',
    p_handoff->'semantic_result'
  );
  IF v_validation->>'status' IS DISTINCT FROM 'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_SEMANTIC_RECEIPT_INVALID',
      'resume_validation',v_validation
    );
  END IF;

  v_binding:=public.lf_router_semantic_action_binding_validate_v1(
    p_handoff->'semantic_request',
    p_handoff->>'profile_code',
    'PERFIL'
  );
  IF coalesce((v_binding->>'valid')::boolean,false) IS NOT TRUE
     OR v_binding->>'candidate_action_code' IS DISTINCT FROM 'PROFILE_EXECUTION'
     OR v_binding->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF' THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_ACTION_BINDING_INVALID',
      'binding_validation',v_binding
    );
  END IF;

  v_route:=p_handoff->'router_result';
  IF jsonb_typeof(v_route)<>'object'
     OR v_route->>'status' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_route->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_route#>>'{asset,codigo_activo}' IS DISTINCT FROM p_handoff->>'profile_code'
     OR v_route#>>'{asset,tipo_activo}' IS DISTINCT FROM 'PERFIL'
     OR coalesce((v_route->>'downstream_execution_allowed')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object('valid',false,'code','PROFILE_HANDOFF_ROUTER_RESULT_INVALID');
  END IF;

  v_current_md5:=md5(pg_get_functiondef(
    'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
  ));
  IF p_handoff->>'router_source_md5' IS DISTINCT FROM v_current_md5 THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_ROUTER_SOURCE_STALE',
      'receipt_router_source_md5',p_handoff->>'router_source_md5',
      'current_router_source_md5',v_current_md5
    );
  END IF;

  v_current_operation_revision:=public.lf_operation_revision_sha256_v1('EJECUCION_PERFIL_LF');
  IF p_handoff->>'operation_revision_sha256' IS DISTINCT FROM v_current_operation_revision THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_OPERATION_REVISION_STALE'
    );
  END IF;

  RETURN jsonb_build_object(
    'valid',true,
    'code','PROFILE_HANDOFF_VALID',
    'channel',p_handoff->>'channel',
    'business',p_handoff->>'business',
    'profile_code',p_handoff->>'profile_code',
    'profile_slug',p_handoff->>'profile_slug',
    'operation_code','EJECUCION_PERFIL_LF',
    'fingerprint_sha256',p_handoff->>'fingerprint_sha256'
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
  TO service_role,supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_begin_from_handoff_v1(
  p_handoff jsonb,
  p_executor_mode text,
  p_execution_id text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_target_repo text,
  p_target_path text,
  p_manifest jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_valid jsonb;
  v_admission jsonb;
  v_begin jsonb;
  v_step jsonb;
  v_profile text:=p_handoff->>'profile_code';
  v_literal text:=p_handoff->>'literal_request';
  v_mode text:=upper(nullif(btrim(coalesce(p_executor_mode,'')),''));
  v_provider text;
  v_existing text;
BEGIN
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,v_literal,v_profile
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_EXECUTION_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  v_admission:=public.lf_profile_execution_executor_admission_v1(v_profile,v_mode);
  IF coalesce((v_admission->>'admitted')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_EXECUTOR_NOT_ADMITTED',
      'executor_admission',v_admission
    );
  END IF;

  v_provider:=case v_mode
    when 'GPT_NATIVE' then 'OPENAI_CHATGPT_NATIVE'
    when 'CLAUDE_NATIVE' then 'ANTHROPIC_CLAUDE_NATIVE'
    else null
  end;

  v_begin:=public.lf_profile_execution_begin_v1(
    p_execution_id,
    p_idempotency_key,
    p_handoff->>'request_sha256',
    p_actor_execution_id,
    v_profile,
    p_target_repo,
    p_target_path,
    coalesce(p_manifest,'{}'::jsonb)
      ||jsonb_build_object(
        'executor_mode',v_mode,
        'executor_provider',v_provider,
        'router_profile_handoff',p_handoff,
        'input_sha256','sha256:'||(p_handoff->>'request_sha256'),
        'read_only',true,
        'no_write',true,
        'no_promotion',true,
        'automatic_impact',false
      )
  );

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='router';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'router',
      'router-handoff://'||(p_handoff->>'fingerprint_sha256'),
      jsonb_build_object(
        'router_read','AUTHORIZED_HANDOFF_VALIDATED',
        'action','PROFILE_EXECUTION',
        'router_result',p_handoff->'router_result',
        'semantic_request',p_handoff->'semantic_request',
        'semantic_result',p_handoff->'semantic_result',
        'handoff_fingerprint_sha256',p_handoff->>'fingerprint_sha256',
        'channel',p_handoff->>'channel',
        'business',p_handoff->>'business',
        'reentered_router',false
      ),
      p_actor_execution_id
    );
  ELSE
    v_step:=jsonb_build_object('outcome','STEP_ALREADY_PRESENT','status',v_existing);
  END IF;

  RETURN v_begin||jsonb_build_object(
    'status','READY',
    'router_handoff_validated',true,
    'router_step',v_step,
    'next_step','profile_resolve',
    'reentered_router',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_execution_begin_from_handoff_v1(
  jsonb,text,text,text,text,text,text,jsonb
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_begin_from_handoff_v1(
  jsonb,text,text,text,text,text,text,jsonb
) TO service_role;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_channel_context_v1(
  p_execution_id text,
  p_base_context jsonb,
  p_handoff jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private','extensions','lf_ops','lf_design'
AS $fn$
DECLARE
  v_valid jsonb;
  v_pc jsonb;
  v_capsule jsonb;
  v_bytes bigint;
  v_tokens bigint;
  v_soft bigint;
  v_hard bigint;
  v_status text;
  v_event_id bigint;
  v_budget_event_id bigint;
  v_digest text;
BEGIN
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,
    p_handoff->>'literal_request',
    p_handoff->>'profile_code'
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_CHANNEL_CONTEXT_HANDOFF_INVALID',
      'handoff_validation',v_valid,
      'server_validated',false
    );
  END IF;

  IF p_handoff->>'channel'<>'PRODUCTO' THEN
    RETURN p_base_context||jsonb_build_object(
      'channel_context_mode','NOT_REQUIRED',
      'channel',p_handoff->>'channel'
    );
  END IF;

  v_pc:=public.lf_router_product_context_v1(
    p_handoff->>'literal_request',
    p_handoff->'scope'
  );
  IF v_pc->>'status' IS DISTINCT FROM 'RESOLVED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_NOT_RESOLVED',
      'product_context_summary',v_pc-'product_context',
      'server_validated',false
    );
  END IF;

  v_capsule:=coalesce(p_base_context->'context_capsule','{}'::jsonb)
    ||jsonb_build_object(
      'channel_context',
      jsonb_build_object(
        'channel','PRODUCTO',
        'source','public.lf_router_product_context_v1',
        'product_context',v_pc
      )
    );

  v_bytes:=octet_length(v_capsule::text);
  v_tokens:=ceil(v_bytes/4.0)::bigint;
  v_soft:=coalesce((p_base_context->>'soft_limit_tokens')::bigint,1500);
  v_hard:=coalesce((p_base_context->>'hard_limit_tokens')::bigint,3000);
  v_status:=case
    when v_tokens>v_hard then 'RED'
    when v_tokens>v_soft then 'YELLOW'
    else 'GREEN'
  end;

  IF v_status='RED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_BUDGET_RED',
      'estimated_tokens',v_tokens,
      'hard_limit_tokens',v_hard,
      'server_validated',false
    );
  END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
  ) VALUES (
    'SESION_INICIO','ACTIVO','ACT-0001',
    'Channel-specific context hydration for governed profile execution.',
    'INFO',
    jsonb_build_object(
      'producer','lf_profile_execution_channel_context_v1',
      'execution_id',p_execution_id,
      'channel','PRODUCTO',
      'base_context_receipt_ref',p_base_context->>'context_receipt_ref',
      'context_receipt',v_capsule
    ),
    'DB_FUNCTION',
    p_execution_id
  ) RETURNING id INTO v_event_id;

  v_budget_event_id:=nextval('private.lf_context_budget_events_v2_id_seq');
  INSERT INTO private.lf_context_budget_events_v2(
    id,execution_id,estimated_tokens,context_status,source,recommendation,evidence_event_id
  ) VALUES (
    v_budget_event_id,p_execution_id,v_tokens,v_status,
    'lf_profile_execution_channel_context_v1',
    case when v_status='YELLOW' then 'Prefer lazy reads for any additional Product detail.' else null end,
    v_event_id
  );

  v_digest:='sha256:'||encode(
    extensions.digest(convert_to(v_capsule::text,'UTF8'),'sha256'),'hex'
  );

  RETURN p_base_context
    ||jsonb_build_object(
      'status','READY',
      'blocking_code',null,
      'server_validated',true,
      'channel','PRODUCTO',
      'channel_context_mode','HYDRATED_BY_EXECUTION',
      'context_event_id',v_event_id,
      'context_budget_event_id',v_budget_event_id,
      'context_receipt_ref','supabase://public.lf_eventos/'||v_event_id::text||'#context_receipt',
      'context_receipt_digest',v_digest,
      'context_budget_status',v_status,
      'context_capsule_estimated_tokens',v_tokens,
      'context_capsule_bytes',v_bytes,
      'context_capsule',v_capsule
    );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)
  TO service_role;

CREATE OR REPLACE FUNCTION programacion.fn_lf_profile_runtime_enqueue_authorized_v1(
  p_handoff jsonb,
  p_requested_by text DEFAULT 'ACT-0001',
  p_github_backup_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_valid jsonb;
  v_remote jsonb;
  v_request_id uuid:=gen_random_uuid();
  v_runtime_target text;
  v_profile text:=p_handoff->>'profile_code';
BEGIN
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,p_handoff->>'literal_request',v_profile
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','PROFILE_RUNTIME_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  v_remote:=public.lf_profile_execution_executor_admission_v1(v_profile,'REMOTE_API');
  IF coalesce((v_remote->>'admitted')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','NATIVE_EXECUTOR_REQUIRED',
      'operation_code','EJECUCION_PERFIL_LF',
      'profile_code',v_profile,
      'gpt_native',public.lf_profile_execution_executor_admission_v1(v_profile,'GPT_NATIVE'),
      'claude_native',public.lf_profile_execution_executor_admission_v1(v_profile,'CLAUDE_NATIVE'),
      'remote_api',v_remote,
      'router_reentry_required',false
    );
  END IF;

  v_runtime_target:=case
    when nullif(btrim(coalesce(p_github_backup_reason,'')),'') is null then 'HETZNER'
    else 'GITHUB_ACTIONS'
  end;

  INSERT INTO private.lf_profile_runtime_queue_v1(
    request_id,operation_code,profile_code,profile_slug,profile_source_paths,
    input_literal,status,requested_by,runtime_target,runtime_request_envelope,
    runtime_backup_reason,router_profile_handoff
  )
  SELECT
    v_request_id,'EJECUCION_PERFIL_LF',a.codigo_activo,a.metadata->>'profile_slug',
    jsonb_build_array(
      coalesce(
        nullif(a.metadata->>'entrypoint_path',''),
        case
          when a.ruta_esperada like '%.md' then a.ruta_esperada
          else rtrim(a.ruta_esperada,'/')||'/SKILL.md'
        end
      )
    ),
    p_handoff->>'literal_request','PENDING',p_requested_by,v_runtime_target,null,
    nullif(btrim(coalesce(p_github_backup_reason,'')),''),p_handoff
  FROM public.lf_activos a
  WHERE a.codigo_activo=v_profile
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','PROFILE_RUNTIME_PROFILE_BINDING_UNRESOLVED'
    );
  END IF;

  RETURN jsonb_build_object(
    'status','PENDING',
    'request_id',v_request_id,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',v_profile,
    'runtime_target',v_runtime_target,
    'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION programacion.fn_lf_profile_runtime_enqueue_authorized_v1(jsonb,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_lf_profile_runtime_enqueue_authorized_v1(jsonb,text,text)
  TO service_role;

-- Stage2 PRODUCTO no longer performs Product work itself.
DO $patch_route$
DECLARE
  v_def text;
  v_start integer;
  v_end integer;
  v_block text;
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure))
     <> '786f040b8df29ac7047a6a5e18971bd9' THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_ROUTE_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure);
  v_start:=strpos(v_def,E'    IF v_channel=''PRODUCTO'' THEN');
  v_end:=strpos(v_def,E'    -- If no exact aggregate product context is available');

  IF v_start=0 OR v_end=0 OR v_end<=v_start THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_PRODUCT_BLOCK_ANCHOR_MISSING';
  END IF;

  v_block:=E'    IF v_channel=''PRODUCTO'' THEN\n'
    ||E'      v_rs:=public.lf_router_resolve_v1(\n'
    ||E'        p_stage1->>''texto_original'',\n'
    ||E'        ''PERFIL-PRODUCT-DIRECTOR-LF'',\n'
    ||E'        ''PROFILE_EXECUTION'',\n'
    ||E'        ''PERFIL'',\n'
    ||E'        ''ROUTER''\n'
    ||E'      );\n\n'
    ||E'      IF v_rs->>''blocking_code''<>''BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED''\n'
    ||E'         OR v_rs#>>''{semantic_handoff_v2,schema_version}''<>''LF_ROUTER_SEMANTIC_REQUEST_V1'' THEN\n'
    ||E'        RETURN v_base||jsonb_build_object(\n'
    ||E'          ''paso'',''PRODUCTO_GATE2_NO_LISTO'',\n'
    ||E'          ''router_resolve'',v_rs,\n'
    ||E'          ''motivo_es'',''El Router no pudo preparar la admision semantica del perfil de Producto.'',\n'
    ||E'          ''siguiente_paso_es'',''Bloquear; no ejecutar perfil ni cargar contexto.''\n'
    ||E'        );\n'
    ||E'      END IF;\n\n'
    ||E'      RETURN v_base||jsonb_build_object(\n'
    ||E'        ''paso'',''PRODUCTO_GATE2_PERFIL'',\n'
    ||E'        ''perfil_candidato'',''PERFIL-PRODUCT-DIRECTOR-LF'',\n'
    ||E'        ''perfil_modo'',''READ_ONLY'',\n'
    ||E'        ''gate2_request'',v_rs->''semantic_handoff_v2'',\n'
    ||E'        ''gate2_result_contract'',''LF_ROUTER_SEMANTIC_RESULT_V1'',\n'
    ||E'        ''after_gate2_handoff_builder'',''public.lf_router_profile_execution_handoff_v1'',\n'
    ||E'        ''siguiente_operacion'',jsonb_build_object(\n'
    ||E'          ''operation_code'',''EJECUCION_PERFIL_LF'',\n'
    ||E'          ''entrypoint'',''ROUTER_AUTHORIZED_HANDOFF_ONLY'',\n'
    ||E'          ''native_begin'',''public.lf_profile_execution_begin_from_handoff_v1'',\n'
    ||E'          ''remote_enqueue'',''programacion.fn_lf_profile_runtime_enqueue_authorized_v1'',\n'
    ||E'          ''context_hydrator'',''public.lf_profile_execution_channel_context_v1'',\n'
    ||E'          ''router_reentry_before_execution'',false,\n'
    ||E'          ''return_to_router_after_profile_result'',true\n'
    ||E'        ),\n'
    ||E'        ''motivo_es'',''Producto deriva a un recurso especializado. El Router autoriza una sola vez; EJECUCION_PERFIL_LF ejecuta y carga el contexto.'',\n'
    ||E'        ''siguiente_paso_es'',''Resolver Gate 2; si PASS, materializar EJECUCION_PERFIL_LF sin volver a enrutar la misma decision.''\n'
    ||E'      );\n'
    ||E'    END IF;\n\n';

  v_def:=left(v_def,v_start-1)||v_block||substr(v_def,v_end);
  EXECUTE v_def;
END
$patch_route$;

UPDATE public.lf_operation_step_contracts
SET resolver_ref='public.lf_profile_execution_context_admission_v1 + public.lf_profile_execution_channel_context_v1'
WHERE operation_code='EJECUCION_PERFIL_LF'
  AND step_id='context_admission';

-- Source-level and runtime-safe invariants.
DO $test$
DECLARE
  v_route_def text;
  v_context_ref text;
  v_native jsonb;
  v_remote jsonb;
BEGIN
  v_route_def:=pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure);

  IF position('PRODUCTO_CONTEXTO_CANONICO' in v_route_def)>0
     OR position('lf_router_product_context_v1(' in substring(v_route_def from position('IF v_channel=''PRODUCTO''' in v_route_def) for 2500))>0
     OR position('PRODUCTO_GATE2_PERFIL' in v_route_def)=0
     OR position('ROUTER_AUTHORIZED_HANDOFF_ONLY' in v_route_def)=0
  THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_ROUTER_STILL_EXECUTES_PRODUCT_WORK';
  END IF;

  SELECT resolver_ref INTO v_context_ref
  FROM public.lf_operation_step_contracts
  WHERE operation_code='EJECUCION_PERFIL_LF' AND step_id='context_admission';

  IF position('lf_profile_execution_channel_context_v1' in coalesce(v_context_ref,''))=0 THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_CHANNEL_CONTEXT_NOT_BOUND';
  END IF;

  v_native:=public.lf_profile_execution_executor_admission_v1(
    'PERFIL-PRODUCT-DIRECTOR-LF','GPT_NATIVE'
  );
  v_remote:=public.lf_profile_execution_executor_admission_v1(
    'PERFIL-PRODUCT-DIRECTOR-LF','REMOTE_API'
  );

  IF coalesce((v_native->>'admitted')::boolean,false) IS NOT TRUE
     OR coalesce((v_remote->>'admitted')::boolean,true) IS NOT FALSE THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_PRODUCT_EXECUTOR_MODE_EXPECTATION_DRIFT';
  END IF;
END
$test$;

COMMIT;
