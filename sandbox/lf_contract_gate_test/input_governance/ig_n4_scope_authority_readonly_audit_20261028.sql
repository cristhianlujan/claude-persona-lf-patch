-- LF IG G4 | N-4 publication provenance audit | READ ONLY | 2026-10-28
-- This is a documentary authority check, not proof that an active selector
-- should be revoked, not a production guard, and not a replacement for owner
-- approval. Treat false/missing approval evidence as NEEDS_AUTHORITY_REVIEW.
-- EKB IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001.
WITH selectors AS (
  SELECT r.id rule_id,r.codigo rule_code,r.valor_config->'applicability_v1' selector,
         r.valor_config->'applicability_v1'->'provenance' provenance
  FROM lf_ops.reglas r
  WHERE r.estado='VIGENTE'
    AND r.valor_config->'applicability_v1'->>'status'='ACTIVE'
), events AS (
  SELECT s.rule_id,s.rule_code,s.provenance,
         d.id AS design_decision_id,d.evento_tipo AS design_decision_type,
         d.payload->>'acceptance_declared' AS design_accepted,
         d.payload->>'production_authorized' AS design_production_authorized,
         r.id AS r14_decision_id,r.evento_tipo AS r14_decision_type,
         r.payload->>'acceptance_declared' AS r14_accepted,
         r.payload->>'production_authorized' AS r14_production_authorized
  FROM selectors s
  LEFT JOIN public.lf_eventos d ON d.id=CASE
    WHEN s.provenance->>'decision_event_id' ~ '^[0-9]+$'
      THEN (s.provenance->>'decision_event_id')::bigint
    ELSE NULL END
  LEFT JOIN public.lf_eventos r ON r.id=CASE
    WHEN s.provenance->>'r14_event_id' ~ '^[0-9]+$'
      THEN (s.provenance->>'r14_event_id')::bigint
    ELSE NULL END
)
SELECT count(*) AS active_selectors,
  count(*) FILTER (WHERE design_decision_id IS NOT NULL
    AND r14_decision_id IS NOT NULL) AS linked_events_exist,
  count(*) FILTER (WHERE design_accepted='true'
    OR r14_accepted='true') AS explicit_acceptance_true_in_linked_events,
  count(*) FILTER (WHERE design_production_authorized='true'
    OR r14_production_authorized='true') AS explicit_production_authorization_true,
  count(*) FILTER (WHERE design_accepted='false'
    AND r14_accepted='false') AS both_events_acceptance_false,
  count(*) FILTER (WHERE design_production_authorized='false'
    AND r14_production_authorized='false') AS both_events_production_false,
  array_agg(DISTINCT design_decision_id) AS design_event_ids,
  array_agg(DISTINCT r14_decision_id) AS r14_event_ids
FROM events;

-- Independent complementary evidence: release readiness vs per-rule scope.
SELECT id,evento_tipo,entidad_codigo,
       payload->>'acceptance_declared' AS acceptance_declared,
       payload->>'production_authorized' AS production_authorized,
       left(descripcion,260) AS documentary_description
FROM public.lf_eventos
WHERE id IN (19948,19951,19962)
ORDER BY id;

-- Technical human-decision/provenance counts; zero rows are not an approval.
SELECT
 (SELECT count(*) FROM programacion.human_decisions) AS human_decision_rows,
 (SELECT count(*) FROM programacion.provenance_receipts
   WHERE receipt_kind='HUMAN_DECISION') AS matching_provenance_receipts;

-- Do not infer absence of all possible approvals from these tables alone.
-- The canonical per-rule scope authority registry/contract is still unverified.
