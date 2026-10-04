-- Temporary rollback-only diagnostic for SC-M4.3D.
-- It performs no qualifying action; it only exposes post-source state.
SELECT jsonb_build_object(
  'marker','SC_M43D_POST_SOURCE_DIAGNOSTIC',
  'revision_sha256',public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF'),
  'qualification_current',public.lf_qualification_current_v1('OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF')),
  'matching_receipts',coalesce((
    select jsonb_agg(jsonb_build_object(
      'qualification_id',qualification_id,
      'revision_sha256',revision_sha256,
      'lifecycle_state_code',lifecycle_state_code,
      'created_by_execution_id',created_by_execution_id,
      'qualified_at',qualified_at
    ) order by created_at desc)
    from public.lf_qualification_receipts
    where subject_type='OPERATION'
      and subject_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
      and revision_sha256=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF')
      and invalidated_at is null
  ),'[]'::jsonb)
) as sc_m43d_post_source_diagnostic;

SELECT 'PASS_SC_M43D_DIAGNOSTIC_ONLY' AS probe_result;
