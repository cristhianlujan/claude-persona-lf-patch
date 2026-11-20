-- P10 forward-only scope boundary READ-ONLY regression.
-- This tests a reference decision matrix and CURRENT data snapshot invariants.
-- It is NOT evidence of candidate DDL compilation or true trigger invocation.
-- No historic rule is changed/reclassified.
WITH
events AS MATERIALIZED (
 SELECT * FROM (VALUES
  ('CREATE_CANDIDATE_WITH_SELECTOR', 'RULE', NULL, 'CANDIDATO', NULL, 'ACTIVE', FALSE, NULL, FALSE, FALSE),
  ('CREATE_VIGENTE_WITH_SELECTOR', 'RULE', NULL, 'VIGENTE', NULL, 'ACTIVE', FALSE, NULL, FALSE, TRUE),
  ('CREATE_VIGENTE_EMPTY', 'RULE', NULL, 'VIGENTE', NULL, 'ABSENT', FALSE, NULL, FALSE, FALSE),
  ('PROMOTE_LINKED_CANDIDATE', 'RULE', 'CANDIDATO', 'VIGENTE', 'ABSENT', 'ABSENT', TRUE, NULL, FALSE, TRUE),
  ('PROMOTE_UNLINKED_LOCAL', 'RULE', 'CANDIDATO', 'VIGENTE', 'ABSENT', 'ABSENT', FALSE, NULL, FALSE, FALSE),
  ('PROMOTE_ACTIVE_WITHOUT_LINKS', 'RULE', 'CANDIDATO', 'VIGENTE', 'ACTIVE', 'ACTIVE', FALSE, NULL, FALSE, TRUE),
  ('EDIT_VIGENTE_SELECTOR', 'RULE', 'VIGENTE', 'VIGENTE', 'ACTIVE', 'UNRESOLVED', FALSE, NULL, FALSE, TRUE),
  ('EDIT_VIGENTE_ABSENT_TO_UNRESOLVED', 'RULE', 'VIGENTE', 'VIGENTE', 'ABSENT', 'UNRESOLVED', TRUE, NULL, FALSE, TRUE),
  ('REVOKE_VIGENTE_RULE', 'RULE', 'VIGENTE', 'CANDIDATO', 'ACTIVE', 'ACTIVE', TRUE, NULL, FALSE, FALSE),
  ('EDIT_UNRELATED_FIELD', 'RULE', 'VIGENTE', 'VIGENTE', 'ACTIVE', 'ACTIVE', TRUE, NULL, FALSE, FALSE),
  ('AUTHOR_CANDIDATE_SELECTOR', 'RULE', 'CANDIDATO', 'CANDIDATO', 'ABSENT', 'ACTIVE', TRUE, NULL, FALSE, FALSE),
  ('LINK_VIGENTE_RULE', 'LINK', NULL, NULL, NULL, NULL, FALSE, 'VIGENTE', TRUE, TRUE),
  ('LINK_CANDIDATE_RULE', 'LINK', NULL, NULL, NULL, NULL, FALSE, 'CANDIDATO', TRUE, FALSE),
  ('LINK_NOOP_UPDATE', 'LINK', NULL, NULL, NULL, NULL, FALSE, 'VIGENTE', FALSE, FALSE),
  ('REPOINT_LINK_TO_VIGENTE', 'LINK', NULL, NULL, NULL, NULL, FALSE, 'VIGENTE', TRUE, TRUE),
  ('REPOINT_LINK_TO_CANDIDATO', 'LINK', NULL, NULL, NULL, NULL, FALSE, 'CANDIDATO', TRUE, FALSE),
  ('NEW_SCREEN_SCOPE_NOT_IMPLICIT', 'SCREEN', NULL, NULL, NULL, NULL, FALSE, NULL, FALSE, FALSE)
 ) AS v(case_id,kind,old_state,new_state,old_selector,new_selector,
         had_links,target_rule_state,link_changed,expected_hold)
),
decisions AS MATERIALIZED (
 SELECT e.*,
 CASE
  WHEN kind='RULE' AND new_state='VIGENTE' AND (
     (old_state IS NULL AND new_selector='ACTIVE')
     OR (old_state='VIGENTE' AND old_selector IS DISTINCT FROM new_selector)
     OR (old_state IS DISTINCT FROM 'VIGENTE' AND had_links IS TRUE)
     OR (old_state IS DISTINCT FROM 'VIGENTE' AND new_selector='ACTIVE')
  ) THEN true
  WHEN kind='LINK' AND link_changed IS TRUE
     AND target_rule_state='VIGENTE' THEN true
  ELSE false END AS actual_hold
 FROM events e
),
screens AS MATERIALIZED (SELECT id FROM lf_ops.pantallas),
existing AS MATERIALIZED (
 SELECT p.id pantalla_id,x.regla_id,x.binding_source
 FROM screens p CROSS JOIN LATERAL
 programacion.fn_input_effective_rule_links_v1(p.id,'INPUT_GOVERNANCE') x
),
snapshot AS MATERIALIZED (
 SELECT pantalla_id,regla_id
 FROM existing WHERE binding_source='DERIVED_GLOBAL'
),
reconstructed AS MATERIALIZED (
 SELECT pantalla_id,regla_id,binding_source FROM existing
 WHERE binding_source<>'DERIVED_GLOBAL'
 UNION ALL
 SELECT pantalla_id,regla_id,'DERIVED_GLOBAL'::text FROM snapshot
),
diff AS MATERIALIZED (
 (SELECT * FROM existing EXCEPT ALL SELECT * FROM reconstructed)
 UNION ALL
 (SELECT * FROM reconstructed EXCEPT ALL SELECT * FROM existing)
),
future_candidates AS MATERIALIZED (
 SELECT id FROM lf_ops.reglas WHERE estado='CANDIDATO'
),
metrics AS MATERIALIZED (
 SELECT
  (SELECT count(*) FROM existing) historical_link_rows,
  (SELECT count(*) FROM snapshot) frozen_legacy_pairs,
  (SELECT count(*) FROM diff) historical_link_differences,
  (SELECT count(*) FROM snapshot s JOIN future_candidates c ON s.regla_id=c.id)
    as candidate_pairs_in_snapshot,
  (SELECT count(*) FROM snapshot s WHERE s.pantalla_id=(SELECT max(id)+1 FROM screens))
    as hypothetical_new_screen_inherited_pairs
)
SELECT count(*)::integer cases,
 count(*) FILTER(WHERE actual_hold IS NOT DISTINCT FROM expected_hold)::integer passed,
 count(*) FILTER(WHERE actual_hold IS DISTINCT FROM expected_hold)::integer failed,
 array_agg(case_id ORDER BY case_id) FILTER(WHERE actual_hold IS DISTINCT FROM expected_hold) failed_ids,
 (SELECT historical_link_rows FROM metrics) historical_link_rows,
 (SELECT frozen_legacy_pairs FROM metrics) frozen_legacy_pairs,
 (SELECT historical_link_differences FROM metrics) historical_link_differences,
 (SELECT candidate_pairs_in_snapshot FROM metrics) candidate_pairs_in_snapshot,
 (SELECT hypothetical_new_screen_inherited_pairs FROM metrics) new_screen_inherited_pairs,
 CASE WHEN count(*)=17
  AND count(*) FILTER(WHERE actual_hold IS DISTINCT FROM expected_hold)=0
  AND (SELECT historical_link_differences FROM metrics)=0
  AND (SELECT candidate_pairs_in_snapshot FROM metrics)=0
  AND (SELECT hypothetical_new_screen_inherited_pairs FROM metrics)=0
 THEN 'P10_FORWARD_PROCESS_SHADOW_PASS'
 ELSE 'P10_FORWARD_PROCESS_SHADOW_FAIL' END verdict
FROM decisions;
