-- LF Router ACT-0001: retorno de un perfil/worker al Router ("llego hasta aqui"), sin reglas por caso y sin que un perfil llame a otro.
-- Hallazgo (caso boton de login B2B): el perfil no tenia como decir "encontre el elemento, pero este dato no existe y debe verlo otro";
-- RETURN_TO_ORCHESTRATOR llega al agente, no al Router. Politica POL-LF-ACTIVATION-ROUTING: los perfiles solo se activan por el Router.
-- lf_router_worker_return_v1(retorno jsonb): valida el informe (LF_ROUTER_WORKER_RETURN_V1) y busca destino con la busqueda de nivel 1 existente,
-- considerando solo activos que pueden trabajar (PERFIL, SKILL, ADAPTER, OPERATION_CODE, CAPABILITY, STRATEGY), nunca reglas.
-- No ejecuta nada, no escribe, downstream_execution_allowed=false; maximo un retorno por solicitud. Aplica solo por ACTUALIZACION_DB_LF / Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_worker_return_v1(p_return jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog','public'
AS $f$
DECLARE
  v_codes text[] := ARRAY[]::text[];
  v_base jsonb := jsonb_build_object('schema_version','LF_ROUTER_WORKER_RETURN_RESULT_V1','router','ACT-0001','downstream_execution_allowed',false);
  v_formas text[]; v_cands jsonb; v_n int; v_informe jsonb; v_n_ret int;
  v_ejecutores constant text[] := ARRAY['PERFIL','SKILL','ADAPTER','OPERATION_CODE','CAPABILITY','STRATEGY'];
BEGIN
  IF p_return IS NULL OR jsonb_typeof(p_return) <> 'object' THEN
    RETURN v_base || jsonb_build_object('paso','RETORNO_INVALIDO','codigos',jsonb_build_array('NOT_AN_OBJECT'),
      'siguiente_paso_es','Rehacer el informe con el contrato LF_ROUTER_WORKER_RETURN_V1.');
  END IF;
  IF p_return->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_WORKER_RETURN_V1' THEN v_codes := array_append(v_codes,'SCHEMA_VERSION'); END IF;
  IF coalesce(p_return->>'perfil','') !~ '^[A-Z][A-Z0-9_-]{2,79}$' THEN v_codes := array_append(v_codes,'PERFIL_INVALIDO'); END IF;
  IF btrim(coalesce(p_return->>'solicitud_literal','')) = '' THEN v_codes := array_append(v_codes,'SOLICITUD_LITERAL_VACIA'); END IF;
  IF btrim(coalesce(p_return->>'hasta_donde_llegue','')) = '' THEN v_codes := array_append(v_codes,'HASTA_DONDE_LLEGUE_VACIO'); END IF;
  IF coalesce(p_return->>'causa','') NOT IN ('DATO_FALTANTE','ENRUTAMIENTO_INCORRECTO','FUERA_DE_MI_ALCANCE') THEN v_codes := array_append(v_codes,'CAUSA_INVALIDA'); END IF;
  IF jsonb_typeof(p_return->'lo_que_encontre') IS DISTINCT FROM 'array' THEN v_codes := array_append(v_codes,'LO_QUE_ENCONTRE_NO_ES_LISTA'); END IF;
  IF jsonb_typeof(p_return->'lo_que_no_existe') IS DISTINCT FROM 'array' THEN v_codes := array_append(v_codes,'LO_QUE_NO_EXISTE_NO_ES_LISTA'); END IF;
  IF jsonb_typeof(p_return->'buscar_destino') IS DISTINCT FROM 'array'
     OR jsonb_array_length(coalesce(p_return->'buscar_destino','[]'::jsonb)) NOT BETWEEN 1 AND 4
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_return->'buscar_destino','[]'::jsonb)) e
                 WHERE jsonb_typeof(e) <> 'string' OR btrim(e#>>'{}') = '' OR length(e#>>'{}') > 200) THEN
    v_codes := array_append(v_codes,'BUSCAR_DESTINO_INVALIDO'); END IF;
  IF (p_return->>'downstream_execution_allowed') IS DISTINCT FROM 'false' THEN v_codes := array_append(v_codes,'DOWNSTREAM_EXECUTION_MUST_BE_FALSE'); END IF;
  IF p_return ? 'retorno_numero' AND (jsonb_typeof(p_return->'retorno_numero') <> 'number' OR (p_return->>'retorno_numero')::numeric < 1) THEN
    v_codes := array_append(v_codes,'RETORNO_NUMERO_INVALIDO'); END IF;

  IF array_length(v_codes,1) > 0 THEN
    RETURN v_base || jsonb_build_object('paso','RETORNO_INVALIDO','codigos',to_jsonb(v_codes),
      'siguiente_paso_es','Rehacer el informe corrigiendo los codigos indicados.');
  END IF;

  v_informe := jsonb_build_object('perfil',p_return->>'perfil','solicitud_literal',p_return->>'solicitud_literal',
    'hasta_donde_llegue',p_return->>'hasta_donde_llegue','lo_que_encontre',p_return->'lo_que_encontre',
    'lo_que_no_existe',p_return->'lo_que_no_existe','causa',p_return->>'causa');
  v_n_ret := coalesce((p_return->>'retorno_numero')::numeric,1)::int;

  IF v_n_ret > 1 THEN
    RETURN v_base || jsonb_build_object('paso','RETORNO_EXCEDIDO','informe',v_informe,
      'pregunta_usuario','Ya hubo un retorno para esta solicitud y el Router no encontro un destino que lo resuelva. ¿Quien deberia revisar esto: '||coalesce(p_return->>'quien_deberia_verlo','indicalo con tus palabras')||'?',
      'motivo_es','Se permite un solo retorno por solicitud para evitar ciclos.',
      'siguiente_paso_es','Hacer esa unica pregunta al usuario.');
  END IF;

  SELECT array_agg(e#>>'{}') INTO v_formas FROM jsonb_array_elements(p_return->'buscar_destino') e;

  SELECT coalesce(jsonb_agg(x ORDER BY (x->>'cobertura')::numeric DESC, (x->>'apariciones')::int DESC, (x->>'mejor_posicion')::int ASC, x->>'codigo'),'[]'::jsonb)
    INTO v_cands
    FROM (
      SELECT jsonb_build_object('codigo',c->>'codigo','tipo',min(c->>'tipo'),'titulo',min(c->>'titulo'),
               'cobertura',round(max((c->>'coinciden')::numeric/nullif((c->>'de')::numeric,0)),2),
               'apariciones',count(*),'mejor_posicion',min(pos)) AS x
        FROM unnest(v_formas) f,
             LATERAL jsonb_array_elements(public.lf_router_search_v1(f,10)->'candidatos') WITH ORDINALITY AS t(c,pos)
       WHERE upper(c->>'tipo') = ANY (v_ejecutores)
       GROUP BY c->>'codigo'
    ) s;
  v_n := jsonb_array_length(v_cands);

  IF v_n = 0 THEN
    RETURN v_base || jsonb_build_object('paso','RETORNO_SIN_DESTINO','informe',v_informe,'candidatos','[]'::jsonb,
      'hueco_inventario_sugerido',true,
      'pregunta_usuario','El perfil '||(p_return->>'perfil')||' llego hasta aqui y el Router no encontro un perfil, skill u operacion que se encargue de: '||coalesce(p_return->>'quien_deberia_verlo','lo que falta')||'. ¿Quien deberia revisarlo?',
      'motivo_es','No hay en el inventario un activo que pueda trabajar esto (las reglas no cuentan como destino). El informe del perfil se conserva tal cual.',
      'siguiente_paso_es','Mostrar al usuario el informe (lo encontrado y lo que no existe) y hacer esa unica pregunta; registrar el hueco del inventario.');
  END IF;

  RETURN v_base || jsonb_build_object('paso','RETORNO_ENRUTADO','informe',v_informe,
    'candidatos',(SELECT jsonb_agg(x) FROM (SELECT x FROM jsonb_array_elements(v_cands) x LIMIT 3) t),
    'motivo_es','El perfil llego hasta aqui; estos activos pueden trabajar lo que falta. Son pistas del nivel 1, no una decision ni un permiso.',
    'siguiente_paso_es','Quien decide elige uno y vuelve a entrar por el Router (etapa 1 y etapa 2) con el informe como contexto; si hay duda, una sola pregunta al usuario.');
END
$f$;

REVOKE ALL ON FUNCTION public.lf_router_worker_return_v1(jsonb) FROM PUBLIC;
DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_router_worker_return_v1(jsonb) FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_router_worker_return_v1(jsonb) TO %I',v_role); END IF;
  END LOOP;
END
$g$;

COMMENT ON FUNCTION public.lf_router_worker_return_v1(jsonb) IS
'Retorno de un perfil/worker al Router ACT-0001 (contrato LF_ROUTER_WORKER_RETURN_V1): el perfil informa hasta donde llego, lo que encontro, lo que no existe, la causa (DATO_FALTANTE | ENRUTAMIENTO_INCORRECTO | FUERA_DE_MI_ALCANCE) y frases para buscar destino. El Router valida y propone destino (solo PERFIL/SKILL/ADAPTER/OPERATION_CODE/CAPABILITY/STRATEGY, nunca reglas) o RETORNO_SIN_DESTINO con una pregunta. Un retorno por solicitud. No ejecuta ni escribe. Manual: docs/programming-agent/LF_ROUTER_FLOW_V1.md.';

DO $t$
DECLARE r jsonb;
  b jsonb := '{"schema_version":"LF_ROUTER_WORKER_RETURN_V1","perfil":"PERFIL-UI-ARCHITECT","solicitud_literal":"Cambiar el texto del boton principal de Iniciar sesion B2B a Acceder","hasta_donde_llegue":"Identifique el boton B2B_AUTH001_SUBMIT (PRIMARY_CTA) en B2B-AUTH-001","lo_que_encontre":[{"ref":"B2B_AUTH001_SUBMIT","detalle":"elemento PRIMARY_CTA de B2B-AUTH-001"}],"lo_que_no_existe":[{"ref":"texto del boton","detalle":"ninguna fuente gobernada guarda el texto de los elementos"}],"causa":"DATO_FALTANTE","quien_deberia_verlo":"quien mantiene el modelo de datos de pantallas","buscar_destino":["modelo de datos de pantallas"],"downstream_execution_allowed":false}'::jsonb;
BEGIN
  r := public.lf_router_worker_return_v1(b);
  IF r->>'paso' NOT IN ('RETORNO_SIN_DESTINO','RETORNO_ENRUTADO') THEN RAISE EXCEPTION 'WR boton: %', r; END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'WR efecto: %', r; END IF;
  IF r#>>'{informe,causa}' IS DISTINCT FROM 'DATO_FALTANTE' OR r#>>'{informe,lo_que_encontre,0,ref}' IS DISTINCT FROM 'B2B_AUTH001_SUBMIT' THEN RAISE EXCEPTION 'WR informe perdido: %', r; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(r->'candidatos','[]'::jsonb)) c WHERE upper(c->>'tipo') NOT IN ('PERFIL','SKILL','ADAPTER','OPERATION_CODE','CAPABILITY','STRATEGY')) THEN
    RAISE EXCEPTION 'WR candidato no ejecutor: %', r; END IF;
  -- control positivo: un destino que si existe se encuentra
  r := public.lf_router_worker_return_v1(b || '{"buscar_destino":["ui architect"]}');
  IF r->>'paso' IS DISTINCT FROM 'RETORNO_ENRUTADO' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'candidatos') c WHERE c->>'codigo'='PERFIL-UI-ARCHITECT') THEN
    RAISE EXCEPTION 'WR control positivo: %', r; END IF;
  -- control negativo: nada que pueda trabajar
  r := public.lf_router_worker_return_v1(b || '{"buscar_destino":["receta de ceviche con ajies"]}');
  IF r->>'paso' IS DISTINCT FROM 'RETORNO_SIN_DESTINO' OR r->>'pregunta_usuario' IS NULL THEN RAISE EXCEPTION 'WR sin destino: %', r; END IF;
  -- segundo retorno: no hay ciclo
  r := public.lf_router_worker_return_v1(b || '{"retorno_numero":2}');
  IF r->>'paso' IS DISTINCT FROM 'RETORNO_EXCEDIDO' THEN RAISE EXCEPTION 'WR excedido: %', r; END IF;
  -- invalidos
  r := public.lf_router_worker_return_v1(b || '{"causa":"ME_DA_FLOJERA"}');
  IF r->>'paso' IS DISTINCT FROM 'RETORNO_INVALIDO' OR NOT (r->'codigos' ? 'CAUSA_INVALIDA') THEN RAISE EXCEPTION 'WR causa: %', r; END IF;
  r := public.lf_router_worker_return_v1(b || '{"downstream_execution_allowed":true}');
  IF r->>'paso' IS DISTINCT FROM 'RETORNO_INVALIDO' OR NOT (r->'codigos' ? 'DOWNSTREAM_EXECUTION_MUST_BE_FALSE') THEN RAISE EXCEPTION 'WR downstream: %', r; END IF;
  r := public.lf_router_worker_return_v1(b || '{"buscar_destino":[]}');
  IF r->>'paso' IS DISTINCT FROM 'RETORNO_INVALIDO' THEN RAISE EXCEPTION 'WR buscar vacio: %', r; END IF;
END
$t$;

COMMIT;
