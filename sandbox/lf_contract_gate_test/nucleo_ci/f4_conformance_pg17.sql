-- SOLO PG17 descartable. No se instala en LF/SALY. Consumir el resolvedor canónico, nunca la tabla legada.
CREATE TEMP TABLE f4_ci_session_guard (marker boolean) ON COMMIT DROP;
CREATE FUNCTION pg_temp.f4_conformance_v1(p_claims jsonb,p_fecha timestamptz)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = pg_catalog AS $f4$
WITH claims AS MATERIALIZED (
 SELECT a.ord AS idx,x.instancia,x.nodo,x.regla,x.version,x.version_hash
 FROM jsonb_array_elements(p_claims) WITH ORDINALITY a(value,ord)
 CROSS JOIN LATERAL jsonb_to_record(a.value) x(instancia text,nodo text,regla text,version integer,version_hash text)
), nodes AS (
 SELECT 'lf_ops'::text instancia,n.codigo,NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_nodos c WHERE c.padre=n.codigo) hoja FROM lf_ops.nucleo_nodos n
 UNION ALL SELECT 'saly',n.codigo,NOT EXISTS(SELECT 1 FROM saly.nucleo_nodos c WHERE c.padre=n.codigo) FROM saly.nucleo_nodos n
), lf_claims AS MATERIALIZED (
 SELECT c.* FROM claims c JOIN nodes n ON n.instancia=c.instancia AND n.codigo=c.nodo AND n.hoja WHERE c.instancia='lf_ops'
), saly_claims AS MATERIALIZED (
 SELECT c.* FROM claims c JOIN nodes n ON n.instancia=c.instancia AND n.codigo=c.nodo AND n.hoja WHERE c.instancia='saly'
), effective AS (
 SELECT c.idx,e.version,e.conflicto FROM lf_claims c CROSS JOIN LATERAL lf_ops.nucleo_reglas_efectivas_v1(c.nodo,p_fecha) e WHERE e.regla=c.regla
 UNION ALL SELECT c.idx,e.version,e.conflicto FROM saly_claims c CROSS JOIN LATERAL saly.nucleo_reglas_efectivas_v1(c.nodo,p_fecha) e WHERE e.regla=c.regla
), effective_one AS (
 SELECT idx,count(*) n,max(version) version,bool_or(conflicto IS NOT NULL) conflicto FROM effective GROUP BY idx
), versions AS (
 SELECT 'lf_ops'::text instancia,v.regla,v.version,v.hash,v.estado,v.publicada_desde,v.exigible_desde,v.impacto FROM lf_ops.nucleo_regla_versiones v
 UNION ALL SELECT 'saly',v.regla,v.version,v.hash,v.estado,v.publicada_desde,v.exigible_desde,v.impacto FROM saly.nucleo_regla_versiones v
), result AS (
 SELECT c.idx,c.instancia,c.nodo,c.regla,c.version AS declarada,e.version AS efectiva,
 CASE
  WHEN n.codigo IS NULL THEN 'NODO_INEXISTENTE'
  WHEN NOT n.hoja THEN 'NODO_NO_HOJA'
  WHEN d.version IS NULL OR d.estado IS DISTINCT FROM 'PUBLICADA' OR d.publicada_desde IS NULL OR d.publicada_desde>p_fecha THEN 'VERSION_NO_PUBLICADA'
  WHEN d.hash IS DISTINCT FROM c.version_hash THEN 'HASH_DISTINTO'
  WHEN e.idx IS NULL THEN 'REGLA_NO_EFECTIVA'
  WHEN e.n<>1 OR e.conflicto THEN 'CONFLICTO_NO_CERTIFICADO'
  WHEN c.version>e.version THEN 'VERSION_FUTURA'
  WHEN c.version=e.version THEN 'AL_DIA'
  WHEN EXISTS(SELECT 1 FROM versions w WHERE w.instancia=c.instancia AND w.regla=c.regla AND w.estado='PUBLICADA' AND w.impacto<>'NINGUNO' AND w.version>c.version AND w.version<=e.version AND w.exigible_desde<=p_fecha) THEN 'DESFASADO'
  WHEN EXISTS(SELECT 1 FROM versions w WHERE w.instancia=c.instancia AND w.regla=c.regla AND w.estado='PUBLICADA' AND w.impacto<>'NINGUNO' AND w.version>c.version AND w.version<=e.version) THEN 'EN_PLAZO'
  ELSE 'AL_DIA_SIN_IMPACTO' END AS estado
 FROM claims c LEFT JOIN nodes n ON n.instancia=c.instancia AND n.codigo=c.nodo
 LEFT JOIN effective_one e ON e.idx=c.idx
 LEFT JOIN versions d ON d.instancia=c.instancia AND d.regla=c.regla AND d.version=c.version
)
SELECT coalesce(jsonb_agg(to_jsonb(result) ORDER BY idx),'[]'::jsonb) FROM result;
$f4$;
