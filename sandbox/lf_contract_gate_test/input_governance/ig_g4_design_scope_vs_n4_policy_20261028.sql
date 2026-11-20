-- LF IG G4: test-only real policy vs N4 matching evidence.
-- Observed differences are REVIEW signals, not proof of an incorrect selector.
-- Test fixture code/decision IDs are not inserted into a runtime rule engine.
WITH
source_decision AS MATERIALIZED (
 SELECT d.id_decision,d.estado_normalizado,d.raw_payload->>'scope' AS decision_scope
 FROM public.lf_decisiones_gov d
 WHERE d.id_decision='DEC-LF-DESIGN-TOKEN-TRANSVERSAL-GOV-001'
),
rule AS MATERIALIZED (
 SELECT codigo,estado,valor_config->>'governance_scope' declared_scope,
 valor_config->'applicability_v1' AS selector
 FROM lf_ops.reglas
 WHERE codigo='B2B-RULE-DESIGN-001'
),
contexts AS MATERIALIZED (
 SELECT p.id,p.codigo,p.activa,
 programacion.fn_input_rule_target_context_v1(p.id,'INPUT_GOVERNANCE') context
 FROM lf_ops.pantallas p
),
matches AS MATERIALIZED (
 SELECT r.codigo rule_code,r.declared_scope, d.decision_scope,
 c.context#>>'{target,app_shell,app_shell_code}' shell,c.activa,
 programacion.fn_input_rule_selector_matches_v1(r.selector,c.context) matched
 FROM rule r CROSS JOIN contexts c CROSS JOIN source_decision d
)
SELECT rule_code,declared_scope,decision_scope,
 COALESCE(shell,'<NULL>') AS shell,count(*) targets,
 count(*) FILTER(WHERE matched IS TRUE) matched,
 count(*) FILTER(WHERE NOT activa) inactive,
 CASE WHEN declared_scope=decision_scope AND
    (count(*) FILTER(WHERE matched IS TRUE)=0)
 THEN 'REVIEW_COVERAGE_VS_POLICY_SCOPE'
 ELSE 'NO_AUTOMATIC_AUTHORITY_CONCLUSION' END AS decision
FROM matches GROUP BY rule_code,declared_scope,decision_scope,shell ORDER BY shell;