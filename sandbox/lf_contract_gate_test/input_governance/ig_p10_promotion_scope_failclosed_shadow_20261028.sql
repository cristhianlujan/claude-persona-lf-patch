-- P10 / LF N-4: executable READ-ONLY PostgreSQL scope/promotion shadow.
-- TEST ONLY: fixture authority booleans are NOT authentic owner receipts.
-- No DB writes/DDL, Router, promotion, release or replacement for source parity.
-- EKB: IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001.
WITH screens AS MATERIALIZED (SELECT count(*)::numeric n FROM lf_ops.pantallas),
test_cases AS MATERIALIZED (
 SELECT * FROM (VALUES
  ('P10N01_POST_PROMOTION_WITHOUT_SCOPE', 'VIGENTE', 'ABSENT', TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, 16, FALSE, FALSE, TRUE),
  ('P10N02_CANDIDATE_NOT_EXECUTABLE', 'CANDIDATO', 'ABSENT', TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, 16, FALSE, FALSE, FALSE),
  ('P10P01_AUTHORIZED_FUTURE_TARGET', 'VIGENTE', 'ACTIVE', TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, 1, TRUE, FALSE, FALSE),
  ('P10N03_UNMATCHED_TARGET', 'VIGENTE', 'ACTIVE', FALSE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N04_OTHER_CONSUMER', 'VIGENTE', 'ACTIVE', TRUE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N05_UNVERIFIED_AUTHORITY', 'VIGENTE', 'ACTIVE', TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N06_STALE_AUTHORITY', 'VIGENTE', 'ACTIVE', TRUE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N07_SCOPE_SHA_MISMATCH', 'VIGENTE', 'ACTIVE', TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N08_UNRESOLVED_CONFLICT', 'VIGENTE', 'ACTIVE', TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N09_UNRESOLVED_SELECTOR', 'VIGENTE', 'UNRESOLVED', TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N10_ACTIVE_BUT_CANDIDATE', 'CANDIDATO', 'ACTIVE', TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10P02_PRESERVE_LEGACY_EXPLICIT', 'VIGENTE', 'ABSENT', TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, TRUE, 16, FALSE, TRUE, FALSE),
  ('P10P03_PRESERVE_PHYSICAL_NO_NEW_SCOPE', 'VIGENTE', 'ACTIVE', FALSE, TRUE, FALSE, TRUE, TRUE, FALSE, TRUE, 1, FALSE, TRUE, FALSE),
  ('P10P04_AUTHORIZED_BROAD_POLICY', 'VIGENTE', 'ACTIVE', TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, 30, TRUE, FALSE, FALSE),
  ('P10N11_NO_DUPLICATE_EXPLICIT', 'VIGENTE', 'ACTIVE', TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, 30, FALSE, TRUE, FALSE),
  ('P10P05_EXPLICIT_WITH_UNPROVEN_SCOPE', 'VIGENTE', 'ACTIVE', TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, TRUE, 1, FALSE, TRUE, FALSE),
  ('P10N12_NULL_MATCH_NOT_TRUE', 'VIGENTE', 'ACTIVE', NULL, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N13_BELOW_FREQUENCY_THRESHOLD', 'VIGENTE', 'ABSENT', TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N14_UNVERIFIED_CONSUMER_AND_OWNER', 'VIGENTE', 'ACTIVE', TRUE, FALSE, FALSE, TRUE, TRUE, FALSE, FALSE, 1, FALSE, FALSE, FALSE),
  ('P10N15_EXPLICIT_CANDIDATE_ANALYTIC_ONLY', 'CANDIDATO', 'ABSENT', TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, TRUE, 16, FALSE, TRUE, FALSE)
 ) AS v(case_id,rule_state,selector_state,matcher_result,consumer_allowed,authority_verified,authority_current,scope_sha_bound,has_conflict,physical_existing,physical_screens,expected_new_scope,expected_existing,expected_legacy_global)
),
reference_guard AS MATERIALIZED (
 SELECT t.*,
  (t.rule_state='VIGENTE'
   AND t.selector_state='ACTIVE'
   AND t.matcher_result IS TRUE
   AND t.consumer_allowed IS TRUE
   AND t.authority_verified IS TRUE
   AND t.authority_current IS TRUE
   AND t.scope_sha_bound IS TRUE
   AND t.has_conflict IS FALSE
   AND t.physical_existing IS FALSE) AS new_scope_shadow,
  (t.physical_existing IS TRUE) AS existing_link_preserved_shadow,
  (t.rule_state='VIGENTE'
   AND t.selector_state='ABSENT'
   AND t.physical_existing IS FALSE
   AND t.physical_screens >= (SELECT n*0.25 FROM screens)) AS legacy_frequency_shadow
 FROM test_cases t
),
verified AS MATERIALIZED (
 SELECT *,
  (new_scope_shadow IS NOT DISTINCT FROM expected_new_scope
   AND existing_link_preserved_shadow IS NOT DISTINCT FROM expected_existing
   AND legacy_frequency_shadow IS NOT DISTINCT FROM expected_legacy_global) AS passes
 FROM reference_guard
),
live_candidate AS MATERIALIZED (
 SELECT r.id, count(DISTINCT rp.pantalla_id)::integer physical_screens
 FROM lf_ops.reglas r
 LEFT JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
 WHERE r.estado='CANDIDATO'
  AND jsonb_typeof(r.valor_config->'applicability_v1') IS DISTINCT FROM 'object'
 GROUP BY r.id
),
current_risk AS MATERIALIZED (
 SELECT count(*) candidate_without_selector,
  count(*) FILTER(WHERE physical_screens >= (SELECT n*0.25 FROM screens))
   AS at_risk_if_technically_promoted
 FROM live_candidate
)
SELECT count(*)::integer tests,
 count(*) FILTER(WHERE passes)::integer passes,
 count(*) FILTER(WHERE passes IS NOT TRUE)::integer failures,
 array_agg(case_id ORDER BY case_id) FILTER(WHERE passes IS NOT TRUE) failed_ids,
 count(*) FILTER(WHERE legacy_frequency_shadow IS TRUE AND new_scope_shadow IS FALSE)
  ::integer legacy_bypass_cases_demonstrated,
 (SELECT candidate_without_selector FROM current_risk)::integer live_candidate_without_selector,
 (SELECT at_risk_if_technically_promoted FROM current_risk)
  ::integer live_frequency_exposure_if_promoted,
 (SELECT n FROM screens) real_target_count,
 CASE WHEN count(*)=20 AND count(*) FILTER(WHERE passes IS NOT TRUE)=0
 THEN 'SHADOW_CONTRACT_PASS_NOT_PRODUCTION' ELSE 'SHADOW_CONTRACT_FAIL' END verdict
FROM verified;
