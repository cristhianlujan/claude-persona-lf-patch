-- SALY_DS_V1 / ACT-0001 — PRE-ADMISSION READBACK ONLY
-- Status: CANDIDATE / NO-GO. This SELECT does not grant business authority.
-- Context: GitHub issue #3714. Run with existing read-only SQL connector.
-- No DDL, no DML, no session role change, no effects.
WITH function_defs AS (
  SELECT p.proname AS function_name, pg_get_functiondef(p.oid) AS source
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname IN (
      'lf_router_route_v1',
      'lf_router_profile_after_selection_v1',
      'lf_router_profile_execution_handoff_v1',
      'lf_router_profile_execution_handoff_validate_v1'
    )
), current_businesses AS (
  SELECT
    max(status) FILTER (WHERE business_code='LF') AS lf_status,
    max(status) FILTER (WHERE business_code='SALY') AS saly_status
  FROM public.lf_router_business_catalog_v1
)
SELECT
  'SALY_ROUTER_UI_REVIEW_PRE_ADMISSION_V1'::text AS evidence_contract,
  current_businesses.lf_status,
  current_businesses.saly_status,
  (SELECT md5(source) FROM function_defs WHERE function_name='lf_router_route_v1') AS router_source_md5,
  (SELECT source LIKE '%b.status=''ENABLED''%'
   FROM function_defs WHERE function_name='lf_router_route_v1') AS router_requires_enabled_business,
  (SELECT position('p_stage1->>''negocio_codigo''<>''LF''' IN source)>0
   FROM function_defs WHERE function_name='lf_router_profile_after_selection_v1') AS after_selection_lf_only_guard,
  (SELECT position('upper(coalesce(p_business,'''')) <> ''LF''' IN source)>0
   FROM function_defs WHERE function_name='lf_router_profile_execution_handoff_v1') AS handoff_builder_lf_only_guard,
  (SELECT position('p_handoff->>''business'' IS DISTINCT FROM ''LF''' IN source)>0
   FROM function_defs WHERE function_name='lf_router_profile_execution_handoff_validate_v1') AS handoff_validator_lf_only_guard,
  (SELECT count(*) FROM function_defs) AS function_count,
  (SELECT count(*) FROM public.lf_operation_step_contracts
   WHERE operation_code='ACTUALIZACION_ROUTER_LF'
   AND status='ACTIVE_ENFORCEMENT') AS governed_router_step_count,
  'PRE_ADMISSION_DIAGNOSTIC_ONLY_NOT_RUNTIME_ACCEPTANCE'::text AS evidence_status
FROM current_businesses;
