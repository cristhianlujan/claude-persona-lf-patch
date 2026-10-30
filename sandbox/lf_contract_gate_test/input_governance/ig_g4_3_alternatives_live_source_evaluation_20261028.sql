-- LF Input Governance / G4: comparison based only on LIVE registry evidence.
-- SELECT-only. No inferred rule owner, no simulated grant, no activation.
-- IMPORTANT: even a nonzero candidate_chain_count is NOT a signed scope binding:
-- the rule/selector/consumer hash contract is not yet defined. Therefore
-- authority stays UNKNOWN (NULL) rather than being approved automatically.
WITH
rules AS MATERIALIZED (
 SELECT id,codigo,estado,valor_config->'applicability_v1' AS applicability
 FROM lf_ops.reglas
),
versioned_policies AS MATERIALIZED (
 SELECT policy_code,policy_version,policy_sha,source_ref,status
 FROM public.lf_policy_versions
),
current_versions AS MATERIALIZED (
 SELECT * FROM versioned_policies WHERE status='ACTIVE'
),
operation_bindings AS MATERIALIZED (
 SELECT operation_code,policy_code,policy_role,required,binding_status
 FROM public.lf_operation_policy_bindings
 WHERE binding_status='ACTIVE'
),
binding_integrity AS MATERIALIZED (
 SELECT b.operation_code,b.policy_code,v.policy_sha
 FROM operation_bindings b
 LEFT JOIN current_versions v ON v.policy_code=b.policy_code
),
reusable_policies AS MATERIALIZED (
 SELECT policy_code,status,source_ref,business_scope,channel_scope,
 capabilities_any,action_families_any,asset_types_any
 FROM private.lf_reusable_policy_registry_v1
),
human_routes AS MATERIALIZED (
 SELECT producer_code,subject_type,status FROM private.lf_human_decision_route_policies_v1
),
human_authority AS MATERIALIZED (
 SELECT authority_ref,status FROM private.lf_human_decision_authority_policies_v1
),
human_receipts AS MATERIALIZED (
 SELECT request_id FROM private.lf_human_decision_receipts_v1
),
evidence_receipts AS MATERIALIZED (
 SELECT subject_type,receipt_kind,verification_state FROM private.lf_evidence_ledger_v1
),
scope_decision_chain AS MATERIALIZED (
 SELECT count(*) AS candidate_chain_count
 FROM private.lf_human_decision_requests_v1 req
 JOIN private.lf_human_decision_receipts_v1 rec ON rec.request_id=req.request_id
 JOIN private.lf_human_decision_route_policies_v1 route
   ON route.producer_code=req.producer_code
  AND route.subject_type=req.subject_type
  AND route.status='ACTIVE'
  AND route.required_authority_ref=req.required_authority_ref
 JOIN private.lf_human_decision_authority_policies_v1 auth
   ON auth.authority_ref=req.required_authority_ref
  AND auth.reviewer_role=req.required_reviewer_role AND auth.status='ACTIVE'
 WHERE req.producer_code='INPUT_GOVERNANCE'
   AND req.subject_type='RULE_APPLICABILITY_CHANGE'
   AND req.status='DECIDED'
   AND req.required_authority_ref=rec.authority_ref
   AND req.required_reviewer_role=rec.reviewer_role
   AND req.currentness_sha256=rec.observed_currentness_sha256
),

measures AS MATERIALIZED (
 SELECT
 (SELECT count(*) FROM rules) AS rule_count,
 (SELECT count(*) FROM rules WHERE estado='VIGENTE' AND applicability->>'status'='ACTIVE') AS selector_count,
 (SELECT count(*) FROM current_versions) AS current_policy_versions,
 (SELECT count(*) FROM current_versions WHERE policy_sha IS NOT NULL AND source_ref IS NOT NULL) AS anchored_versions,
 (SELECT count(*) FROM operation_bindings) AS bound_operations,
 (SELECT count(*) FROM binding_integrity WHERE policy_sha IS NULL) AS bindings_without_active_policy,
 (SELECT count(*) FROM reusable_policies WHERE status='VIGENTE' AND source_ref IS NOT NULL
 AND cardinality(action_families_any)>0 AND cardinality(capabilities_any)>0) AS attributable_scope_policies,
 (SELECT count(*) FROM human_routes WHERE status='ACTIVE') AS active_human_routes,
 (SELECT count(*) FROM human_routes WHERE producer_code='INPUT_GOVERNANCE'
 AND subject_type='RULE_APPLICABILITY_CHANGE' AND status='ACTIVE') AS active_scope_route,
 (SELECT count(*) FROM human_authority WHERE status='ACTIVE') AS active_authority_channels,
 (SELECT count(*) FROM human_receipts) AS real_human_receipts,
 (SELECT count(*) FROM evidence_receipts WHERE subject_type ILIKE '%RULE%'
 OR subject_type ILIKE '%SCOPE%') AS rule_scope_evidence_receipts,
 (SELECT candidate_chain_count FROM scope_decision_chain) AS candidate_chain_count
),
alternatives AS MATERIALIZED (
 SELECT 'A_VERSIONED_POLICY' AS alternative,
 (current_policy_versions>0 AND anchored_versions=current_policy_versions AND
  bound_operations>0 AND bindings_without_active_policy=0) AS technical_reuse_check,
 CASE WHEN candidate_chain_count=0 THEN false ELSE NULL::boolean END
 AS rule_competence_proven,
 'existing policy hashes and 69 active operation bindings do not prove rule-specific delegation' AS unmet_contract
 FROM measures
 UNION ALL
 SELECT 'B_DECLARATIVE_REGISTRY',
 attributable_scope_policies>0,
 CASE WHEN candidate_chain_count=0 THEN false ELSE NULL::boolean END,
 'scope matching registry has no verified issuer/authority receipt for a rule'
 FROM measures
 UNION ALL
 SELECT 'C_HUMAN_EVIDENCE',
 active_human_routes>0 AND active_scope_route>0 AND active_authority_channels>0
 AND real_human_receipts>0 AND rule_scope_evidence_receipts>0,
 CASE WHEN candidate_chain_count=0 THEN false ELSE NULL::boolean END,
 'no live scope decision route, authority policy or signed rule-scope receipt'
 FROM measures
 UNION ALL
 SELECT 'COMPOSITE_DESIGN',
 (SELECT technical_reuse_check FROM (SELECT
   (current_policy_versions>0 AND bound_operations>0 AND bindings_without_active_policy=0)
   AS technical_reuse_check FROM measures) z)
 AND attributable_scope_policies>0,
 CASE WHEN candidate_chain_count=0 THEN false ELSE NULL::boolean END,
 'design can reuse versioning, selectors, evidence and exceptional human routing, but cannot publish without owner delegation'
 FROM measures
)
SELECT a.alternative,a.technical_reuse_check,a.rule_competence_proven,
 CASE WHEN a.technical_reuse_check AND a.rule_competence_proven IS TRUE
      THEN 'OPERATIONAL_ADMISSION_CANDIDATE' ELSE 'HOLD_AUTHORITY' END AS verdict,
 a.unmet_contract,m.rule_count,m.selector_count,m.current_policy_versions,
 m.bound_operations,m.bindings_without_active_policy,m.attributable_scope_policies,
 m.active_scope_route,m.active_authority_channels,m.real_human_receipts,
 m.rule_scope_evidence_receipts,m.candidate_chain_count
FROM alternatives a CROSS JOIN measures m ORDER BY alternative;