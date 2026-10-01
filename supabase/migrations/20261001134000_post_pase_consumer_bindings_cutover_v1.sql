-- SADM-PP-L5-022 isolated cutover 15: CONSUMER_BINDINGS.
-- Materializes the verified canonical consumer-binding contract and relations.
-- No parallel registry, no owner recalculation, no runtime/deploy/production.

do $$
declare
  v_execution_id constant text := 'EXEC-L5-CONSUMER-BINDINGS-CUTOVER-V1-20261001';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid;
  v_missing text;
begin
  if to_regclass('public.lf_capability_registry') is null then raise exception 'BLOCK_CONSUMER_BINDINGS_CAPABILITY_REGISTRY_MISSING'; end if;
  if to_regclass('public.lf_capability_current') is null then raise exception 'BLOCK_CONSUMER_BINDINGS_CAPABILITY_CURRENT_MISSING'; end if;
  if to_regclass('public.lf_activo_relaciones') is null then raise exception 'BLOCK_CONSUMER_BINDINGS_RELATIONS_MISSING'; end if;
  if to_regprocedure('public.fn_lf_capability_bind_from_orchestrator_v1(text,text,text,text,uuid,text)') is null then raise exception 'BLOCK_CONSUMER_BINDINGS_CANONICAL_BIND_ENTRYPOINT_MISSING'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='POST_PASE_ORCHESTRATOR' and version='1.0.0') then raise exception 'BLOCK_CONSUMER_BINDINGS_ORCHESTRATOR_NOT_CURRENT'; end if;
  foreach v_missing in array array['LF_GOVERNANCE','OWNER_RUNNER_CARRIER_AUTHORITY','POST_PASE_ORCHESTRATOR','CURRENTNESS_AUTHORITY','GITHUB_RECONCILIATION','AUTHORITY_READBACK','RUNTIME_DEPLOY_VERIFICATION','EVIDENCE_LEDGER','FINAL_EVIDENCE','CLOSURE_GATE'] loop
    if not exists(select 1 from public.lf_activos where codigo_activo=v_missing and archived_at is null) then raise exception 'BLOCK_CONSUMER_BINDINGS_REQUIRED_ASSET_NOT_MATERIALIZED:%',v_missing; end if;
  end loop;
  if not exists(select 1 from public.lf_capability_current where capability_code='CURRENTNESS_AUTHORITY' and version='1.0.0') then raise exception 'BLOCK_CONSUMER_BINDINGS_CURRENTNESS_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='GITHUB_RECONCILIATION' and version='1.0.0') then raise exception 'BLOCK_CONSUMER_BINDINGS_GITHUB_RECONCILIATION_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='AUTHORITY_READBACK' and version='1.0.0') then raise exception 'BLOCK_CONSUMER_BINDINGS_AUTHORITY_READBACK_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='RUNTIME_DEPLOY_VERIFICATION' and version='1.0.0') then raise exception 'BLOCK_CONSUMER_BINDINGS_RUNTIME_VERIFY_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_LEDGER' and version='1.1.0') then raise exception 'BLOCK_CONSUMER_BINDINGS_LEDGER_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='FINAL_EVIDENCE' and version='1.0.0') then raise exception 'BLOCK_CONSUMER_BINDINGS_FINAL_EVIDENCE_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='CLOSURE_GATE' and version='1.0.0') then raise exception 'BLOCK_CONSUMER_BINDINGS_CLOSURE_GATE_NOT_CURRENT'; end if;

  insert into public.lf_activos(codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id)
  values('CONSUMER_BINDINGS','CONSUMER_BINDINGS_V1','CONTRACT','CAPABILITY_CONSUMER_BINDING','GITHUB_CONTRACT','CANDIDATE_READ_ONLY','VIGENTE','ACTIVO','BLOQUEADO','1.0.0','sandbox/lf_contract_gate_test/consumer_bindings/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','CONSUMER_BINDINGS_20261001',1,
    jsonb_build_object('solution_code','CONSUMER_BINDINGS_V1','work_code','SADM-PP-L4-021','resolution_mode','CANONICAL_CAPABILITY_AUTHORITY_ONLY','parallel_registry',false,'owner_recalculation',false,'binding_bypass_allowed',false,'applicability_rediscovery',false,'cutover_executed',true,'runtime_authorized',false,'production_authorized',false,'legacy_execution_path_retained',true),
    jsonb_build_object('schema_version','CONSUMER_BINDINGS_ASSET_METADATA_V1','registry','public.lf_capability_registry','current','public.lf_capability_current','relations','public.lf_activo_relaciones','binding_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','owner_runner_carrier_authority','OWNER_RUNNER_CARRIER_AUTHORITY_V1','entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1','artifact_transport_policy','PASE_POST_PASE_ARTIFACT_TRANSPORT_NO_ZIP_V1','binding_state','CANONICAL_RELATIONS_MATERIALIZED','source_revision','4d0d7ef97d9cd1b1aa802f8d20264ef34e59f73f'),
    v_batch,v_execution_id,v_execution_id)
  on conflict(codigo_activo) do update set estado_documental='VIGENTE',estado_operativo='ACTIVO',version='1.0.0',owner_name='LF_GOVERNANCE',raw_payload=excluded.raw_payload,metadata=excluded.metadata,updated_at=now(),updated_by_execution_id=v_execution_id;

  insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id) values
   ('CONSUMER_BINDINGS','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative governance root','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id),
   ('CONSUMER_BINDINGS','OWNER_RUNNER_CARRIER_AUTHORITY','DEPENDE_DE','owner/runner/carrier is resolved only by canonical authority','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','CURRENTNESS_AUTHORITY','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','GITHUB_RECONCILIATION','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','AUTHORITY_READBACK','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','RUNTIME_DEPLOY_VERIFICATION','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','EVIDENCE_LEDGER','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','FINAL_EVIDENCE','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id),
   ('POST_PASE_ORCHESTRATOR','CLOSURE_GATE','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json',v_batch,v_execution_id,v_execution_id)
  on conflict do nothing;
end $$;
