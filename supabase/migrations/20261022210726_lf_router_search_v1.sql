-- Level-1 search for the Router: one function over BOTH inventories (governance assets and product rules in
-- lf_ops.reglas), Spanish full-text with title weight and a coverage rule (>=2 distinct query terms, up to 60%,
-- cap 3; single-term queries need 1) so unrelated phrases return nothing. Output are CLUES, never decisions:
-- downstream_execution_allowed is always false. Empty result => next level (broad search). Read-only, additive.
-- Applied only through ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_search_v1(p_request_text text, p_limit integer DEFAULT 5)
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
               translate(lower(p.t),'áéíóúü','aeiouu')))) l WHERE l ~ '^[a-z0-9]+$') AS lex,
         replace(plainto_tsquery('spanish', translate(lower(p.t),'áéíóúü','aeiouu'))::text,' & ',' | ')::tsquery AS orq
  FROM p
), qn AS (
  SELECT qt.*, cardinality(qt.lex) AS n FROM qt
), docs AS (
  SELECT 'INVENTARIO'::text AS origen, b.codigo_activo AS codigo, b.tipo_activo AS tipo,
         b.nombre_canonico AS titulo,
         setweight(to_tsvector('spanish', translate(lower(b.codigo_activo||' '||coalesce(b.nombre_canonico,'')),'áéíóúü','aeiouu')),'A')
      || setweight(to_tsvector('spanish', translate(lower(coalesce(b.aliases::text,'')||' '||coalesce(b.keywords::text,'')),'áéíóúü','aeiouu')),'B')
      || setweight(to_tsvector('spanish', translate(lower(coalesce(b.router_search_text,'')),'áéíóúü','aeiouu')),'C') AS v
  FROM public.v_lf_fuente_operativa_busqueda b
  UNION ALL
  SELECT 'REGLAS_PRODUCTO', r.codigo, 'REGLA_'||coalesce(r.estado,'SIN_ESTADO'), r.titulo,
         setweight(to_tsvector('spanish', translate(lower(r.codigo||' '||coalesce(r.titulo,'')),'áéíóúü','aeiouu')),'A')
      || setweight(to_tsvector('spanish', translate(lower(coalesce(r.descripcion,'')),'áéíóúü','aeiouu')),'C')
  FROM lf_ops.reglas r
), m AS (
  SELECT qn.t, qn.lim, qn.n, d.origen, d.codigo, d.tipo, d.titulo,
         (length(d.codigo)>=6 AND position(lower(d.codigo) IN lower(qn.t))>0) AS exacto,
         (SELECT count(*) FROM unnest(qn.lex) l WHERE d.v @@ quote_literal(l)::tsquery)::int AS matched,
         ts_rank_cd(d.v, qn.orq, 32) AS rk
  FROM qn CROSS JOIN docs d
), f AS (
  SELECT m.*, row_number() OVER (PARTITION BY m.t ORDER BY m.exacto DESC, m.matched DESC, m.rk DESC, m.codigo) AS ord
  FROM m
  WHERE m.exacto
     OR (m.n>0 AND m.matched>0 AND m.matched >= least(m.n, least(3, greatest(2, ceil(m.n*0.6)::int))))
), fin AS (
  SELECT qn.t,
    jsonb_build_object(
      'schema_version','LF_ROUTER_SEARCH_V1','router','ACT-0001','nivel',1,
      'terminos_consulta', to_jsonb(qn.lex),
      'resultado', CASE WHEN EXISTS (SELECT 1 FROM f WHERE f.t=qn.t AND f.ord<=qn.lim) THEN 'ENCONTRADO' ELSE 'NO_ENCONTRADO' END,
      'candidatos', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'origen',f.origen,'codigo',f.codigo,'tipo',f.tipo,'titulo',f.titulo,
            'coinciden',f.matched,'de',f.n,'exacto',f.exacto) ORDER BY f.ord)
          FROM f WHERE f.t=qn.t AND f.ord<=qn.lim),'[]'::jsonb),
      'siguiente_nivel_si_vacio','NIVEL_2_BUSQUEDA_AMPLIA',
      'nota_es','Son pistas, no decisiones: no autorizan ningun efecto; la capa semantica decide si alguna responde.',
      'downstream_execution_allowed', false) AS r
  FROM qn
)
SELECT r FROM fin
$f$;

REVOKE ALL ON FUNCTION public.lf_router_search_v1(text,integer) FROM PUBLIC;
DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_router_search_v1(text,integer) FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_router_search_v1(text,integer) TO %I',v_role); END IF;
  END LOOP;
END
$g$;

-- in-transaction rehearsal (aborts the migration on failure); expectations measured on the live data beforehand
DO $t$
DECLARE r jsonb;
BEGIN
  r := public.lf_router_search_v1('Yape solo para el monto inicial');
  IF r#>>'{candidatos,0,codigo}' IS DISTINCT FROM 'REG_CHK_CUO_003' THEN RAISE EXCEPTION 'REHEARSAL regla: %', r; END IF;
  r := public.lf_router_search_v1('el orquestador del pipeline');
  IF r#>>'{candidatos,0,codigo}' IS DISTINCT FROM 'ACT-0058' THEN RAISE EXCEPTION 'REHEARSAL inventario: %', r; END IF;
  r := public.lf_router_search_v1('qué hora es en Lima');
  IF r->>'resultado' IS DISTINCT FROM 'NO_ENCONTRADO' OR jsonb_array_length(r->'candidatos')<>0 THEN RAISE EXCEPTION 'REHEARSAL negativo: %', r; END IF;
  r := public.lf_router_search_v1('quiero tomar un café con mi equipo');
  IF r->>'resultado' IS DISTINCT FROM 'NO_ENCONTRADO' THEN RAISE EXCEPTION 'REHEARSAL negativo2: %', r; END IF;
  r := public.lf_router_search_v1('REG_SEG_003');
  IF r#>>'{candidatos,0,codigo}' IS DISTINCT FROM 'REG_SEG_003' OR (r#>>'{candidatos,0,exacto}')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'REHEARSAL codigo exacto: %', r; END IF;
  IF (r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'REHEARSAL efecto: %', r; END IF;
END
$t$;

COMMIT;
