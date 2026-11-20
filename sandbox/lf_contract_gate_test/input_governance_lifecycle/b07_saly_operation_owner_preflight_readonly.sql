-- B07 SALY — preflight SQL SOLO LECTURA; NO registra ninguna operacion ni owner.
-- Ejecutar con rol de lectura tras verificar autoridad de la solicitud.
SELECT operation_code, version, status, source_model, source_repo,
       operation_family, operation_domain, operation_type,
       applies_to_asset_type, created_by_execution_id, lifecycle_state_code
FROM public.lf_operation_registry
WHERE operation_code = 'ACTUALIZACION_REGLA_SALY';

SELECT project_code, owner_name, owner_profile_code, identity_mode,
       status, authority_receipt_sha256, source_execution_id
FROM public.lf_ig_project_owner_v2
WHERE project_code = 'SALY';

SELECT codigo_activo, tipo_activo, estado_operativo
FROM public.lf_activos
WHERE tipo_activo = 'PERFIL'
  AND (codigo_activo ILIKE '%SALY%' OR codigo_activo ILIKE '%PRODUCT-DIRECTOR%')
ORDER BY codigo_activo;

SELECT to_regprocedure('public.lf_ig_saly_rule_finalize_b07_v1(text)') AS writer_installed,
       to_regclass('saly.reglas_versiones_b07') AS child_history_installed;

SELECT count(*) AS validado_conservado FROM saly.reglas WHERE estado = 'VALIDADO';
