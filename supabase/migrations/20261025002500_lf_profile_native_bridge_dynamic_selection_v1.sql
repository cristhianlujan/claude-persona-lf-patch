BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_product_gate2_result_from_selection_v1(
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

COMMENT ON FUNCTION public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb) IS
'Deterministically derives the Gate2 semantic result from an already validated SELECTED profile choice. No second model call and no route/effect authority are introduced.';

REVOKE ALL ON FUNCTION public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_product_gate2_result_from_selection_v1(jsonb,jsonb)
  TO service_role, supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_begin_v1(
  p_stage1 jsonb,
  p_semantic_result jsonb,
  p_executor_mode text DEFAULT 'GPT_NATIVE'::text,
  p_actor_execution_id text DEFAULT NULL::text
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

  v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);

  IF v_route->>'paso'<>'PRODUCTO_PROFILE_SELECTION_REQUIRED'
     OR v_route->>'canal_candidato'<>'PRODUCTO'
     OR v_route->>'negocio_codigo'<>'LF'
     OR jsonb_typeof(v_route->'profile_selection_request')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_ROUTE_NOT_READY',
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

  v_after_selection:=public.lf_router_product_profile_after_selection_v1(
    p_stage1,p_semantic_result
  );

  IF v_after_selection->>'status'<>'READY_FOR_GATE2'
     OR v_after_selection->>'paso'<>'PRODUCTO_GATE2_PERFIL'
     OR jsonb_typeof(v_after_selection->'gate2_request')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_GATE2_NOT_READY',
      'after_profile_selection',v_after_selection
    );
  END IF;

  v_request:=v_after_selection->'gate2_request';

  v_gate2_derived:=public.lf_router_product_gate2_result_from_selection_v1(
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
    v_after_selection->>'canal_candidato',
    v_after_selection->>'negocio_codigo',
    v_after_selection->'alcance',
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
      'canal_candidato',v_route->>'canal_candidato',
      'negocio_codigo',v_route->>'negocio_codigo',
      'perfil_candidato',v_after_selection->>'perfil_candidato'
    )
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text) IS
'Consumes a validated semantic profile-selection result, deterministically derives Gate2, and materializes the authorized GPT_NATIVE profile execution.';

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)
  FROM PUBLIC, anon, authenticated, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)
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
  src text;
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
    'formas_busqueda',jsonb_build_array('login B2B','reglas login B2B'),
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

  IF f->>'status'<>'VALID' THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DYNAMIC_SELECTION_FIXTURE_INVALID:%',
      left(f::text,1600);
  END IF;

  a:=public.lf_router_product_profile_after_selection_v1(
    s,f->'result'
  );

  IF a->>'status'<>'READY_FOR_GATE2'
     OR a->>'perfil_candidato'<>'PERFIL-PRODUCT-DIRECTOR-LF' THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DYNAMIC_AFTER_SELECTION_INVALID:%',
      left(a::text,1600);
  END IF;

  d:=public.lf_router_product_gate2_result_from_selection_v1(
    a->'gate2_request',f->'result'
  );

  IF d->>'status'<>'READY'
     OR coalesce((d->>'second_model_call_required')::boolean,true)
     OR d#>>'{gate2_result,decision}'<>'RESOLVED'
     OR d#>>'{gate2_result,positive_target_refs,0}'
          <>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR d#>>'{validation,status}'<>'VALID'
  THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DYNAMIC_GATE2_DERIVATION_INVALID:%',
      left(d::text,1800);
  END IF;

  h:=public.lf_router_profile_execution_handoff_v1(
    a->'gate2_request',
    d->'gate2_result',
    'PRODUCTO',
    'LF',
    s->'alcance'
  );

  IF h->>'status'<>'READY'
     OR h#>>'{handoff,profile_code}'<>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR h#>>'{handoff,operation_code}'<>'EJECUCION_PERFIL_LF'
     OR coalesce((h#>>'{handoff,profile_execution_allowed}')::boolean,false)
        IS NOT TRUE
     OR coalesce((h->>'downstream_execution_allowed')::boolean,false)
        IS NOT TRUE
  THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DYNAMIC_HANDOFF_INVALID:%',
      left(h::text,2000);
  END IF;

  src:=pg_get_functiondef(
    'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)'::regprocedure
  );

  IF strpos(src,'PRODUCTO_PROFILE_SELECTION_REQUIRED')=0
     OR strpos(src,'lf_profile_selector_semantic_validate_v1')=0
     OR strpos(src,'lf_router_product_profile_after_selection_v1')=0
     OR strpos(src,'lf_router_product_gate2_result_from_selection_v1')=0
     OR strpos(src,'lf_router_profile_execution_after_gate2_v1')=0
     OR strpos(src,'second_model_call_required')=0
     OR strpos(src,$x$v_route->>'paso'<>'PRODUCTO_GATE2_PERFIL'$x$)>0
  THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DYNAMIC_BRIDGE_SOURCE_INVALID';
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
    RAISE EXCEPTION 'PROFILE_NATIVE_DYNAMIC_BRIDGE_ACL_INVALID';
  END IF;
END
$postcheck$;

COMMIT;
