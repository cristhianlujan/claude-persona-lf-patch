-- LF IG P07 optimized read-only audit (PostgreSQL 17.6).
-- A single snapshot. MATERIALIZED avoids recomputing the LATERAL effective
-- rule resolver for independent bucket/total queries.
-- It is a TEMPORARY query result, NOT CREATE MATERIALIZED VIEW.
-- Shell source/destination are discovery evidence, never scope authority.
WITH
targets AS MATERIALIZED (
 SELECT p.id AS pantalla_id,p.activa,m.app_shell_code AS target_shell
 FROM lf_ops.pantallas p
 LEFT JOIN lf_ops.modulos m ON m.module_id=p.module_id
),
source_shells AS MATERIALIZED (
 SELECT rp.regla_id,
   array_agg(DISTINCT m.app_shell_code ORDER BY m.app_shell_code)
     FILTER (WHERE m.app_shell_code IS NOT NULL) AS origin_shells
 FROM lf_ops.reglas_pantallas rp
 JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
 LEFT JOIN lf_ops.modulos m ON m.module_id=p.module_id
 GROUP BY rp.regla_id
),
derived AS MATERIALIZED (
 SELECT t.pantalla_id,t.activa,t.target_shell,e.regla_id
 FROM targets t
 CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(
   t.pantalla_id,'INPUT_GOVERNANCE'
 ) e
 WHERE e.binding_source='DERIVED_GLOBAL'
),
classified AS MATERIALIZED (
 SELECT d.pantalla_id,d.regla_id,d.activa,
 CASE
  WHEN d.target_shell IS NULL THEN 'DESTINATION_SHELL_UNKNOWN'
  WHEN COALESCE(cardinality(s.origin_shells),0)=0 THEN 'ORIGIN_SHELL_UNKNOWN'
  WHEN d.target_shell=ANY(s.origin_shells) THEN 'WITHIN_OBSERVED_SOURCE_SHELL'
  ELSE 'OUTSIDE_OBSERVED_SOURCE_SHELL'
 END AS bucket
 FROM derived d
 LEFT JOIN source_shells s ON s.regla_id=d.regla_id
),
groups AS MATERIALIZED (
 SELECT bucket,count(*) AS pairs,
   count(DISTINCT regla_id) AS rule_count,
   count(DISTINCT pantalla_id) AS screen_count,
   count(*) FILTER(WHERE NOT activa) AS inactive_pairs
 FROM classified GROUP BY bucket
),
totals AS MATERIALIZED (
 SELECT count(*) AS pairs,count(DISTINCT regla_id) AS rule_count,
 count(DISTINCT pantalla_id) AS screen_count,
 count(*) FILTER(WHERE NOT activa) AS inactive_pairs
 FROM classified
)
SELECT x.bucket,x.pairs,x.rule_count,x.screen_count,x.inactive_pairs,x.partition_ok
FROM (
 SELECT 0 AS is_total,g.bucket,g.pairs,g.rule_count,g.screen_count,g.inactive_pairs,
 (SELECT COALESCE(sum(pairs),0) FROM groups) = (SELECT pairs FROM totals)
 AS partition_ok FROM groups g
 UNION ALL
 SELECT 1,'TOTAL',t.pairs,t.rule_count,t.screen_count,t.inactive_pairs,
 (SELECT COALESCE(sum(pairs),0) FROM groups)=t.pairs
 FROM totals t
) x
ORDER BY x.is_total,x.bucket;
