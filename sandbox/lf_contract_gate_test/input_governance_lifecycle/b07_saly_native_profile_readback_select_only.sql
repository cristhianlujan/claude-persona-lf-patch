-- SALY B07: NATIVE PROFILE CREATION READBACK / SELECT ONLY, never an admission RPC.
-- Replace the sentinel ID only with execution_id returned by authenticated Issue/OIDC/Edge
-- for THIS request. Do not reuse historical COMPLETED executions. NO DML/DDL.
-- The profile pack PR #3835 is not the real EXEC-CREACION-PERFIL-LF-OIDC-* receipt.

WITH expected AS (
  SELECT '__UNFILLED_NEW_NATIVE_EXECUTION_ID__'::text AS execution_id,
         'PERFIL-PRODUCT-DIRECTOR-SALY'::text AS target_code,
         'profiles/saly_product_director'::text AS target_path
)
SELECT
  CASE WHEN e.execution_id IS NULL THEN 'BLOCK_RUN_MISSING_OR_SENTINEL'
       WHEN e.operation_code<>'CREACION_PERFIL_LF'
         OR e.target_type<>'PERFIL'
         OR e.target_code<>p.target_code
         OR e.target_repo<>'cristhianlujan/claude-persona-lf-patch'
         OR e.target_path<>p.target_path
       THEN 'BLOCK_NATIVE_RUN_TARGET_SCOPE_DRIFT'
       WHEN e.status<>'COMPLETED' THEN 'BLOCK_NATIVE_RUN_NOT_COMPLETED'
       ELSE 'CHECK_STEPS_AND_PROFILE_ROW' END AS assessment,
  e.execution_id,e.operation_code,e.target_type,e.target_code,e.target_path,
  e.status,e.created_at,e.completed_at,e.created_by_execution_id,
  e.manifest->>'router' AS router,
  e.manifest->>'governed_caller_method' AS caller_method,
  e.manifest->>'caller_workflow_ref' AS workflow_ref,
  e.manifest->>'caller_run_id' AS workflow_run_id,
  e.manifest->>'production_authorized' AS production_authorized
FROM expected p
LEFT JOIN public.lf_operation_execution e ON e.execution_id=p.execution_id;

WITH expected AS (
  SELECT '__UNFILLED_NEW_NATIVE_EXECUTION_ID__'::text AS execution_id
)
SELECT c.step_order,c.step_id,c.status AS contract_status,
       s.status AS recorded_status,s.evidence_ref,
       s.observed_at,
       CASE WHEN s.execution_id IS NULL THEN 'MISSING_EVIDENCE'
            ELSE 'VERIFY_STEP_CONTRACT_AND_JUDGE' END AS assessment
FROM public.lf_operation_steps c
CROSS JOIN expected p
LEFT JOIN public.lf_operation_execution_steps s
  ON s.execution_id=p.execution_id
 AND s.step_id=c.step_id
 AND s.step_order=c.step_order
WHERE c.operation_code='CREACION_PERFIL_LF'
ORDER BY c.step_order;

WITH expected AS (
  SELECT '__UNFILLED_NEW_NATIVE_EXECUTION_ID__'::text AS execution_id,
         'PERFIL-PRODUCT-DIRECTOR-SALY'::text AS code
)
SELECT a.codigo_activo,a.tipo_activo,a.estado_documental,
       a.estado_operativo,a.runtime_estado,a.owner_name,
       a.created_by_execution_id,a.archived_at,
       CASE WHEN a.codigo_activo IS NULL
            THEN 'BLOCK_NATIVE_PROFILE_ROW_NOT_REGISTERED'
            WHEN a.tipo_activo<>'PERFIL'
              OR a.estado_documental<>'CANDIDATO'
              OR a.estado_operativo<>'READ_ONLY'
              OR a.archived_at IS NOT NULL
              OR a.created_by_execution_id<>p.execution_id
            THEN 'BLOCK_PROFILE_ROW_OR_PROVENANCE_DRIFT'
            ELSE 'CHECK_RUNTIME_AND_IDENTITY' END AS assessment
FROM expected p
LEFT JOIN public.lf_activos a ON a.codigo_activo=p.code;

SELECT asset_type,action_code,operation_code,status,write_allowed
FROM public.lf_router_action_registry
WHERE asset_type='PERFIL' AND action_code='PROFILE_CREATE';

SELECT project_code,owner_name,owner_profile_code,identity_mode,status,
       authority_receipt_sha256,source_execution_id
FROM public.lf_ig_project_owner_v2
WHERE project_code='SALY';

SELECT operation_code,status,lifecycle_state_code,created_by_execution_id
FROM public.lf_operation_registry
WHERE operation_code='ACTUALIZACION_REGLA_SALY';

-- No assertion of Auth or production; if missing any valid step/asset, state BLOCK.
