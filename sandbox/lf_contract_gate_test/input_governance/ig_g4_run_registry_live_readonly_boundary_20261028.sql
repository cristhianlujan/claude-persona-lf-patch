-- LF IG N-4 / G4. Live read-only integration of existing IG run and
-- canonical human-decision authority registries. No new run or schema.
-- This verifies the authority frontier only; it never emits approval.
-- P10 publication guard remains the enforcing write boundary.
WITH current_ig AS MATERIALIZED (
 SELECT r.id AS run_id,r.version_id,r.pantalla_id,r.status,
        r.invalidated_at,r.source_snapshot_sha256
 FROM programacion.input_readiness_runs r
 WHERE r.status='COMPLETED' AND r.invalidated_at IS NULL
 ORDER BY r.id DESC LIMIT 1
),
run_currentness AS MATERIALIZED (
 SELECT r.*,
        programacion.fn_input_governance_continuation_currentness_v1(r.run_id) AS verdict
 FROM current_ig r
),
consumer_contract AS MATERIALIZED (
 SELECT r.run_id, c.especificacion->'allowed_consumers' AS consumers
 FROM run_currentness r
 LEFT JOIN programacion.contratos c ON c.version_id=r.version_id
    AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    AND c.estado='defined'
),
authority_routes AS MATERIALIZED (
 SELECT count(*)::integer AS all_routes,
        count(*) FILTER (WHERE status='ACTIVE')::integer AS active_routes
 FROM private.lf_human_decision_route_policies_v1
 WHERE producer_code='INPUT_GOVERNANCE'
   AND subject_type='RULE_APPLICABILITY_CHANGE'
),
authority_issuers AS MATERIALIZED (
 SELECT count(*) FILTER (WHERE status='ACTIVE')::integer AS active_issuers
 FROM private.lf_human_decision_authority_policies_v1
),
authority_receipts AS MATERIALIZED (
 SELECT count(*)::integer AS scope_receipt_count
 FROM private.lf_human_decision_receipts_v1 rc
 JOIN private.lf_human_decision_requests_v1 rq
  ON rq.request_id=rc.request_id
 WHERE rq.producer_code='INPUT_GOVERNANCE'
   AND rq.subject_type='RULE_APPLICABILITY_CHANGE'
),
assessment AS MATERIALIZED (
 SELECT r.run_id,r.status AS run_status,r.pantalla_id,
        r.verdict->>'code' AS currentness_code,
        COALESCE((r.verdict->>'continuation_current')::boolean,false) AS run_current,
        (jsonb_typeof(c.consumers)='array' AND c.consumers ? 'CONTEXT_PACK') AS consumer_supported,
        a.all_routes,a.active_routes,i.active_issuers,
        h.scope_receipt_count
 FROM run_currentness r
 LEFT JOIN consumer_contract c USING(run_id)
 CROSS JOIN authority_routes a
 CROSS JOIN authority_issuers i
 CROSS JOIN authority_receipts h
)
SELECT run_id,pantalla_id,currentness_code,
       COALESCE(consumer_supported,false) AS consumer_supported,
       all_routes,active_routes,active_issuers,scope_receipt_count,
       CASE
        WHEN NOT run_current THEN 'HOLD_IG_RUN_NOT_CURRENT'
        WHEN NOT COALESCE(consumer_supported,false) THEN 'HOLD_CONSUMER_NOT_ALLOWED'
        WHEN active_routes=0 THEN 'HOLD_NO_SCOPE_AUTHORITY_ROUTE'
        WHEN active_issuers=0 THEN 'HOLD_NO_ACTIVE_AUTHORITY_ISSUER'
        WHEN scope_receipt_count=0 THEN 'HOLD_NO_SCOPE_RECEIPT'
        ELSE 'REQUIRES_EXACT_RULE_SCOPE_RECEIPT_VERIFICATION'
       END AS g4_scope_change_prepublication
FROM assessment;
