BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_v1(
  p_request jsonb,
  p_result jsonb,
  p_channel text,
  p_business text,
  p_scope jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_validation jsonb;
  v_binding jsonb;
  v_profile text;
  v_slug text;
  v_router_md5 text;
  v_operation_revision text;
  v_auth_core jsonb;
  v_auth_fp text;
  v_auth_receipt jsonb;
  v_body jsonb;
  v_fp text;
  v_task_intent text;
  v_repair_write_allowed boolean:=false;
  v_repair_core jsonb;
  v_repair_fp text;
  v_repair_authority jsonb;
BEGIN
  IF upper(coalesce(p_channel,'')) NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR upper(coalesce(p_business,'')) <> 'LF' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_CHANNEL_OR_BUSINESS_INVALID',
      'downstream_execution_allowed',false
    );
  END IF;

  v_validation:=public.lf_router_semantic_resume_validate_v1(
    p_request,p_result
  );

  IF v_validation->>'status' IS DISTINCT FROM 'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE
     OR p_result->>'decision' IS DISTINCT FROM 'RESOLVED'
     OR jsonb_array_length(coalesce(p_result->'positive_target_refs','[]'::jsonb))<>1
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_GATE2_INVALID',
      'resume_validation',v_validation,
      'downstream_execution_allowed',false
    );
  END IF;

  v_profile:=p_result#>>'{positive_target_refs,0}';

  v_binding:=public.lf_router_semantic_action_binding_validate_v1(
    p_request,
    v_profile,
    'PERFIL'
  );

  IF coalesce((v_binding->>'valid')::boolean,false) IS NOT TRUE
     OR v_binding->>'candidate_action_code' IS DISTINCT FROM 'PROFILE_EXECUTION'
     OR v_binding->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_ACTION_BINDING_INVALID',
      'binding_validation',v_binding,
      'downstream_execution_allowed',false
    );
  END IF;

  v_task_intent:=upper(coalesce(
    p_request#>>'{router_action_binding,profile_task_intent}',
    ''
  ));

  v_repair_write_allowed:=
    v_profile='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    AND v_task_intent='REPAIR_MISSING_PRODUCT_STRUCTURE';

  SELECT a.metadata->>'profile_slug'
    INTO v_slug
  FROM public.lf_activos a
  JOIN public.lf_profile_selection_registry_v1 r
    ON r.profile_code=a.codigo_activo
   AND r.descriptor_status='CURRENT'
  WHERE a.codigo_activo=v_profile
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
    AND nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
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

  v_operation_revision:=
    public.lf_operation_revision_sha256_v1('EJECUCION_PERFIL_LF');

  v_auth_core:=jsonb_build_object(
    'schema_version','LF_ROUTER_PROFILE_AUTHORIZATION_RECEIPT_V1',
    'router','ACT-0001',
    'authority_ref','ROUTER_PROFILE_EXECUTION_AUTHORIZATION',
    'source','ACT-0001_PRE_SEMANTIC_BINDING_PLUS_GATE2',
    'request_sha256',p_request->>'request_sha256',
    'profile_code',v_profile,
    'asset_type','PERFIL',
    'action_code',v_binding->>'candidate_action_code',
    'operation_code',v_binding->>'operation_code',
    'router_action_binding_sha256',v_binding->>'binding_sha256',
    'gate2_semantic_receipt_sha256',p_result->>'semantic_receipt_sha256',
    'router_source_md5',v_router_md5,
    'operation_revision_sha256',v_operation_revision,
    'channel',upper(p_channel),
    'business',upper(p_business),
    'scope',p_scope,
    'profile_execution_allowed',true,
    'effect_authority',false,
    'router_reentry_before_execution',false,
    'issued_at',to_char(
      clock_timestamp() at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    )
  );

  v_auth_fp:=encode(
    extensions.digest(convert_to(v_auth_core::text,'UTF8'),'sha256'),
    'hex'
  );
  v_auth_receipt:=v_auth_core||jsonb_build_object(
    'fingerprint_sha256',v_auth_fp
  );

  IF v_repair_write_allowed THEN
    v_repair_core:=jsonb_build_object(
      'schema_version','LF_SRCR_REPAIR_EXECUTION_AUTHORITY_V1',
      'mode','GOVERNED_REPAIR_WRITE',
      'profile_code',v_profile,
      'profile_task_intent',v_task_intent,
      'operation_code','EJECUCION_PERFIL_LF',
      'request_sha256',p_request->>'request_sha256',
      'router_action_binding_sha256',v_binding->>'binding_sha256',
      'router_authorization_fingerprint_sha256',v_auth_fp,
      'scope',p_scope,
      'readback_required',true,
      'rollback_required',true,
      'promotion_allowed',false,
      'automatic_impact',false,
      'direct_profile_invocation_allowed',false,
      'return_to_router_after_result',true,
      'issued_at',to_char(
        clock_timestamp() at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      )
    );
    v_repair_fp:=encode(
      extensions.digest(convert_to(v_repair_core::text,'UTF8'),'sha256'),
      'hex'
    );
    v_repair_authority:=v_repair_core||jsonb_build_object(
      'fingerprint_sha256',v_repair_fp
    );
  ELSE
    v_repair_authority:=NULL;
  END IF;

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
    'router_authorization_receipt',v_auth_receipt,
    'repair_execution_authority',v_repair_authority,
    'router_source_md5',v_router_md5,
    'operation_revision_sha256',v_operation_revision,
    'profile_execution_allowed',true,
    'effect_authority',false,
    'reenter_router_before_execution',false,
    'return_to_router_after_profile_result',true,
    'issued_at',to_char(
      clock_timestamp() at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    )
  );

  v_fp:=encode(
    extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'handoff',v_body||jsonb_build_object('fingerprint_sha256',v_fp),
    'downstream_execution_allowed',true,
    'router_reentered',false,
    'governed_repair_write_allowed',v_repair_write_allowed
  );
END
$function$;


CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(
  p_handoff jsonb,
  p_literal_request text DEFAULT NULL::text,
  p_profile_code text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_core jsonb;
  v_expected_fp text;
  v_validation jsonb;
  v_binding jsonb;
  v_current_md5 text;
  v_current_operation_revision text;
  v_auth jsonb;
  v_auth_core jsonb;
  v_expected_auth_fp text;
  v_profile_slug text;
  v_task_intent text;
  v_repair_expected boolean:=false;
  v_repair jsonb;
  v_repair_core jsonb;
  v_expected_repair_fp text;
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
     OR jsonb_typeof(p_handoff->'router_authorization_receipt')<>'object'
  THEN
    RETURN jsonb_build_object('valid',false,'code','PROFILE_HANDOFF_SHAPE_INVALID');
  END IF;

  IF p_handoff ? 'router_result' THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_LEGACY_ROUTER_RESULT_FORBIDDEN'
    );
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
       extensions.digest(
         convert_to(coalesce(p_handoff->>'literal_request',''),'UTF8'),
         'sha256'
       ),
       'hex'
     ) IS DISTINCT FROM p_handoff->>'request_sha256'
  THEN
    RETURN jsonb_build_object('valid',false,'code','PROFILE_HANDOFF_REQUEST_SHA_INVALID');
  END IF;

  v_core:=p_handoff-'fingerprint_sha256';
  v_expected_fp:=encode(
    extensions.digest(convert_to(v_core::text,'UTF8'),'sha256'),
    'hex'
  );

  IF coalesce(p_handoff->>'fingerprint_sha256','') !~ '^[0-9a-f]{64}$'
     OR p_handoff->>'fingerprint_sha256' IS DISTINCT FROM v_expected_fp
  THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_FINGERPRINT_INVALID'
    );
  END IF;

  v_validation:=public.lf_router_semantic_resume_validate_v1(
    p_handoff->'semantic_request',
    p_handoff->'semantic_result'
  );

  IF v_validation->>'status' IS DISTINCT FROM 'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE
  THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','PROFILE_HANDOFF_SEMANTIC_RECEIPT_INVALID',
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
     OR v_binding->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
  THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','PROFILE_HANDOFF_ACTION_BINDING_INVALID',
      'binding_validation',v_binding
    );
  END IF;

  SELECT a.metadata->>'profile_slug'
    INTO v_profile_slug
  FROM public.lf_activos a
  JOIN public.lf_profile_selection_registry_v1 r
    ON r.profile_code=a.codigo_activo
   AND r.descriptor_status='CURRENT'
  WHERE a.codigo_activo=p_handoff->>'profile_code'
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
    AND nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
  LIMIT 1;

  IF nullif(v_profile_slug,'') IS NULL
     OR v_profile_slug IS DISTINCT FROM p_handoff->>'profile_slug'
  THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_PROFILE_CURRENTNESS_INVALID'
    );
  END IF;

  v_auth:=p_handoff->'router_authorization_receipt';

  IF v_auth->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_PROFILE_AUTHORIZATION_RECEIPT_V1'
     OR v_auth->>'router' IS DISTINCT FROM 'ACT-0001'
     OR v_auth->>'authority_ref' IS DISTINCT FROM 'ROUTER_PROFILE_EXECUTION_AUTHORIZATION'
     OR v_auth->>'source' IS DISTINCT FROM 'ACT-0001_PRE_SEMANTIC_BINDING_PLUS_GATE2'
     OR v_auth->>'request_sha256' IS DISTINCT FROM p_handoff->>'request_sha256'
     OR v_auth->>'profile_code' IS DISTINCT FROM p_handoff->>'profile_code'
     OR v_auth->>'asset_type' IS DISTINCT FROM 'PERFIL'
     OR v_auth->>'action_code' IS DISTINCT FROM 'PROFILE_EXECUTION'
     OR v_auth->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_auth->>'router_action_binding_sha256' IS DISTINCT FROM v_binding->>'binding_sha256'
     OR v_auth->>'gate2_semantic_receipt_sha256' IS DISTINCT FROM
        p_handoff#>>'{semantic_result,semantic_receipt_sha256}'
     OR v_auth->>'channel' IS DISTINCT FROM p_handoff->>'channel'
     OR v_auth->>'business' IS DISTINCT FROM p_handoff->>'business'
     OR v_auth->'scope' IS DISTINCT FROM p_handoff->'scope'
     OR coalesce((v_auth->>'profile_execution_allowed')::boolean,false) IS NOT TRUE
     OR coalesce((v_auth->>'effect_authority')::boolean,true) IS NOT FALSE
     OR coalesce((v_auth->>'router_reentry_before_execution')::boolean,true) IS NOT FALSE
  THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_ROUTER_AUTHORIZATION_IDENTITY_INVALID'
    );
  END IF;

  v_auth_core:=v_auth-'fingerprint_sha256';
  v_expected_auth_fp:=encode(
    extensions.digest(convert_to(v_auth_core::text,'UTF8'),'sha256'),
    'hex'
  );

  IF coalesce(v_auth->>'fingerprint_sha256','') !~ '^[0-9a-f]{64}$'
     OR v_auth->>'fingerprint_sha256' IS DISTINCT FROM v_expected_auth_fp
  THEN
    RETURN jsonb_build_object(
      'valid',false,'code','PROFILE_HANDOFF_ROUTER_AUTHORIZATION_FINGERPRINT_INVALID'
    );
  END IF;

  v_task_intent:=upper(coalesce(
    p_handoff#>>'{semantic_request,router_action_binding,profile_task_intent}',
    ''
  ));
  v_repair_expected:=
    p_handoff->>'profile_code'='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    AND v_task_intent='REPAIR_MISSING_PRODUCT_STRUCTURE';
  v_repair:=p_handoff->'repair_execution_authority';

  IF v_repair_expected THEN
    IF jsonb_typeof(v_repair)<>'object'
       OR v_repair->>'schema_version'<>'LF_SRCR_REPAIR_EXECUTION_AUTHORITY_V1'
       OR v_repair->>'mode'<>'GOVERNED_REPAIR_WRITE'
       OR v_repair->>'profile_code'<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       OR v_repair->>'profile_task_intent'<>'REPAIR_MISSING_PRODUCT_STRUCTURE'
       OR v_repair->>'operation_code'<>'EJECUCION_PERFIL_LF'
       OR v_repair->>'request_sha256' IS DISTINCT FROM p_handoff->>'request_sha256'
       OR v_repair->>'router_action_binding_sha256' IS DISTINCT FROM v_binding->>'binding_sha256'
       OR v_repair->>'router_authorization_fingerprint_sha256' IS DISTINCT FROM
          v_auth->>'fingerprint_sha256'
       OR v_repair->'scope' IS DISTINCT FROM p_handoff->'scope'
       OR coalesce((v_repair->>'readback_required')::boolean,false) IS NOT TRUE
       OR coalesce((v_repair->>'rollback_required')::boolean,false) IS NOT TRUE
       OR coalesce((v_repair->>'promotion_allowed')::boolean,true) IS NOT FALSE
       OR coalesce((v_repair->>'automatic_impact')::boolean,true) IS NOT FALSE
       OR coalesce((v_repair->>'direct_profile_invocation_allowed')::boolean,true) IS NOT FALSE
       OR coalesce((v_repair->>'return_to_router_after_result')::boolean,false) IS NOT TRUE
    THEN
      RETURN jsonb_build_object(
        'valid',false,'code','PROFILE_HANDOFF_REPAIR_AUTHORITY_INVALID'
      );
    END IF;

    v_repair_core:=v_repair-'fingerprint_sha256';
    v_expected_repair_fp:=encode(
      extensions.digest(convert_to(v_repair_core::text,'UTF8'),'sha256'),
      'hex'
    );

    IF coalesce(v_repair->>'fingerprint_sha256','') !~ '^[0-9a-f]{64}$'
       OR v_repair->>'fingerprint_sha256' IS DISTINCT FROM v_expected_repair_fp
    THEN
      RETURN jsonb_build_object(
        'valid',false,'code','PROFILE_HANDOFF_REPAIR_AUTHORITY_FINGERPRINT_INVALID'
      );
    END IF;
  ELSE
    IF v_repair IS NOT NULL AND jsonb_typeof(v_repair)<>'null' THEN
      RETURN jsonb_build_object(
        'valid',false,'code','PROFILE_HANDOFF_UNAUTHORIZED_REPAIR_AUTHORITY_PRESENT'
      );
    END IF;
  END IF;

  v_current_md5:=md5(pg_get_functiondef(
    'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
  ));

  IF p_handoff->>'router_source_md5' IS DISTINCT FROM v_current_md5
     OR v_auth->>'router_source_md5' IS DISTINCT FROM v_current_md5
  THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','PROFILE_HANDOFF_ROUTER_SOURCE_STALE',
      'receipt_router_source_md5',v_auth->>'router_source_md5',
      'current_router_source_md5',v_current_md5
    );
  END IF;

  v_current_operation_revision:=
    public.lf_operation_revision_sha256_v1('EJECUCION_PERFIL_LF');

  IF p_handoff->>'operation_revision_sha256'
       IS DISTINCT FROM v_current_operation_revision
     OR v_auth->>'operation_revision_sha256'
       IS DISTINCT FROM v_current_operation_revision
  THEN
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
    'router_authorization_fingerprint_sha256',
      v_auth->>'fingerprint_sha256',
    'fingerprint_sha256',p_handoff->>'fingerprint_sha256',
    'router_reentered',false,
    'governed_repair_write_allowed',v_repair_expected,
    'repair_execution_authority_fingerprint_sha256',
      case when v_repair_expected then v_repair->>'fingerprint_sha256' else null end
  );
END
$function$;


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
AS $function$
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
  v_repair_write boolean:=false;
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

  v_admission:=public.lf_profile_execution_executor_admission_v1(
    v_profile,v_mode
  );

  IF coalesce((v_admission->>'admitted')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_EXECUTOR_NOT_ADMITTED',
      'executor_admission',v_admission
    );
  END IF;

  v_repair_write:=coalesce(
    (v_valid->>'governed_repair_write_allowed')::boolean,
    false
  );

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
        'router_authority_receipt',
          p_handoff->'router_authorization_receipt',
        'repair_execution_authority',
          p_handoff->'repair_execution_authority',
        'input_sha256','sha256:'||(p_handoff->>'request_sha256'),
        'read_only',not v_repair_write,
        'no_write',not v_repair_write,
        'governed_repair_write',v_repair_write,
        'readback_required',v_repair_write,
        'rollback_required',v_repair_write,
        'no_promotion',true,
        'automatic_impact',false
      )
  );

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='router';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'router',
      'router-authorization://'
        ||(p_handoff#>>'{router_authorization_receipt,fingerprint_sha256}'),
      jsonb_build_object(
        'router_read','AUTHORIZED_HANDOFF_RECEIPT_VALIDATED',
        'action','PROFILE_EXECUTION',
        'router_authorization_receipt',
          p_handoff->'router_authorization_receipt',
        'repair_execution_authority',
          p_handoff->'repair_execution_authority',
        'governed_repair_write',v_repair_write,
        'semantic_request',p_handoff->'semantic_request',
        'semantic_result',p_handoff->'semantic_result',
        'handoff_fingerprint_sha256',
          p_handoff->>'fingerprint_sha256',
        'channel',p_handoff->>'channel',
        'business',p_handoff->>'business',
        'reentered_router',false
      ),
      p_actor_execution_id
    );
  ELSE
    v_step:=jsonb_build_object(
      'outcome','STEP_ALREADY_PRESENT',
      'status',v_existing
    );
  END IF;

  RETURN v_begin||jsonb_build_object(
    'status','READY',
    'router_handoff_validated',true,
    'router_authorization_carried_forward',true,
    'governed_repair_write',v_repair_write,
    'repair_execution_authority',
      p_handoff->'repair_execution_authority',
    'router_step',v_step,
    'next_step','profile_resolve',
    'reentered_router',false
  );
END
$function$;


CREATE OR REPLACE FUNCTION public.lf_profile_execution_scope_authority_packet_v1(
  p_execution_id text,
  p_input_literal text,
  p_input_source_ref text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  reqs jsonb := '[]'::jsonb;
  constraints_json jsonb := '[]'::jsonb;
  forbidden_json jsonb := '[]'::jsonb;
  packet_body jsonb;
  packet jsonb;
  digest_value text;
  execution_ref text;
  v_repair_write boolean:=false;
  v_repair_auth jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_input_literal,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_input_source_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_PACKET_INPUT_INVALID');
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND OR e.operation_code<>'EJECUCION_PERFIL_LF' OR e.target_type<>'PERFIL' THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_EXECUTION_INVALID');
  END IF;

  IF e.manifest ? 'input_sha256' THEN
    IF e.manifest->>'input_sha256' IS DISTINCT FROM
       'sha256:'||encode(
         extensions.digest(convert_to(p_input_literal,'UTF8'),'sha256'),'hex')
    THEN
      RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_INPUT_DIGEST_MISMATCH');
    END IF;
  END IF;

  IF e.manifest ? 'queue_request_id' THEN
    IF nullif(e.manifest->>'queue_request_id','') IS NULL
       OR nullif(e.manifest->>'input_sha256','') IS NULL
    THEN
      RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_QUEUE_BINDING_INCOMPLETE');
    END IF;

    IF p_input_source_ref IS DISTINCT FROM
       'queue://private.lf_profile_runtime_queue_v1/'||
       (e.manifest->>'queue_request_id')||'@'||(e.manifest->>'input_sha256')
    THEN
      RETURN jsonb_build_object('status','BLOCKED','code','SCOPE_AUTHORITY_QUEUE_SOURCE_MISMATCH');
    END IF;
  END IF;

  v_repair_write:=coalesce((e.manifest->>'governed_repair_write')::boolean,false);
  v_repair_auth:=e.manifest->'repair_execution_authority';

  IF v_repair_write THEN
    IF e.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       OR jsonb_typeof(v_repair_auth)<>'object'
       OR v_repair_auth->>'schema_version'<>'LF_SRCR_REPAIR_EXECUTION_AUTHORITY_V1'
       OR v_repair_auth->>'mode'<>'GOVERNED_REPAIR_WRITE'
       OR v_repair_auth->>'profile_task_intent'<>'REPAIR_MISSING_PRODUCT_STRUCTURE'
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED','code','SCOPE_AUTHORITY_GOVERNED_REPAIR_INVALID'
      );
    END IF;
  END IF;

  execution_ref:='supabase://public.lf_operation_execution/'||p_execution_id||'#manifest';
  reqs:=jsonb_build_array(jsonb_build_object(
    'id','REQ-INPUT-LITERAL',
    'statement',p_input_literal,
    'source_ref',p_input_source_ref,
    'materiality','MATERIAL'
  ));

  constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
    'id','CON-TARGET-EXACT',
    'statement','Execution target must remain exact: '||e.target_type||'/'||e.target_code||'.',
    'source_ref',execution_ref,
    'materiality','BLOCKING'
  ));

  IF coalesce((e.manifest->>'read_only')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-READ-ONLY','statement','Execution is read-only.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF coalesce((e.manifest->>'no_write')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-NO-WRITE','statement','No operational write is authorized.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
    forbidden_json:=forbidden_json||jsonb_build_array(jsonb_build_object(
      'id','FORBID-WRITE','statement','Do not perform operational mutation.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF v_repair_write THEN
    constraints_json:=constraints_json||jsonb_build_array(
      jsonb_build_object(
        'id','CON-GOVERNED-REPAIR-WRITE',
        'statement','Only the minimum sufficient in-scope repair is authorized; post-write readback and rollback evidence are mandatory.',
        'source_ref','router-repair-authority://'||(v_repair_auth->>'fingerprint_sha256'),
        'materiality','BLOCKING'
      ),
      jsonb_build_object(
        'id','CON-REPAIR-SCOPE-EXACT',
        'statement','Repair scope is exactly the Router-carried scope and may not be widened.',
        'source_ref',execution_ref,
        'materiality','BLOCKING'
      )
    );
    forbidden_json:=forbidden_json||jsonb_build_array(
      jsonb_build_object(
        'id','FORBID-OUT-OF-SCOPE-REPAIR',
        'statement','Do not mutate unrelated assets or semantics outside the carried repair scope.',
        'source_ref',execution_ref,
        'materiality','BLOCKING'
      ),
      jsonb_build_object(
        'id','FORBID-DIRECT-PROFILE-INVOKE',
        'statement','After repair, return to Router; do not invoke another profile directly.',
        'source_ref',execution_ref,
        'materiality','BLOCKING'
      )
    );
  END IF;

  IF coalesce((e.manifest->>'no_promotion')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-NO-PROMOTION','statement','No promotion is authorized.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
    forbidden_json:=forbidden_json||jsonb_build_array(jsonb_build_object(
      'id','FORBID-PROMOTION','statement','Do not promote or activate the target.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF coalesce((e.manifest->>'automatic_impact')::boolean,false)=false THEN
    forbidden_json:=forbidden_json||jsonb_build_array(jsonb_build_object(
      'id','FORBID-AUTOMATIC-IMPACT',
      'statement','Do not introduce unrequested automatic impact outside the explicit repair.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF coalesce((e.manifest->>'prior_output_reuse_forbidden')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-NO-PRIOR-OUTPUT-REUSE','statement','Prior candidate/output reuse is forbidden.',
      'source_ref',execution_ref,'materiality','BLOCKING'
    ));
  END IF;

  IF coalesce((e.manifest->>'blind_holdout_required')::boolean,false) THEN
    constraints_json:=constraints_json||jsonb_build_array(jsonb_build_object(
      'id','CON-BLIND-HOLDOUT','statement','Blind holdout separation must be preserved.',
      'source_ref',execution_ref,'materiality','MATERIAL'
    ));
  END IF;

  packet_body:=jsonb_build_object(
    'packet_version','LF_SCOPE_AUTHORITY_PACKET_V1',
    'execution_id',p_execution_id,
    'subject_ref',execution_ref,
    'authorized_requirements',reqs,
    'constraints',constraints_json,
    'forbidden_changes',forbidden_json,
    'repair_execution_authority',
      case when v_repair_write then v_repair_auth else null end,
    'authority_precedence',jsonb_build_array(
      jsonb_build_object(
        'rank',1,'source_ref',execution_ref,
        'reason','Exact execution manifest and literal request define authorized scope.'
      ),
      jsonb_build_object(
        'rank',2,
        'source_ref','supabase://public.v_lf_operation_policy_snapshot/EJECUCION_PERFIL_LF',
        'reason','Canonical operation policies constrain execution behavior.'
      )
    ),
    'related_context_refs','[]'::jsonb,
    'source_refs',jsonb_build_array(
      execution_ref,
      p_input_source_ref,
      'supabase://public.v_lf_operation_policy_snapshot/EJECUCION_PERFIL_LF'
    ),
    'compiled_at',to_jsonb(e.started_at),
    'canonicalization_rule','POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
  );

  digest_value:='sha256:'||
    encode(extensions.digest(convert_to(packet_body::text,'UTF8'),'sha256'),'hex');
  packet:=packet_body||jsonb_build_object('sha256',digest_value);

  RETURN jsonb_build_object(
    'status','READY',
    'scope_authority_packet',packet,
    'scope_packet_sha256',digest_value,
    'canonicalization_rule','POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
  );
END
$function$;


CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(
  p_execution_id text,
  p_source_revision text,
  p_source_digest text,
  p_actor_execution_id text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_handoff jsonb;
  v_valid jsonb;
  v_actor text;
  v_slug text;
  v_source_ref text;
  v_existing text;
  v_step jsonb;
  v_input jsonb;
  v_base_context jsonb;
  v_context jsonb;
  v_baseline jsonb;
  v_clean integer;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR coalesce(p_source_revision,'') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_source_digest,'') !~ '^sha256:[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_SOURCE_BINDING_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTION_INVALID'
    );
  END IF;

  v_handoff:=e.manifest->'router_profile_handoff';
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    v_handoff,
    v_handoff->>'literal_request',
    e.target_code
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  SELECT metadata->>'profile_slug' INTO v_slug
  FROM public.lf_activos
  WHERE codigo_activo=e.target_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL;

  IF nullif(v_slug,'') IS NULL
     OR nullif(e.target_repo,'') IS NULL
     OR nullif(e.target_path,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_UNRESOLVED'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_source_ref:='github://'||e.target_repo||'@'||p_source_revision||'/'||e.target_path;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_resolve';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_resolve',
      'supabase://public.lf_activos/'||e.target_code,
      jsonb_build_object(
        'exact_profile_resolved',true,
        'codigo_activo',e.target_code,
        'profile_slug',v_slug
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_RESOLVE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_source_read';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_source_read',
      v_source_ref,
      jsonb_build_object(
        'profile_source_ref',v_source_ref,
        'source_revision',p_source_revision,
        'profile_source_digest',p_source_digest,
        'profile_source_path',e.target_path
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input IS NULL THEN
    v_input:=public.lf_profile_execution_input_validate_v1(
      p_execution_id,
      v_handoff->>'literal_request',
      v_source_ref,
      v_handoff
    );

    IF v_input->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status',coalesce(v_input->>'status','BLOCKED'),
        'blocking_code',coalesce(
          v_input->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_VALIDATE_NOT_READY'
        ),
        'execution_id',p_execution_id,
        'input_validate',v_input,
        'router_reentry_required',false
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'input_validate',
      'supabase://public.lf_profile_execution_input_validate_v1/'||p_execution_id,
      v_input,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context IS NULL THEN
    v_base_context:=public.lf_profile_execution_context_admission_v1(p_execution_id);
    IF v_base_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_base_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_BASE_CONTEXT_NOT_READY'
        ),
        'base_context',v_base_context
      );
    END IF;

    v_context:=public.lf_profile_execution_channel_context_v1(
      p_execution_id,
      v_base_context,
      v_handoff
    );
    IF v_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_NOT_READY'
        ),
        'channel_context',v_context
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'context_admission',
      v_context->>'context_receipt_ref',
      v_context,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_baseline IS NULL THEN
    v_baseline:=public.lf_profile_execution_research_baseline_v1(
      p_execution_id,
      NULL,
      v_actor
    );
    IF coalesce(v_baseline->>'outcome','') NOT IN (
         'STEP_RECORDED',
         'STEP_ALREADY_RECORDED'
       )
       AND NOT EXISTS(
         SELECT 1
         FROM public.lf_operation_execution_steps
         WHERE execution_id=p_execution_id
           AND step_id='research_baseline_freeze'
           AND status='STEP_PASS_WITH_EVIDENCE'
       ) THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_BASELINE_NOT_READY',
        'baseline_result',v_baseline
      );
    END IF;

    SELECT evidence_payload INTO v_baseline
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id
      AND step_id='research_baseline_freeze'
      AND status='STEP_PASS_WITH_EVIDENCE';
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>7 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',7
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_MODEL_INPUT_READY',
    'execution_id',p_execution_id,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',e.target_code,
    'profile_slug',v_slug,
    'profile_source_ref',v_source_ref,
    'profile_source_digest',p_source_digest,
    'literal_request',v_handoff->>'literal_request',
    'input_governance',v_input->'input_governance',
    'context_receipt_ref',v_context->>'context_receipt_ref',
    'context_receipt_digest',v_context->>'context_receipt_digest',
    'context_capsule',v_context->'context_capsule',
    'research_baseline',v_baseline,
    'repair_execution_authority',
      e.manifest->'repair_execution_authority',
    'execution_write_mode',
      case
        when coalesce((e.manifest->>'governed_repair_write')::boolean,false)
          then 'GOVERNED_REPAIR_WRITE'
        else 'READ_ONLY'
      end,
    'clean_step_count',v_clean,
    'next_step','execute_profile',
    'next_action','EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT',
    'semantic_judge_after_output','INDEPENDENT_CONTEXT_REQUIRED',
    'router_reentry_required',false
  );
END
$function$;


SELECT public.lf_profile_selector_descriptor_sync_v1(
  'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
  jsonb_build_object(
    'schema_version','LF_PROFILE_SELECTION_DESCRIPTOR_V1',
    'description',
      'Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and produce the minimum sufficient repair that eliminates the failure class. By default the profile is read-only. When the Router-selected execution carries a valid governed repair authority for an explicitly allowed repair intent, it may implement the minimum sufficient in-scope repair, perform deterministic readback and return control to the Router. It never self-authorizes writes, broadens scope or promotes/activates the repaired asset.',
    'selection_evidence',jsonb_build_array(
      jsonb_build_object(
        'kind','PURPOSE',
        'source_section','Purpose',
        'value',
          'Resolve recurrent or architecturally material incidents with evidence-grounded systemic root-cause reasoning and produce the minimum sufficient, implementable repair specification that eliminates the failure class rather than the first plausible local fix. By default it remains read-only; with valid repair_execution_authority it may implement the minimum sufficient repair, read it back and return to Router.'
      ),
      jsonb_build_object(
        'kind','ACTIVATION',
        'source_section','Activation',
        'value',
          'Use for recurrent failures, repeated local repairs, cross-run regressions, stale-state or authority contradictions, architecture/lifecycle audits, and bounded structural repair requests whose immediate local fix is insufficient to eliminate the failure class.'
      ),
      jsonb_build_object(
        'kind','BOUNDARY',
        'source_section','Governed repair execution (V0.7R1 bounded extension)',
        'value',
          'READ_ONLY by default. Governed writes require LF_SRCR_REPAIR_EXECUTION_AUTHORITY_V1, exact Router scope, allowed intent REPAIR_MISSING_PRODUCT_STRUCTURE, mandatory readback/rollback, no promotion, no automatic scope expansion and return to Router after the repair.'
      )
    )
  ),
  'GITHUB_SKILL',
  'github://cristhianlujan/claude-persona-lf-patch@4a4e090abde9a4066c212e58953c2fd529060bca/profiles/systemic_root_cause_repair_lf/SKILL.md',
  '35bbadad5c76b7a4b42b695f01beefa30cd8f272',
  'SRCR-GOVERNED-REPAIR-WRITE-V1'
);


DO $postcheck$
DECLARE
  s jsonb;
  r jsonb;
  sel jsonb;
  a jsonb;
  d jsonb;
  h jsonb;
  hv jsonb;
  s_ro jsonb;
  r_ro jsonb;
  sel_ro jsonb;
  a_ro jsonb;
  d_ro jsonb;
  h_ro jsonb;
  hv_ro jsonb;
  reg public.lf_profile_selection_registry_v1%rowtype;
  src_begin text;
  src_scope text;
  src_bridge text;
BEGIN
  s:=jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original',
      'Reparar la estructura faltante de cancelación en B2B-CARGA-002 sin cambiar permisos ni transiciones.',
    'downstream_execution_allowed',false,
    'es_operacion',true,
    'ambiguo',false,
    'respuesta_directa',false,
    'sujeto','B2B-CARGA-002 estructura de cancelación',
    'accion','REPAIR_MISSING_PRODUCT_STRUCTURE',
    'formas_busqueda',jsonb_build_array(
      'B2B_CARGA002_CANCEL_ACTION',
      'PENDING_SEMANTIC_COMPONENT',
      'requires_comment'
    ),
    'alternativas','[]'::jsonb,
    'pregunta_usuario',null,
    'capability_hint',null,
    'correcciones','[]'::jsonb,
    'canal_candidato','PRODUCTO',
    'negocio_codigo','LF',
    'negocios_afectados','[]'::jsonb,
    'ruta_transversal',null,
    'razon_seleccion','Reparación estructural requerida por definición de producto.',
    'alcance',jsonb_build_object(
      'target_type','PANTALLA',
      'target_hint','B2B-CARGA-002',
      'resolution_status','UNRESOLVED'
    )
  );

  IF coalesce((public.lf_router_stage1_validate_v2(s)->>'valid')::boolean,false)
     IS NOT TRUE THEN
    RAISE EXCEPTION 'SRCR_GOVERNED_WRITE_STAGE1_INVALID:%',
      public.lf_router_stage1_validate_v2(s);
  END IF;

  r:=public.lf_router_route_v1(s);

  sel:=public.lf_profile_selector_semantic_finalize_v1(
    r->'profile_selection_request',
    jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Structural repair request matches systemic repair activation.',
      'evidence_refs',jsonb_build_array(jsonb_build_object(
        'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
        'kind','ACTIVATION',
        'source_section','Activation'
      )),
      'material_ambiguities','[]'::jsonb
    )
  );

  IF sel->>'status'<>'VALID' THEN
    RAISE EXCEPTION 'SRCR_GOVERNED_WRITE_SELECTION_INVALID:%',left(sel::text,1800);
  END IF;

  a:=public.lf_router_product_profile_after_selection_v1(s,sel->'result');
  d:=public.lf_router_product_gate2_result_from_selection_v1(
    a->'gate2_request',
    sel->'result'
  );
  h:=public.lf_router_profile_execution_handoff_v1(
    a->'gate2_request',
    d->'gate2_result',
    'PRODUCTO','LF',s->'alcance'
  );

  IF h->>'status'<>'READY'
     OR coalesce((h->>'governed_repair_write_allowed')::boolean,false) IS NOT TRUE
     OR h#>>'{handoff,repair_execution_authority,schema_version}'
          <>'LF_SRCR_REPAIR_EXECUTION_AUTHORITY_V1'
     OR h#>>'{handoff,repair_execution_authority,mode}'
          <>'GOVERNED_REPAIR_WRITE'
     OR h#>>'{handoff,repair_execution_authority,profile_task_intent}'
          <>'REPAIR_MISSING_PRODUCT_STRUCTURE'
     OR coalesce(
          (h#>>'{handoff,repair_execution_authority,promotion_allowed}')::boolean,
          true
        )
     OR coalesce(
          (h#>>'{handoff,repair_execution_authority,readback_required}')::boolean,
          false
        ) IS NOT TRUE
     OR coalesce(
          (h#>>'{handoff,repair_execution_authority,rollback_required}')::boolean,
          false
        ) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'SRCR_GOVERNED_WRITE_HANDOFF_INVALID:%',left(h::text,2200);
  END IF;

  hv:=public.lf_router_profile_execution_handoff_validate_v1(
    h->'handoff',
    s->>'texto_original',
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
  );

  IF coalesce((hv->>'valid')::boolean,false) IS NOT TRUE
     OR coalesce((hv->>'governed_repair_write_allowed')::boolean,false) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'SRCR_GOVERNED_WRITE_VALIDATION_INVALID:%',left(hv::text,1800);
  END IF;

  s_ro:=jsonb_set(s,'{accion}',to_jsonb('ARCHITECTURE_AUDIT'::text),false);
  s_ro:=jsonb_set(
    s_ro,
    '{texto_original}',
    to_jsonb('Auditar la arquitectura de cancelación de B2B-CARGA-002 sin ejecutar cambios.'::text),
    false
  );
  s_ro:=jsonb_set(
    s_ro,
    '{razon_seleccion}',
    to_jsonb('Auditoría estructural sin autorización de escritura.'::text),
    false
  );

  r_ro:=public.lf_router_route_v1(s_ro);
  sel_ro:=public.lf_profile_selector_semantic_finalize_v1(
    r_ro->'profile_selection_request',
    jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Architecture audit matches systemic repair profile.',
      'evidence_refs',jsonb_build_array(jsonb_build_object(
        'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
        'kind','ACTIVATION',
        'source_section','Activation'
      )),
      'material_ambiguities','[]'::jsonb
    )
  );
  a_ro:=public.lf_router_product_profile_after_selection_v1(s_ro,sel_ro->'result');
  d_ro:=public.lf_router_product_gate2_result_from_selection_v1(
    a_ro->'gate2_request',
    sel_ro->'result'
  );
  h_ro:=public.lf_router_profile_execution_handoff_v1(
    a_ro->'gate2_request',
    d_ro->'gate2_result',
    'PRODUCTO','LF',s_ro->'alcance'
  );
  hv_ro:=public.lf_router_profile_execution_handoff_validate_v1(
    h_ro->'handoff',
    s_ro->>'texto_original',
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
  );

  IF h_ro->>'status'<>'READY'
     OR coalesce((h_ro->>'governed_repair_write_allowed')::boolean,true) IS NOT FALSE
     OR h_ro#>'{handoff,repair_execution_authority}' IS DISTINCT FROM 'null'::jsonb
     OR coalesce((hv_ro->>'valid')::boolean,false) IS NOT TRUE
     OR coalesce((hv_ro->>'governed_repair_write_allowed')::boolean,true) IS NOT FALSE
  THEN
    RAISE EXCEPTION 'SRCR_READ_ONLY_DEFAULT_REGRESSION:%',left(h_ro::text,2200);
  END IF;

  SELECT * INTO reg
  FROM public.lf_profile_selection_registry_v1
  WHERE profile_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF';

  IF reg.descriptor_status<>'CURRENT'
     OR reg.source_revision<>'35bbadad5c76b7a4b42b695f01beefa30cd8f272'
     OR position('governed repair authority' in lower(reg.descriptor->>'description'))=0
  THEN
    RAISE EXCEPTION 'SRCR_SELECTOR_DESCRIPTOR_NOT_UPDATED:%',left(to_jsonb(reg)::text,1800);
  END IF;

  src_begin:=pg_get_functiondef(
    'public.lf_profile_execution_begin_from_handoff_v1(jsonb,text,text,text,text,text,text,jsonb)'::regprocedure
  );
  src_scope:=pg_get_functiondef(
    'public.lf_profile_execution_scope_authority_packet_v1(text,text,text)'::regprocedure
  );
  src_bridge:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  IF position('governed_repair_write' in src_begin)=0
     OR position('''read_only'',not v_repair_write' in src_begin)=0
     OR position('''no_write'',not v_repair_write' in src_begin)=0
     OR position('CON-GOVERNED-REPAIR-WRITE' in src_scope)=0
     OR position('FORBID-OUT-OF-SCOPE-REPAIR' in src_scope)=0
     OR position('repair_execution_authority' in src_bridge)=0
  THEN
    RAISE EXCEPTION 'SRCR_GOVERNED_WRITE_RUNTIME_SOURCE_INCOMPLETE';
  END IF;
END
$postcheck$;

COMMIT;
