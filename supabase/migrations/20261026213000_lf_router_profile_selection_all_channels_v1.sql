-- ACT-0001 profile administration across PRODUCTO / PROGRAMACION / OPERACIONES.
-- Profiles are transversal resources. Channel-specific preconditions remain mandatory
-- before channel effects, while EJECUCION_PERFIL_LF stays read-only/no-effect.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     )) <> '42828a549c0e4ce15e45c902816fa9ea' THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PROFILE_SELECTION_ROUTE_SOURCE_DRIFT';
  END IF;
END
$precheck$;

CREATE OR REPLACE FUNCTION public.lf_router_profile_after_selection_v1(
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
  v_channel text;
  v_schema text;
  v_channel_precondition jsonb;
BEGIN
  v_stage1_validation:=public.lf_router_stage1_validate_v2(p_stage1);
  v_channel:=upper(coalesce(p_stage1->>'canal_candidato',''));
  v_schema:=case
    when v_channel='PRODUCTO' then 'LF_ROUTER_PRODUCT_PROFILE_AFTER_SELECTION_V1'
    else 'LF_ROUTER_CHANNEL_PROFILE_AFTER_SELECTION_V1'
  end;

  v_base:=jsonb_build_object(
    'schema_version',v_schema,
    'router','ACT-0001',
    'channel',v_channel,
    'downstream_execution_allowed',false
  );

  IF coalesce((v_stage1_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_STAGE1_INVALID',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_SELECTION_STAGE1_INVALID',
      'stage1_validation',v_stage1_validation
    );
  END IF;

  IF p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
     OR v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR p_stage1->>'negocio_codigo'<>'LF'
     OR nullif(p_stage1->>'ruta_transversal','') IS NOT NULL
     OR jsonb_array_length(coalesce(p_stage1->'negocios_afectados','[]'::jsonb))<>0
  THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_ROUTE_MISMATCH',
      'blocking_code','BLOCK_'||coalesce(nullif(v_channel,''),'UNKNOWN')||'_PROFILE_SELECTION_ROUTE_MISMATCH'
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
      'paso',v_channel||'_PROFILE_SELECTION_INVALID',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_SELECTION_INVALID',
      'profile_selection_validation',v_selection_validation
    );
  END IF;

  v_decision:=p_selection_result->>'decision';

  IF v_decision='AMBIGUOUS' THEN
    RETURN v_base||jsonb_build_object(
      'status','WAITING_DECISION',
      'paso',v_channel||'_PROFILE_SELECTION_AMBIGUOUS',
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
      'paso',v_channel||'_PROFILE_SELECTION_NO_MATCH',
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
      'paso',v_channel||'_PROFILE_SELECTION_DECISION_INVALID',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_SELECTION_DECISION_INVALID'
    );
  END IF;

  v_profile:=p_selection_result->>'selected_profile_code';

  SELECT a.estado_operativo
    INTO v_profile_mode
  FROM public.lf_activos a
  JOIN public.lf_profile_selection_registry_v1 r
    ON r.profile_code=a.codigo_activo
   AND r.descriptor_status='CURRENT'
  WHERE a.codigo_activo=v_profile
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
    AND nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
  LIMIT 1;

  IF nullif(v_profile_mode,'') IS NULL THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_PROFILE_NOT_CURRENT',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_SELECTION_PROFILE_NOT_CURRENT',
      'perfil_candidato',v_profile
    );
  END IF;

  v_channel_precondition:=case v_channel
    when 'PRODUCTO' then jsonb_build_object(
      'code','PRODUCTO_PROFILE_ADMINISTRATION',
      'required_before_profile_execution',false,
      'required_before_channel_effect',true,
      'effect_boundary','SEPARATE_GOVERNED_OPERATION'
    )
    when 'PROGRAMACION' then jsonb_build_object(
      'code','PROGRAMACION_PRECHECK_DEFINICION',
      'precondition_required','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
      'if_definition_missing_or_differs','PRODUCTO_PRIMERO',
      'if_definition_current','PROGRAMACION_ADMISION_REQUERIDA',
      'programming_entry_contract','PROGRAMMING_ENTRY_CONTRACT_V1',
      'upstream_required','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
      'required_before_profile_execution',false,
      'required_before_channel_effect',true,
      'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'
    )
    else jsonb_build_object(
      'code','OPERACIONES_CAPACIDAD_REQUERIDA',
      'capability_status_required','ACTIVE',
      'actor_scope_authorization_required',true,
      'required_before_profile_execution',false,
      'required_before_channel_effect',true,
      'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'
    )
  end;

  v_rs:=public.lf_router_resolve_v1(
    p_stage1->>'texto_original',
    v_profile,
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );

  v_profile_task_intent:=upper(coalesce(p_stage1->>'accion',''));
  v_profile_ig_requirement:=case
    when v_channel='PRODUCTO'
      and v_profile_task_intent='READ_PRODUCT_DEFINITION'
      then 'NOT_REQUIRED_CANONICAL_READ'
    else 'REQUIRED_BY_TASK'
  end;

  IF jsonb_typeof(v_rs#>'{semantic_handoff_v2,router_action_binding}')='object' THEN
    v_profile_action_binding:=
      (v_rs#>'{semantic_handoff_v2,router_action_binding}')
      ||jsonb_build_object(
        'profile_task_intent',v_profile_task_intent,
        'input_governance_requirement',v_profile_ig_requirement,
        'channel',v_channel,
        'channel_precondition',v_channel_precondition,
        'channel_effect_authority',false
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
      'paso',v_channel||'_GATE2_NO_LISTO',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_GATE2_NOT_READY',
      'perfil_candidato',v_profile,
      'router_resolve',v_rs,
      'channel_precondition',v_channel_precondition,
      'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
      'siguiente_paso_es','Bloquear; la seleccion no pudo materializar un Gate2 ligado al perfil elegido.'
    );
  END IF;

  RETURN v_base||jsonb_build_object(
    'status','READY_FOR_GATE2',
    'paso',v_channel||'_GATE2_PERFIL',
    'perfil_candidato',v_profile,
    'perfil_modo',v_profile_mode,
    'profile_selection_result',p_selection_result,
    'profile_selection_validation',v_selection_validation,
    'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
    'canonical_investigation_owner','SELECTED_PROFILE_READ_ONLY',
    'profile_context_hydrator','public.lf_profile_execution_channel_context_v1',
    'channel_precondition',v_channel_precondition,
    'channel_precondition_enforcement','BEFORE_CHANNEL_EFFECT_NOT_BEFORE_READ_ONLY_PROFILE_ADMINISTRATION',
    'gate2_request',v_rs->'semantic_handoff_v2',
    'gate2_result_contract','LF_ROUTER_SEMANTIC_RESULT_V1',
    'gate2_result_deriver','public.lf_router_profile_gate2_result_from_selection_v1',
    'after_gate2_handoff_builder','public.lf_router_profile_execution_handoff_v1',
    'gate2_pass_entrypoint','public.lf_router_profile_execution_after_gate2_v1',
    'siguiente_operacion',jsonb_build_object(
      'operation_code','EJECUCION_PERFIL_LF',
      'entrypoint','GATE2_AUTO_MATERIALIZER',
      'materializer','public.lf_router_profile_execution_after_gate2_v1',
      'context_hydrator','public.lf_profile_execution_channel_context_v1',
      'router_reentry_before_execution',false,
      'return_to_router_after_profile_result',true,
      'effect_authority',false
    ),
    'motivo_es','La seleccion semantica eligio un perfil CURRENT para administrar el canal en solo lectura; las precondiciones del canal siguen siendo obligatorias antes de cualquier efecto.',
    'siguiente_paso_es','Resolver Gate2 para EJECUCION_PERFIL_LF; cualquier efecto posterior debe satisfacer la precondicion del canal y su operacion gobernada.',
    'downstream_execution_allowed',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_profile_after_selection_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_after_selection_v1(jsonb,jsonb)
  TO service_role,supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_router_profile_after_selection_raw_v1(
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
  v_channel text:=upper(coalesce(p_stage1->>'canal_candidato',''));
BEGIN
  IF p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
     OR v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR p_stage1->>'negocio_codigo'<>'LF'
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PROFILE_AFTER_SELECTION_RAW_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_SELECTION_RAW_ROUTE_MISMATCH',
      'channel',v_channel,
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
      'schema_version','LF_ROUTER_PROFILE_AFTER_SELECTION_RAW_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_SELECTION_RAW_INVALID',
      'channel',v_channel,
      'profile_selection_consume',v_consumed,
      'downstream_execution_allowed',false
    );
  END IF;

  v_out:=public.lf_router_profile_after_selection_v1(
    p_stage1,
    v_consumed->'result'
  );

  RETURN v_out||jsonb_build_object(
    'profile_selection_consumer_status',v_consumed->>'status',
    'profile_selection_raw_normalized',true
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_profile_after_selection_raw_v1(jsonb,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_after_selection_raw_v1(jsonb,text)
  TO service_role,supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(
  p_gate2_request jsonb,
  p_profile_selection_result jsonb
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
  SELECT public.lf_router_product_gate2_result_from_selection_v1(
    p_gate2_request,
    p_profile_selection_result
  )
$function$;

REVOKE ALL ON FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb)
  TO service_role,supabase_read_only_user;

DO $patch_route$
DECLARE
  d text;
  old_programming text := $old$
    IF v_channel='PROGRAMACION' THEN
      RETURN v_base || jsonb_build_object(
        'paso','PROGRAMACION_PRECHECK_DEFINICION',
        'precondicion_requerida','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
        'si_definicion_falta_o_difiere','PRODUCTO_PRIMERO',
        'si_definicion_vigente','PROGRAMACION_ADMISION_REQUERIDA',
        'contrato_entrada_despues_precheck','PROGRAMMING_ENTRY_CONTRACT_V1',
        'upstream_requerido_despues_precheck','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
        'alcance_requiere_ready',v_scope IS NOT NULL,
        'motivo_es','Antes de Programacion se verifica la definicion funcional canonica. Si falta o difiere, Producto la corrige primero; si coincide, continua la admision tecnica.',
        'siguiente_paso_es','Verificar la fuente canonica y su currentness; solo con definicion vigente continuar a PG-01.'
      );
    END IF;
$old$;
  new_programming text := $new$
    IF v_channel='PROGRAMACION' THEN
      v_profile_selection_request:=
        public.lf_profile_selector_semantic_prepare_v1(
          p_stage1->>'texto_original'
        );

      RETURN v_base || jsonb_build_object(
        'paso','PROGRAMACION_PROFILE_SELECTION_REQUIRED',
        'router_work_mode','DERIVATION_ONLY',
        'channel_precondition',jsonb_build_object(
          'code','PROGRAMACION_PRECHECK_DEFINICION',
          'precondicion_requerida','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
          'si_definicion_falta_o_difiere','PRODUCTO_PRIMERO',
          'si_definicion_vigente','PROGRAMACION_ADMISION_REQUERIDA',
          'contrato_entrada_despues_precheck','PROGRAMMING_ENTRY_CONTRACT_V1',
          'upstream_requerido_despues_precheck','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
          'alcance_requiere_ready',v_scope IS NOT NULL,
          'required_before_channel_effect',true,
          'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'
        ),
        'canonical_investigation_owner','SELECTED_PROFILE_READ_ONLY',
        'profile_context_hydrator','public.lf_profile_execution_channel_context_v1',
        'profile_selection_request',v_profile_selection_request,
        'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
        'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
        'profile_selection_resume_entrypoint','public.lf_router_profile_after_selection_raw_v1',
        'profile_selection_candidate_count',
          (v_profile_selection_request->>'catalog_profile_count')::integer,
        'gate2_after_profile_selection',true,
        'gate2_authorizes_profile_effects',false,
        'motivo_es','Programacion se administra por perfiles. El perfil puede investigar en solo lectura; definicion/currentness y PG-01 siguen siendo obligatorios antes de cualquier efecto tecnico.',
        'siguiente_paso_es','Seleccionar perfil CURRENT, resolver Gate2 para administracion READ_ONLY y exigir la precondicion de Programacion antes de implementar/probar/desplegar.',
        'downstream_execution_allowed',false
      );
    END IF;
$new$;
  old_operations text := $old$
    IF v_channel='OPERACIONES' THEN
      RETURN v_base || jsonb_build_object(
        'paso','OPERACIONES_CAPACIDAD_REQUERIDA',
        'capability_hint_candidato',nullif(p_stage1->>'capability_hint',''),
        'capability_hint_autoridad','CANDIDATE_ONLY',
        'alcance_requiere_autorizacion',v_scope IS NOT NULL,
        'motivo_es','Operaciones solo usa capacidades existentes y autorizadas para actor y alcance.',
        'siguiente_paso_es','Resolver una capacidad ACTIVE y su identidad/tenant/alcance; si no existe, devolver brecha.'
      );
    END IF;
$old$;
  new_operations text := $new$
    IF v_channel='OPERACIONES' THEN
      v_profile_selection_request:=
        public.lf_profile_selector_semantic_prepare_v1(
          p_stage1->>'texto_original'
        );

      RETURN v_base || jsonb_build_object(
        'paso','OPERACIONES_PROFILE_SELECTION_REQUIRED',
        'router_work_mode','DERIVATION_ONLY',
        'channel_precondition',jsonb_build_object(
          'code','OPERACIONES_CAPACIDAD_REQUERIDA',
          'capability_hint_candidato',nullif(p_stage1->>'capability_hint',''),
          'capability_hint_autoridad','CANDIDATE_ONLY',
          'alcance_requiere_autorizacion',v_scope IS NOT NULL,
          'capability_status_required','ACTIVE',
          'actor_scope_authorization_required',true,
          'required_before_channel_effect',true,
          'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'
        ),
        'canonical_investigation_owner','SELECTED_PROFILE_READ_ONLY',
        'profile_context_hydrator','public.lf_profile_execution_channel_context_v1',
        'profile_selection_request',v_profile_selection_request,
        'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
        'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
        'profile_selection_resume_entrypoint','public.lf_router_profile_after_selection_raw_v1',
        'profile_selection_candidate_count',
          (v_profile_selection_request->>'catalog_profile_count')::integer,
        'gate2_after_profile_selection',true,
        'gate2_authorizes_profile_effects',false,
        'motivo_es','Operaciones se administra por perfiles. Gate2 autoriza solo la investigacion del perfil; la capacidad ACTIVE y el alcance del actor siguen siendo obligatorios antes de ejecutar una operacion.',
        'siguiente_paso_es','Seleccionar perfil CURRENT y resolver Gate2 READ_ONLY; cualquier efecto operativo exige capacidad/actor/alcance autorizados.',
        'downstream_execution_allowed',false
      );
    END IF;
$new$;
  old_product_resume text :=
    '''profile_selection_resume_entrypoint'',''public.lf_router_product_profile_after_selection_raw_v1''';
  new_product_resume text :=
    '''profile_selection_resume_entrypoint'',''public.lf_router_profile_after_selection_raw_v1''';
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_programming,'')))/length(old_programming)<>1 THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PROGRAMMING_ANCHOR_DRIFT';
  END IF;
  IF (length(d)-length(replace(d,old_operations,'')))/length(old_operations)<>1 THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_OPERATIONS_ANCHOR_DRIFT';
  END IF;
  IF (length(d)-length(replace(d,old_product_resume,'')))/length(old_product_resume)<>1 THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PRODUCT_RESUME_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_programming,new_programming);
  d:=replace(d,old_operations,new_operations);
  d:=replace(d,old_product_resume,new_product_resume);
  EXECUTE d;
END
$patch_route$;

COMMENT ON FUNCTION public.lf_router_profile_after_selection_v1(jsonb,jsonb) IS
'Common ACT-0001 profile-selection continuation for PRODUCTO, PROGRAMACION and OPERACIONES. Profiles are transversal administrators; Gate2 authorizes EJECUCION_PERFIL_LF without channel effect authority. Channel-specific effect preconditions travel in the signed router action binding.';

COMMENT ON FUNCTION public.lf_router_profile_after_selection_raw_v1(jsonb,text) IS
'Common raw semantic-selection consumer for all three LF channels. It reuses the canonical profile catalog and semantic consumer, then continues to Gate2 without granting channel effects.';

COMMENT ON FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(jsonb,jsonb) IS
'Channel-neutral alias for deterministic Gate2 derivation from a validated profile selection.';

DO $postcheck$
DECLARE
  s_product jsonb := '{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Analiza la definicion funcional del Login B2B sin cambiar nada.",
    "es_operacion":true,
    "respuesta_directa":false,
    "accion":"analizar definicion funcional",
    "sujeto":"Login B2B",
    "correcciones":[],
    "formas_busqueda":["B2B-AUTH-001"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PRODUCTO",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Revision funcional",
    "alcance":{"target_type":"PANTALLA","target_hint":"B2B-AUTH-001","resolution_status":"UNRESOLVED"}
  }'::jsonb;
  s_program jsonb := '{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Analiza tecnicamente como implementar el Login B2B ya definido, sin ejecutar cambios.",
    "es_operacion":true,
    "respuesta_directa":false,
    "accion":"analizar implementacion tecnica",
    "sujeto":"Login B2B",
    "correcciones":[],
    "formas_busqueda":["B2B-AUTH-001 implementacion"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PROGRAMACION",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Analisis tecnico sin efecto",
    "alcance":{"target_type":"PANTALLA","target_hint":"B2B-AUTH-001","resolution_status":"UNRESOLVED"}
  }'::jsonb;
  s_ops jsonb := '{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Consulta el estado operativo del Login B2B sin modificar nada.",
    "es_operacion":true,
    "respuesta_directa":false,
    "accion":"consultar estado operativo",
    "sujeto":"Login B2B",
    "correcciones":[],
    "formas_busqueda":["B2B-AUTH-001 estado operativo"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"OPERACIONES",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Consulta sobre funcionalidad existente",
    "alcance":{"target_type":"PANTALLA","target_hint":"B2B-AUTH-001","resolution_status":"UNRESOLVED"}
  }'::jsonb;
  r_product jsonb;
  r_program jsonb;
  r_ops jsonb;
  req jsonb;
  ev jsonb;
  finalized jsonb;
  selected jsonb;
  after_program jsonb;
  gate2 jsonb;
  handoff jsonb;
BEGIN
  r_product:=public.lf_router_route_v1(s_product);
  r_program:=public.lf_router_route_v1(s_program);
  r_ops:=public.lf_router_route_v1(s_ops);

  IF r_product->>'paso' IS DISTINCT FROM 'PRODUCTO_PROFILE_SELECTION_REQUIRED'
     OR r_product->>'profile_selection_resume_entrypoint'
        IS DISTINCT FROM 'public.lf_router_profile_after_selection_raw_v1'
  THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PRODUCT_ROUTE_FAIL:%',r_product;
  END IF;

  IF r_program->>'paso' IS DISTINCT FROM 'PROGRAMACION_PROFILE_SELECTION_REQUIRED'
     OR r_program#>>'{channel_precondition,code}'
        IS DISTINCT FROM 'PROGRAMACION_PRECHECK_DEFINICION'
     OR r_program#>>'{channel_precondition,contrato_entrada_despues_precheck}'
        IS DISTINCT FROM 'PROGRAMMING_ENTRY_CONTRACT_V1'
     OR coalesce((r_program->>'profile_selection_candidate_count')::integer,0)<=0
     OR coalesce((r_program->>'gate2_authorizes_profile_effects')::boolean,true) IS TRUE
  THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PROGRAM_ROUTE_FAIL:%',r_program;
  END IF;

  IF r_ops->>'paso' IS DISTINCT FROM 'OPERACIONES_PROFILE_SELECTION_REQUIRED'
     OR r_ops#>>'{channel_precondition,code}'
        IS DISTINCT FROM 'OPERACIONES_CAPACIDAD_REQUERIDA'
     OR coalesce((r_ops->>'profile_selection_candidate_count')::integer,0)<=0
     OR coalesce((r_ops->>'gate2_authorizes_profile_effects')::boolean,true) IS TRUE
  THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_OPS_ROUTE_FAIL:%',r_ops;
  END IF;

  IF r_product->>'profile_selection_candidate_count'
       IS DISTINCT FROM r_program->>'profile_selection_candidate_count'
     OR r_product->>'profile_selection_candidate_count'
       IS DISTINCT FROM r_ops->>'profile_selection_candidate_count'
  THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_CATALOG_CARDINALITY_DRIFT';
  END IF;

  req:=public.lf_profile_selector_semantic_prepare_v1(
    s_program->>'texto_original'
  );

  SELECT e.item INTO ev
  FROM jsonb_array_elements(req->'candidate_profiles') p(profile),
       LATERAL jsonb_array_elements(p.profile#>'{descriptor,selection_evidence}') e(item)
  WHERE p.profile->>'profile_code'='PERFIL-PRODUCT-DIRECTOR-LF'
  ORDER BY e.item->>'kind',e.item->>'source_section'
  LIMIT 1;

  IF ev IS NULL THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_TEST_PROFILE_EVIDENCE_MISSING';
  END IF;

  finalized:=public.lf_profile_selector_semantic_finalize_v1(
    req,
    jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Mechanical all-channel integration postcheck using one CURRENT catalog profile.',
      'evidence_refs',jsonb_build_array(jsonb_build_object(
        'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
        'kind',ev->>'kind',
        'source_section',ev->>'source_section'
      )),
      'material_ambiguities','[]'::jsonb
    )
  );

  IF finalized->>'status'<>'VALID' THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_SELECTION_FINALIZE_FAIL:%',finalized;
  END IF;

  selected:=finalized->'result';
  after_program:=public.lf_router_profile_after_selection_v1(
    s_program,
    selected
  );

  IF after_program->>'status'<>'READY_FOR_GATE2'
     OR after_program->>'channel'<>'PROGRAMACION'
     OR after_program#>>'{channel_precondition,code}'
        IS DISTINCT FROM 'PROGRAMACION_PRECHECK_DEFINICION'
     OR after_program#>>'{gate2_request,router_action_binding,channel}'
        IS DISTINCT FROM 'PROGRAMACION'
     OR after_program#>>'{gate2_request,router_action_binding,channel_precondition,code}'
        IS DISTINCT FROM 'PROGRAMACION_PRECHECK_DEFINICION'
     OR coalesce((after_program->>'downstream_execution_allowed')::boolean,true) IS TRUE
  THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PROGRAM_AFTER_SELECTION_FAIL:%',after_program;
  END IF;

  gate2:=public.lf_router_profile_gate2_result_from_selection_v1(
    after_program->'gate2_request',
    selected
  );

  IF gate2->>'status'<>'READY'
     OR gate2#>>'{validation,status}'<>'VALID'
  THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PROGRAM_GATE2_FAIL:%',gate2;
  END IF;

  handoff:=public.lf_router_profile_execution_handoff_v1(
    after_program->'gate2_request',
    gate2->'gate2_result',
    'PROGRAMACION',
    'LF',
    s_program->'alcance'
  );

  IF handoff->>'status'<>'READY'
     OR handoff#>>'{handoff,channel}'<>'PROGRAMACION'
     OR coalesce((handoff#>>'{handoff,effect_authority}')::boolean,true) IS TRUE
     OR handoff#>>'{handoff,semantic_request,router_action_binding,channel_precondition,code}'
        IS DISTINCT FROM 'PROGRAMACION_PRECHECK_DEFINICION'
  THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PROGRAM_HANDOFF_FAIL:%',handoff;
  END IF;

  IF strpos(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     ),'''PROGRAMACION_PRECHECK_DEFINICION''')=0
     OR strpos(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     ),'''OPERACIONES_CAPACIDAD_REQUERIDA''')=0
  THEN
    RAISE EXCEPTION 'ROUTER_ALL_CHANNEL_PRECONDITION_GUARDS_REMOVED';
  END IF;
END
$postcheck$;

COMMIT;
