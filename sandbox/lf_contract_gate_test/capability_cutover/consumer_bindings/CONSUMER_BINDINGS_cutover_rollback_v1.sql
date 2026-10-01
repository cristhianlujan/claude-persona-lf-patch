-- Reversible non-production rollback for SADM-PP-L5-022 / CONSUMER_BINDINGS.
do $$
declare
  v_execution_id constant text := 'EXEC-L5-CONSUMER-BINDINGS-ROLLBACK-V1-20261001';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid;
begin
  delete from public.lf_activo_relaciones
  where migration_batch_id=v_batch
    and created_by_execution_id='EXEC-L5-CONSUMER-BINDINGS-CUTOVER-V1-20261001';
  update public.lf_activos
  set estado_documental='CANDIDATO',estado_operativo='READ_ONLY',version='1.0.0-candidate',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('binding_state','ROLLED_BACK_TO_SOURCE_ONLY','registry_cutover_state','ROLLED_BACK'),
      updated_at=now(),updated_by_execution_id=v_execution_id
  where codigo_activo='CONSUMER_BINDINGS' and archived_at is null;
end $$;
