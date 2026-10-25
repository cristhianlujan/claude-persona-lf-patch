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
    extensions.digest(
      convert_to(v_auth_core::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_auth_receipt:=v_auth_core||jsonb_build_object(
    'fingerprint_sha256',v_auth_fp
  );

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
    'router_reentered',false
  );
END
$function$;

COMMENT ON FUNCTION public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb) IS
'Builds the authorized profile-execution handoff directly from the ACT-0001 action binding plus validated Gate2 result. No Router re-entry occurs before execution.';

REVOKE ALL ON FUNCTION public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)
  TO service_role, supabase_read_only_user;


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
    RETURN jsonb_build_object(
      'valid',false,
      'code','PROFILE_HANDOFF_SHAPE_INVALID'
    );
  END IF;

  IF p_handoff ? 'router_result' THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','PROFILE_HANDOFF_LEGACY_ROUTER_RESULT_FORBIDDEN'
    );
  END IF;

  IF p_literal_request IS NOT NULL
     AND p_handoff->>'literal_request' IS DISTINCT FROM p_literal_request THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','PROFILE_HANDOFF_LITERAL_MISMATCH'
    );
  END IF;

  IF p_profile_code IS NOT NULL
     AND p_handoff->>'profile_code' IS DISTINCT FROM p_profile_code THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','PROFILE_HANDOFF_PROFILE_MISMATCH'
    );
  END IF;

  IF encode(
       extensions.digest(
         convert_to(coalesce(p_handoff->>'literal_request',''),'UTF8'),
         'sha256'
       ),
       'hex'
     ) IS DISTINCT FROM p_handoff->>'request_sha256'
  THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','PROFILE_HANDOFF_REQUEST_SHA_INVALID'
    );
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
      'valid',false,
      'code','PROFILE_HANDOFF_FINGERPRINT_INVALID'
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
      'valid',false,
      'code','PROFILE_HANDOFF_PROFILE_CURRENTNESS_INVALID'
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
      'valid',false,
      'code','PROFILE_HANDOFF_ROUTER_AUTHORIZATION_IDENTITY_INVALID'
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
      'valid',false,
      'code','PROFILE_HANDOFF_ROUTER_AUTHORIZATION_FINGERPRINT_INVALID'
    );
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
      'valid',false,
      'code','PROFILE_HANDOFF_OPERATION_REVISION_STALE'
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
    'router_reentered',false
  );
END
$function$;

COMMENT ON FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text) IS
'Validates the carried ACT-0001 profile authorization plus Gate2 receipt without re-entering the Router.';

REVOKE ALL ON FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
  TO service_role, supabase_read_only_user;


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
        'input_sha256','sha256:'||(p_handoff->>'request_sha256'),
        'read_only',true,
        'no_write',true,
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
    'router_step',v_step,
    'next_step','profile_resolve',
    'reentered_router',false
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_execution_begin_from_handoff_v1(jsonb,text,text,text,text,text,text,jsonb) IS
'Begins governed profile execution from a validated carried-forward Router authorization receipt; it does not re-enter ACT-0001.';

REVOKE ALL ON FUNCTION public.lf_profile_execution_begin_from_handoff_v1(jsonb,text,text,text,text,text,text,jsonb)
  FROM PUBLIC, anon, authenticated, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_begin_from_handoff_v1(jsonb,text,text,text,text,text,text,jsonb)
  TO service_role;


DO $postcheck$
DECLARE
  s jsonb;
  r jsonb;
  q jsonb;
  f jsonb;
  a jsonb;
  d jsonb;
  h jsonb;
  hv jsonb;
  src_h text;
  src_v text;
  src_b text;
BEGIN
  s:=jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original','Dame las reglas en el login B2B',
    'downstream_execution_allowed',false,
    'es_operacion',true,
    'ambiguo',false,
    'respuesta_directa',false,
    'sujeto','login B2B',
    'accion','READ_PRODUCT_DEFINITION',
    'formas_busqueda',jsonb_build_array(
      'login B2B','reglas login B2B'
    ),
    'alternativas','[]'::jsonb,
    'pregunta_usuario',null,
    'capability_hint',null,
    'correcciones','[]'::jsonb,
    'canal_candidato','PRODUCTO',
    'negocio_codigo','LF',
    'negocios_afectados','[]'::jsonb,
    'ruta_transversal',null,
    'razon_seleccion','Consulta funcional de reglas de producto.',
    'alcance',jsonb_build_object(
      'target_type','PANTALLA',
      'target_hint','B2B-AUTH-001',
      'resolution_status','UNRESOLVED'
    )
  );

  r:=public.lf_router_route_v1(s);
  q:=r->'profile_selection_request';

  f:=public.lf_profile_selector_semantic_finalize_v1(
    q,
    jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Functional product rules request matches the Product Director purpose.',
      'evidence_refs',jsonb_build_array(jsonb_build_object(
        'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
        'kind','PURPOSE',
        'source_section','Purpose'
      )),
      'material_ambiguities','[]'::jsonb
    )
  );

  a:=public.lf_router_product_profile_after_selection_v1(
    s,f->'result'
  );

  d:=public.lf_router_product_gate2_result_from_selection_v1(
    a->'gate2_request',
    f->'result'
  );

  h:=public.lf_router_profile_execution_handoff_v1(
    a->'gate2_request',
    d->'gate2_result',
    'PRODUCTO',
    'LF',
    s->'alcance'
  );

  IF h->>'status'<>'READY'
     OR h#>>'{handoff,profile_code}'
          <>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR h#>>'{handoff,operation_code}'
          <>'EJECUCION_PERFIL_LF'
     OR h#>>'{handoff,router_authorization_receipt,schema_version}'
          <>'LF_ROUTER_PROFILE_AUTHORIZATION_RECEIPT_V1'
     OR h#>>'{handoff,router_authorization_receipt,action_code}'
          <>'PROFILE_EXECUTION'
     OR h#>>'{handoff,router_authorization_receipt,operation_code}'
          <>'EJECUCION_PERFIL_LF'
     OR coalesce(
          (h#>>'{handoff,router_authorization_receipt,router_reentry_before_execution}')::boolean,
          true
        )
     OR h#>'{handoff}' ? 'router_result'
     OR coalesce((h->>'router_reentered')::boolean,true)
  THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_NO_REENTRY_BUILD_FAILED:%',
      left(h::text,2200);
  END IF;

  hv:=public.lf_router_profile_execution_handoff_validate_v1(
    h->'handoff',
    'Dame las reglas en el login B2B',
    'PERFIL-PRODUCT-DIRECTOR-LF'
  );

  IF coalesce((hv->>'valid')::boolean,false) IS NOT TRUE
     OR hv->>'code'<>'PROFILE_HANDOFF_VALID'
     OR coalesce((hv->>'router_reentered')::boolean,true)
  THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_NO_REENTRY_VALIDATE_FAILED:%',
      left(hv::text,1800);
  END IF;

  src_h:=pg_get_functiondef(
    'public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)'::regprocedure
  );
  src_v:=pg_get_functiondef(
    'public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)'::regprocedure
  );
  src_b:=pg_get_functiondef(
    'public.lf_profile_execution_begin_from_handoff_v1(jsonb,text,text,text,text,text,text,jsonb)'::regprocedure
  );

  IF position('v_resume:=public.lf_router_semantic_resume_route_v1' in src_h)>0
     OR position(':=public.lf_router_resolve_v1(' in src_h)>0
     OR position('p_handoff->''router_result''' in src_h)>0
     OR position('v_resume:=public.lf_router_semantic_resume_route_v1' in src_v)>0
     OR position('p_handoff->''router_result''' in src_v)>0
     OR position('p_handoff->''router_result''' in src_b)>0
  THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_ROUTER_REENTRY_SOURCE_REMAINS';
  END IF;

  IF position('router_authorization_receipt' in src_h)=0
     OR position('router_authorization_receipt' in src_v)=0
     OR position('router_authorization_receipt' in src_b)=0
     OR position('reentered_router'',false' in src_b)=0
  THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_AUTHORIZATION_CARRY_SOURCE_MISSING';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_execution_begin_from_handoff_v1(jsonb,text,text,text,text,text,text,jsonb)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_NO_REENTRY_ACL_FAILED';
  END IF;
END
$postcheck$;

COMMIT;
