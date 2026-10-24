-- ACT-0001: resolve Product subject first, then load its aggregate canonical context.
-- target_type remains a semantic hint/consistency check and never selects a search table.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_product_context_v1(
  p_request_text text,
  p_scope jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','lf_design','extensions'
AS $pc$
DECLARE
  v_rs jsonb;
  v_subject jsonb;
  v_subject_count integer := 0;
  v_app_shell_code text;
  v_module_code text;
  v_screen_code text;
  v_screen_name text;
  v_screen_status text;
  v_screen_version text;
  v_contract_version text;
  v_contract jsonb;
  v_elements jsonb := '[]'::jsonb;
  v_full jsonb;
  v_sections jsonb := '[]'::jsonb;
  v_hint text;
BEGIN
  IF btrim(coalesce(p_request_text,''))='' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status','INVALID_REQUEST',
      'downstream_execution_allowed',false
    );
  END IF;

  v_rs := public.lf_router_resolve_v1(p_request_text);
  v_subject_count := jsonb_array_length(coalesce(v_rs->'subject_candidates','[]'::jsonb));

  IF v_rs->>'subject_binding_state' IS DISTINCT FROM 'RESOLVED'
     OR v_subject_count <> 1 THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status',CASE WHEN v_subject_count>1 THEN 'AMBIGUOUS_SUBJECT' ELSE 'SUBJECT_NOT_RESOLVED' END,
      'router_resolve',jsonb_build_object(
        'status',v_rs->>'status',
        'blocking_code',v_rs->>'blocking_code',
        'subject_binding_state',v_rs->>'subject_binding_state',
        'subject_candidates',coalesce(v_rs->'subject_candidates','[]'::jsonb)
      ),
      'target_type_hint',upper(nullif(coalesce(p_scope->>'target_type',''),'')),
      'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
      'downstream_execution_allowed',false
    );
  END IF;

  v_subject := v_rs->'subject_candidates'->0;
  IF nullif(v_subject->>'screen_code','') IS NULL
     OR nullif(v_subject->>'pantalla_id','') IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status','AGGREGATE_CONTEXT_NOT_AVAILABLE_FOR_SUBJECT',
      'subject',v_subject,
      'target_type_hint',upper(nullif(coalesce(p_scope->>'target_type',''),'')),
      'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
      'downstream_execution_allowed',false
    );
  END IF;

  SELECT s.app_shell_code,m.module_code,p.codigo,p.nombre,p.estado,p.version
    INTO v_app_shell_code,v_module_code,v_screen_code,v_screen_name,v_screen_status,v_screen_version
  FROM lf_ops.pantallas p
  JOIN lf_ops.modulos m ON m.module_id=p.module_id
  JOIN lf_ops.app_shells s ON s.app_shell_id=m.app_shell_id
  WHERE p.id=(v_subject->>'pantalla_id')::integer
    AND p.codigo=v_subject->>'screen_code'
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status','CANONICAL_SUBJECT_NOT_FOUND',
      'subject',v_subject,
      'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
      'downstream_execution_allowed',false
    );
  END IF;

  SELECT sc.contract_version,sc.contract
    INTO v_contract_version,v_contract
  FROM lf_ops.fn_screen_contract_v1(
    v_app_shell_code,v_module_code,v_screen_code
  ) sc
  LIMIT 1;

  IF v_contract IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
      'status','CANONICAL_CONTEXT_NOT_FOUND',
      'subject_ref',v_screen_code,
      'resolved_target_type','PANTALLA',
      'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
      'downstream_execution_allowed',false
    );
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'element_id',e.element_id,
      'element_code',e.element_code,
      'element_role',e.element_role,
      'context_key',e.context_key,
      'label_visible',e.label_visible,
      'component_token_id',e.component_token_id,
      'component_token_code',ct.component_token_code,
      'semantic_binding_status',e.semantic_binding_status,
      'required_for_implementation',e.required_for_implementation,
      'source_refs',e.source_refs,
      'status',e.status
    ) ORDER BY e.element_id),'[]'::jsonb)
    INTO v_elements
  FROM lf_ops.pantalla_elementos e
  LEFT JOIN lf_design.component_tokens ct
    ON ct.component_token_id=e.component_token_id
  WHERE e.pantalla_id=(v_subject->>'pantalla_id')::integer;

  v_full := v_contract || jsonb_build_object('elements',v_elements);
  SELECT coalesce(jsonb_agg(k ORDER BY k),'[]'::jsonb)
    INTO v_sections
  FROM jsonb_object_keys(v_full) k;

  v_hint := upper(nullif(coalesce(p_scope->>'target_type',''),''));

  RETURN jsonb_build_object(
    'schema_version','LF_ROUTER_PRODUCT_CONTEXT_V1',
    'status','RESOLVED',
    'subject_ref',v_screen_code,
    'subject_name',v_screen_name,
    'resolved_target_type','PANTALLA',
    'screen_status',v_screen_status,
    'screen_version',v_screen_version,
    'target_type_hint',v_hint,
    'target_type_authority','HINT_ONLY_NOT_SEARCH_SELECTOR',
    'target_type_hint_consistency',CASE
      WHEN v_hint IS NULL OR v_hint='PANTALLA' THEN 'CONSISTENT'
      ELSE 'MISMATCH_HINT_ONLY'
    END,
    'canonical_context_source',jsonb_build_object(
      'function','lf_ops.fn_screen_contract_v1',
      'app_shell_code',v_app_shell_code,
      'module_code',v_module_code,
      'screen_code',v_screen_code,
      'contract_version',v_contract_version,
      'augmented_with','lf_ops.pantalla_elementos'
    ),
    'context_sections',v_sections,
    'context_summary',jsonb_build_object(
      'elements',jsonb_array_length(coalesce(v_full->'elements','[]'::jsonb)),
      'fields',jsonb_array_length(coalesce(v_full->'fields','[]'::jsonb)),
      'rules',jsonb_array_length(coalesce(v_full->'rules','[]'::jsonb)),
      'errors',jsonb_array_length(coalesce(v_full->'errors','[]'::jsonb)),
      'profiles',jsonb_array_length(coalesce(v_full->'profiles','[]'::jsonb)),
      'analytics',jsonb_array_length(coalesce(v_full->'analytics','[]'::jsonb))
    ),
    'product_context',v_full,
    'downstream_execution_allowed',false
  );
END
$pc$;

REVOKE ALL ON FUNCTION public.lf_router_product_context_v1(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_router_product_context_v1(text,jsonb) TO service_role;

COMMENT ON FUNCTION public.lf_router_product_context_v1(text,jsonb) IS
'ACT-0001 internal read-only Product context loader. Resolves canonical subject first, then loads aggregate screen context. Stage1 target_type is hint/consistency only, never a search selector or authority.';


CREATE OR REPLACE FUNCTION public.lf_router_route_v1(
  p_stage1 jsonb,
  p_caller jsonb DEFAULT '{}'::jsonb,
  p_nivel2_consentido boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog','public'
AS $f$
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
      v_pc := public.lf_router_product_context_v1(
        p_stage1->>'texto_original',
        v_scope
      );

      IF v_pc->>'status'='RESOLVED' THEN
        RETURN v_base || jsonb_build_object(
          'paso','PRODUCTO_CONTEXTO_CANONICO',
          'contexto_producto',v_pc-'product_context',
          'target_type_uso','HINT_ONLY_NOT_SEARCH_SELECTOR',
          'clasificacion_pendiente','WITHIN_CANONICAL_PRODUCT_CONTEXT',
          'context_loader',jsonb_build_object(
            'function','public.lf_router_product_context_v1',
            'read_only',true,
            'contains_full_context',true
          ),
          'motivo_es','Producto resolvio primero el sujeto canonico y su contexto agregado. target_type es una pista de coherencia, no un filtro de busqueda.',
          'siguiente_paso_es','Clasificar el cambio dentro del contexto canonico; actualizar la definicion solo si difiere. Programacion entra despues de currentness y admision.'
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
$f$;

COMMENT ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) IS
'Punto unico Stage2 ACT-0001. PRODUCTO resuelve primero el sujeto y su contexto canonico agregado; target_type es hint/control, no selector de busqueda. PROGRAMACION requiere precheck de definicion vigente; OPERACIONES exige capacidad y alcance autorizados.';

DO $t$
DECLARE
  pc jsonb;
  r_screen jsonb;
  r_rule_hint jsonb;
  submit jsonb;
BEGIN
  pc := public.lf_router_product_context_v1(
    'Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a Acceder, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.',
    '{"target_type":"PANTALLA","target_hint":"Login B2B","resolution_status":"UNRESOLVED"}'::jsonb
  );

  IF pc->>'status' IS DISTINCT FROM 'RESOLVED'
     OR pc->>'subject_ref' IS DISTINCT FROM 'B2B-AUTH-001'
     OR pc->>'resolved_target_type' IS DISTINCT FROM 'PANTALLA'
     OR pc->>'target_type_authority' IS DISTINCT FROM 'HINT_ONLY_NOT_SEARCH_SELECTOR'
     OR pc->>'target_type_hint_consistency' IS DISTINCT FROM 'CONSISTENT' THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_SCREEN_RESOLUTION:%',pc-'product_context';
  END IF;

  SELECT x INTO submit
  FROM jsonb_array_elements(pc#>'{product_context,elements}') x
  WHERE x->>'element_code'='B2B_AUTH001_SUBMIT'
  LIMIT 1;

  IF submit IS NULL OR submit->>'label_visible' IS DISTINCT FROM 'Acceder' THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_ELEMENT_MISSING:%',submit;
  END IF;

  r_screen := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a Acceder, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.",
    "es_operacion":true,"respuesta_directa":false,
    "accion":"cambiar definición visual","sujeto":"botón principal de Iniciar sesión B2B",
    "correcciones":[],"formas_busqueda":["Login B2B","botón principal Acceder"],
    "ambiguo":false,"alternativas":[],"pregunta_usuario":null,"capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PRODUCTO","negocio_codigo":"LF","negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Cambio de definición de producto.",
    "alcance":{"target_type":"PANTALLA","target_hint":"Login B2B","resolution_status":"UNRESOLVED"}
  }'::jsonb);

  r_rule_hint := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a Acceder, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.",
    "es_operacion":true,"respuesta_directa":false,
    "accion":"cambiar definición visual","sujeto":"botón principal de Iniciar sesión B2B",
    "correcciones":[],"formas_busqueda":["Login B2B","botón principal Acceder"],
    "ambiguo":false,"alternativas":[],"pregunta_usuario":null,"capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PRODUCTO","negocio_codigo":"LF","negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Cambio de definición de producto.",
    "alcance":{"target_type":"REGLA","target_hint":"Login B2B","resolution_status":"UNRESOLVED"}
  }'::jsonb);

  IF r_screen->>'paso' IS DISTINCT FROM 'PRODUCTO_CONTEXTO_CANONICO'
     OR r_rule_hint->>'paso' IS DISTINCT FROM 'PRODUCTO_CONTEXTO_CANONICO' THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_ROUTE_NOT_USED:%:%',r_screen,r_rule_hint;
  END IF;

  IF r_screen#>>'{contexto_producto,subject_ref}' IS DISTINCT FROM 'B2B-AUTH-001'
     OR r_rule_hint#>>'{contexto_producto,subject_ref}' IS DISTINCT FROM 'B2B-AUTH-001' THEN
    RAISE EXCEPTION 'TARGET_TYPE_CHANGED_SUBJECT_SEARCH:%:%',r_screen,r_rule_hint;
  END IF;

  IF r_screen#>>'{contexto_producto,target_type_hint_consistency}' IS DISTINCT FROM 'CONSISTENT'
     OR r_rule_hint#>>'{contexto_producto,target_type_hint_consistency}' IS DISTINCT FROM 'MISMATCH_HINT_ONLY' THEN
    RAISE EXCEPTION 'TARGET_TYPE_HINT_SEMANTICS:%:%',r_screen,r_rule_hint;
  END IF;

  IF r_screen ? 'candidatos' OR r_rule_hint ? 'candidatos' THEN
    RAISE EXCEPTION 'BROAD_SEARCH_SHOULD_NOT_COMPETE_AFTER_SUBJECT_RESOLUTION:%:%',r_screen,r_rule_hint;
  END IF;

  IF r_screen#>'{contexto_producto}' ? 'product_context'
     OR r_rule_hint#>'{contexto_producto}' ? 'product_context' THEN
    RAISE EXCEPTION 'FULL_CONTEXT_MUST_NOT_BLOAT_ROUTE_RESPONSE';
  END IF;

  IF (r_screen->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR (r_rule_hint->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'PRODUCT_CONTEXT_EFFECT_AUTHORITY';
  END IF;
END
$t$;

COMMIT;
