-- Read-only shadow tests for N-4/T-REMED DEV review (safe on live read-only).
-- Reports evidence, does not mutate database, does not call promotion functions.
-- Important: synthetic test is selector evaluation only, not a proof of runtime
-- matching on a persisted future screen. Counts are not approval.
WITH base AS MATERIALIZED (
  SELECT p.id pantalla_id,p.codigo pantalla_codigo,p.activa,e.regla_id,
         e.binding_source,r.estado,r.codigo regla_codigo,r.es_transversal
  FROM lf_ops.pantallas p
  CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
  JOIN lf_ops.reglas r ON r.id=e.regla_id
)
SELECT count(*) AS current_returned,
  count(*) FILTER (WHERE binding_source='DERIVED_GLOBAL') AS inherited_without_selector,
  count(*) FILTER (WHERE binding_source='DERIVED_GLOBAL' AND NOT es_transversal) AS nontransversal_derived,
  count(*) FILTER (WHERE binding_source<>'DERIVED_GLOBAL' AND estado='VIGENTE') AS shadow_vigente_applicable,
  count(*) FILTER (WHERE binding_source<>'DERIVED_GLOBAL' AND estado='CANDIDATO') AS candidate_review_only,
  count(*) FILTER (WHERE NOT activa AND binding_source='DERIVED_GLOBAL') AS inherited_inactive,
  count(DISTINCT pantalla_id) AS screens
FROM base;

-- Initial physical binding set parity for the shadow projection (NOT a future invariant).
WITH shadow AS (
 SELECT p.id pantalla_id,e.regla_id FROM lf_ops.pantallas p
 CROSS JOIN LATERAL programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e
 WHERE e.binding_source<>'DERIVED_GLOBAL'
), physical AS (
 SELECT pantalla_id,regla_id FROM lf_ops.reglas_pantallas
)
SELECT (SELECT count(*) FROM (SELECT * FROM shadow EXCEPT SELECT * FROM physical) z) unexpected_pairs,
       (SELECT count(*) FROM (SELECT * FROM physical EXCEPT SELECT * FROM shadow) z) missing_pairs;

-- Representative positive/negative semantic scope hypothesis:
-- the rule identifiers here are TEST FIXTURES only, never hardcoded in runtime.
SELECT r.codigo AS rule_code, p.codigo AS screen_code,e.binding_source,r.estado
FROM lf_ops.reglas r CROSS JOIN lf_ops.pantallas p
LEFT JOIN LATERAL programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') e ON e.regla_id=r.id
WHERE r.codigo IN ('B2B-RULE-SESSION-001','REG_SES_001','REG_ABT_004')
  AND p.codigo='B2B-AUTH-001'
ORDER BY r.codigo,e.binding_source;

-- Future screen test using only a synthetic context, no row inserts.
WITH ctx AS (
  SELECT programacion.fn_input_rule_target_context_v1(p.id,'INPUT_GOVERNANCE') c
  FROM lf_ops.pantallas p WHERE p.codigo='B2B-AUTH-001'
), synthetic AS (
 SELECT jsonb_set(c,'{target,screen,id}','999999'::jsonb,true) c FROM ctx
)
SELECT r.codigo AS test_rule,
  programacion.fn_input_rule_selector_matches_v1(r.valor_config->'applicability_v1',(SELECT c FROM ctx)) AS current_match,
  programacion.fn_input_rule_selector_matches_v1(r.valor_config->'applicability_v1',(SELECT c FROM synthetic)) AS new_screen_same_module_match
FROM lf_ops.reglas r
WHERE r.codigo IN ('B2B-RULE-DESIGN-001','B2B-RULE-STORY-READINESS-001')
ORDER BY r.codigo;

-- Unresolved selectors fail closed.
SELECT r.valor_config->'applicability_v1'->>'status' AS scope_status,count(*) as rules
FROM lf_ops.reglas r
WHERE r.estado='VIGENTE'
  AND jsonb_typeof(r.valor_config->'applicability_v1')='object'
GROUP BY 1 ORDER BY 1;

-- Read-only contract result and candidate count: verify no future "PASS"
-- claim from a stale completed run.
SELECT x.screen_code,x.contract_version,
       jsonb_array_length(x.contract->'rules') AS returned_rules,
       (SELECT count(*) FROM jsonb_array_elements(x.contract->'rules') j WHERE j->>'status'='CANDIDATO') AS candidate_rules
FROM lf_ops.fn_b2b_backoffice_login_contract() x;

SELECT programacion.fn_input_governance_continuation_currentness_v1(833) AS historical_run_currentness;
