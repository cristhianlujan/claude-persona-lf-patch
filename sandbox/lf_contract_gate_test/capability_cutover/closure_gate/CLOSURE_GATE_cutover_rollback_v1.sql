-- Reversible authority rollback for SADM-PP-L5-022 / CLOSURE_GATE.
do $$
declare
  v_execution_id constant text := 'EXEC-L5-CLOSURE-GATE-ROLLBACK-V1-20261001';
  v_expected_manifest text;
begin
  select manifest_sha256 into v_expected_manifest
  from public.lf_capability_version_registry
  where capability_code='CLOSURE_GATE' and version='1.0.0';
  if v_expected_manifest is null then raise exception 'BLOCK_CLOSURE_GATE_ROLLBACK_VERSION_MISSING'; end if;
  if exists(
    select 1 from public.lf_capability_current
    where capability_code='CLOSURE_GATE'
      and (version is distinct from '1.0.0' or manifest_sha256 is distinct from v_expected_manifest)
  ) then raise exception 'BLOCK_CLOSURE_GATE_ROLLBACK_CURRENT_DRIFT'; end if;
  delete from public.lf_capability_current
  where capability_code='CLOSURE_GATE' and version='1.0.0' and manifest_sha256=v_expected_manifest;
  update public.lf_capability_registry
  set status='DEPRECATED',updated_at=now(),updated_by_execution_id=v_execution_id
  where capability_code='CLOSURE_GATE';
  update public.lf_activos
  set estado_documental='CANDIDATO',estado_operativo='READ_ONLY',version='1.0.0-candidate',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('registry_cutover_state','ROLLED_BACK'),
      updated_at=now(),updated_by_execution_id=v_execution_id
  where codigo_activo='CLOSURE_GATE' and archived_at is null;
end $$;
