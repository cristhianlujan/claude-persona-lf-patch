-- ACT-0001: enforce Product definition/currentness before Programming admission.
-- Follow-up to PR #3136. Keeps the single Stage 2 entrypoint and three-channel model.
BEGIN;

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

    -- PRODUCTO reuses the current canonical asset resolution/search path.
    -- A V2 model hint is not enough to dispatch by itself.
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
'Punto unico Stage2 ACT-0001. PRODUCTO define/verifica la fuente canonica; PROGRAMACION requiere precheck de definicion vigente antes de PG-01; OPERACIONES exige capacidad y alcance autorizados.';

DO $t$
DECLARE
  r jsonb;
BEGIN
  -- Technical work cannot advance directly to programming admission until the
  -- canonical product definition/currentness has been checked.
  r := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Corregir el backend del login B2B ya definido",
    "es_operacion":true,
    "respuesta_directa":false,
    "accion":"corregir",
    "sujeto":"backend login B2B",
    "correcciones":[],
    "formas_busqueda":["backend login B2B"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PROGRAMACION",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Correccion tecnica sobre definicion vigente",
    "alcance":{"target_type":"COMPONENTE","target_hint":"backend login B2B","resolution_status":"UNRESOLVED"}
  }'::jsonb);

  IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_PRECHECK_DEFINICION' THEN
    RAISE EXCEPTION 'V2_PROGRAMACION_PRECHECK:%',r;
  END IF;
  IF r->>'si_definicion_falta_o_difiere' IS DISTINCT FROM 'PRODUCTO_PRIMERO' THEN
    RAISE EXCEPTION 'V2_PRODUCTO_PRECEDENCE_MISSING:%',r;
  END IF;
  IF r->>'si_definicion_vigente' IS DISTINCT FROM 'PROGRAMACION_ADMISION_REQUERIDA' THEN
    RAISE EXCEPTION 'V2_PROGRAMACION_CONTINUATION_MISSING:%',r;
  END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'V2_PROGRAMACION_EFFECT:%',r;
  END IF;

  -- A mixed "define and implement" request is not semantic ambiguity:
  -- its first responsible channel is PRODUCTO.
  r := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Crear una nueva regla de ofertas y programarla",
    "es_operacion":true,
    "respuesta_directa":false,
    "accion":"definir e implementar",
    "sujeto":"regla de ofertas",
    "correcciones":[],
    "formas_busqueda":["regla de ofertas"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PRODUCTO",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Solicitud mixta: definicion funcional primero",
    "alcance":{"target_type":"REGLA","target_hint":"regla de ofertas","resolution_status":"UNRESOLVED"}
  }'::jsonb);

  IF r->>'canal_candidato' IS DISTINCT FROM 'PRODUCTO'
     OR r->>'paso'='ASK_USER' THEN
    RAISE EXCEPTION 'V2_MIXED_MUST_START_PRODUCTO:%',r;
  END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'V2_MIXED_EFFECT:%',r;
  END IF;

  -- Operations stays unchanged.
  r := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Consultar el estado de mi oferta en LF",
    "es_operacion":true,
    "respuesta_directa":false,
    "accion":"consultar",
    "sujeto":"oferta",
    "correcciones":[],
    "formas_busqueda":["estado oferta"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":"ESTADO_EN_CURSO",
    "downstream_execution_allowed":false,
    "canal_candidato":"OPERACIONES",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Consulta existente",
    "alcance":{"target_type":"OFERTA","target_hint":"mi oferta","resolution_status":"UNRESOLVED"}
  }'::jsonb);

  IF r->>'paso' IS DISTINCT FROM 'OPERACIONES_CAPACIDAD_REQUERIDA'
     OR r->>'capability_hint_autoridad' IS DISTINCT FROM 'CANDIDATE_ONLY' THEN
    RAISE EXCEPTION 'V2_OPERACIONES_REGRESSION:%',r;
  END IF;
END
$t$;

COMMIT;
