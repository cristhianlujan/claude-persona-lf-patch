-- RW1-05_C2: preserve ACT-0001 action continuity across semantic resume and
-- move profile runtime-state compatibility to the executor-aware operation boundary.
-- No executor is selected by the semantic specialist. No runtime is enabled.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_action_binding_snapshot_v1(
  p_request_text text,
  p_asset_type text,
  p_action_code text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  v_rule public.lf_router_action_registry%rowtype;
  v_body jsonb;
BEGIN
  SELECT * INTO v_rule
  FROM public.lf_router_action_registry
  WHERE asset_type=upper(nullif(btrim(coalesce(p_asset_type,'')),''))
    AND action_code=upper(nullif(btrim(coalesce(p_action_code,'')),''))
    AND status='ACTIVE'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_ACTION_BINDING_V1',
      'valid',false,
      'code','ROUTER_ACTION_BINDING_REGISTRY_MISSING'
    );
  END IF;

  v_body:=jsonb_build_object(
    'schema_version','LF_ROUTER_ACTION_BINDING_V1',
    'source','ACT-0001_PRE_SEMANTIC_DERIVATION',
    'request_sha256',encode(extensions.digest(convert_to(coalesce(p_request_text,''),'UTF8'),'sha256'),'hex'),
    'asset_type',v_rule.asset_type,
    'candidate_action_code',v_rule.action_code,
    'action_registry_operation_code',v_rule.operation_code,
    'action_registry_status',v_rule.status,
    'router_source_md5',md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
  );

  RETURN v_body||jsonb_build_object(
    'binding_sha256','sha256:'||encode(
      extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),'hex'
    )
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_router_action_binding_snapshot_v1(text,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_action_binding_snapshot_v1(text,text,text)
  TO postgres,service_role,supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_router_semantic_action_binding_validate_v1(
  p_request jsonb,
  p_target text,
  p_asset_type text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  v_binding jsonb;
  v_body jsonb;
  v_expected_sha text;
  v_rule_count integer:=0;
  v_operation_code text;
BEGIN
  v_binding:=p_request->'router_action_binding';
  IF jsonb_typeof(v_binding)<>'object' THEN
    RETURN jsonb_build_object('valid',false,'code','ROUTER_ACTION_BINDING_MISSING');
  END IF;

  v_body:=v_binding-'binding_sha256';
  v_expected_sha:='sha256:'||encode(
    extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),'hex'
  );

  IF v_binding->>'schema_version'<>'LF_ROUTER_ACTION_BINDING_V1'
     OR v_binding->>'source'<>'ACT-0001_PRE_SEMANTIC_DERIVATION'
     OR v_binding->>'request_sha256' IS DISTINCT FROM p_request->>'request_sha256'
     OR upper(coalesce(v_binding->>'asset_type','')) IS DISTINCT FROM upper(coalesce(p_asset_type,''))
     OR nullif(btrim(coalesce(v_binding->>'candidate_action_code','')),'') IS NULL
     OR v_binding->>'router_source_md5' IS DISTINCT FROM
        md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))
     OR v_binding->>'binding_sha256' IS DISTINCT FROM v_expected_sha
  THEN
    RETURN jsonb_build_object('valid',false,'code','ROUTER_ACTION_BINDING_INTEGRITY_FAILED');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_request->'candidate_subjects') x(item)
    WHERE coalesce(
      x.item->>'asset_code',x.item->>'operation_code',x.item->>'codigo_activo',x.item->>'code'
    )=p_target
      AND upper(coalesce(
        x.item->>'asset_type',
        case when x.item ? 'operation_code' then 'OPERATION_CODE' else null end,
        ''
      ))=upper(coalesce(p_asset_type,''))
  ) THEN
    RETURN jsonb_build_object('valid',false,'code','ROUTER_ACTION_BINDING_TARGET_MISMATCH');
  END IF;

  SELECT count(*),min(operation_code)
    INTO v_rule_count,v_operation_code
  FROM public.lf_router_action_registry
  WHERE asset_type=upper(p_asset_type)
    AND action_code=upper(v_binding->>'candidate_action_code')
    AND status='ACTIVE';

  IF v_rule_count<>1
     OR v_binding->>'action_registry_operation_code' IS DISTINCT FROM v_operation_code
  THEN
    RETURN jsonb_build_object('valid',false,'code','ROUTER_ACTION_BINDING_REGISTRY_DRIFT');
  END IF;

  RETURN jsonb_build_object(
    'valid',true,
    'code','ROUTER_ACTION_BINDING_VALID',
    'candidate_action_code',v_binding->>'candidate_action_code',
    'operation_code',v_operation_code,
    'binding_sha256',v_binding->>'binding_sha256'
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_router_semantic_action_binding_validate_v1(jsonb,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_semantic_action_binding_validate_v1(jsonb,text,text)
  TO postgres,service_role,supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_executor_admission_v1(
  p_profile_code text,
  p_executor_mode text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_asset public.lf_activos%rowtype;
  v_mode text:=upper(nullif(btrim(coalesce(p_executor_mode,'')),''));
BEGIN
  IF v_mode IS NULL OR v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
    RETURN jsonb_build_object(
      'admitted',false,'code','PROFILE_EXECUTION_EXECUTOR_MODE_INVALID','executor_mode',v_mode
    );
  END IF;

  SELECT * INTO v_asset
  FROM public.lf_activos
  WHERE codigo_activo=p_profile_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'admitted',false,'code','PROFILE_EXECUTION_PROFILE_NOT_FOUND','executor_mode',v_mode
    );
  END IF;

  IF nullif(btrim(coalesce(v_asset.estado_documental,'')),'') IS NULL
     OR nullif(btrim(coalesce(v_asset.estado_operativo,'')),'') IS NULL
  THEN
    RETURN jsonb_build_object(
      'admitted',false,'code','PROFILE_EXECUTION_PROFILE_STATE_INCOMPLETE','executor_mode',v_mode
    );
  END IF;

  IF upper(v_asset.estado_operativo) IN ('BLOQUEADO','ELIMINADO')
     OR upper(v_asset.estado_documental)='ELIMINADO'
  THEN
    RETURN jsonb_build_object(
      'admitted',false,'code','PROFILE_EXECUTION_PROFILE_STATE_NOT_AUTHORIZED',
      'executor_mode',v_mode
    );
  END IF;

  IF v_mode IN ('GPT_NATIVE','CLAUDE_NATIVE') THEN
    IF upper(v_asset.estado_operativo)<>'READ_ONLY' THEN
      RETURN jsonb_build_object(
        'admitted',false,'code','PROFILE_EXECUTION_NATIVE_REQUIRES_READ_ONLY_PROFILE',
        'executor_mode',v_mode,'estado_operativo',v_asset.estado_operativo
      );
    END IF;

    RETURN jsonb_build_object(
      'admitted',true,
      'code','PROFILE_EXECUTION_NATIVE_MODE_ADMITTED',
      'executor_mode',v_mode,
      'profile_code',v_asset.codigo_activo,
      'estado_documental',v_asset.estado_documental,
      'estado_operativo',v_asset.estado_operativo,
      'runtime_estado',v_asset.runtime_estado,
      'runtime_state_role','EXECUTION_MODE_COMPATIBILITY_NOT_LIFECYCLE',
      'remote_runtime_required',false
    );
  END IF;

  IF nullif(btrim(coalesce(v_asset.runtime_estado,'')),'') IS NULL
     OR upper(v_asset.runtime_estado) IN ('NO_HABILITADO','NO_APLICA')
  THEN
    RETURN jsonb_build_object(
      'admitted',false,
      'code','PROFILE_EXECUTION_REMOTE_RUNTIME_STATE_NOT_AUTHORIZED',
      'executor_mode',v_mode,
      'profile_code',v_asset.codigo_activo,
      'runtime_estado',v_asset.runtime_estado
    );
  END IF;

  RETURN jsonb_build_object(
    'admitted',true,
    'code','PROFILE_EXECUTION_REMOTE_MODE_ADMITTED',
    'executor_mode',v_mode,
    'profile_code',v_asset.codigo_activo,
    'runtime_estado',v_asset.runtime_estado,
    'remote_runtime_required',true
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_execution_executor_admission_v1(text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_executor_admission_v1(text,text)
  TO postgres,service_role,supabase_read_only_user;

DO $patch_router$
DECLARE
  v_def text;
  v_old text;
  v_new text;
  v_before text;
BEGIN
  v_before:=md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure));
  IF v_before<>'9fff43d8f2e58a6e6320c1cd53b5bbf2' THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_ROUTER_SOURCE_DRIFT:%',v_before;
  END IF;

  v_def:=pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure);

  v_old:=E'    if upper(v_asset.runtime_estado) in (''NO_HABILITADO'',''NO_APLICA'')\n       or upper(v_asset.estado_operativo) in (''BLOQUEADO'',''ELIMINADO'')\n       or upper(v_asset.estado_documental) = ''ELIMINADO'' then';
  v_new:=E'    -- runtime_estado is executor-mode compatibility, not lifecycle authority.\n    -- Mode-specific admission is enforced by lf_profile_execution_begin_v1.\n    if upper(v_asset.estado_operativo) in (''BLOQUEADO'',''ELIMINADO'')\n       or upper(v_asset.estado_documental) = ''ELIMINADO'' then';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_RUNTIME_GUARD_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=E'''semantic_handoff_v2'',public.lf_router_intent_handoff_v2(\n        p_request_text,case when v_asset_found then\n          jsonb_build_array(jsonb_build_object(\n            ''asset_code'',v_asset.codigo_activo,\n            ''asset_type'',v_asset.tipo_activo))\n          else ''[]''::jsonb end,''CANONICAL_ASSET''),\n      ''semantic_resolution_required'',true,\n      ''semantic_gap_code'',''EXPLICIT_TARGET_IS_NOT_SCOPE_AUTHORITY''';
  v_new:=E'''semantic_handoff_v2'',public.lf_router_intent_handoff_v2(\n        p_request_text,case when v_asset_found then\n          jsonb_build_array(jsonb_build_object(\n            ''asset_code'',v_asset.codigo_activo,\n            ''asset_type'',v_asset.tipo_activo))\n          else ''[]''::jsonb end,''CANONICAL_ASSET'')\n        || jsonb_build_object(\n          ''router_action_binding'',\n          public.lf_router_action_binding_snapshot_v1(p_request_text,v_type_hint,v_action)\n        ),\n      ''semantic_resolution_required'',true,\n      ''semantic_gap_code'',''EXPLICIT_TARGET_IS_NOT_SCOPE_AUTHORITY''';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_ACTION_BINDING_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  EXECUTE v_def;
END
$patch_router$;

DO $patch_resume_validator$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure))
     <>'4dc0dad03d7259009583e2f77f5930fb'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_RESUME_VALIDATE_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef('public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)'::regprocedure);
  v_old:=E' IF ok AND p_result ?| ARRAY[''operation_code'',''executor'',''effect_authority'',''downstream_execution_allowed'',''route_authority''] THEN ok:=false; END IF;';
  v_new:=E' IF ok AND p_result ?| ARRAY[''operation_code'',''action_code'',''candidate_action_code'',''router_action_binding'',''executor'',''executor_mode'',''effect_authority'',''downstream_execution_allowed'',''route_authority''] THEN ok:=false; END IF;';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_RESULT_AUTHORITY_ANCHOR_MISSING';
  END IF;
  EXECUTE replace(v_def,v_old,v_new);
END
$patch_resume_validator$;

DO $patch_resume_route$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_semantic_resume_route_v1(jsonb,jsonb)'::regprocedure))
     <>'632462560cd7f45fc1e0aa7a0f2e576f'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_RESUME_ROUTE_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef('public.lf_router_semantic_resume_route_v1(jsonb,jsonb)'::regprocedure);

  v_old:=E'  v_route jsonb;\n  v_request_sha text;';
  v_new:=E'  v_route jsonb;\n  v_request_sha text;\n  v_action_binding jsonb;';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_RESUME_DECLARATION_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=E'  -- Probe ACT-0001 normally. This is the only source of candidate_action_code.\n  v_probe:=public.lf_router_resolve_v1(\n    p_request->>''literal_request'',\n    v_target,\n    null,\n    v_asset_type,\n    ''ROUTER''\n  );\n\n  IF v_probe->>''blocking_code''<>''BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED''\n     OR nullif(v_probe->>''candidate_action_code'','''') IS NULL\n     OR v_probe->>''candidate_asset_type'' IS DISTINCT FROM v_asset_type\n  THEN\n    RETURN jsonb_build_object(\n      ''schema_version'',''LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1'',\n      ''status'',''BLOCKED'',\n      ''blocking_code'',''BLOCK_SEMANTIC_RESUME_ROUTER_PROBE_UNEXPECTED'',\n      ''resume_validation'',v_validation,\n      ''router_probe'',v_probe,\n      ''semantic_result_route_authority'',false,\n      ''semantic_result_effect_authority'',false,\n      ''downstream_execution_allowed'',false\n    );\n  END IF;\n\n  v_action:=v_probe->>''candidate_action_code'';\n  v_request_sha:=p_request->>''request_sha256'';';

  v_new:=E'  v_request_sha:=p_request->>''request_sha256'';\n\n  IF p_request ? ''router_action_binding'' THEN\n    v_action_binding:=public.lf_router_semantic_action_binding_validate_v1(\n      p_request,v_target,v_asset_type\n    );\n    IF coalesce((v_action_binding->>''valid'')::boolean,false) IS NOT TRUE THEN\n      RETURN jsonb_build_object(\n        ''schema_version'',''LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1'',\n        ''status'',''BLOCKED'',\n        ''blocking_code'',''BLOCK_SEMANTIC_RESUME_ACTION_BINDING_INVALID'',\n        ''resume_validation'',v_validation,\n        ''router_action_binding_validation'',v_action_binding,\n        ''semantic_result_route_authority'',false,\n        ''semantic_result_effect_authority'',false,\n        ''downstream_execution_allowed'',false\n      );\n    END IF;\n    v_action:=v_action_binding->>''candidate_action_code'';\n\n    -- Re-read ACT-0001 using the original Router-derived action candidate.\n    -- The specialist never supplies or changes this value.\n    v_probe:=public.lf_router_resolve_v1(\n      p_request->>''literal_request'',v_target,v_action,v_asset_type,''ROUTER''\n    );\n    IF v_probe->>''blocking_code''<>''BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED''\n       OR v_probe->>''candidate_action_code'' IS DISTINCT FROM v_action\n       OR v_probe->>''candidate_asset_type'' IS DISTINCT FROM v_asset_type\n    THEN\n      RETURN jsonb_build_object(\n        ''schema_version'',''LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1'',\n        ''status'',''BLOCKED'',\n        ''blocking_code'',''BLOCK_SEMANTIC_RESUME_ACTION_BINDING_RECHECK_FAILED'',\n        ''resume_validation'',v_validation,\n        ''router_action_binding_validation'',v_action_binding,\n        ''router_probe'',v_probe,\n        ''semantic_result_route_authority'',false,\n        ''semantic_result_effect_authority'',false,\n        ''downstream_execution_allowed'',false\n      );\n    END IF;\n  ELSE\n    -- Legacy T2 requests retain the prior fail-closed derivation path.\n    v_probe:=public.lf_router_resolve_v1(\n      p_request->>''literal_request'',v_target,null,v_asset_type,''ROUTER''\n    );\n    IF v_probe->>''blocking_code''<>''BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED''\n       OR nullif(v_probe->>''candidate_action_code'','''') IS NULL\n       OR v_probe->>''candidate_asset_type'' IS DISTINCT FROM v_asset_type\n    THEN\n      RETURN jsonb_build_object(\n        ''schema_version'',''LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1'',\n        ''status'',''BLOCKED'',\n        ''blocking_code'',''BLOCK_SEMANTIC_RESUME_ROUTER_PROBE_UNEXPECTED'',\n        ''resume_validation'',v_validation,\n        ''router_probe'',v_probe,\n        ''semantic_result_route_authority'',false,\n        ''semantic_result_effect_authority'',false,\n        ''downstream_execution_allowed'',false\n      );\n    END IF;\n    v_action:=v_probe->>''candidate_action_code'';\n  END IF;';

  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_RESUME_PROBE_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  EXECUTE v_def;
END
$patch_resume_route$;

DO $patch_profile_begin$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  IF md5(pg_get_functiondef('public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure))
     <>'de7eadeab303c629c9f9cbd9ff853093'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_PROFILE_BEGIN_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef('public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure);

  v_old:=E'  v_baseline_contract jsonb;\nbegin';
  v_new:=E'  v_baseline_contract jsonb;\n  v_executor_mode text;\n  v_executor_admission jsonb;\nbegin';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_PROFILE_BEGIN_DECLARATION_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=E'  select coalesce(nullif(metadata->>''research_baseline_mode'',''''),''NOT_REQUIRED''),';
  v_new:=E'  v_executor_mode:=upper(nullif(btrim(coalesce(p_manifest->>''executor_mode'','''')),''''));\n  IF v_executor_mode IS NULL AND nullif(btrim(coalesce(p_manifest->>''queue_request_id'','''')) ,'''') IS NOT NULL THEN\n    v_executor_mode:=''REMOTE_API'';\n  END IF;\n  v_executor_admission:=public.lf_profile_execution_executor_admission_v1(\n    p_profile_code,v_executor_mode\n  );\n  IF coalesce((v_executor_admission->>''admitted'')::boolean,false) IS NOT TRUE THEN\n    raise exception ''PROFILE_EXECUTION_EXECUTOR_ADMISSION_BLOCKED:%'',v_executor_admission::text;\n  END IF;\n\n  select coalesce(nullif(metadata->>''research_baseline_mode'',''''),''NOT_REQUIRED''),';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_PROFILE_BEGIN_ADMISSION_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=E'      ''automatic_impact'',false\n    )';
  v_new:=E'      ''automatic_impact'',false,\n      ''executor_mode'',v_executor_mode,\n      ''executor_admission_receipt'',v_executor_admission\n    )';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_PROFILE_BEGIN_MANIFEST_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  EXECUTE v_def;
END
$patch_profile_begin$;

COMMENT ON FUNCTION public.lf_profile_execution_executor_admission_v1(text,text) IS
'Executor-aware profile admission. Native GPT/Claude require READ_ONLY profile state and do not require remote runtime state. REMOTE_API retains runtime-state admission.';

COMMENT ON FUNCTION public.lf_router_semantic_action_binding_validate_v1(jsonb,text,text) IS
'Validates ACT-0001 request-side action continuity. Semantic result cannot select action, operation, executor or effect authority.';

DO $post$
DECLARE
  v_literal text:='Canario read-only RW1-05_C2: revisa la afirmación operacional «el artefacto inexistente está vigente y aplicado» usando únicamente la referencia proporcionada github://cristhianlujan/claude-persona-lf-patch@0000000000000000000000000000000000000000/docs/nonexistent.json. No hay evidencia adicional. No inventes ni sustituyas fuentes; devuelve el estado correcto de Evidence Lineage Reviewer.';
  v_initial jsonb;
  v_request jsonb;
  v_result jsonb;
  v_resume jsonb;
  v_native jsonb;
  v_remote jsonb;
  v_tampered jsonb;
  v_tamper_out jsonb;
BEGIN
  v_initial:=public.lf_router_resolve_v1(
    v_literal,
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );

  IF v_initial->>'blocking_code'<>'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED'
     OR v_initial->>'candidate_action_code'<>'PROFILE_EXECUTION'
     OR v_initial#>>'{semantic_handoff_v2,router_action_binding,candidate_action_code}'<>'PROFILE_EXECUTION'
     OR v_initial#>>'{semantic_handoff_v2,router_action_binding,action_registry_operation_code}'<>'EJECUCION_PERFIL_LF'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_INITIAL_BINDING_FAILED:%',v_initial::text;
  END IF;

  v_request:=v_initial->'semantic_handoff_v2';
  v_result:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1',
    'request_sha256',v_request->>'request_sha256',
    'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array('PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'),
    'excluded_target_refs','[]'::jsonb,
    'allowed_scope',jsonb_build_array('PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'),
    'forbidden_scope','[]'::jsonb,
    'conditions','[]'::jsonb,
    'material_ambiguities','[]'::jsonb,
    'clarification_question',null,
    'semantic_receipt_sha256',repeat('a',64)
  );

  v_resume:=public.lf_router_semantic_resume_route_v1(v_request,v_result);
  IF v_resume->>'status'<>'ROUTER_REDERIVED'
     OR v_resume->>'router_derived_action_code'<>'PROFILE_EXECUTION'
     OR v_resume#>>'{router_result,status}'<>'READY_TO_EXECUTE'
     OR v_resume#>>'{router_result,operation_code}'<>'EJECUCION_PERFIL_LF'
     OR v_resume#>>'{router_result,asset,codigo_activo}'<>'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_RESUME_FAILED:%',v_resume::text;
  END IF;

  v_native:=public.lf_profile_execution_executor_admission_v1(
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','GPT_NATIVE'
  );
  v_remote:=public.lf_profile_execution_executor_admission_v1(
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF','REMOTE_API'
  );
  IF coalesce((v_native->>'admitted')::boolean,false) IS NOT TRUE
     OR v_native->>'remote_runtime_required'<>'false'
     OR coalesce((v_remote->>'admitted')::boolean,true) IS NOT FALSE
     OR v_remote->>'code'<>'PROFILE_EXECUTION_REMOTE_RUNTIME_STATE_NOT_AUTHORIZED'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_EXECUTOR_ADMISSION_FAILED native=% remote=%',
      v_native::text,v_remote::text;
  END IF;

  v_tampered:=jsonb_set(
    v_request,
    '{router_action_binding,candidate_action_code}',
    to_jsonb('ASSET_INSPECTION'::text),
    false
  );
  v_tamper_out:=public.lf_router_semantic_resume_route_v1(v_tampered,v_result);
  IF v_tamper_out->>'blocking_code'<>'BLOCK_SEMANTIC_RESUME_INVALID'
     AND v_tamper_out->>'blocking_code'<>'BLOCK_SEMANTIC_RESUME_ACTION_BINDING_INVALID'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_TAMPER_NOT_BLOCKED:%',v_tamper_out::text;
  END IF;

  IF public.lf_profile_execution_executor_admission_v1(
       'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','GPT_NATIVE'
     )->>'admitted'<>'true'
  THEN
    RAISE EXCEPTION 'RW105_C2_NATIVE_CONTINUITY_SYSTEMIC_NATIVE_REGRESSION';
  END IF;
END
$post$;

COMMIT;
