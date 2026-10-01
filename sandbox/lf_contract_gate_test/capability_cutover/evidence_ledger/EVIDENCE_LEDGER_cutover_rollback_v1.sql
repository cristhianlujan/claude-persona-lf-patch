-- Reversible rollback for SADM-PP-L5-022 / EVIDENCE_LEDGER cutover.
-- Never mutates private.lf_evidence_ledger_v1 rows.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-EVIDENCE-LEDGER-ROLLBACK-V1-20261001';
  v_expected_manifest text;
begin
  select manifest_sha256 into v_expected_manifest from public.lf_capability_version_registry
  where capability_code='EVIDENCE_LEDGER' and version='1.1.0';
  if v_expected_manifest is null then raise exception 'BLOCK_EVIDENCE_LEDGER_ROLLBACK_VERSION_MISSING'; end if;
  if exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_LEDGER' and (version is distinct from '1.1.0' or manifest_sha256 is distinct from v_expected_manifest)) then raise exception 'BLOCK_EVIDENCE_LEDGER_ROLLBACK_CURRENT_DRIFT'; end if;
  delete from public.lf_capability_current where capability_code='EVIDENCE_LEDGER' and version='1.1.0' and manifest_sha256=v_expected_manifest;
  update public.lf_capability_registry set owner_scope='SUPER_ADMIN',status='ACTIVE',updated_at=now(),updated_by_execution_id=v_execution_id where capability_code='EVIDENCE_LEDGER';
  update public.lf_activos set estado_documental='CANDIDATO',estado_operativo='READ_ONLY',version=null,owner_name='SUPER_ADMIN',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('registry_cutover_state','ROLLED_BACK','ledger_rows_mutated',false),updated_at=now(),updated_by_execution_id=v_execution_id where codigo_activo='EVIDENCE_LEDGER' and archived_at is null;
  delete from public.lf_activo_relaciones where codigo_activo='EVIDENCE_LEDGER' and relacionado_codigo='LF_GOVERNANCE' and migration_batch_id='8c1d2f6c-4a1c-4f80-9d5d-022000000007'::uuid;
end $$;
