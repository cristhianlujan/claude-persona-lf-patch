-- Reversible rollback for SADM-PP-L5-022 / FINAL_EVIDENCE.
do $$
declare v_execution_id constant text := 'EXEC-L5-FINAL-EVIDENCE-ROLLBACK-V1-20261001'; v_expected_manifest text;
begin
 select manifest_sha256 into v_expected_manifest from public.lf_capability_version_registry where capability_code='FINAL_EVIDENCE' and version='1.0.0';
 if v_expected_manifest is null then raise exception 'BLOCK_FINAL_EVIDENCE_ROLLBACK_VERSION_MISSING'; end if;
 if exists(select 1 from public.lf_capability_current where capability_code='FINAL_EVIDENCE' and (version is distinct from '1.0.0' or manifest_sha256 is distinct from v_expected_manifest)) then raise exception 'BLOCK_FINAL_EVIDENCE_ROLLBACK_CURRENT_DRIFT'; end if;
 delete from public.lf_capability_current where capability_code='FINAL_EVIDENCE' and version='1.0.0' and manifest_sha256=v_expected_manifest;
 update public.lf_capability_registry set status='DEPRECATED',updated_at=now(),updated_by_execution_id=v_execution_id where capability_code='FINAL_EVIDENCE';
 update public.lf_activos set estado_documental='CANDIDATO',estado_operativo='READ_ONLY',version='1.0.0-candidate',owner_name='LF_GOVERNANCE',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('registry_cutover_state','ROLLED_BACK'),updated_at=now(),updated_by_execution_id=v_execution_id where codigo_activo='FINAL_EVIDENCE' and archived_at is null;
end $$;
