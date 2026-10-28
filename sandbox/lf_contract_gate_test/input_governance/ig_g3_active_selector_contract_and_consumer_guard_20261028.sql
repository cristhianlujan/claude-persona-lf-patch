-- LF IG N-4, G3: source-only selector integrity and consumer isolation.
-- NO screen-by-screen recomputation and NO DB writes; use SELECT only.
-- MATERIALIZED is used for shared active snapshot and clause flattening.
WITH active AS MATERIALIZED (
 SELECT id,codigo,valor_config->'applicability_v1' selector
 FROM lf_ops.reglas
 WHERE estado='VIGENTE'
   AND valor_config->'applicability_v1'->>'status'='ACTIVE'
), clauses AS MATERIALIZED (
 SELECT a.id,clause_item.value clause
 FROM active a
 CROSS JOIN LATERAL jsonb_array_elements(
  (CASE WHEN jsonb_typeof(a.selector->'all')='array'
         THEN a.selector->'all' ELSE '[]'::jsonb END) ||
  (CASE WHEN jsonb_typeof(a.selector->'any')='array'
         THEN a.selector->'any' ELSE '[]'::jsonb END)
 ) AS clause_item(value)
),
structural AS MATERIALIZED (
 SELECT id,
 CASE WHEN jsonb_typeof(selector)='object'
       AND jsonb_typeof(selector->'consumer_roles')='array'
       AND jsonb_typeof(selector->'all')='array'
       AND jsonb_typeof(selector->'any')='array'
  THEN selector->>'schema_version'='lf-rule-applicability/v1'
       AND jsonb_array_length(selector->'consumer_roles')>0
       AND (jsonb_array_length(selector->'all')+jsonb_array_length(selector->'any'))>0
  ELSE false END AS well_formed
 FROM active
),
cross_consumer AS MATERIALIZED (
 SELECT id,
 programacion.fn_input_rule_selector_matches_v1(
  selector,
  '{"consumer_role":"IG_UNAUTHORIZED_CROSS_CONSUMER_PROBE","target":{"screen":{"id":0}}}'::jsonb
 ) AS forbidden_match
 FROM active
)
SELECT
 (SELECT count(*) FROM active) active_selectors,
 (SELECT count(*) FROM structural WHERE well_formed IS NOT TRUE) invalid_outer_schema,
 (SELECT count(*) FROM clauses WHERE
  jsonb_typeof(clause) <> 'object'
  OR jsonb_typeof(clause->'path') <> 'array'
  OR jsonb_typeof(clause->'op') <> 'string'
  OR clause->'path'->>0 IS DISTINCT FROM 'target'
  OR upper(clause->>'op') NOT IN ('EXISTS','EQ','IN')
 ) malformed_clauses,
 (SELECT count(*) FROM cross_consumer WHERE forbidden_match IS DISTINCT FROM false)
 AS unauthorized_consumer_matches,
 (SELECT count(*) FROM clauses) clause_count;