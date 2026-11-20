-- LF Input Governance N-4 / G4 — authority-source reuse: false-positive regression.
-- SELECT ONLY. Audit fixture codes are NOT runtime authorization mappings.
-- Existing policy-version authority fields may belong to ANOTHER operation
-- and must never be accepted as authority to expand a rule's selector.
WITH sample(rule_code) AS MATERIALIZED (
 VALUES ('REG_SES_001'::text),('REG_ABT_004'),('B2B-RULE-AUTH-001'),
        ('B2B-RULE-DESIGN-001'),('B2B-RULE-STORY-READINESS-001')
), rules AS MATERIALIZED (
 SELECT s.rule_code,r.estado,r.origen,
   (SELECT count(*) FROM public.lf_decisiones_gov d
     WHERE d.estado_normalizado='VIGENTE'
       AND r.origen LIKE '%'||d.id_decision||'%') AS source_decisions
 FROM sample s LEFT JOIN lf_ops.reglas r ON r.codigo=s.rule_code
), scope_authority AS MATERIALIZED (
 SELECT
  (SELECT count(*) FROM private.lf_human_decision_authority_policies_v1
   WHERE status='ACTIVE') AS active_issuers,
  (SELECT count(*) FROM private.lf_human_decision_route_policies_v1
   WHERE producer_code='INPUT_GOVERNANCE'
     AND subject_type='RULE_APPLICABILITY_CHANGE' AND status='ACTIVE') AS active_scope_routes,
  (SELECT count(*) FROM private.lf_human_decision_receipts_v1) AS decision_receipts
), foreign_policy AS MATERIALIZED (
 SELECT policy_code,policy_payload->>'governance_authority_binding' AS authority_binding,
        policy_payload->>'applies_to_operation_code' AS operation_code
 FROM public.lf_policy_versions
 WHERE policy_code='POL-PROFILE-UPDATE-PASS' AND status='ACTIVE'
), proofs AS MATERIALIZED (
 SELECT 'NO_MISSING_RULES'::text AS control,
  (SELECT count(*)=5 AND bool_and(estado='VIGENTE') FROM rules) AS passed
 UNION ALL SELECT 'NO_SCOPE_ROUTE_FROM_CROSS_DOMAIN_POLICY',
  (SELECT count(*)=1 AND bool_and(
         authority_binding='OWNER_ROLE_ONLY_NOT_HUMAN_DECISION'
         AND operation_code IS DISTINCT FROM 'INPUT_GOVERNANCE'
        ) FROM foreign_policy)
 UNION ALL SELECT 'HOLD_WITHOUT_ACTIVE_SCOPE_AUTHORITY',
  (SELECT count(*)=5 AND bool_and(
        a.active_issuers=0 OR a.active_scope_routes=0
       ) FROM rules CROSS JOIN scope_authority a)
 UNION ALL SELECT 'VIGENTE_DECISION_IS_NOT_SCOPE_RECEIPT',
  (SELECT count(*)=1 FROM rules WHERE source_decisions>0)
 UNION ALL SELECT 'NO_HUMAN_RECEIPTS_TO_REUSE',
  (SELECT decision_receipts=0 FROM scope_authority)
)
SELECT control,
 CASE WHEN passed IS TRUE THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM proofs ORDER BY control;
