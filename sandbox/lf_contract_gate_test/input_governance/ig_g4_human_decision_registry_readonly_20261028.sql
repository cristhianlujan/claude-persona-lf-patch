-- LF G4: read-only model of the EXISTING policy registry's first decision gates.
-- This reproduces classification and route state; it DOES NOT call the
-- restricted security-definer resolver or admit any human action.
WITH scenarios(test_id,producer_code,subject_type,context) AS MATERIALIZED (
 VALUES
  ('EXISTING_PRIVACY_GAP','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','{"family_code":"PRIVACY_PII"}'::jsonb),
  ('EXISTING_RUNTIME_GAP','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','{"family_code":"RUNTIME_CONFIG"}'::jsonb),
  ('PROPOSED_SCOPE_SUBJECT_UNREGISTERED','INPUT_GOVERNANCE','RULE_APPLICABILITY_CHANGE','{"family_code":"PRIVACY_PII"}'::jsonb),
  ('UNKNOWN_FAMILY','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','{"family_code":"NO_REGISTERED_FAMILY_CASE"}'::jsonb),
  ('INVALID_CONTEXT','INPUT_GOVERNANCE','INPUT_GAP_PROPOSAL','[]'::jsonb)
),
classified AS MATERIALIZED (
 SELECT s.test_id,s.producer_code,s.subject_type,s.context,
  c.decision_class,c.rule_code, ROW_NUMBER() OVER (
   PARTITION BY s.test_id ORDER BY c.priority DESC,c.rule_code
  ) AS priority_rank
 FROM scenarios s LEFT JOIN private.lf_human_decision_classification_rules_v1 c
 ON c.status='ACTIVE' AND c.producer_code=s.producer_code
 AND c.subject_type=s.subject_type
 AND (
   c.attribute_name='ANY'
   OR (c.attribute_name='FAMILY_CODE' AND c.attribute_value=s.context->>'family_code')
   OR (c.attribute_name='REQUIRED_REVIEWER_ROLE' AND c.attribute_value=s.context->>'required_reviewer_role')
 )
),
outcomes AS MATERIALIZED (
 SELECT c.test_id,c.decision_class,c.rule_code,
  p.policy_code,p.status route_status,
  CASE WHEN jsonb_typeof(c.context)<>'object' THEN 'BLOCKED_INVALID_CONTEXT'
   WHEN c.decision_class IS NULL THEN 'BLOCKED_NO_CLASSIFICATION'
   WHEN p.policy_code IS NULL THEN 'BLOCKED_NO_ROUTE'
   WHEN p.status<>'ACTIVE' THEN 'BLOCKED_ROUTE_NOT_ACTIVE'
   WHEN NOT EXISTS (
     SELECT 1 FROM private.lf_human_decision_authority_policies_v1 a
     WHERE a.authority_ref=p.required_authority_ref
       AND a.reviewer_role=p.required_reviewer_role AND a.status='ACTIVE'
   ) THEN 'BLOCKED_AUTHORITY_CHANNEL_NOT_ACTIVE'
   ELSE 'REQUIRES_FULL_RESOLVER_AND_RECEIPT_VERIFICATION'
  END AS preliminary_state
 FROM classified c
 LEFT JOIN private.lf_human_decision_route_policies_v1 p
   ON p.decision_class=c.decision_class
  AND p.producer_code=c.producer_code
  AND p.subject_type=c.subject_type
 WHERE c.priority_rank=1
)
SELECT test_id,decision_class,rule_code,policy_code,route_status,preliminary_state
FROM outcomes ORDER BY test_id;