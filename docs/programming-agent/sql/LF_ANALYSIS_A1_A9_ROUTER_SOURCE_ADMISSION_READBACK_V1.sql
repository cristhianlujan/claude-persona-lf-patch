-- LF Analysis A1-A9 — real source/Router admission readback.
-- 2026-11-03. READ ONLY; does not register/activate a profile or execute a model.
-- Source GitHub: profiles/programming_analysis_lf (candidate, not released).
WITH expected AS (
  SELECT 'PERFIL-PROGRAMMING-ANALYSIS-LF'::text profile_code,
         'programming_analysis_lf'::text profile_slug,
         'profiles/programming_analysis_lf'::text repo_path
), actual AS (
  SELECT e.profile_code,
    count(DISTINCT a.codigo_activo)::int asset_rows,
    count(DISTINCT r.profile_code)::int descriptor_rows,
    count(DISTINCT b.adapter_code)::int adapter_rows,
    bool_or(coalesce(r.descriptor_status='CURRENT',false)) descriptor_current,
    bool_or(coalesce(a.metadata->>'profile_slug'=e.profile_slug,false)) slug_matches,
    bool_or(coalesce(a.metadata->>'repo_path'=e.repo_path,false)) path_matches
  FROM expected e
  LEFT JOIN public.lf_activos a ON a.codigo_activo=e.profile_code
    AND a.tipo_activo='PERFIL' AND a.archived_at IS NULL
  LEFT JOIN public.lf_profile_selection_registry_v1 r ON r.profile_code=e.profile_code
  LEFT JOIN public.v_lf_router_adapter_bindings b ON b.target_asset_code=e.profile_code
  GROUP BY e.profile_code
), runtime AS (
  SELECT count(*)::int execution_count
  FROM public.lf_operation_execution
  WHERE operation_code='EJECUCION_PERFIL_LF'
    AND (target_code='PERFIL-PROGRAMMING-ANALYSIS-LF'
         OR manifest::text ILIKE '%PERFIL-PROGRAMMING-ANALYSIS-LF%'
         OR manifest::text ILIKE '%programming_analysis_lf%')
), receipts AS (
  SELECT count(*)::int total,
         count(*) FILTER (WHERE verdict='ACCEPT')::int accepted
  FROM private.lf_programming_context_handoff_receipts_v1
)
SELECT a.*, s.info AS source_eligibility, runtime.execution_count,
       receipts.total AS handoff_receipts,
       receipts.accepted AS accepted_receipts,
       CASE WHEN (s.info->>'eligible')::boolean IS DISTINCT FROM true THEN
         'BLOCK_ANALYSIS_PROFILE_SOURCE_NOT_REGISTERED_OR_ELIGIBLE'
       WHEN a.adapter_rows=0 THEN
         'BLOCK_ANALYSIS_ROUTER_ADAPTER_BINDING_MISSING'
       WHEN runtime.execution_count=0 THEN
         'BLOCK_ANALYSIS_REAL_PROFILE_EXECUTION_MISSING'
       WHEN receipts.accepted=0 THEN
         'BLOCK_PG01_ACCEPT_HANDOFF_MISSING'
       ELSE 'PRECHECK_ONLY_REQUIRE_CURRENTNESS_JUDGE_AND_EXACT_RUN_READBACK'
       END AS first_blocker,
       false AS production_authority_granted
FROM actual a
CROSS JOIN LATERAL (
  SELECT public.lf_profile_execution_source_eligibility_v1(a.profile_code) AS info
) s
CROSS JOIN runtime
CROSS JOIN receipts;
