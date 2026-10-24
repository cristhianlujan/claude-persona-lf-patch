-- ACT-0001: direct Stage1 V2 Canal/Negocio/Alcance consumption for LF.
-- Source migration in PR #3136. Do not treat this file as applied authority.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_stage1_validate_v2(p_stage1 jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog','public'
AS $f$
DECLARE
  v_codes text[] := '{}';
  v_es_op jsonb;
  v_amb jsonb;
  v_formas jsonb;
  v_alts jsonb;
  v_corr jsonb;
  v_preg jsonb;
  v_hint jsonb;
  v_scope jsonb;
  v_businesses jsonb;
  v_channel text;
  v_business text;
  v_transversal text;
  v_reason text;
  v_scope_state text;
  v_nformas int := 0;
  v_nalts int := 0;
BEGIN
  IF p_stage1 IS NULL OR jsonb_typeof(p_stage1) <> 'object' THEN
    RETURN jsonb_build_object('valid',false,'codes',jsonb_build_array('NOT_AN_OBJECT'));
  END IF;

  IF p_stage1->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_STAGE1_V2' THEN
    v_codes := array_append(v_codes,'BAD_V2_SCHEMA_VERSION');
  END IF;
  IF p_stage1 ? 'sistema' THEN
    v_codes := array_append(v_codes,'CAMPO_LEGACY_SISTEMA_NO_PERMITIDO_EN_V2');
  END IF;
  IF nullif(btrim(coalesce(p_stage1->>'texto_original','')),'') IS NULL THEN
    v_codes := array_append(v_codes,'ORIGINAL_TEXT_REQUIRED');
  END IF;
  IF p_stage1->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
    v_codes := array_append(v_codes,'DOWNSTREAM_EXECUTION_MUST_BE_FALSE');
  END IF;

  v_es_op := p_stage1->'es_operacion';
  v_amb := p_stage1->'ambiguo';
  IF jsonb_typeof(v_es_op) IS DISTINCT FROM 'boolean' THEN
    v_codes := array_append(v_codes,'ES_OPERACION_BOOL_REQUIRED');
  END IF;
  IF jsonb_typeof(v_amb) IS DISTINCT FROM 'boolean' THEN
    v_codes := array_append(v_codes,'AMBIGUO_BOOL_REQUIRED');
  END IF;

  v_formas := coalesce(p_stage1->'formas_busqueda','[]'::jsonb);
  IF jsonb_typeof(v_formas) <> 'array' THEN
    v_codes := array_append(v_codes,'FORMAS_BUSQUEDA_INVALID');
    v_formas := '[]'::jsonb;
  ELSIF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_formas) e
    WHERE jsonb_typeof(e) <> 'string' OR btrim(e#>>'{}')=''
  ) THEN
    v_codes := array_append(v_codes,'FORMAS_BUSQUEDA_INVALID');
    v_formas := '[]'::jsonb;
  END IF;
  v_nformas := jsonb_array_length(v_formas);
  IF v_nformas > 4 THEN v_codes := array_append(v_codes,'TOO_MANY_FORMAS'); END IF;

  v_alts := coalesce(p_stage1->'alternativas','[]'::jsonb);
  IF jsonb_typeof(v_alts) <> 'array' THEN
    v_codes := array_append(v_codes,'ALTERNATIVAS_INVALID');
    v_alts := '[]'::jsonb;
  ELSIF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_alts) e
    WHERE jsonb_typeof(e) <> 'string' OR btrim(e#>>'{}')=''
  ) THEN
    v_codes := array_append(v_codes,'ALTERNATIVAS_INVALID');
    v_alts := '[]'::jsonb;
  END IF;
  v_nalts := jsonb_array_length(v_alts);
  IF v_nalts > 3 THEN v_codes := array_append(v_codes,'TOO_MANY_ALTERNATIVAS'); END IF;

  v_preg := p_stage1->'pregunta_usuario';
  IF v_preg IS NOT NULL AND jsonb_typeof(v_preg) IS DISTINCT FROM 'null' THEN
    IF jsonb_typeof(v_preg) <> 'string' OR btrim(v_preg#>>'{}')='' THEN
      v_codes := array_append(v_codes,'PREGUNTA_INVALID');
    END IF;
  END IF;

  v_hint := p_stage1->'capability_hint';
  IF v_hint IS NOT NULL AND jsonb_typeof(v_hint) IS DISTINCT FROM 'null' THEN
    IF jsonb_typeof(v_hint) <> 'string' OR (v_hint#>>'{}') !~ '^[A-Z][A-Z0-9_]{2,63}$' THEN
      v_codes := array_append(v_codes,'CAPABILITY_HINT_INVALID');
    END IF;
  END IF;

  v_corr := coalesce(p_stage1->'correcciones','[]'::jsonb);
  IF jsonb_typeof(v_corr) <> 'array' THEN
    v_codes := array_append(v_codes,'CORRECCIONES_INVALID');
  ELSIF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_corr) e
    WHERE jsonb_typeof(e)<>'object'
       OR jsonb_typeof(e->'de')<>'string'
       OR jsonb_typeof(e->'a')<>'string'
       OR btrim(e->>'de')=''
       OR btrim(e->>'a')=''
       OR lower(btrim(e->>'de'))=lower(btrim(e->>'a'))
  ) THEN
    v_codes := array_append(v_codes,'CORRECCIONES_INVALID');
  END IF;

  v_channel := nullif(btrim(coalesce(p_stage1->>'canal_candidato','')),'');
  v_business := nullif(btrim(coalesce(p_stage1->>'negocio_codigo','')),'');
  v_transversal := nullif(btrim(coalesce(p_stage1->>'ruta_transversal','')),'');
  v_reason := nullif(btrim(coalesce(p_stage1->>'razon_seleccion','')),'');
  v_scope := p_stage1->'alcance';
  v_businesses := coalesce(p_stage1->'negocios_afectados','[]'::jsonb);

  IF jsonb_typeof(v_businesses) <> 'array' THEN
    v_codes := array_append(v_codes,'NEGOCIOS_AFECTADOS_INVALIDOS');
    v_businesses := '[]'::jsonb;
  ELSE
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_businesses) e
      WHERE jsonb_typeof(e)<>'string' OR (e#>>'{}') !~ '^[A-Z][A-Z0-9_]{1,63}$'
    ) THEN
      v_codes := array_append(v_codes,'NEGOCIOS_AFECTADOS_INVALIDOS');
      v_businesses := '[]'::jsonb;
    ELSIF (
      SELECT count(*) FROM jsonb_array_elements(v_businesses)
    ) <> (
      SELECT count(DISTINCT e#>>'{}') FROM jsonb_array_elements(v_businesses) e
    ) THEN
      v_codes := array_append(v_codes,'NEGOCIOS_AFECTADOS_INVALIDOS');
      v_businesses := '[]'::jsonb;
    END IF;
  END IF;

  IF v_scope IS NOT NULL AND jsonb_typeof(v_scope) IS DISTINCT FROM 'null' THEN
    IF jsonb_typeof(v_scope) <> 'object' THEN
      v_codes := array_append(v_codes,'ALCANCE_INVALID');
    ELSE
      IF coalesce(v_scope->>'target_type','') !~ '^[A-Z][A-Z0-9_]{1,63}$' THEN
        v_codes := array_append(v_codes,'ALCANCE_TIPO_INVALIDO');
      END IF;
      IF v_scope ? 'target_hint'
         AND jsonb_typeof(v_scope->'target_hint') IS DISTINCT FROM 'null'
         AND (jsonb_typeof(v_scope->'target_hint')<>'string' OR btrim(v_scope->>'target_hint')='') THEN
        v_codes := array_append(v_codes,'ALCANCE_PISTA_INVALIDA');
      END IF;
      v_scope_state := coalesce(v_scope->>'resolution_status','UNRESOLVED');
      IF v_scope_state NOT IN ('NOT_REQUIRED','UNRESOLVED','MULTIPLE_MATCHES') THEN
        v_codes := array_append(v_codes,'ALCANCE_ESTADO_NO_PERMITIDO_EN_STAGE1');
      END IF;
      IF nullif(v_scope->>'target_ref','') IS NOT NULL OR v_scope->'verified'='true'::jsonb THEN
        v_codes := array_append(v_codes,'ALCANCE_NO_PUEDE_CERTIFICARSE_EN_STAGE1');
      END IF;
    END IF;
  END IF;

  IF v_es_op='false'::jsonb THEN
    IF p_stage1->'respuesta_directa' IS DISTINCT FROM 'true'::jsonb THEN
      v_codes := array_append(v_codes,'NON_OPERATION_REQUIRES_DIRECT_ANSWER');
    END IF;
    IF v_nformas>0 OR (v_hint IS NOT NULL AND jsonb_typeof(v_hint) IS DISTINCT FROM 'null') THEN
      v_codes := array_append(v_codes,'NON_OPERATION_MUST_NOT_SEARCH');
    END IF;
    IF v_channel IS NOT NULL OR v_business IS NOT NULL OR v_transversal IS NOT NULL THEN
      v_codes := array_append(v_codes,'NO_OPERACION_NO_TIENE_RUTA');
    END IF;
    IF jsonb_array_length(v_businesses)>0 THEN
      v_codes := array_append(v_codes,'NO_OPERACION_NO_TIENE_NEGOCIOS');
    END IF;
    IF v_scope IS NOT NULL AND jsonb_typeof(v_scope) IS DISTINCT FROM 'null' THEN
      v_codes := array_append(v_codes,'NO_OPERACION_NO_TIENE_ALCANCE');
    END IF;
  ELSIF v_es_op='true'::jsonb THEN
    IF p_stage1->'respuesta_directa'='true'::jsonb THEN
      v_codes := array_append(v_codes,'OPERATION_CANNOT_BE_DIRECT_ANSWER');
    END IF;
    IF NOT (
      nullif(btrim(coalesce(p_stage1->>'sujeto','')),'') IS NOT NULL
      OR nullif(btrim(coalesce(p_stage1->>'accion','')),'') IS NOT NULL
    ) THEN
      v_codes := array_append(v_codes,'SUBJECT_OR_ACTION_REQUIRED');
    END IF;
    IF v_nformas=0 THEN v_codes := array_append(v_codes,'FORMAS_BUSQUEDA_REQUIRED'); END IF;

    IF v_transversal IS NOT NULL THEN
      IF v_transversal<>'GESTION_ACTIVOS_IA' OR v_channel IS NOT NULL THEN
        v_codes := array_append(v_codes,'RUTA_TRANSVERSAL_INVALIDA');
      END IF;
    ELSIF v_channel IS NULL OR v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES') THEN
      v_codes := array_append(v_codes,'CANAL_NO_RECONOCIDO');
    END IF;

    IF v_reason IS NULL THEN v_codes := array_append(v_codes,'RAZON_SELECCION_REQUERIDA'); END IF;
    IF v_business IS NULL AND jsonb_array_length(v_businesses)=0 THEN
      v_codes := array_append(v_codes,'NEGOCIO_REQUERIDO_EN_V2');
    END IF;
    IF v_business IS NOT NULL AND v_business !~ '^[A-Z][A-Z0-9_]{1,63}$' THEN
      v_codes := array_append(v_codes,'NEGOCIO_CODIGO_INVALIDO');
    END IF;
    IF jsonb_array_length(v_businesses)>0 AND (v_business IS NOT NULL OR jsonb_array_length(v_businesses)<2) THEN
      v_codes := array_append(v_codes,'MULTINEGOCIO_INCONSISTENTE');
    END IF;
  END IF;

  IF v_amb='true'::jsonb AND NOT (
    v_nalts BETWEEN 2 AND 3
    AND jsonb_typeof(v_preg)='string'
    AND btrim(v_preg#>>'{}')<>''
  ) THEN
    v_codes := array_append(v_codes,'AMBIGUOUS_REQUIRES_ALTERNATIVES_AND_ONE_QUESTION');
  END IF;
  IF v_amb='false'::jsonb AND v_nalts>0 THEN
    v_codes := array_append(v_codes,'ALTERNATIVES_WITHOUT_AMBIGUITY');
  END IF;

  SELECT coalesce(array_agg(DISTINCT c ORDER BY c),'{}') INTO v_codes FROM unnest(v_codes) c;
  RETURN jsonb_build_object('valid',cardinality(v_codes)=0,'codes',to_jsonb(v_codes));
END
$f$;

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
        'paso','PROGRAMACION_ADMISION_REQUERIDA',
        'contrato_entrada','PROGRAMMING_ENTRY_CONTRACT_V1',
        'upstream_requerido','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
        'alcance_requiere_ready',v_scope IS NOT NULL,
        'motivo_es','Programacion requiere definicion vigente, analisis, currentness, alcance READY y admision.',
        'siguiente_paso_es','Completar la admision PG-01 antes de implementar, probar o desplegar.'
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

COMMENT ON FUNCTION public.lf_router_stage1_validate_v2(jsonb) IS
'Valida LF_ROUTER_STAGE1_V2 con canal_candidato, negocio_codigo y alcance. Rechaza el campo legado sistema y nunca concede autoridad.';

COMMENT ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) IS
'Punto unico Stage2 ACT-0001. Conserva V1 y consume Stage1 V2 directamente: PRODUCTO reutiliza resolucion/busqueda; PROGRAMACION exige admision; OPERACIONES exige capacidad y alcance autorizados.';

DO $t$
DECLARE
  r jsonb;
BEGIN
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
  IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_ADMISION_REQUERIDA' THEN
    RAISE EXCEPTION 'V2_PROGRAMACION:%',r;
  END IF;
  IF r ? 'sistema' THEN RAISE EXCEPTION 'V2_SISTEMA_LEAK:%',r; END IF;

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
  IF r->>'paso' IS DISTINCT FROM 'OPERACIONES_CAPACIDAD_REQUERIDA' THEN
    RAISE EXCEPTION 'V2_OPERACIONES:%',r;
  END IF;
  IF r->>'capability_hint_autoridad' IS DISTINCT FROM 'CANDIDATE_ONLY' THEN
    RAISE EXCEPTION 'V2_HINT_AUTHORITY:%',r;
  END IF;

  r := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Consultar una regla vigente de LF",
    "es_operacion":true,
    "respuesta_directa":false,
    "accion":"consultar",
    "sujeto":"regla vigente",
    "correcciones":[],
    "formas_busqueda":["regla vigente"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"PRODUCTO",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Consulta de definicion funcional",
    "alcance":{"target_type":"REGLA","target_hint":"regla vigente","resolution_status":"UNRESOLVED"}
  }'::jsonb);
  IF r->>'canal_candidato' IS DISTINCT FROM 'PRODUCTO'
     OR r->>'negocio_codigo' IS DISTINCT FROM 'LF' THEN
    RAISE EXCEPTION 'V2_PRODUCTO_DIMENSIONS:%',r;
  END IF;
  IF r ? 'sistema' THEN RAISE EXCEPTION 'V2_PRODUCTO_SISTEMA_LEAK:%',r; END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'V2_EFFECT:%',r;
  END IF;

  r := public.lf_router_route_v1('{
    "schema_version":"LF_ROUTER_STAGE1_V2",
    "texto_original":"Consultar oferta en LF",
    "es_operacion":true,
    "respuesta_directa":false,
    "sistema":"LF",
    "accion":"consultar",
    "sujeto":"oferta",
    "correcciones":[],
    "formas_busqueda":["oferta"],
    "ambiguo":false,
    "alternativas":[],
    "pregunta_usuario":null,
    "capability_hint":null,
    "downstream_execution_allowed":false,
    "canal_candidato":"OPERACIONES",
    "negocio_codigo":"LF",
    "negocios_afectados":[],
    "ruta_transversal":null,
    "razon_seleccion":"Consulta existente",
    "alcance":null
  }'::jsonb);
  IF r->>'paso' IS DISTINCT FROM 'INVALID_STAGE1_V2' THEN
    RAISE EXCEPTION 'V2_LEGACY_ACCEPTED:%',r;
  END IF;
  IF NOT (r->'codigos' ? 'CAMPO_LEGACY_SISTEMA_NO_PERMITIDO_EN_V2') THEN
    RAISE EXCEPTION 'V2_LEGACY_CODE_MISSING:%',r;
  END IF;
END
$t$;

COMMIT;
