-- LF Router ACT-0001: busqueda NIVEL 2 (fuera del inventario de gobierno) sobre el indice global existente
-- inventory.search_index (archivos del repo indexados, funciones/tablas/vistas/politicas de la base, contratos, operaciones).
-- No crea un indice nuevo: lee el existente. Solo lectura. Entrega PISTAS con su vigencia; nunca permiso.
-- Se invoca solo con consentimiento del usuario (el Router avisa que sale del inventario). Segunda pasada: el usuario
-- aporta un detalle y se repite con sus palabras, sin expandir sinonimos.
-- Cubre lo que el indice tiene; lo que no esta indexado lo debe buscar la capa llamadora directamente en el repo.
-- Se aplica solo por ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_search_nivel2_v1(p_request_text text, p_limit integer DEFAULT 5)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog','public'
AS $f$
WITH p AS (
  SELECT coalesce(p_request_text,'') AS t, least(greatest(coalesce(p_limit,5),1),10) AS lim
), qt AS (
  SELECT p.t, p.lim,
         array(SELECT l FROM unnest(tsvector_to_array(to_tsvector('spanish',
               translate(lower(p.t),'áéíóúü','aeiouu')))) l WHERE l ~ '^[a-z0-9]+$') AS lex
  FROM p
), docs AS (
  SELECT s.object_type, s.object_ref, s.currentness, s.observed_at,
         to_tsvector('spanish', translate(regexp_replace(coalesce(s.object_ref_lc,'')||' '||coalesce(s.tags_lc::text,''),'[^a-z0-9]+',' ','g'),'áéíóúü','aeiouu')) AS v
  FROM inventory.search_index s
), m AS (
  SELECT d.object_type, d.object_ref, d.currentness, d.observed_at, cardinality(qt.lex) AS n,
         (SELECT count(*) FROM unnest(qt.lex) l WHERE d.v @@ quote_literal(l)::tsquery)::int AS matched
  FROM qt CROSS JOIN docs d
  WHERE cardinality(qt.lex) > 0
), f AS (
  SELECT m.*, row_number() OVER (ORDER BY m.matched DESC, m.object_ref) AS ord
  FROM m
  WHERE m.matched > 0 AND m.matched >= least(m.n, least(3, greatest(2, ceil(m.n*0.6)::int)))
), top AS (
  SELECT * FROM f WHERE ord <= (SELECT lim FROM p)
), fin AS (
  SELECT jsonb_build_object(
    'schema_version','LF_ROUTER_SEARCH_NIVEL2_V1',
    'router','ACT-0001',
    'nivel',2,
    'fuente','inventory.search_index',
    'terminos_consulta',(SELECT to_jsonb(lex) FROM qt),
    'resultado', CASE WHEN EXISTS (SELECT 1 FROM top) THEN 'ENCONTRADO_FUERA_DE_INVENTARIO' ELSE 'NO_ENCONTRADO_EN_INDICE' END,
    'candidatos', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'origen',t.object_type,'ref',t.object_ref,'vigencia',t.currentness,'observado',t.observed_at,
        'coinciden',t.matched,'de',t.n) ORDER BY t.ord) FROM top t),'[]'::jsonb),
    'consentimiento_requerido_antes_de_usar',true,
    'tambien_buscar_en_repo_si_no_alcanza',true,
    'pregunta_detalle_es','Si no es lo que buscas, dime un detalle: donde esta, como se llama mas o menos o que hace; repito la busqueda con tus palabras.',
    'hueco_inventario_sugerido', EXISTS (SELECT 1 FROM top),
    'nota_es','Son pistas fuera del inventario de gobierno: evidencia de que algo existe, no permiso ni decision. El indice solo cubre lo que se alimento; lo que no este indexado hay que buscarlo directamente en el repo.',
    'downstream_execution_allowed',false
  ) AS r
)
SELECT r FROM fin
$f$;

REVOKE ALL ON FUNCTION public.lf_router_search_nivel2_v1(text,integer) FROM PUBLIC;
DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_router_search_nivel2_v1(text,integer) FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_router_search_nivel2_v1(text,integer) TO %I',v_role); END IF;
  END LOOP;
END
$g$;

-- ensayo en la transaccion (aborta si falla); expectativas medidas antes en los datos reales
DO $t$
DECLARE r jsonb;
BEGIN
  r := public.lf_router_search_nivel2_v1('estado en curso');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'candidatos') c WHERE c->>'ref' ILIKE '%lf_estado_en_curso_v1%') THEN RAISE EXCEPTION 'NIVEL2 estado en curso: %', r; END IF;
  r := public.lf_router_search_nivel2_v1('sonda de familia completa de input governance');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'candidatos') c WHERE c->>'ref' ILIKE '%fn_input_governance_family_complete_probe_v1%') THEN RAISE EXCEPTION 'NIVEL2 sonda: %', r; END IF;
  r := public.lf_router_search_nivel2_v1('registrar paso de operación de tarjeta, record card operation step');
  IF r#>>'{candidatos,0,ref}' NOT ILIKE '%lf_record_card_operation_step_v1%' THEN RAISE EXCEPTION 'NIVEL2 segunda pasada: %', r; END IF;
  r := public.lf_router_search_nivel2_v1('quiero tomar un café con mi equipo');
  IF r->>'resultado' IS DISTINCT FROM 'NO_ENCONTRADO_EN_INDICE' OR jsonb_array_length(r->'candidatos')<>0 THEN RAISE EXCEPTION 'NIVEL2 negativo: %', r; END IF;
  r := public.lf_router_search_nivel2_v1('receta de lomo saltado para el almuerzo');
  IF r->>'resultado' IS DISTINCT FROM 'NO_ENCONTRADO_EN_INDICE' THEN RAISE EXCEPTION 'NIVEL2 negativo2: %', r; END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false OR (r->>'consentimiento_requerido_antes_de_usar')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'NIVEL2 contrato: %', r; END IF;
END
$t$;

COMMIT;
