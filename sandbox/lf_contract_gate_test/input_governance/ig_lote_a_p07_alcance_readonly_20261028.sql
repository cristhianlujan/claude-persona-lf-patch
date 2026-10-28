-- LF Input Governance P07 structural scope audit, SELECT only.
-- Inputs from live catalogs: NO hardcoded rule IDs, no new engine, no mutation.
-- No scope may be authorized by a source-shell match alone.
-- Expect target unknown in some historical/unmapped screens: never coerce to a shell.

WITH observed_origin AS (
 SELECT rp.regla_id,
  array_agg(DISTINCT m.app_shell_code ORDER BY m.app_shell_code)
    FILTER (WHERE m.app_shell_code IS NOT NULL) AS source_shells
 FROM lf_ops.reglas_pantallas rp
 JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
 LEFT JOIN lf_ops.modulos m ON m.module_id=p.module_id
 GROUP BY rp.regla_id
),
derived AS (
 SELECT p.id AS pantalla_id,p.codigo AS screen_code,p.activa,
  e.regla_id,m.app_shell_code AS target_shell,o.source_shells
 FROM lf_ops.pantallas p
 LEFT JOIN lf_ops.modulos m ON m.module_id=p.module_id
 CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
 LEFT JOIN observed_origin o ON o.regla_id=e.regla_id
 WHERE e.binding_source='DERIVED_GLOBAL'
),
classified AS (
 SELECT *,
 CASE
  WHEN target_shell IS NULL THEN 'DESTINATION_SHELL_UNKNOWN'
  WHEN coalesce(cardinality(source_shells),0)=0 THEN 'ORIGIN_SHELL_UNKNOWN'
  WHEN target_shell=ANY(source_shells) THEN 'WITHIN_OBSERVED_SOURCE_SHELL'
  ELSE 'OUTSIDE_OBSERVED_SOURCE_SHELL'
 END AS discovery_bucket
 FROM derived
)
SELECT discovery_bucket,
 count(*) AS derived_pairs,
 count(DISTINCT regla_id) AS rules_affected,
 count(DISTINCT pantalla_id) AS screens_affected,
 count(*) FILTER(WHERE NOT activa) AS links_to_inactive_screens
FROM classified
GROUP BY discovery_bucket ORDER BY discovery_bucket;

-- Verify exhaustive, disjoint partition and current catalog size;
-- expected numbers are a historical audit reference only, never runtime logic.
WITH observed_origin AS (
 SELECT rp.regla_id,
  array_agg(DISTINCT m.app_shell_code ORDER BY m.app_shell_code)
   FILTER (WHERE m.app_shell_code IS NOT NULL) AS source_shells
 FROM lf_ops.reglas_pantallas rp JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
 LEFT JOIN lf_ops.modulos m ON m.module_id=p.module_id GROUP BY rp.regla_id
), derived AS (
 SELECT p.id,m.app_shell_code AS target_shell,e.regla_id,o.source_shells
 FROM lf_ops.pantallas p LEFT JOIN lf_ops.modulos m ON m.module_id=p.module_id
 CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
 LEFT JOIN observed_origin o ON o.regla_id=e.regla_id WHERE e.binding_source='DERIVED_GLOBAL'
)
SELECT count(*) AS derived_pairs,
 count(DISTINCT regla_id) AS derived_rules,
 count(*) FILTER(WHERE target_shell IS NULL) AS unknown_target,
 count(*) FILTER(WHERE target_shell IS NOT NULL AND coalesce(cardinality(source_shells),0)=0) AS unknown_origin,
 count(*) FILTER(WHERE target_shell IS NOT NULL AND coalesce(cardinality(source_shells),0)>0 AND target_shell=ANY(source_shells)) AS within,
 count(*) FILTER(WHERE target_shell IS NOT NULL AND coalesce(cardinality(source_shells),0)>0 AND NOT(target_shell=ANY(source_shells))) AS outside,
 count(*) = (
 count(*) FILTER(WHERE target_shell IS NULL) +
 count(*) FILTER(WHERE target_shell IS NOT NULL AND coalesce(cardinality(source_shells),0)=0) +
 count(*) FILTER(WHERE target_shell IS NOT NULL AND coalesce(cardinality(source_shells),0)>0 AND target_shell=ANY(source_shells)) +
 count(*) FILTER(WHERE target_shell IS NOT NULL AND coalesce(cardinality(source_shells),0)>0 AND NOT(target_shell=ANY(source_shells)))
 ) AS partition_complete
FROM derived;
