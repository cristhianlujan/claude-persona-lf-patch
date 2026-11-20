-- LF IG G4: five real rules, read-only, no hardcoded runtime grants.
-- Test fixture codes represent diverse categories, not an owner mapping.
WITH cases(rule_code,issue) AS MATERIALIZED (
 VALUES
 ('REG_SES_001'::text,'SESSION_CONTEXT'),
 ('REG_ABT_004','EXPERIMENT_COMPOUND'),
 ('B2B-RULE-AUTH-001','AUTHORIZATION_GUARD'),
 ('B2B-RULE-DESIGN-001','DESIGN_POLICY'),
 ('B2B-RULE-STORY-READINESS-001','FAMILY_SELECTION')
),
rules AS MATERIALIZED (
 SELECT r.codigo,r.estado,r.categoria,r.origen,
 r.valor_config->'applicability_v1' AS selector,
 r.es_transversal
 FROM lf_ops.reglas r JOIN cases c ON c.rule_code=r.codigo
),
human_scope AS MATERIALIZED (
 SELECT req.subject_type,req.subject_key,req.status,rec.receipt_id
 FROM private.lf_human_decision_requests_v1 req
 LEFT JOIN private.lf_human_decision_receipts_v1 rec ON rec.request_id=req.request_id
 WHERE req.producer_code='INPUT_GOVERNANCE'
 AND req.subject_type='RULE_APPLICABILITY_CHANGE'
),
routes AS MATERIALIZED (
 SELECT status FROM private.lf_human_decision_route_policies_v1
 WHERE producer_code='INPUT_GOVERNANCE' AND subject_type='RULE_APPLICABILITY_CHANGE'
),
observed AS MATERIALIZED (
 SELECT c.rule_code,c.issue,r.estado,r.categoria,r.es_transversal,
 (r.selector->>'status'='ACTIVE') AS active_selector,
 coalesce(jsonb_array_length(r.selector->'any'),0) AS any_clauses,
 (SELECT count(*) FROM routes WHERE status='ACTIVE') AS approved_route_count,
 (SELECT count(*) FROM human_scope WHERE receipt_id IS NOT NULL) AS receipts_for_subject
 FROM cases c LEFT JOIN rules r ON r.codigo=c.rule_code
)
SELECT rule_code,issue,estado,categoria,es_transversal,
 COALESCE(active_selector,false) as active_selector,
 any_clauses,approved_route_count,receipts_for_subject,
 CASE WHEN estado IS NULL THEN 'MISSING_RULE'
      WHEN approved_route_count=0 OR receipts_for_subject=0 THEN 'HOLD_NEW_SCOPE_APPROVAL'
      ELSE 'AUTHORITY_CHAIN_REQUIRES_EXACT_HASH_VERIFICATION'
 END AS next_gate
FROM observed ORDER BY rule_code;