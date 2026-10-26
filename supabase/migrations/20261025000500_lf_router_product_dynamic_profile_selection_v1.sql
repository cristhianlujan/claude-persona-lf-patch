BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_product_profile_after_selection_v1(
  p_stage1 jsonb,
  p_selection_result jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_stage1_validation jsonb;
  v_selection_request jsonb;
  v_selection_validation jsonb;
  v_base jsonb;
  v_decision text;
  v_profile text;
  v_profile_mode text;
  v_rs jsonb;
  v_profile_task_intent text;
  v_profile_ig_requirement text;
  v_profile_action_binding jsonb;
BEGIN
  v_stage1_validation:=public.lf_router_stage1_validate_v2(p_stage1);

  v_base:=jsonb_build_object(
    'schema_version','LF_ROUTER_PRODUCT_PROFILE_AFTER_SELECTION_V1',
    'router','ACT-0001',
    'downstream_execution_allowed',false
  );

  IF coalesce((v_stage1_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_PROFILE_SELECTION_STAGE1_INVALID',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_STAGE1_INVALID',
      'stage1_validation',v_stage1_validation
    );
  END IF;

  IF p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
     OR p_stage1->>'canal_candidato'<>'PRODUCTO'
     OR p_stage1->>'negocio_codigo'<>'LF'
     OR nullif(p_stage1->>'ruta_transversal','') IS NOT NULL
     OR jsonb_array_length(coalesce(p_stage1->'negocios_afectados','[]'::jsonb))<>0
  THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_PROFILE_SELECTION_ROUTE_MISMATCH',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_ROUTE_MISMATCH'
    );
  END IF;

  v_selection_request:=public.lf_profile_selector_semantic_prepare_v1(
    p_stage1->>'texto_original'
  );

  v_selection_validation:=public.lf_profile_selector_semantic_validate_v1(
    v_selection_request,
    p_selection_result
  );

  IF v_selection_validation->>'status'<>'VALID' THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_PROFILE_SELECTION_INVALID',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_INVALID',
      'profile_selection_validation',v_selection_validation
    );
  END IF;

  v_decision:=p_selection_result->>'decision';

  IF v_decision='AMBIGUOUS' THEN
    RETURN v_base||jsonb_build_object(
      'status','WAITING_DECISION',
      'paso','PRODUCTO_PROFILE_SELECTION_AMBIGUOUS',
      'decision','AMBIGUOUS',
      'candidatos',p_selection_result->'ambiguous_profile_codes',
      'material_ambiguities',p_selection_result->'material_ambiguities',
      'reason',p_selection_result->>'reason',
      'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
      'siguiente_paso_es','Resolver la ambiguedad material antes de Gate2.',
      'downstream_execution_allowed',false
    );
  END IF;

  IF v_decision='NO_MATCH' THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_PROFILE_SELECTION_NO_MATCH',
      'decision','NO_MATCH',
      'reason',p_selection_result->>'reason',
      'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
      'siguiente_paso_es','No ejecutar perfil; registrar la brecha de capacidad o revisar el canal.',
      'downstream_execution_allowed',false
    );
  END IF;

  IF v_decision<>'SELECTED'
     OR nullif(btrim(coalesce(p_selection_result->>'selected_profile_code','')),'') IS NULL
  THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_PROFILE_SELECTION_DECISION_INVALID',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_DECISION_INVALID'
    );
  END IF;

  v_profile:=p_selection_result->>'selected_profile_code';

  SELECT a.estado_operativo
    INTO v_profile_mode
  FROM public.lf_activos a
  WHERE a.codigo_activo=v_profile
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
    AND nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
  LIMIT 1;

  IF nullif(v_profile_mode,'') IS NULL THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_PROFILE_SELECTION_PROFILE_NOT_CURRENT',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_PROFILE_NOT_CURRENT',
      'perfil_candidato',v_profile
    );
  END IF;

  v_rs:=public.lf_router_resolve_v1(
    p_stage1->>'texto_original',
    v_profile,
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );

  v_profile_task_intent:=upper(coalesce(p_stage1->>'accion',''));
  v_profile_ig_requirement:=case
    when v_profile_task_intent='READ_PRODUCT_DEFINITION'
      then 'NOT_REQUIRED_CANONICAL_READ'
    else 'REQUIRED_BY_TASK'
  end;

  IF jsonb_typeof(v_rs#>'{semantic_handoff_v2,router_action_binding}')='object' THEN
    v_profile_action_binding:=
      (v_rs#>'{semantic_handoff_v2,router_action_binding}')
      ||jsonb_build_object(
        'profile_task_intent',v_profile_task_intent,
        'input_governance_requirement',v_profile_ig_requirement
      );

    v_profile_action_binding:=v_profile_action_binding||jsonb_build_object(
      'binding_sha256',
      'sha256:'||encode(
        extensions.digest(
          convert_to((v_profile_action_binding-'binding_sha256')::text,'UTF8'),
          'sha256'
        ),
        'hex'
      )
    );

    v_rs:=jsonb_set(
      v_rs,
      '{semantic_handoff_v2,router_action_binding}',
      v_profile_action_binding,
      true
    );
  END IF;

  IF v_rs->>'blocking_code'<>'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED'
     OR v_rs#>>'{semantic_handoff_v2,schema_version}'<>'LF_ROUTER_SEMANTIC_REQUEST_V1'
     OR v_rs#>>'{semantic_handoff_v2,candidate_subjects,0,asset_code}' IS DISTINCT FROM v_profile
  THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_GATE2_NO_LISTO',
      'blocking_code','BLOCK_PRODUCT_PROFILE_GATE2_NOT_READY',
      'perfil_candidato',v_profile,
      'router_resolve',v_rs,
      'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
      'siguiente_paso_es','Bloquear; la seleccion no pudo materializar un Gate2 ligado al perfil elegido.'
    );
  END IF;

  RETURN v_base||jsonb_build_object(
    'status','READY_FOR_GATE2',
    'paso','PRODUCTO_GATE2_PERFIL',
    'perfil_candidato',v_profile,
    'perfil_modo',v_profile_mode,
    'profile_selection_result',p_selection_result,
    'profile_selection_validation',v_selection_validation,
    'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
    'gate2_request',v_rs->'semantic_handoff_v2',
    'gate2_result_contract','LF_ROUTER_SEMANTIC_RESULT_V1',
    'after_gate2_handoff_builder','public.lf_router_profile_execution_handoff_v1',
    'gate2_pass_entrypoint','public.lf_router_profile_execution_after_gate2_v1',
    'siguiente_operacion',jsonb_build_object(
      'operation_code','EJECUCION_PERFIL_LF',
      'entrypoint','GATE2_AUTO_MATERIALIZER',
      'materializer','public.lf_router_profile_execution_after_gate2_v1',
      'context_hydrator','public.lf_profile_execution_channel_context_v1',
      'router_reentry_before_execution',false,
      'return_to_router_after_profile_result',true
    ),
    'motivo_es','La seleccion semantica eligio un perfil del catalogo CURRENT; ACT-0001 prepara Gate2 para ese perfil sin reinterpretar la eleccion.',
    'siguiente_paso_es','Resolver Gate2; solo con PASS materializar EJECUCION_PERFIL_LF.',
    'downstream_execution_allowed',false
  );
END
$function$;

COMMENT ON FUNCTION public.lf_router_product_profile_after_selection_v1(jsonb,jsonb) IS
'Validates a profile-selection semantic result against the current deterministic catalog and prepares Gate2 for the selected profile. It never grants execution authority itself.';

REVOKE ALL ON FUNCTION public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)
  TO service_role, supabase_read_only_user;


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
DECLARE
  v_request jsonb;
  v_consumed jsonb;
  v_out jsonb;
BEGIN
  IF p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
     OR p_stage1->>'canal_candidato'<>'PRODUCTO'
     OR p_stage1->>'negocio_codigo'<>'LF'
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_PROFILE_AFTER_SELECTION_RAW_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_RAW_ROUTE_MISMATCH',
      'downstream_execution_allowed',false
    );
  END IF;

  v_request:=public.lf_profile_selector_semantic_prepare_v1(
    p_stage1->>'texto_original'
  );

  v_consumed:=public.lf_profile_selector_semantic_consume_raw_v1(
    v_request,
    p_raw
  );

  IF v_consumed->>'status'<>'VALID' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_PROFILE_AFTER_SELECTION_RAW_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_PRODUCT_PROFILE_SELECTION_RAW_INVALID',
      'profile_selection_consume',v_consumed,
      'downstream_execution_allowed',false
    );
  END IF;

  v_out:=public.lf_router_product_profile_after_selection_v1(
    p_stage1,
    v_consumed->'result'
  );

  RETURN v_out||jsonb_build_object(
    'profile_selection_consumer_status',v_consumed->>'status',
    'profile_selection_raw_normalized',true
  );
END
$function$;

COMMENT ON FUNCTION public.lf_router_product_profile_after_selection_raw_v1(jsonb,text) IS
'Consumes raw GPT/native profile-selection JSON, validates it against the current catalog, then prepares dynamic Gate2.';

REVOKE ALL ON FUNCTION public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)
  TO service_role, supabase_read_only_user;


DO $patch$
DECLARE
  d text;
  decl_old text;
  decl_new text;
  marker_start text;
  marker_end text;
  block_new text;
  p_start integer;
  p_end integer;
  k integer;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
  );

  decl_old:=$decl$
  v_pc jsonb;
  v_profile_task_intent text;
  v_profile_ig_requirement text;
  v_profile_action_binding jsonb;$decl$;

  decl_new:=$decl$
  v_profile_selection_request jsonb;$decl$;

  k:=(length(d)-length(replace(d,decl_old,'')))/length(decl_old);
  IF k<>1 THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_DECLARATION_DRIFT:%',k;
  END IF;
  d:=replace(d,decl_old,decl_new);

  marker_start:=$m$
    IF v_channel='PRODUCTO' THEN
$m$;
  marker_end:=$m$
    -- If no exact aggregate product context is available, preserve the bounded
$m$;

  p_start:=strpos(d,marker_start);
  p_end:=strpos(d,marker_end);

  IF p_start<=0 OR p_end<=p_start THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_PRODUCT_BLOCK_MARKER_DRIFT:start=% end=%',
      p_start,p_end;
  END IF;

  IF (
    length(d)-length(replace(d,marker_start,''))
  )/length(marker_start)<>1 THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_PRODUCT_BLOCK_NOT_UNIQUE';
  END IF;

  block_new:=$new$
    IF v_channel='PRODUCTO' THEN
      v_profile_selection_request:=
        public.lf_profile_selector_semantic_prepare_v1(
          p_stage1->>'texto_original'
        );

      RETURN v_base||jsonb_build_object(
        'paso','PRODUCTO_PROFILE_SELECTION_REQUIRED',
        'profile_selection_request',v_profile_selection_request,
        'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
        'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
        'profile_selection_resume_entrypoint','public.lf_router_product_profile_after_selection_raw_v1',
        'profile_selection_candidate_count',
          (v_profile_selection_request->>'catalog_profile_count')::integer,
        'gate2_after_profile_selection',true,
        'motivo_es','Producto requiere elegir semanticamente el perfil sobre el catalogo deterministico CURRENT antes de preparar Gate2.',
        'siguiente_paso_es','Ejecutar una sola eleccion semantica sobre el catalogo entregado; validar la salida y solo si SELECTED preparar Gate2.',
        'downstream_execution_allowed',false
      );
    END IF;

$new$;

  d:=substring(d from 1 for p_start-1)
     ||block_new
     ||substring(d from p_end);

  IF strpos(d,'PERFIL-PRODUCT-DIRECTOR-LF')>0 THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_FIXED_PRODUCT_DIRECTOR_REMAINS';
  END IF;

  IF strpos(d,'PRODUCTO_PROFILE_SELECTION_REQUIRED')=0
     OR strpos(d,'lf_profile_selector_semantic_prepare_v1')=0
     OR strpos(d,'lf_router_product_profile_after_selection_raw_v1')=0
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_PATCH_INCOMPLETE';
  END IF;

  EXECUTE d;
END
$patch$;


DO $postcheck$
DECLARE
  s jsonb;
  r jsonb;
  q jsonb;
  f jsonb;
  g jsonb;
  ui_s jsonb;
  ui_r jsonb;
  ui_q jsonb;
  ui_f jsonb;
  ui_g jsonb;
  amb_f jsonb;
  amb_g jsonb;
  nm_f jsonb;
  nm_g jsonb;
  raw_g jsonb;
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

  IF coalesce((public.lf_router_stage1_validate_v2(s)->>'valid')::boolean,false)
     IS NOT TRUE
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_STAGE1_FIXTURE_INVALID:%',
      public.lf_router_stage1_validate_v2(s);
  END IF;

  r:=public.lf_router_route_v1(s);

  IF r->>'paso'<>'PRODUCTO_PROFILE_SELECTION_REQUIRED'
     OR r ? 'perfil_candidato'
     OR r ? 'gate2_request'
     OR r#>>'{profile_selection_request,schema_version}'
          <>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
     OR coalesce((r->>'profile_selection_candidate_count')::integer,0)<>10
     OR coalesce((r->>'downstream_execution_allowed')::boolean,true)
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_ROUTE_POSTCHECK_FAILED:%',
      left(r::text,1800);
  END IF;

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
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_PRODUCT_SELECTION_INVALID:%',
      left(f::text,1600);
  END IF;

  g:=public.lf_router_product_profile_after_selection_v1(
    s,
    f->'result'
  );

  IF g->>'status'<>'READY_FOR_GATE2'
     OR g->>'paso'<>'PRODUCTO_GATE2_PERFIL'
     OR g->>'perfil_candidato'<>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR g#>>'{gate2_request,schema_version}'<>'LF_ROUTER_SEMANTIC_REQUEST_V1'
     OR g#>>'{gate2_request,candidate_subjects,0,asset_code}'
          <>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR g#>>'{gate2_request,router_action_binding,profile_task_intent}'
          <>'READ_PRODUCT_DEFINITION'
     OR g#>>'{gate2_request,router_action_binding,input_governance_requirement}'
          <>'NOT_REQUIRED_CANONICAL_READ'
     OR coalesce((g->>'downstream_execution_allowed')::boolean,true)
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_PRODUCT_GATE2_POSTCHECK_FAILED:%',
      left(g::text,2200);
  END IF;

  raw_g:=public.lf_router_product_profile_after_selection_raw_v1(
    s,
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
    )::text
  );

  IF raw_g->>'status'<>'READY_FOR_GATE2'
     OR raw_g->>'perfil_candidato'<>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR coalesce((raw_g->>'profile_selection_raw_normalized')::boolean,false)
        IS NOT TRUE
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_RAW_RESUME_POSTCHECK_FAILED:%',
      left(raw_g::text,1800);
  END IF;

  ui_s:=jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original','Reorganiza visualmente el login B2B, jerarquia de botones y estados, sin cambiar reglas',
    'downstream_execution_allowed',false,
    'es_operacion',true,
    'ambiguo',false,
    'respuesta_directa',false,
    'sujeto','login B2B',
    'accion','REMEDIATE_UI',
    'formas_busqueda',jsonb_build_array('login B2B','jerarquia visual login B2B'),
    'alternativas','[]'::jsonb,
    'pregunta_usuario',null,
    'capability_hint',null,
    'correcciones','[]'::jsonb,
    'canal_candidato','PRODUCTO',
    'negocio_codigo','LF',
    'negocios_afectados','[]'::jsonb,
    'ruta_transversal',null,
    'razon_seleccion','Cambio de experiencia de producto en una pantalla existente.',
    'alcance',jsonb_build_object(
      'target_type','PANTALLA',
      'target_hint','B2B-AUTH-001',
      'resolution_status','UNRESOLVED'
    )
  );

  ui_r:=public.lf_router_route_v1(ui_s);
  ui_q:=ui_r->'profile_selection_request';

  ui_f:=public.lf_profile_selector_semantic_finalize_v1(
    ui_q,
    jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','PERFIL-UI-ARCHITECT',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Presentation, hierarchy and UI states match UI Architect ownership.',
      'evidence_refs',jsonb_build_array(jsonb_build_object(
        'profile_code','PERFIL-UI-ARCHITECT',
        'kind','PURPOSE',
        'source_section','Purpose'
      )),
      'material_ambiguities','[]'::jsonb
    )
  );

  ui_g:=public.lf_router_product_profile_after_selection_v1(
    ui_s,
    ui_f->'result'
  );

  IF ui_g->>'status'<>'READY_FOR_GATE2'
     OR ui_g->>'perfil_candidato'<>'PERFIL-UI-ARCHITECT'
     OR ui_g#>>'{gate2_request,candidate_subjects,0,asset_code}'
          <>'PERFIL-UI-ARCHITECT'
     OR ui_g#>>'{gate2_request,router_action_binding,profile_task_intent}'
          <>'REMEDIATE_UI'
     OR ui_g#>>'{gate2_request,router_action_binding,input_governance_requirement}'
          <>'REQUIRED_BY_TASK'
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_UI_GATE2_POSTCHECK_FAILED:%',
      left(ui_g::text,2200);
  END IF;

  amb_f:=public.lf_profile_selector_semantic_finalize_v1(
    q,
    jsonb_build_object(
      'decision','AMBIGUOUS',
      'selected_profile_code',null,
      'ambiguous_profile_codes',jsonb_build_array(
        'PERFIL-PRODUCT-DIRECTOR-LF',
        'PERFIL-UI-ARCHITECT'
      ),
      'reason','Fixture preserves a material Product/UI tie.',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object(
          'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
          'kind','PURPOSE',
          'source_section','Purpose'
        ),
        jsonb_build_object(
          'profile_code','PERFIL-UI-ARCHITECT',
          'kind','PURPOSE',
          'source_section','Purpose'
        )
      ),
      'material_ambiguities',jsonb_build_array(
        jsonb_build_object('kind','PRODUCT_VS_UI')
      )
    )
  );

  amb_g:=public.lf_router_product_profile_after_selection_v1(
    s,
    amb_f->'result'
  );

  IF amb_g->>'paso'<>'PRODUCTO_PROFILE_SELECTION_AMBIGUOUS'
     OR amb_g ? 'gate2_request'
     OR coalesce((amb_g->>'downstream_execution_allowed')::boolean,true)
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_AMBIGUOUS_FALSE_GATE2:%',
      left(amb_g::text,1800);
  END IF;

  nm_f:=public.lf_profile_selector_semantic_finalize_v1(
    q,
    jsonb_build_object(
      'decision','NO_MATCH',
      'selected_profile_code',null,
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Fixture has no matching profile.',
      'evidence_refs','[]'::jsonb,
      'material_ambiguities','[]'::jsonb
    )
  );

  nm_g:=public.lf_router_product_profile_after_selection_v1(
    s,
    nm_f->'result'
  );

  IF nm_g->>'paso'<>'PRODUCTO_PROFILE_SELECTION_NO_MATCH'
     OR nm_g ? 'gate2_request'
     OR coalesce((nm_g->>'downstream_execution_allowed')::boolean,true)
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_NO_MATCH_FALSE_GATE2:%',
      left(nm_g::text,1800);
  END IF;

  src:=pg_get_functiondef(
    'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
  );

  IF strpos(src,'PERFIL-PRODUCT-DIRECTOR-LF')>0
     OR strpos(src,'PRODUCTO_PROFILE_SELECTION_REQUIRED')=0
     OR strpos(src,'lf_profile_selector_semantic_prepare_v1')=0
     OR strpos(src,'lf_router_product_profile_after_selection_raw_v1')=0
     OR strpos(src,'v_profile_task_intent')>0
     OR strpos(src,'v_profile_ig_requirement')>0
     OR strpos(src,'v_profile_action_binding')>0
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_ROUTER_SOURCE_CLEANUP_FAILED';
  END IF;

  IF has_function_privilege(
       'anon',
       'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'authenticated',
       'public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_product_profile_after_selection_raw_v1(jsonb,text)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_PROFILE_SELECTOR_ACL_POSTCHECK_FAILED';
  END IF;
END
$postcheck$;

COMMIT;
