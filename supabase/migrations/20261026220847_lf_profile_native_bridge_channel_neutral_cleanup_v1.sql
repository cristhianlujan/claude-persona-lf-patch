-- Clean channel-neutral GPT Native profile bridge and collapse product-specific duplicate logic.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)'::regprocedure
     )) <> '42d3251960abc27fe66393cdefd65045' THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_CHANNEL_NEUTRAL_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb)'::regprocedure
     )) <> '4bbb29bef330bb2edf6d38cb1dc03b83' THEN
    RAISE EXCEPTION 'GENERIC_PROFILE_GATE2_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb)'::regprocedure
     )) <> '94df88cdbf9afdf4d77ffc54e9a32b05' THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_GATE2_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
     )) <> '1ee972a4bca6ca0d17a2ee1b7ca97142' THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_AFTER_SELECTION_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)'::regprocedure
     )) <> '678ea9d2b336c7c330eecff2b97d57b4' THEN
    RAISE EXCEPTION 'LEGACY_PRODUCT_AFTER_SELECTION_RAW_SOURCE_DRIFT';
  END IF;
END
$precheck$;

-- Canonical Gate2 derivation owns the implementation.
CREATE OR REPLACE FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(
  p_gate2_request jsonb,
  p_profile_selection_result jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_profile text;
  v_body jsonb;
  v_result jsonb;
  v_receipt text;
  v_validation jsonb;
BEGIN
  IF jsonb_typeof(p_gate2_request)<>'object'
     OR jsonb_typeof(p_profile_selection_result)<>'object'
     OR p_gate2_request->>'schema_version'<>'LF_ROUTER_SEMANTIC_REQUEST_V1'
     OR p_profile_selection_result->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1'
     OR p_profile_selection_result->>'decision'<>'SELECTED'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_GATE2_DERIVATION_INPUT_INVALID'
    );
  END IF;

  v_profile:=nullif(btrim(coalesce(
    p_profile_selection_result->>'selected_profile_code',''
  )),'');

  IF v_profile IS NULL
     OR jsonb_array_length(coalesce(
       p_gate2_request->'candidate_subjects','[]'::jsonb
     ))<>1
     OR p_gate2_request#>>'{candidate_subjects,0,asset_code}'
          IS DISTINCT FROM v_profile
     OR p_gate2_request#>>'{candidate_subjects,0,asset_type}'
          IS DISTINCT FROM 'PERFIL'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_GATE2_DERIVATION_TARGET_MISMATCH',
      'selected_profile_code',v_profile
    );
  END IF;

  v_body:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1',
    'request_sha256',p_gate2_request->>'request_sha256',
    'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array(v_profile),
    'excluded_target_refs',coalesce(
      p_gate2_request->'excluded_target_refs','[]'::jsonb
    ),
    'allowed_scope',coalesce(
      p_gate2_request->'allowed_scope',jsonb_build_array(v_profile)
    ),
    'forbidden_scope',coalesce(
      p_gate2_request->'forbidden_scope','[]'::jsonb
    ),
    'conditions',coalesce(
      p_gate2_request->'conditions','[]'::jsonb
    ),
    'material_ambiguities','[]'::jsonb,
    'clarification_question',null
  );

  v_receipt:=encode(
    extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),
    'hex'
  );

  v_result:=v_body||jsonb_build_object(
    'semantic_receipt_sha256',v_receipt
  );

  v_validation:=public.lf_router_semantic_resume_validate_v1(
    p_gate2_request,v_result
  );

  IF v_validation->>'status'<>'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false)
        IS NOT TRUE
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_GATE2_DERIVATION_VALIDATION_FAILED',
      'validation',v_validation
    );
  END IF;

  RETURN jsonb_build_object(
    'status','READY',
    'derivation_mode','DETERMINISTIC_FROM_VALIDATED_PROFILE_SELECTION',
    'second_model_call_required',false,
    'gate2_result',v_result,
    'validation',v_validation
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb)
  TO service_role,supabase_read_only_user;

-- Legacy PRODUCTO name remains only as a compatibility wrapper.
CREATE OR REPLACE FUNCTION public.lf_router_product_gate2_result_from_selection_v1(
  p_gate2_request jsonb,
  p_profile_selection_result jsonb
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
  SELECT public.lf_router_profile_gate2_result_from_selection_v1(
    p_gate2_request,
    p_profile_selection_result
  )
$function$;

REVOKE ALL ON FUNCTION public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb)
  TO service_role,supabase_read_only_user;

-- Legacy PRODUCTO continuation remains product-only but delegates all real logic.
CREATE OR REPLACE FUNCTION public.lf_router_product_profile_after_selection_v1(
  p_stage1 jsonb,
  p_selection_result jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
BEGIN
  IF p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
     OR upper(coalesce(p_stage1->>'canal_candidato',''))<>'PRODUCTO'
     OR p_stage1->>'negocio_codigo'<>'LF'
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_PROFILE_AFTER_SELECTION_V1',
      'router','ACT-0001',
      'status','BLOCKED',
      'paso','PRODUCTO_PROFILE_SELECTION_ROUTE_MISMATCH',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_ROUTE_MISMATCH',
      'downstream_execution_allowed',false
    );
  END IF;

  RETURN public.lf_router_profile_after_selection_v1(
    p_stage1,
    p_selection_result
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)
  TO service_role,supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_router_product_profile_after_selection_raw_v1(
  p_stage1 jsonb,
  p_raw text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
BEGIN
  IF p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
     OR upper(coalesce(p_stage1->>'canal_candidato',''))<>'PRODUCTO'
     OR p_stage1->>'negocio_codigo'<>'LF'
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_PROFILE_AFTER_SELECTION_RAW_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_RAW_ROUTE_MISMATCH',
      'downstream_execution_allowed',false
    );
  END IF;

  RETURN public.lf_router_profile_after_selection_raw_v1(
    p_stage1,
    p_raw
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)
  TO service_role,supabase_read_only_user;

-- GPT Native entrypoint is channel-neutral. Stage1 is the canonical source of
-- channel/business/scope; after-selection output is not used as a second source.
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_begin_v1(
  p_stage1 jsonb,
  p_semantic_result jsonb,
  p_executor_mode text DEFAULT 'GPT_NATIVE',
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_route jsonb;
  v_selection_request jsonb;
  v_selection_validation jsonb;
  v_after_selection jsonb;
  v_gate2_derived jsonb;
  v_request jsonb;
  v_gate2_result jsonb;
  v_validation jsonb;
  v_materialized jsonb;
  v_actor text;
  v_channel text;
  v_expected_route_step text;
  v_expected_gate2_step text;
BEGIN
  IF jsonb_typeof(p_stage1)<>'object'
     OR jsonb_typeof(p_semantic_result)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_INVALID'
    );
  END IF;

  IF upper(coalesce(p_executor_mode,''))<>'GPT_NATIVE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTOR_MODE',
      'required_executor_mode','GPT_NATIVE'
    );
  END IF;

  IF p_semantic_result->>'schema_version'
       <>'LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SELECTION_RESULT_REQUIRED',
      'required_schema_version','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1'
    );
  END IF;

  v_channel:=upper(coalesce(p_stage1->>'canal_candidato',''));
  IF v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR p_stage1->>'negocio_codigo'<>'LF' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_CHANNEL_OR_BUSINESS_INVALID',
      'channel',v_channel,
      'business',p_stage1->>'negocio_codigo'
    );
  END IF;

  v_expected_route_step:=v_channel||'_PROFILE_SELECTION_REQUIRED';
  v_expected_gate2_step:=v_channel||'_GATE2_PERFIL';

  v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);

  IF v_route->>'paso' IS DISTINCT FROM v_expected_route_step
     OR upper(coalesce(v_route->>'canal_candidato','')) IS DISTINCT FROM v_channel
     OR v_route->>'negocio_codigo'<>'LF'
     OR jsonb_typeof(v_route->'profile_selection_request')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_ROUTE_NOT_READY',
      'expected_route_step',v_expected_route_step,
      'route',v_route
    );
  END IF;

  v_selection_request:=v_route->'profile_selection_request';
  v_selection_validation:=public.lf_profile_selector_semantic_validate_v1(
    v_selection_request,p_semantic_result
  );

  IF v_selection_validation->>'status'<>'VALID'
     OR p_semantic_result->>'decision'<>'SELECTED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SELECTION_INVALID',
      'profile_selection_validation',v_selection_validation
    );
  END IF;

  v_after_selection:=public.lf_router_profile_after_selection_v1(
    p_stage1,p_semantic_result
  );

  IF v_after_selection->>'status'<>'READY_FOR_GATE2'
     OR v_after_selection->>'paso' IS DISTINCT FROM v_expected_gate2_step
     OR v_after_selection->>'channel' IS DISTINCT FROM v_channel
     OR jsonb_typeof(v_after_selection->'gate2_request')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_GATE2_NOT_READY',
      'expected_gate2_step',v_expected_gate2_step,
      'after_profile_selection',v_after_selection
    );
  END IF;

  v_request:=v_after_selection->'gate2_request';

  v_gate2_derived:=public.lf_router_profile_gate2_result_from_selection_v1(
    v_request,p_semantic_result
  );

  IF v_gate2_derived->>'status'<>'READY'
     OR jsonb_typeof(v_gate2_derived->'gate2_result')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_GATE2_DERIVATION_FAILED',
      'gate2_derivation',v_gate2_derived
    );
  END IF;

  v_gate2_result:=v_gate2_derived->'gate2_result';
  v_validation:=v_gate2_derived->'validation';

  v_actor:=coalesce(
    nullif(btrim(p_actor_execution_id),''),
    'PROFILE-NATIVE-BRIDGE-'||upper(substr(v_request->>'request_sha256',1,20))
  );

  v_materialized:=public.lf_router_profile_execution_after_gate2_v1(
    v_request,
    v_gate2_result,
    v_channel,
    p_stage1->>'negocio_codigo',
    p_stage1->'alcance',
    'GPT_NATIVE',
    v_actor,
    NULL
  );

  IF v_materialized->>'status'<>'NATIVE_EXECUTION_READY' THEN
    RETURN v_materialized||jsonb_build_object(
      'bridge_status','BLOCKED',
      'bridge_stage','GATE2_MATERIALIZATION',
      'profile_selection_result',p_semantic_result,
      'gate2_result',v_gate2_result
    );
  END IF;

  RETURN v_materialized||jsonb_build_object(
    'bridge_status','READY',
    'bridge_stage','NATIVE_EXECUTION_MATERIALIZED',
    'stage1',p_stage1,
    'profile_selection_result',p_semantic_result,
    'profile_selection_validation',v_selection_validation,
    'gate2_result',v_gate2_result,
    'gate2_validation',v_validation,
    'gate2_derivation_mode','DETERMINISTIC_FROM_VALIDATED_PROFILE_SELECTION',
    'second_model_call_required',false,
    'router_route_summary',jsonb_build_object(
      'paso',v_route->>'paso',
      'canal_candidato',v_channel,
      'negocio_codigo',p_stage1->>'negocio_codigo',
      'perfil_candidato',v_after_selection->>'perfil_candidato'
    )
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text) IS
'Channel-neutral service-role GPT Native bridge for PRODUCTO, PROGRAMACION and OPERACIONES. Reuses the common profile selection continuation and Gate2 derivation; Stage1 is the sole source of channel/business/scope.';

COMMENT ON FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb) IS
'Canonical channel-neutral deterministic Gate2 derivation from a validated SELECTED profile result. No second model call and no effect authority.';

COMMENT ON FUNCTION public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb) IS
'Legacy PRODUCTO compatibility alias. Canonical implementation is public.lf_router_profile_gate2_result_from_selection_v1.';

COMMENT ON FUNCTION public.lf_router_product_profile_after_selection_v1(jsonb,jsonb) IS
'Legacy PRODUCTO compatibility wrapper. Canonical implementation is public.lf_router_profile_after_selection_v1.';

COMMENT ON FUNCTION public.lf_router_product_profile_after_selection_raw_v1(jsonb,text) IS
'Legacy PRODUCTO compatibility wrapper. Canonical implementation is public.lf_router_profile_after_selection_raw_v1.';

DO $postcheck$
DECLARE
  s jsonb := '{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Analiza la causa raíz del bloqueo de ejecución en PROGRAMACIÓN sin aplicar cambios. Prueba bridge channel-neutral 2026-10-26.",
    "es_operacion":true,
    "respuesta_directa":false,
    "accion":"analizar causa raíz de bloqueo de ejecución",
    "sujeto":"ejecución de perfil en programación",
    "correcciones":[],
    "formas_busqueda":["bloqueo ejecución perfil programación"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PROGRAMACION",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Diagnóstico técnico sin efecto",
    "alcance":{"target_type":"RUNTIME","target_hint":"EJECUCION_PERFIL_LF","resolution_status":"UNRESOLVED"}
  }'::jsonb;
  req jsonb;
  fin jsonb;
  bridge jsonb;
  expected_execution_id text;
  bridge_src text;
  legacy_after_src text;
  legacy_raw_src text;
  legacy_gate2_src text;
BEGIN
  req:=public.lf_profile_selector_semantic_prepare_v1(s->>'texto_original');

  fin:=public.lf_profile_selector_semantic_finalize_v1(
    req,
    jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Postcheck mechanically binds the CURRENT SRCR profile to a root-cause analysis request.',
      'evidence_refs',jsonb_build_array(jsonb_build_object(
        'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
        'kind','PURPOSE',
        'source_section','Purpose'
      )),
      'material_ambiguities','[]'::jsonb
    )
  );

  IF fin->>'status'<>'VALID' THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_CHANNEL_NEUTRAL_SELECTION_FAIL:%',fin;
  END IF;

  expected_execution_id:=
    'EXEC-PROFILE-GATE2-'||upper(substr(req->>'request_sha256',1,24));

  BEGIN
    bridge:=public.lf_profile_native_bridge_begin_v1(
      s,
      fin->'result',
      'GPT_NATIVE',
      'MIG-NATIVE-BRIDGE-CHANNEL-NEUTRAL-POSTCHECK'
    );

    IF bridge->>'status'<>'NATIVE_EXECUTION_READY'
       OR bridge->>'bridge_status'<>'READY'
       OR bridge->>'profile_code'<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       OR bridge#>>'{router_profile_handoff,channel}'<>'PROGRAMACION'
       OR bridge#>>'{router_profile_handoff,business}'<>'LF'
       OR coalesce(
         (bridge#>>'{router_profile_handoff,effect_authority}')::boolean,
         true
       ) IS TRUE
       OR bridge#>>'{router_route_summary,canal_candidato}'<>'PROGRAMACION'
       OR bridge#>>'{router_route_summary,paso}'
            <>'PROGRAMACION_PROFILE_SELECTION_REQUIRED'
    THEN
      RAISE EXCEPTION 'NATIVE_BRIDGE_CHANNEL_NEUTRAL_PROGRAMACION_FAIL:%',bridge;
    END IF;

    RAISE EXCEPTION USING
      ERRCODE='PZ271',
      MESSAGE='NATIVE_BRIDGE_CHANNEL_NEUTRAL_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'PZ271' THEN
      NULL;
  END;

  IF EXISTS(
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id=expected_execution_id
  ) THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_CHANNEL_NEUTRAL_POSTCHECK_RESIDUE:%',
      expected_execution_id;
  END IF;

  bridge_src:=pg_get_functiondef(
    'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)'::regprocedure
  );
  legacy_after_src:=pg_get_functiondef(
    'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
  );
  legacy_raw_src:=pg_get_functiondef(
    'public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)'::regprocedure
  );
  legacy_gate2_src:=pg_get_functiondef(
    'public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb)'::regprocedure
  );

  IF strpos(bridge_src,'public.lf_router_profile_after_selection_v1')=0
     OR strpos(bridge_src,'public.lf_router_profile_gate2_result_from_selection_v1')=0
     OR strpos(bridge_src,'p_stage1->>''negocio_codigo''')=0
     OR strpos(bridge_src,'p_stage1->''alcance''')=0
     OR strpos(bridge_src,'public.lf_router_product_profile_after_selection_v1')>0
     OR strpos(bridge_src,'public.lf_router_product_gate2_result_from_selection_v1')>0
     OR strpos(bridge_src,'''PRODUCTO_PROFILE_SELECTION_REQUIRED''')>0
     OR strpos(bridge_src,'''PRODUCTO_GATE2_PERFIL''')>0
  THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_CHANNEL_NEUTRAL_SOURCE_POSTCHECK_FAIL';
  END IF;

  IF strpos(legacy_after_src,'public.lf_router_profile_after_selection_v1')=0
     OR strpos(legacy_after_src,'lf_profile_selector_semantic_prepare_v1')>0
     OR strpos(legacy_raw_src,'public.lf_router_profile_after_selection_raw_v1')=0
     OR strpos(legacy_raw_src,'lf_profile_selector_semantic_consume_raw_v1')>0
     OR strpos(legacy_gate2_src,'public.lf_router_profile_gate2_result_from_selection_v1')=0
     OR strpos(legacy_gate2_src,'lf_router_semantic_resume_validate_v1')>0
  THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_LEGACY_WRAPPER_CLEANUP_FAIL';
  END IF;

  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'NATIVE_BRIDGE_EXECUTION_ACL_REGRESSION';
  END IF;
END
$postcheck$;

COMMIT;
