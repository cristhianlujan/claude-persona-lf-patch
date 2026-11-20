-- SALY_DS_V1 — exact-scope admission guard / READ-ONLY READBACK
-- Purpose: prove that a generic read-only profile mode cannot be treated as
-- business/asset-level authority. Does not grant rights or change records.
-- 2026-11-09 | Issue #3714 | PR #3715
WITH facts AS (
 SELECT
   (SELECT status FROM public.lf_router_business_catalog_v1 WHERE business_code='SALY') AS saly_status,
   (SELECT status FROM public.lf_router_business_catalog_v1 WHERE business_code='LF') AS lf_status,
   (SELECT count(*) FROM private.lf_reusable_policy_registry_v1
    WHERE status='VIGENTE' AND 'SALY'=ANY(business_scope)) AS saly_policies,
   (SELECT count(*) FROM public.lf_router_governed_callers
    WHERE status='ACTIVE'
      AND (upper(coalesce(notes,'')) LIKE '%SALY%'
        OR upper(coalesce(literal_template,'')) LIKE '%SALY%')) AS candidate_saly_callers_by_text,
   (SELECT count(*) FROM public.lf_operation_mode_bindings
    WHERE operation_code='EJECUCION_PERFIL_LF'
      AND status='ACTIVE' AND allowed AND NOT write_allowed) AS generic_read_only_modes,
   (SELECT count(*) FROM public.lf_router_action_registry
    WHERE asset_type='PERFIL' AND action_code='PROFILE_EXECUTION'
      AND operation_code='EJECUCION_PERFIL_LF'
      AND status='ACTIVE' AND NOT write_allowed) AS general_profile_bindings,
   (SELECT count(*) FROM public.lf_router_governed_callers
    WHERE status='ACTIVE') AS active_governed_caller_count,
   (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='public' AND table_name='lf_operation_mode_bindings'
      AND column_name IN ('business_code','negocio_codigo','target_code','target_asset')) AS direct_scope_columns
)
SELECT 'SALY_DS_AUTHORITY_PREFLIGHT_V1' AS contract,
  lf_status,saly_status,saly_policies,candidate_saly_callers_by_text,
  active_governed_caller_count,generic_read_only_modes,general_profile_bindings,
  direct_scope_columns,
  CASE
   WHEN lf_status='ENABLED' AND saly_status<>'ENABLED'
    AND saly_policies=0 AND candidate_saly_callers_by_text=0
    AND generic_read_only_modes>0 AND general_profile_bindings>0
    AND direct_scope_columns=0
   THEN 'NO_GO_EXACT_SALY_AUTHORITY_NOT_EVIDENCED'
   ELSE 'MANUAL_AUTHORITY_RECONCILIATION_REQUIRED'
  END AS evidence_verdict,
  false AS saly_permission_granted,
  false AS runtime_execution_proven
FROM facts;
