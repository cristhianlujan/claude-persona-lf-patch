-- LF IG G3: canonical vs minimal context, SELECT only, PG17.6.
-- Existing 14 ACTIVE x 58 targets, one MATERIALIZED context per target.
-- NOT a migration or materialized view. Do not infer scope authority from matches.
WITH
targets AS MATERIALIZED (
 SELECT p.id AS screen_id,
   programacion.fn_input_rule_target_context_v1(
     p.id,'INPUT_GOVERNANCE'
   ) AS original_context
 FROM lf_ops.pantallas p
),
selectors AS MATERIALIZED (
 SELECT r.id AS rule_id,r.valor_config->'applicability_v1' AS selector
 FROM lf_ops.reglas r
 WHERE r.estado='VIGENTE'
   AND r.valor_config->'applicability_v1'->>'status'='ACTIVE'
),
contexts AS MATERIALIZED (
 SELECT t.screen_id,t.original_context,
 jsonb_build_object(
  'consumer_role',t.original_context->'consumer_role',
  'target',jsonb_build_object(
   'screen',jsonb_build_object('id',t.original_context#>'{target,screen,id}'),
   'module',CASE
     WHEN jsonb_typeof(t.original_context#>'{target,module}')='object'
     THEN jsonb_build_object(
       'module_code',t.original_context#>'{target,module,module_code}')
     ELSE 'null'::jsonb END,
   'app_shell',CASE
     WHEN jsonb_typeof(t.original_context#>'{target,app_shell}')='object'
     THEN jsonb_build_object(
       'app_shell_code',t.original_context#>'{target,app_shell,app_shell_code}')
     ELSE 'null'::jsonb END
 )) AS projected_context
 FROM targets t
),
pairs AS MATERIALIZED (
 SELECT s.rule_id,t.screen_id,
 programacion.fn_input_rule_selector_matches_v1(s.selector,t.original_context)
   AS original_match,
 programacion.fn_input_rule_selector_matches_v1(s.selector,t.projected_context)
   AS projected_match
 FROM selectors s CROSS JOIN contexts t
)
SELECT count(*) AS compared_pairs,
 count(DISTINCT rule_id) AS rules_checked,
 count(DISTINCT screen_id) AS targets_checked,
 count(*) FILTER(WHERE original_match IS TRUE) AS original_matches,
 count(*) FILTER(WHERE projected_match IS TRUE) AS projected_matches,
 count(*) FILTER(WHERE original_match IS DISTINCT FROM projected_match)
   AS mismatches
FROM pairs;
