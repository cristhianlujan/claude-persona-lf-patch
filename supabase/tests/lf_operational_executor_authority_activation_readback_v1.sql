-- LF_OPERATION_EXECUTOR_AUTHORITY_READBACK_V1
-- Read-only report. This file never authorizes or changes an operation.
-- Run through the existing Supabase READ_ONLY connector; no elevated grants.
WITH facts AS (
 SELECT
 (SELECT count(*) FROM private.lf_human_decision_classification_rules_v1
  WHERE producer_code='LF_OPERATION_EXECUTOR'
    AND subject_type='OPERATIONAL_EXECUTION'
    AND decision_class='DATA_OPERATIONS' AND status='ACTIVE')
  AS active_decision_class_rules,
 (SELECT count(*) FROM private.lf_human_decision_route_policies_v1
  WHERE producer_code='LF_OPERATION_EXECUTOR'
    AND subject_type='OPERATIONAL_EXECUTION'
    AND decision_class='DATA_OPERATIONS' AND status='ACTIVE')
  AS active_decision_routes,
 (SELECT count(*) FROM private.lf_human_decision_route_policies_v1
  WHERE producer_code='LF_OPERATION_EXECUTOR'
    AND subject_type='OPERATIONAL_EXECUTION'
    AND status='PENDING_AUTHORITY')
  AS pending_authority_routes,
 (SELECT count(*) FROM private.lf_human_decision_authority_policies_v1
  WHERE status='ACTIVE')
  AS active_authority_policies_total,
 (SELECT count(*)
    FROM private.lf_human_decision_route_policies_v1 r
    JOIN private.lf_human_decision_authority_policies_v1 a
      ON a.authority_ref=r.required_authority_ref
     AND a.reviewer_role=r.required_reviewer_role
    JOIN programacion.provenance_channels ch
      ON ch.channel_code=a.issuer_channel
   WHERE r.producer_code='LF_OPERATION_EXECUTOR'
     AND r.subject_type='OPERATIONAL_EXECUTION'
     AND r.decision_class='DATA_OPERATIONS'
     AND r.status='ACTIVE' AND a.status='ACTIVE'
     AND a.receipt_kind='HUMAN_ROUTING_DECISION'
     AND ch.allowed_kinds @> ARRAY['HUMAN_ROUTING_DECISION']::text[])
  AS active_authority_with_verified_channel_for_operation,
 (SELECT count(*) FROM programacion.provenance_channels
   WHERE allowed_kinds @> ARRAY['HUMAN_ROUTING_DECISION']::text[])
  AS channels_allowed_for_human_routing_decision,
 (SELECT count(*) FROM private.lf_human_decision_requests_v1
  WHERE producer_code='LF_OPERATION_EXECUTOR'
    AND subject_type='OPERATIONAL_EXECUTION' AND status='DECIDED')
  AS decided_operational_requests,
 (SELECT count(*) FROM private.lf_human_decision_receipts_v1 d
  JOIN private.lf_human_decision_requests_v1 r ON r.request_id=d.request_id
  WHERE r.producer_code='LF_OPERATION_EXECUTOR'
    AND r.subject_type='OPERATIONAL_EXECUTION'
    AND r.status='DECIDED' AND d.decision_code='APPROVE')
  AS operational_approval_receipts,
 (SELECT count(*) FROM public.lf_operation_registry
  WHERE operation_code='EJECUCION_OPERATIVA_LF')
  AS operational_operation_count,
 (SELECT count(*) FROM public.lf_router_action_registry
  WHERE asset_type='OPERATIONAL_DB' AND action_code='OPERATION_EXECUTE'
    AND operation_code='EJECUCION_OPERATIVA_LF' AND status='ACTIVE')
  AS operational_router_binding_count,
 (SELECT count(*) FROM pg_roles
  WHERE rolname IN ('lf_operational_admission_authority',
                    'lf_operation_executor_runtime'))
  AS operational_group_roles,
 (SELECT count(*) FROM public.lf_router_action_registry
  WHERE asset_type='DB' AND action_code='UPDATE'
    AND operation_code='ACTUALIZACION_DB_LF' AND status='ACTIVE')
  AS migration_train_binding_count
)
SELECT jsonb_build_object(
 'schema_version','LF_OPERATION_EXECUTOR_AUTHORITY_READBACK_V1',
 'source','EXISTING_LF_CATALOGUES_READ_ONLY',
 'counts',to_jsonb(facts),
 'blocking_codes',to_jsonb(array_remove(ARRAY[
   CASE WHEN active_decision_class_rules<>1
     THEN 'BLOCK_OPERATIONAL_DECISION_CLASSIFICATION_NOT_EXACT' END,
   CASE WHEN active_decision_routes<>1
     THEN 'BLOCK_OPERATIONAL_DECISION_ROUTE_NOT_ACTIVE' END,
   CASE WHEN active_authority_with_verified_channel_for_operation<>1
     THEN 'BLOCK_OPERATIONAL_AUTHORITY_AND_CHANNEL_BINDING_NOT_CURRENT' END,
   CASE WHEN channels_allowed_for_human_routing_decision<1
     THEN 'BLOCK_HUMAN_ROUTING_PROVENANCE_CHANNEL_NOT_PROVISIONED' END,
   CASE WHEN decided_operational_requests<1 OR operational_approval_receipts<1
     THEN 'BLOCK_OPERATIONAL_VERIFIED_APPROVAL_NOT_PRESENT' END,
   CASE WHEN operational_operation_count<>1 OR operational_router_binding_count<>1
     THEN 'BLOCK_OPERATIONAL_ROUTER_NOT_INSTALLED' END,
   CASE WHEN operational_group_roles<>2
     THEN 'BLOCK_OPERATIONAL_ROLE_GROUPS_NOT_INSTALLED' END,
   CASE WHEN migration_train_binding_count<>1
     THEN 'BLOCK_MIGRATION_TRAIN_ROUTE_NOT_PRESERVED' END
 ],NULL::text)),
 'authorization_verified',false,
 'note','Catalog counts are discovery only. Even zero blockers do not prove a specific decision is current, nor authorize deployment.'
) AS readback
FROM facts;
