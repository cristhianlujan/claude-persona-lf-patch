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
 SELECT id, CASE
  WHEN jsonb_typeof(selector) IS DISTINCT FROM 'object'
    OR jsonb_typeof(selector->'consumer_roles') IS DISTINCT FROM 'array'
    OR jsonb_typeof(selector->'all') IS DISTINCT FROM 'array'
    OR jsonb_typeof(selector->'any') IS DISTINCT FROM 'array' THEN false
  ELSE
    selector->>'schema_version' IS NOT DISTINCT FROM 'lf-rule-applicability/v1'
    AND selector->>'status' IS NOT DISTINCT FROM 'ACTIVE'
    AND jsonb_array_length(selector->'consumer_roles')>0
    AND jsonb_array_length(selector->'all')+jsonb_array_length(selector->'any')>0
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(selector->'consumer_roles') x(value)
                    WHERE jsonb_typeof(x.value) IS DISTINCT FROM 'string'
                       OR btrim(x.value #>> '{}')='')
    AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(selector) k(key)
                    WHERE k.key NOT IN ('schema_version','status','consumer_roles','all','any','provenance'))
  END AS well_formed
 FROM active
),
clause_validation AS MATERIALIZED (
 SELECT id, CASE
   WHEN jsonb_typeof(clause) IS DISTINCT FROM 'object'
     OR jsonb_typeof(clause->'path') IS DISTINCT FROM 'array'
     OR jsonb_typeof(clause->'op') IS DISTINCT FROM 'string' THEN false
   WHEN jsonb_array_length(clause->'path') < 2 THEN false
   ELSE
     clause #>> '{path,0}' IS NOT DISTINCT FROM 'target'
     AND upper(clause->>'op') IN ('EXISTS','EQ','IN')
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(clause->'path') x(value)
                     WHERE jsonb_typeof(x.value) IS DISTINCT FROM 'string'
                        OR btrim(x.value #>> '{}')='')
     AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(clause) k(key)
                     WHERE k.key NOT IN ('path','op')
                       AND NOT (upper(clause->>'op')='EQ' AND k.key='value')
                       AND NOT (upper(clause->>'op')='IN' AND k.key='values'))
     AND CASE WHEN upper(clause->>'op')='EQ'
         THEN (clause?'value') AND jsonb_typeof(clause->'value') IS DISTINCT FROM 'null'
         WHEN upper(clause->>'op')='IN'
         THEN CASE WHEN jsonb_typeof(clause->'values') IS DISTINCT FROM 'array'
           THEN false
           ELSE jsonb_array_length(clause->'values')>0
            AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(clause->'values') x(value)
                            WHERE jsonb_typeof(x.value)='null') END
         ELSE true END
  END AS well_formed
 FROM clauses
),
cross_consumer AS MATERIALIZED (
 SELECT a.id,
 CASE WHEN s.well_formed IS TRUE
  THEN programacion.fn_input_rule_selector_matches_v1(
   a.selector,
   '{"consumer_role":"IG_UNAUTHORIZED_CROSS_CONSUMER_PROBE","target":{"screen":{"id":0}}}'::jsonb
  )
  ELSE false END AS forbidden_match
 FROM active a JOIN structural s ON s.id=a.id
)
SELECT
 (SELECT count(*) FROM active) active_selectors,
 (SELECT count(*) FROM structural WHERE well_formed IS NOT TRUE) invalid_outer_schema,
 (SELECT count(*) FROM clause_validation WHERE well_formed IS NOT TRUE) malformed_clauses,
 (SELECT count(*) FROM cross_consumer WHERE forbidden_match IS DISTINCT FROM false)
 AS unauthorized_consumer_matches,
 (SELECT count(*) FROM clauses) clause_count;