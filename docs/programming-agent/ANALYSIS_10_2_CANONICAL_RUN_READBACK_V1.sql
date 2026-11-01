-- SOURCE-ONLY / READ-ONLY. No INSERT, UPDATE, RPC writer, elevated role or synthetic RUN.
-- Repeatedly inspect the canonical LF Router -> profile -> RUN -> checkpoint gates.
-- Every count represents live catalog/readback; no alias is counted as persisted evidence.
WITH config AS (
 SELECT 'PERFIL-PROGRAMMING-ANALYSIS-LF'::text profile_code, 'LF'::text business
),
run_rows AS (
 SELECT e.execution_id,e.status,e.checkpoint_payload,e.created_at,e.manifest
 FROM public.lf_operation_execution e, config c
 WHERE e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_code=c.profile_code
   AND e.manifest->>'business'=c.business
),
answer AS (
 SELECT
   (SELECT COUNT(*) FROM public.lf_activos a,config c
      WHERE a.codigo_activo=c.profile_code AND a.tipo_activo='PERFIL'
        AND a.archived_at IS NULL) AS registered_profile_assets,
   (SELECT COUNT(*) FROM public.lf_profile_selection_registry_v1 d,config c
      WHERE d.profile_code=c.profile_code AND d.descriptor_status='CURRENT') AS current_selector_descriptors,
   (SELECT COUNT(*) FROM public.v_lf_router_adapter_bindings v,config c
      WHERE v.target_asset_code=c.profile_code) AS adapter_bindings,
   (SELECT COUNT(*) FROM run_rows) AS canonical_runs,
   (SELECT COUNT(*) FROM run_rows WHERE status='IN_PROGRESS') AS runs_in_progress,
   (SELECT COUNT(*) FROM run_rows
      WHERE checkpoint_payload ? 'analysis_stage_progress_v1') AS runs_with_a1_a9_progress,
   (SELECT COUNT(*) FROM run_rows
      WHERE checkpoint_payload::text LIKE '%10.1%'
        AND checkpoint_payload::text LIKE '%10.2%') AS runs_with_both_substep_markers_not_receipt_proof,
   (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
      JOIN run_rows e USING(execution_id)) AS official_step_rows,
   (SELECT MAX(created_at) FROM run_rows) AS newest_run_created_at
)
SELECT 'ANALYSIS_10_1_TO_10_2_READBACK_V1' AS schema_version,
       c.business,c.profile_code,a.*,
       public.lf_profile_execution_source_eligibility_v1(c.profile_code) AS source_eligibility,
       CASE
         WHEN a.registered_profile_assets=0 OR a.current_selector_descriptors=0
           THEN 'BLOCKED_PROFILE_NOT_REGISTERED'
         WHEN a.canonical_runs=0
           THEN 'BLOCKED_NO_CANONICAL_RUN'
         WHEN a.runs_with_a1_a9_progress=0
           THEN 'BLOCKED_NO_A1_A9_CHECKPOINT'
         ELSE 'REQUIRES_INDEPENDENT_RECEIPT_REVIEW'
       END AS diagnostic_only
FROM answer a CROSS JOIN config c;
