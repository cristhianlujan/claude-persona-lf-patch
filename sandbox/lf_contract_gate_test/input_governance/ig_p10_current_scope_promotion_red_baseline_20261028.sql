-- P10 red baseline: SOURCE+LIVE-DATA current-state guard (read-only).
-- Intentionally RED until explicit scope authority protects the real effective resolver.
-- Does not invoke promotion or make DDL/DML changes. No production alteration.
-- Interpretation: conditional risk, NOT proof that any candidate was approved/promoted.
WITH
source AS MATERIALIZED (
 SELECT
  pg_get_functiondef('programacion.fn_input_effective_rule_links_v1(integer,text)'::regprocedure) AS effective_src,
  pg_get_functiondef('programacion.fn_t_remed_global_rules_v1(numeric)'::regprocedure) AS global_src,
  pg_get_functiondef('programacion.fn_t_remed_rule_promotion_verdicts_v1(integer,bigint)'::regprocedure) AS verdict_src,
  pg_get_functiondef('programacion.fn_t_remed_promote_v1(boolean,integer,integer)'::regprocedure) AS promotion_src
),
screen_count AS MATERIALIZED (
 SELECT count(*)::numeric n FROM lf_ops.pantallas
),
candidates AS MATERIALIZED (
 SELECT r.id,
  count(DISTINCT rp.pantalla_id)::integer physical_screens
 FROM lf_ops.reglas r
 LEFT JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
 WHERE r.estado='CANDIDATO'
   AND jsonb_typeof(r.valor_config->'applicability_v1') IS DISTINCT FROM 'object'
 GROUP BY r.id
),
risk AS MATERIALIZED (
 SELECT count(*)::integer without_selector,
  count(*) FILTER (WHERE physical_screens >= (SELECT n*0.25 FROM screen_count))::integer
   AS threshold_exposed_if_promoted
 FROM candidates
),
contracts AS MATERIALIZED (
 SELECT
  effective_src LIKE '%DERIVED_GLOBAL%' AND
   effective_src LIKE '%fn_t_remed_global_rules_v1%' AS old_global_in_effective,
  global_src LIKE '%p_min_share%' AND global_src LIKE '%VIGENTE%' AS frequency_global_gate,
  verdict_src LIKE '%USED_BY_ENOUGH_SCREENS%' AND
    verdict_src NOT ILIKE '%applicability_v1%' AS technical_verdict_without_scope_check,
  promotion_src LIKE '%p_apply%' AND promotion_src LIKE '%set estado=%VIGENTE%' AS technical_promotion_route
 FROM source
)
SELECT
 r.without_selector,
 r.threshold_exposed_if_promoted,
 (SELECT n FROM screen_count) total_screens,
 c.old_global_in_effective,
 c.frequency_global_gate,
 c.technical_verdict_without_scope_check,
 c.technical_promotion_route,
 CASE WHEN r.threshold_exposed_if_promoted>0
       AND c.old_global_in_effective
       AND c.frequency_global_gate
       AND c.technical_verdict_without_scope_check
       AND c.technical_promotion_route
      THEN 'FAIL_P10_CURRENT_PROMOTION_SCOPE_SEPARATION'
      ELSE 'REVIEW_REQUIRED_NO_AUTO_PASS' END AS regression_verdict
FROM risk r CROSS JOIN contracts c;
