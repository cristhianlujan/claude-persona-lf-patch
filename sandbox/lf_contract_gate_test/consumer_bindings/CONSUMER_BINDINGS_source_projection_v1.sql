-- SADM-PP-L4-021 CONSUMER_BINDINGS source-only candidate.
-- DO NOT APPLY in Phase 03. No cutover/runtime/production. No parallel registry. No owner recalculation.

begin;

do $pre$
declare
  v_missing text;
begin
  if to_regclass('public.lf_capability_registry') is null then raise exception 'BLOCK_CONSUMER_BINDINGS_CAPABILITY_REGISTRY_MISSING'; end if;
  if to_regclass('public.lf_capability_current') is null then raise exception 'BLOCK_CONSUMER_BINDINGS_CAPABILITY_CURRENT_MISSING'; end if;
  if to_regclass('public.lf_activo_relaciones') is null then raise exception 'BLOCK_CONSUMER_BINDINGS_RELATIONS_MISSING'; end if;
  if to_regprocedure('public.fn_lf_capability_bind_from_orchestrator_v1(text,text,text,text,uuid,text)') is null then
    raise exception 'BLOCK_CONSUMER_BINDINGS_CANONICAL_BIND_ENTRYPOINT_MISSING';
  end if;
  foreach v_missing in array array[
    'LF_GOVERNANCE','OWNER_RUNNER_CARRIER_AUTHORITY','POST_PASE_ORCHESTRATOR',
    'CURRENTNESS_AUTHORITY','GITHUB_RECONCILIATION','AUTHORITY_READBACK','RUNTIME_DEPLOY_VERIFICATION',
    'EVIDENCE_LEDGER','FINAL_EVIDENCE','CLOSURE_GATE'
  ] loop
    if not exists(select 1 from public.lf_activos where codigo_activo=v_missing and archived_at is null) then
      raise exception 'BLOCK_CONSUMER_BINDINGS_REQUIRED_ASSET_NOT_MATERIALIZED:%',v_missing;
    end if;
  end loop;
  if exists(select 1 from public.lf_activos where codigo_activo='CONSUMER_BINDINGS' and archived_at is null) then
    raise exception 'BLOCK_CONSUMER_BINDINGS_ALREADY_MATERIALIZED';
  end if;
end
$pre$;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,
  estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
  source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values (
  'CONSUMER_BINDINGS','CONSUMER_BINDINGS_V1','CONTRACT','CAPABILITY_CONSUMER_BINDING',
  'GITHUB_CONTRACT','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','BLOQUEADO','1.0.0-candidate',
  'sandbox/lf_contract_gate_test/consumer_bindings/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','CONSUMER_BINDINGS_20261001',1,
  jsonb_build_object(
    'solution_code','CONSUMER_BINDINGS_V1','work_code','SADM-PP-L4-021',
    'resolution_mode','CANONICAL_CAPABILITY_AUTHORITY_ONLY','parallel_registry',false,
    'owner_recalculation',false,'binding_bypass_allowed',false,'applicability_rediscovery',false,
    'supabase_applied',false,'promotion_executed',false,'cutover_executed',false,'runtime_authorized',false,'production_authorized',false
  ),
  jsonb_build_object(
    'schema_version','CONSUMER_BINDINGS_ASSET_METADATA_V1',
    'registry','public.lf_capability_registry','current','public.lf_capability_current',
    'relations','public.lf_activo_relaciones','binding_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
    'owner_runner_carrier_authority','OWNER_RUNNER_CARRIER_AUTHORITY_V1',
    'entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1',
    'artifact_transport_policy','PASE_POST_PASE_ARTIFACT_TRANSPORT_NO_ZIP_V1'
  ),
  '8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,
  'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'
) on conflict(codigo_activo) do nothing;

insert into public.lf_activo_relaciones(
  codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values
 ('CONSUMER_BINDINGS','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative governance root','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'),
 ('CONSUMER_BINDINGS','OWNER_RUNNER_CARRIER_AUTHORITY','DEPENDE_DE','owner/runner/carrier is resolved only by canonical authority','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','CURRENTNESS_AUTHORITY','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','GITHUB_RECONCILIATION','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','AUTHORITY_READBACK','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','RUNTIME_DEPLOY_VERIFICATION','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','EVIDENCE_LEDGER','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','FINAL_EVIDENCE','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','CLOSURE_GATE','DEPENDE_DE','consumer binding uses canonical capability authority only','sandbox/lf_contract_gate_test/consumer_bindings/consumer_bindings_contract_v1.json','8c1d2f6c-4a1c-4f80-9d4d-021000000001'::uuid,'EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1','EXEC-CONSUMER-BINDINGS-SOURCE-PROJECTION-V1')
on conflict do nothing;

commit;
