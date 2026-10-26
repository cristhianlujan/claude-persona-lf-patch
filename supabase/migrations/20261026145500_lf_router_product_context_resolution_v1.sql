-- ACT-0001: restore canonical Product read before dynamic profile selection.
-- Regression fixed: 20261025000500 replaced the PRODUCTO context-first block with
-- immediate profile selection. This migration preserves dynamic deterministic+semantic
-- profile selection, but only after current canonical Product context is read.
-- No product/runtime mutation is authorized here. Updater/insert remains a separate
-- governed operation and must pass through LF Migration Merge Train.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     )) <> 'b6b5d10fd21912c8303222aea0c98927' THEN
    RAISE EXCEPTION 'LF_ROUTER_PRODUCT_CONTEXT_FIRST_ROUTE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
     )) <> '7e77862c060fba95b58389f410b31902' THEN
    RAISE EXCEPTION 'LF_ROUTER_PRODUCT_CONTEXT_FIRST_AFTER_SELECTION_SOURCE_DRIFT';
  END IF;
END
$precheck$;

-- Read-only audit principal may inspect the canonical Product context.
-- No application role is widened and no write/runtime bridge permission changes.
GRANT EXECUTE ON FUNCTION public.lf_router_product_context_v1(text,jsonb)
  TO supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_router_route_v1(p_stage1 jsonb, p_caller jsonb DEFAULT '{}'::jsonb, p_nivel2_consentido boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_rs jsonb;
  v jsonb;
  v_formas text[];
  v_hint text;
  v_cands jsonb;
  v_n int;
  v_l2 jsonb;
  v_d jsonb;
  v_schema text;
  v_channel text;
  v_business text;
  v_scope jsonb;
  v_transversal text;
  v_is_v2 boolean := false;
  v_base jsonb;
  v_profile_selection_request jsonb;
  v_pc jsonb;
BEGIN
  v_schema := p_stage1->>'schema_version';
  v_is_v2 := v_schema='LF_ROUTER_STAGE1_V2';

  IF v_is_v2 THEN
    v := public.lf_router_stage1_validate_v2(p_stage1);
  ELSE
    v := public.lf_router_stage1_validate_v1(p_stage1);
  END IF;

  v_base := jsonb_build_object(
    'schema_version','LF_ROUTER_ROUTE_V1',
    'router','ACT-0001',
    'stage1_schema_version',v_schema,
    'downstream_execution_allowed',false
  );

  IF (v->>'valid')::boolean IS NOT TRUE THEN
    RETURN v_base || jsonb_build_object(
      'paso',CASE WHEN v_is_v2 THEN 'INVALID_STAGE1_V2' ELSE 'INVALID_STAGE1' END,
      'codigos',v->'codes',
      'motivo_es','La salida de la etapa 1 no cumple el contrato.',
      'siguiente_paso_es','Rehacer la etapa 1 corrigiendo los codigos indicados.'
    );
  END IF;

  IF (p_stage1->>'es_operacion')::boolean IS FALSE THEN
    RETURN v_base || jsonb_build_object(
      'paso','DIRECT_ANSWER',
      'motivo_es','No es una operacion: se responde sin inventario.',
      'siguiente_paso_es','Responder directamente al usuario.'
    );
  END IF;

  IF (p_stage1->>'ambiguo')::boolean IS TRUE THEN
    RETURN v_base || jsonb_build_object(
      'paso','ASK_USER',
      'pregunta_usuario',p_stage1->'pregunta_usuario',
      'alternativas',p_stage1->'alternativas',
      'motivo_es','La solicitud tiene mas de una lectura posible.',
      'siguiente_paso_es','Hacer esa unica pregunta y repetir la etapa 1.'
    );
  END IF;

  IF v_is_v2 THEN
    v_channel := nullif(p_stage1->>'canal_candidato','');
    v_business := nullif(p_stage1->>'negocio_codigo','');
    v_scope := p_stage1->'alcance';
    v_transversal := nullif(p_stage1->>'ruta_transversal','');

    v_base := v_base || jsonb_build_object(
      'canal_candidato',v_channel,
      'negocio_codigo',v_business,
      'alcance',v_scope,
      'ruta_transversal',v_transversal
    );

    IF jsonb_array_length(coalesce(p_stage1->'negocios_afectados','[]'::jsonb))>0 THEN
      RETURN v_base || jsonb_build_object(
        'paso','MULTINEGOCIO_PENDIENTE',
        'negocios_afectados',p_stage1->'negocios_afectados',
        'motivo_es','La fase actual esta cerrada a LF.',
        'siguiente_paso_es','Resolver autoridad por negocio antes de habilitar una ruta transversal.'
      );
    END IF;

    IF v_business IS DISTINCT FROM 'LF' THEN
      RETURN v_base || jsonb_build_object(
        'paso','NEGOCIO_NO_HABILITADO',
        'motivo_es','La fase actual del Router atiende exclusivamente LF.',
        'siguiente_paso_es','No despachar; otros negocios se habilitan en una fase separada.'
      );
    END IF;

    IF v_transversal='GESTION_ACTIVOS_IA' THEN
      v_rs := public.lf_router_resolve_v1(p_stage1->>'texto_original');
      RETURN v_base || jsonb_build_object(
        'paso','RUTA_TRANSVERSAL_GESTION_ACTIVOS_IA',
        'router_resolve',v_rs,
        'motivo_es','Gestionar el propio perfil o skill es una ruta transversal, no un cuarto canal.',
        'siguiente_paso_es','Seguir la operacion gobernada exacta que determine ACT-0001.'
      );
    END IF;

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

    IF v_channel='PRODUCTO' THEN
      -- PRODUCTO must inspect current canonical truth before selecting a worker.
      -- This is read-only and carries no effect authority.
      v_pc:=public.lf_router_product_context_v1(
        p_stage1->>'texto_original',
        v_scope
      );

      IF v_pc->>'status'='RESOLVED' THEN
        v_profile_selection_request:=
          public.lf_profile_selector_semantic_prepare_v1(
            p_stage1->>'texto_original'
          );

        RETURN v_base||jsonb_build_object(
          'paso','PRODUCTO_PROFILE_SELECTION_REQUIRED',
          'product_context_read_before_profile_selection',true,
          'product_context_read',v_pc-'product_context',
          'product_context_mutation_authority',false,
          'profile_selection_request',v_profile_selection_request,
          'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
          'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
          'profile_selection_resume_entrypoint','public.lf_router_product_profile_after_selection_raw_v1',
          'profile_selection_candidate_count',
            (v_profile_selection_request->>'catalog_profile_count')::integer,
          'gate2_after_profile_selection',true,
          'motivo_es','Producto verifico primero la fuente canonica actual; solo despues prepara la seleccion dinamica del perfil en modo sin efectos.',
          'siguiente_paso_es','Seleccionar un perfil sobre el catalogo CURRENT para analizar el contexto en solo lectura. Cualquier updater/insert requiere una operacion gobernada separada y Merge Train.',
          'downstream_execution_allowed',false
        );
      END IF;
    END IF;


    -- If no exact aggregate product context is available, preserve the bounded
    -- canonical search fallback. target_type never narrows the search by itself.
    v_hint := NULL;
  ELSE
    -- Legacy V1 compatibility only. V2 never reads or emits this field.
    IF p_stage1->>'sistema'<>'LF' THEN
      RETURN v_base || jsonb_build_object(
        'paso','SYSTEM_NOT_SUPPORTED',
        'sistema',p_stage1->'sistema',
        'motivo_es','El contrato V1 heredado solo atiende LF.',
        'siguiente_paso_es','Informar al usuario; no despachar.'
      );
    END IF;

    v_hint := nullif(p_stage1->>'capability_hint','');
    IF v_hint IS NOT NULL THEN
      v_d := public.lf_router_dispatch_v1(
        p_stage1->>'texto_original',
        v_hint,
        coalesce(p_caller,'{}'::jsonb)
      );
      RETURN v_base || jsonb_build_object(
        'paso','DISPATCHED',
        'despacho',v_d,
        'motivo_es','Se conserva el despacho del contrato V1 heredado.',
        'siguiente_paso_es','Seguir el resultado del despacho.'
      );
    END IF;
  END IF;

  IF coalesce(p_stage1->>'accion','') ~* '(cambi|modific|actualiz|edit|correg|renombr|update|change|modify|fix|rename)' THEN
    v_rs := public.lf_router_resolve_v1(p_stage1->>'texto_original');
    IF v_rs->>'subject_binding_state'='RESOLVED'
       AND jsonb_array_length(coalesce(v_rs->'executor_candidates','[]'::jsonb))>0
       AND v_rs->>'blocking_code'='BLOCK_EXECUTOR_CAPABILITY_UNATTESTED' THEN
      RETURN v_base || jsonb_build_object(
        'paso','PROPUESTA_PERFIL',
        'sujeto',v_rs->'subject_candidates',
        'perfil_candidato',v_rs#>'{executor_candidates,0}',
        'modo','PROPUESTA_SOLO_LECTURA',
        'instruccion_literal',p_stage1->>'texto_original',
        'router_resolve',jsonb_build_object(
          'status',v_rs->>'status',
          'blocking_code',v_rs->>'blocking_code',
          'semantic_gap_code',v_rs->>'semantic_gap_code',
          'request_sha256',v_rs->>'request_sha256'
        ),
        'siguiente_operacion',jsonb_build_object(
          'operation_code','EJECUCION_PERFIL_LF',
          'entrypoint','ROUTER_ONLY',
          'executor_mode','GPT_NATIVE',
          'read_only',true,
          'no_write',true
        ),
        'motivo_es','El sujeto esta resuelto y el perfil candidato solo puede trabajar en propuesta.',
        'siguiente_paso_es','Trabajar la propuesta y volver al Router para cualquier efecto.'
      );
    END IF;
  END IF;

  SELECT array_agg(e#>>'{}')
  INTO v_formas
  FROM jsonb_array_elements(p_stage1->'formas_busqueda') e;

  SELECT coalesce(
    jsonb_agg(
      x ORDER BY
      (x->>'exacto')::boolean DESC,
      (x->>'cobertura')::numeric DESC,
      (x->>'apariciones')::int DESC,
      (x->>'mejor_posicion')::int ASC,
      x->>'codigo'
    ),
    '[]'::jsonb
  )
  INTO v_cands
  FROM (
    SELECT jsonb_build_object(
      'origen',min(c->>'origen'),
      'codigo',c->>'codigo',
      'tipo',min(c->>'tipo'),
      'titulo',min(c->>'titulo'),
      'exacto',bool_or((c->>'exacto')::boolean),
      'cobertura',round(max((c->>'coinciden')::numeric/nullif((c->>'de')::numeric,0)),2),
      'apariciones',count(*),
      'mejor_posicion',min(pos)
    ) AS x
    FROM unnest(v_formas) f,
         LATERAL jsonb_array_elements(public.lf_router_search_v1(f,5)->'candidatos')
           WITH ORDINALITY AS t(c,pos)
    GROUP BY c->>'codigo'
  ) s;

  v_n := jsonb_array_length(v_cands);
  IF v_n=1 OR (
    v_n>1
    AND (v_cands->0->>'exacto')::boolean IS TRUE
    AND (v_cands->1->>'exacto')::boolean IS NOT TRUE
  ) THEN
    RETURN v_base || jsonb_build_object(
      'paso','CANDIDATO_UNICO',
      'candidatos',jsonb_build_array(v_cands->0),
      'motivo_es','El nivel 1 dio un candidato unico o exacto. Es una pista, no autoridad.',
      'siguiente_paso_es','Confirmar identidad y continuar por la autoridad correspondiente.'
    );
  ELSIF v_n>1 THEN
    RETURN v_base || jsonb_build_object(
      'paso','ELEGIR_O_PROFUNDIZAR',
      'candidatos',v_cands,
      'sondeo_sugerido',jsonb_build_object(
        'leer_juntos',(
          SELECT jsonb_agg(x->>'codigo')
          FROM (SELECT x FROM jsonb_array_elements(v_cands) x LIMIT 3) t
        ),
        'max_sondeos_por_duda',3,
        'cuarto_sondeo_requiere_autorizacion_del_propietario',true,
        'solo_lectura',true
      ),
      'motivo_es','El nivel 1 dio varios candidatos.',
      'siguiente_paso_es','Elegir con evidencia acotada; preguntar solo si persiste ambiguedad material.'
    );
  END IF;

  IF NOT coalesce(p_nivel2_consentido,false) THEN
    RETURN v_base || jsonb_build_object(
      'paso','NIVEL_2_CONSENTIMIENTO',
      'candidatos','[]'::jsonb,
      'pregunta_usuario','Busque en el inventario y no lo encuentro. ¿Busco fuera del inventario (repo y tablas, solo lectura)?',
      'motivo_es','El nivel 1 no dio candidatos.',
      'siguiente_paso_es','Pedir consentimiento antes del nivel 2.'
    );
  END IF;

  SELECT coalesce(
    jsonb_agg(x ORDER BY (x->>'coinciden')::int DESC,x->>'ref'),
    '[]'::jsonb
  )
  INTO v_l2
  FROM (
    SELECT DISTINCT ON (c->>'ref') c AS x
    FROM unnest(v_formas) f,
         LATERAL jsonb_array_elements(public.lf_router_search_nivel2_v1(f,5)->'candidatos') c
    ORDER BY c->>'ref',(c->>'coinciden')::int DESC
  ) d;

  RETURN v_base || jsonb_build_object(
    'paso','NIVEL_2_RESULTADO',
    'resultado',CASE
      WHEN jsonb_array_length(v_l2)>0 THEN 'ENCONTRADO_FUERA_DE_INVENTARIO'
      ELSE 'NO_ENCONTRADO_EN_INDICE'
    END,
    'candidatos',(
      SELECT coalesce(jsonb_agg(x),'[]'::jsonb)
      FROM (SELECT x FROM jsonb_array_elements(v_l2) x LIMIT 5) t
    ),
    'downstream_execution_allowed',false
  );
END
$function$
;

CREATE OR REPLACE FUNCTION public.lf_router_product_profile_after_selection_v1(p_stage1 jsonb, p_selection_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
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
  v_pc jsonb;
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

  -- Re-read canonical Product context before Gate2 so a stale or unresolved
  -- selection can never advance directly to profile execution.
  v_pc:=public.lf_router_product_context_v1(
    p_stage1->>'texto_original',
    p_stage1->'alcance'
  );

  IF v_pc->>'status'<>'RESOLVED' THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_CONTEXT_RECHECK_FAILED',
      'blocking_code','BLOCK_PRODUCT_CONTEXT_NOT_RESOLVED_BEFORE_GATE2',
      'product_context_read_before_gate2',true,
      'product_context_read',v_pc-'product_context',
      'siguiente_paso_es','Resolver nuevamente la fuente canonica en PRODUCTO; no preparar Gate2.',
      'downstream_execution_allowed',false
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
    'product_context_read_before_gate2',true,
    'product_context_read',v_pc-'product_context',
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
$function$
;

COMMENT ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) IS
'Punto unico Stage2 ACT-0001. PRODUCTO lee primero sujeto/contexto canonico vigente y solo despues prepara seleccion dinamica de perfil. Seleccion de perfil no concede efectos. PROGRAMACION requiere definicion vigente; OPERACIONES exige capacidad y alcance autorizados.';

COMMENT ON FUNCTION public.lf_router_product_context_v1(text,jsonb) IS
'ACT-0001 read-only Product context loader. Resolves canonical subject first, then loads aggregate screen context. EXECUTE is allowed to service_role and supabase_read_only_user only; it never grants mutation authority.';

DO $postcheck$
DECLARE
  s jsonb;
  r jsonb;
  pc jsonb;
  submit jsonb;
BEGIN
  s:=jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original','Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.',
    'downstream_execution_allowed',false,
    'es_operacion',true,
    'ambiguo',false,
    'respuesta_directa',false,
    'sujeto','botón principal de la pantalla Iniciar sesión B2B',
    'accion','cambiar texto visible',
    'formas_busqueda',jsonb_build_array(
      'botón principal Iniciar sesión B2B',
      'texto visible botón Login B2B'
    ),
    'alternativas','[]'::jsonb,
    'pregunta_usuario',null,
    'capability_hint',null,
    'correcciones','[]'::jsonb,
    'canal_candidato','PRODUCTO',
    'negocio_codigo','LF',
    'negocios_afectados','[]'::jsonb,
    'ruta_transversal',null,
    'razon_seleccion','La solicitud cambia una definición visible del producto y excluye cambios de autenticación y validaciones.',
    'alcance',jsonb_build_object(
      'target_type','PANTALLA',
      'target_hint','Iniciar sesión B2B',
      'resolution_status','UNRESOLVED'
    )
  );

  pc:=public.lf_router_product_context_v1(
    s->>'texto_original',
    s->'alcance'
  );

  IF pc->>'status' IS DISTINCT FROM 'RESOLVED'
     OR pc->>'subject_ref' IS DISTINCT FROM 'B2B-AUTH-001'
     OR pc->>'screen_version' IS DISTINCT FROM 'v0.5'
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_CANONICAL_READ_FAILED:%',pc-'product_context';
  END IF;

  SELECT x
    INTO submit
  FROM jsonb_array_elements(pc#>'{product_context,elements}') x
  WHERE x->>'element_code'='B2B_AUTH001_SUBMIT'
  LIMIT 1;

  IF submit IS NULL
     OR submit->>'label_visible' IS DISTINCT FROM 'Acceder'
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_LOGIN_LABEL_REGRESSION:%',submit;
  END IF;

  r:=public.lf_router_route_v1(s,'{}'::jsonb,false);

  IF r->>'paso' IS DISTINCT FROM 'PRODUCTO_PROFILE_SELECTION_REQUIRED'
     OR coalesce((r->>'product_context_read_before_profile_selection')::boolean,false) IS NOT TRUE
     OR r#>>'{product_context_read,status}' IS DISTINCT FROM 'RESOLVED'
     OR r#>>'{product_context_read,subject_ref}' IS DISTINCT FROM 'B2B-AUTH-001'
     OR coalesce((r->>'product_context_mutation_authority')::boolean,true) IS NOT FALSE
     OR coalesce((r->>'downstream_execution_allowed')::boolean,true) IS NOT FALSE
     OR jsonb_typeof(r->'profile_selection_request') IS DISTINCT FROM 'object'
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_ROUTE_REGRESSION:%',r;
  END IF;

  IF NOT has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_product_context_v1(text,jsonb)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_READ_ONLY_EXECUTE_MISSING';
  END IF;

  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_profile_execution_after_gate2_v1(jsonb,jsonb,text,text,jsonb,text,text,text)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_EXECUTION_PRIVILEGE_WIDENED';
  END IF;

  IF strpos(
       pg_get_functiondef(
         'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
       ),
       'BLOCK_PRODUCT_CONTEXT_NOT_RESOLVED_BEFORE_GATE2'
     )=0
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_GATE2_RECHECK_MISSING';
  END IF;
END
$postcheck$;

COMMIT;
