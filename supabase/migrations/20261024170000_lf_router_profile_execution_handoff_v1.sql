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

-- UI / UX / Product profiles consume Input Governance directly.
-- Adapters may add context, but they are not the authority that decides whether IG applies.
DO $bind_profile_input_governance$
DECLARE
  v_profile text;
  v_batch uuid:=gen_random_uuid();
  v_profiles text[]:=ARRAY[
    'PERFIL-PRODUCT-DIRECTOR-LF',
    'PERFIL-UI-ARCHITECT',
    'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531',
    'PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING'
  ];
BEGIN
  FOREACH v_profile IN ARRAY v_profiles LOOP
    IF NOT EXISTS(
      SELECT 1 FROM public.lf_activos
      WHERE codigo_activo=v_profile
        AND tipo_activo='PERFIL'
        AND archived_at IS NULL
    ) THEN
      RAISE EXCEPTION 'PROFILE_INPUT_GOVERNANCE_PROFILE_NOT_FOUND:%',v_profile;
    END IF;

    UPDATE public.lf_activos
    SET metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'input_governance_binding_contract','INPUT_GOVERNANCE_EXECUTION_CONTRACT',
      'input_governance_consumer','CONTEXT_PACK',
      'input_governance_binding_mode','DIRECT_PROFILE',
      'input_governance_router_reentry_required',false
    )
    WHERE codigo_activo=v_profile
      AND tipo_activo='PERFIL'
      AND archived_at IS NULL;

    INSERT INTO public.lf_activo_relaciones(
      codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
      migration_batch_id,created_by_execution_id
    )
    SELECT
      v_profile,
      'INPUT_GOVERNANCE_EXECUTION_CONTRACT',
      'GOBERNADO_POR',
      'DIRECT_PROFILE_INPUT_GOVERNANCE;consumer=CONTEXT_PACK;router_reentry_required=false',
      'ROUTER_PROFILE_EXECUTION_HANDOFF_V1',
      v_batch,
      'ROUTER_PROFILE_EXECUTION_HANDOFF_V1'
    WHERE NOT EXISTS(
      SELECT 1 FROM public.lf_activo_relaciones
      WHERE codigo_activo=v_profile
        AND relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        AND relacion_tipo='GOBERNADO_POR'
    );
  END LOOP;
END
$bind_profile_input_governance$;

CREATE OR REPLACE FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(
  p_request_text text,
  p_profile_code text,
  p_scope jsonb DEFAULT NULL,
  p_consumer text DEFAULT 'CONTEXT_PACK'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE
  v_bound boolean:=false;
  v_screen_count integer:=0;
  v_pantalla_id integer;
  v_screen_code text;
  v_target_hint text:=nullif(btrim(coalesce(p_scope->>'target_hint','')),'');
  v_req text;
  v_result jsonb;
  v_worker jsonb;
BEGIN
  SELECT EXISTS(
    SELECT 1
    FROM public.lf_activo_relaciones r
    JOIN public.lf_activos a
      ON a.codigo_activo=r.codigo_activo
     AND a.archived_at IS NULL
     AND a.tipo_activo='PERFIL'
    WHERE r.codigo_activo=p_profile_code
      AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND r.relacion_tipo='GOBERNADO_POR'
      AND a.metadata->>'input_governance_binding_mode'='DIRECT_PROFILE'
      AND a.metadata->>'input_governance_consumer'=p_consumer
  ) INTO v_bound;

  IF NOT v_bound THEN
    RETURN jsonb_build_object(
      'applicable',false,
      'status','NOT_REQUIRED',
      'decision','N/A',
      'continuation_allowed',true,
      'profile_code',p_profile_code,
      'binding_mode','NO_DIRECT_PROFILE_BINDING',
      'router_reentry_required',false
    );
  END IF;

  IF v_target_hint IS NOT NULL THEN
    SELECT count(*),min(id),min(codigo)
      INTO v_screen_count,v_pantalla_id,v_screen_code
    FROM lf_ops.pantallas
    WHERE activa
      AND (
        upper(codigo)=upper(v_target_hint)
        OR upper(nombre)=upper(v_target_hint)
      );
  END IF;

  IF v_screen_count=0 THEN
    v_req:=' '||btrim(regexp_replace(lower(coalesce(p_request_text,'')),'[^a-z0-9_]+',' ','g'))||' ';
    SELECT count(*),min(id),min(codigo)
      INTO v_screen_count,v_pantalla_id,v_screen_code
    FROM lf_ops.pantallas
    WHERE activa
      AND strpos(
        v_req,
        ' '||btrim(regexp_replace(lower(codigo),'[^a-z0-9_]+',' ','g'))||' '
      )>0;
  END IF;

  IF v_screen_count=0 THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','INPUT_GOVERNANCE_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED',
      'decision','PENDING',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_screen_count>1 THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS',
      'decision','BLOCKED',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  v_result:=public.fn_input_governance_execute(v_pantalla_id,p_consumer);

  IF v_result->>'status'='READY' THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','READY',
      'blocking_code',null,
      'decision','PASS',
      'continuation_allowed',true,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'run_id',v_result->'run_id',
      'governance_output_sha256',v_result->'output_sha256',
      'context_manifest',v_result->'context_manifest',
      'governance_result',v_result,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_result->>'status' IN ('CURATOR_RUNTIME_REQUIRED','VALIDATOR_RUNTIME_REQUIRED') THEN
    v_worker:=coalesce(
      v_result->'worker_spec',
      public.fn_input_governance_worker_spec(v_pantalla_id,p_consumer)
    );
    RETURN jsonb_build_object(
      'applicable',true,
      'status','INPUT_GOVERNANCE_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_REQUIRED',
      'decision','PENDING',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'agent_status',v_result->>'status',
      'worker_spec',v_worker,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_result->>'status'='HUMAN_DECISION_REQUIRED' THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','HUMAN_DECISION_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',
      'decision','PARTIAL',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'governance_result',v_result,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  RETURN jsonb_build_object(
    'applicable',true,
    'status','BLOCKED',
    'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE',
    'decision','BLOCKED',
    'continuation_allowed',false,
    'profile_code',p_profile_code,
    'consumer',p_consumer,
    'binding_mode','DIRECT_PROFILE',
    'pantalla_id',v_pantalla_id,
    'screen_code',v_screen_code,
    'governance_result',v_result,
    'resume_via','EJECUCION_PERFIL_LF/input_validate',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1(
  p_execution_id text,
  p_input_literal text,
  p_input_source_ref text,
  p_handoff jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion'
AS $fn$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_handoff_validation jsonb;
  v_scope jsonb;
  v_adapters jsonb:='[]'::jsonb;
  v_ig jsonb;
  v_direct_profile_ig boolean:=false;
BEGIN
  SELECT * INTO v_exec
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR v_exec.operation_code<>'EJECUCION_PERFIL_LF'
     OR v_exec.target_type<>'PERFIL'
     OR v_exec.status<>'IN_PROGRESS' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_EXECUTION_INVALID',
      'router_reentry_required',false
    );
  END IF;

  v_handoff_validation:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,p_input_literal,v_exec.target_code
  );
  IF coalesce((v_handoff_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_HANDOFF_INVALID',
      'handoff_validation',v_handoff_validation,
      'router_reentry_required',false
    );
  END IF;

  v_scope:=public.lf_profile_execution_scope_authority_packet_v1(
    p_execution_id,p_input_literal,p_input_source_ref
  );
  IF v_scope->>'status' IS DISTINCT FROM 'READY'
     OR jsonb_typeof(v_scope->'scope_authority_packet')<>'object'
     OR nullif(v_scope->>'scope_packet_sha256','') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_SCOPE_NOT_READY',
      'scope_result',v_scope,
      'router_reentry_required',false
    );
  END IF;

  SELECT EXISTS(
    SELECT 1
    FROM public.lf_activo_relaciones r
    WHERE r.codigo_activo=v_exec.target_code
      AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND r.relacion_tipo='GOBERNADO_POR'
  ) INTO v_direct_profile_ig;

  IF v_direct_profile_ig THEN
    v_ig:=programacion.fn_lf_profile_input_governance_resolve_v1(
      p_input_literal,
      v_exec.target_code,
      p_handoff->'scope',
      'CONTEXT_PACK'
    );
  ELSE
    SELECT coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb)
      INTO v_adapters
    FROM public.v_lf_router_adapter_bindings x
    WHERE x.target_asset_code=v_exec.target_code;

    IF jsonb_array_length(v_adapters)>0 THEN
      v_ig:=programacion.fn_lf_router_input_governance_resolve_v1(
        p_input_literal,v_adapters,'CONTEXT_PACK'
      );
    ELSE
      v_ig:=jsonb_build_object(
        'applicable',false,
        'status','NOT_REQUIRED',
        'blocking_code',null,
        'decision','N/A',
        'continuation_allowed',true,
        'required_by_adapters','[]'::jsonb,
        'binding_mode','NONE'
      );
    END IF;
  END IF;

  IF coalesce((v_ig->>'applicable')::boolean,false)
     AND coalesce((v_ig->>'continuation_allowed')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status',coalesce(v_ig->>'status','BLOCKED'),
      'blocking_code',coalesce(v_ig->>'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_NOT_READY'),
      'input_governance',
        v_ig||jsonb_build_object(
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        ),
      'scope_authority_packet',v_scope->'scope_authority_packet',
      'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
      'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
      'router_reentry_required',false,
      'next_action','RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'
    );
  END IF;

  RETURN jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'server_validated',true,
    'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
    'activation_trigger_match',true,
    'scope_authority_packet',v_scope->'scope_authority_packet',
    'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
    'input_governance',
      coalesce(v_ig,'{}'::jsonb)||jsonb_build_object(
        'resume_via','EJECUCION_PERFIL_LF/input_validate',
        'router_reentry_required',false
      ),
    'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb) IS
'Canonical EJECUCION_PERFIL_LF input gate. Validates the traveling Router handoff, exact scope packet and Input Governance. Pending IG is retried at input_validate and never re-enters ACT-0001.';

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

CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_after_gate2_v1(
  p_request jsonb,
  p_result jsonb,
  p_channel text,
  p_business text,
  p_scope jsonb,
  p_executor_mode text,
  p_actor_execution_id text DEFAULT NULL,
  p_github_backup_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_built jsonb;
  v_handoff jsonb;
  v_mode text:=upper(nullif(btrim(coalesce(p_executor_mode,'')),''));
  v_profile text;
  v_slug text;
  v_path text;
  v_execution_id text;
  v_actor text;
  v_begin jsonb;
  v_remote jsonb;
BEGIN
  v_built:=public.lf_router_profile_execution_handoff_v1(
    p_request,p_result,p_channel,p_business,p_scope
  );
  IF v_built->>'status' IS DISTINCT FROM 'READY'
     OR jsonb_typeof(v_built->'handoff')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_GATE2_HANDOFF_NOT_READY',
      'handoff_result',v_built,
      'router_reentry_required',false
    );
  END IF;

  v_handoff:=v_built->'handoff';
  v_profile:=v_handoff->>'profile_code';

  IF v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_EXECUTOR_MODE_REQUIRED',
      'profile_code',v_profile,
      'allowed_executor_modes',jsonb_build_array('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API'),
      'router_reentry_required',false
    );
  END IF;

  IF v_mode='REMOTE_API' THEN
    v_remote:=programacion.fn_lf_profile_runtime_enqueue_authorized_v1(
      v_handoff,
      coalesce(nullif(btrim(p_actor_execution_id),''),'ACT-0001-GATE2'),
      p_github_backup_reason
    );
    RETURN v_remote||jsonb_build_object(
      'gate2_materialized',v_remote->>'status' IN ('PENDING','NATIVE_EXECUTOR_REQUIRED'),
      'router_profile_handoff',v_handoff,
      'router_reentry_required',false,
      'return_to_router_after_profile_result',true
    );
  END IF;

  SELECT a.metadata->>'profile_slug',
         coalesce(
           nullif(a.metadata->>'entrypoint_path',''),
           case
             when a.ruta_esperada like '%.md' then a.ruta_esperada
             when nullif(a.ruta_esperada,'') is not null
               then rtrim(a.ruta_esperada,'/')||'/SKILL.md'
             else null
           end
         )
    INTO v_slug,v_path
  FROM public.lf_activos a
  WHERE a.codigo_activo=v_profile
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
  LIMIT 1;

  IF nullif(v_slug,'') IS NULL OR nullif(v_path,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_GATE2_SOURCE_BINDING_UNRESOLVED',
      'profile_code',v_profile,
      'router_reentry_required',false
    );
  END IF;

  v_execution_id:='EXEC-PROFILE-GATE2-'||upper(substr(v_handoff->>'request_sha256',1,24));
  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),v_execution_id);

  v_begin:=public.lf_profile_execution_begin_from_handoff_v1(
    v_handoff,
    v_mode,
    v_execution_id,
    'router-profile-gate2:'||(v_handoff->>'request_sha256')||':'||v_profile,
    v_actor,
    'cristhianlujan/claude-persona-lf-patch',
    v_path,
    jsonb_build_object(
      'gate2_auto_materialized',true,
      'channel',p_channel,
      'business',p_business
    )
  );

  IF v_begin->>'status' IS DISTINCT FROM 'READY' THEN
    RETURN v_begin||jsonb_build_object(
      'router_profile_handoff',v_handoff,
      'router_reentry_required',false
    );
  END IF;

  RETURN v_begin||jsonb_build_object(
    'status','NATIVE_EXECUTION_READY',
    'gate2_materialized',true,
    'executor_mode',v_mode,
    'profile_code',v_profile,
    'profile_slug',v_slug,
    'profile_source_path',v_path,
    'router_profile_handoff',v_handoff,
    'next_action','EXECUTE_PROFILE_IN_AUTHORIZED_NATIVE_CONTEXT',
    'router_reentry_required',false,
    'return_to_router_after_profile_result',true
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_router_profile_execution_after_gate2_v1(
  jsonb,jsonb,text,text,jsonb,text,text,text
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_execution_after_gate2_v1(
  jsonb,jsonb,text,text,jsonb,text,text,text
) TO service_role;

COMMENT ON FUNCTION public.lf_router_profile_execution_after_gate2_v1(
  jsonb,jsonb,text,text,jsonb,text,text,text
) IS
'Consumes a resolved semantic Gate 2 once and materializes EJECUCION_PERFIL_LF. It never re-routes the same decision. Native modes begin the canonical operation; REMOTE_API uses the authorized queue only when admitted.';

-- For EJECUCION_PERFIL_LF, Input Governance is an internal input_validate gate.
-- ACT-0001 authorizes entry into the operation once; a pending IG receipt must not
-- force the same request through ACT-0001 again.
DO $patch_profile_ig_owner$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
     )) <> '5bbac630485dafb653cf67b78e0f2784' THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_ROUTER_RESOLVE_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef(
    'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
  );

  v_old:=E'    if coalesce((v_input_governance->>''applicable'')::boolean,false) then\n'
    ||E'      if not coalesce((v_input_governance->>''continuation_allowed'')::boolean,false) then\n'
    ||E'        return jsonb_build_object(\n';

  v_new:=E'    if coalesce((v_input_governance->>''applicable'')::boolean,false) then\n'
    ||E'      if v_operation.operation_code=''EJECUCION_PERFIL_LF''\n'
    ||E'         and v_input_governance->>''status''=''INPUT_GOVERNANCE_REQUIRED''\n'
    ||E'         and v_input_governance->>''decision''=''PENDING'' then\n'
    ||E'        v_input_governance:=v_input_governance||jsonb_build_object(\n'
    ||E'          ''execution_gate_owner'',''EJECUCION_PERFIL_LF/input_validate'',\n'
    ||E'          ''resume_via'',''EJECUCION_PERFIL_LF/input_validate'',\n'
    ||E'          ''router_reentry_required'',false\n'
    ||E'        );\n'
    ||E'      elsif not coalesce((v_input_governance->>''continuation_allowed'')::boolean,false) then\n'
    ||E'        return jsonb_build_object(\n';

  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_ROUTER_IG_BLOCK_ANCHOR_MISSING';
  END IF;

  v_def:=replace(v_def,v_old,v_new);
  EXECUTE v_def;
END
$patch_profile_ig_owner$;

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
    ||E'        ''gate2_pass_entrypoint'',''public.lf_router_profile_execution_after_gate2_v1'',\n'
    ||E'        ''siguiente_operacion'',jsonb_build_object(\n'
    ||E'          ''operation_code'',''EJECUCION_PERFIL_LF'',\n'
    ||E'          ''entrypoint'',''GATE2_AUTO_MATERIALIZER'',\n'
    ||E'          ''materializer'',''public.lf_router_profile_execution_after_gate2_v1'',\n'
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
SET resolver_ref='public.lf_profile_execution_input_validate_v1 + programacion.fn_lf_profile_input_governance_resolve_v1'
WHERE operation_code='EJECUCION_PERFIL_LF'
  AND step_id='input_validate';

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
     OR position('GATE2_AUTO_MATERIALIZER' in v_route_def)=0
     OR position('lf_router_profile_execution_after_gate2_v1' in v_route_def)=0
     OR position('lf_profile_execution_input_validate_v1' in pg_get_functiondef(
          'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
        ))=0
     OR position('EJECUCION_PERFIL_LF/input_validate' in pg_get_functiondef(
          'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
        ))=0
  THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_ROUTER_STILL_EXECUTES_PRODUCT_WORK';
  END IF;

  SELECT resolver_ref INTO v_context_ref
  FROM public.lf_operation_step_contracts
  WHERE operation_code='EJECUCION_PERFIL_LF' AND step_id='context_admission';

  IF position('lf_profile_execution_channel_context_v1' in coalesce(v_context_ref,''))=0 THEN
    RAISE EXCEPTION 'PROFILE_HANDOFF_CHANNEL_CONTEXT_NOT_BOUND';
  END IF;

  IF (
    SELECT count(*)
    FROM public.lf_activo_relaciones r
    JOIN public.lf_activos a ON a.codigo_activo=r.codigo_activo
    WHERE r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND r.relacion_tipo='GOBERNADO_POR'
      AND r.codigo_activo IN (
        'PERFIL-PRODUCT-DIRECTOR-LF',
        'PERFIL-UI-ARCHITECT',
        'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531',
        'PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING'
      )
      AND a.metadata->>'input_governance_binding_mode'='DIRECT_PROFILE'
      AND a.metadata->>'input_governance_consumer'='CONTEXT_PACK'
  )<>4 THEN
    RAISE EXCEPTION 'PROFILE_INPUT_GOVERNANCE_DIRECT_BINDING_INCOMPLETE';
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
