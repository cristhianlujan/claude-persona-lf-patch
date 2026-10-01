-- SADM-PP-L4-020 POST_PASE_ORCHESTRATOR source-only candidate.
-- DO NOT APPLY in Phase 03. Sequential immutable-plan consumer only; no applicability rediscovery/cutover/runtime/production.

begin;

do $pre$
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then
    raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_LF_GOVERNANCE_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='POST_PASE_ROUTER' and archived_at is null) then
    raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_ROUTER_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='OWNER_RUNNER_CARRIER_AUTHORITY' and archived_at is null) then
    raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_OWNER_RUNNER_CARRIER_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then
    raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_EXECUTION_CONTRACT_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='EVIDENCE_LEDGER' and archived_at is null) then
    raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_EVIDENCE_LEDGER_NOT_MATERIALIZED';
  end if;
  if exists(select 1 from public.lf_activos where codigo_activo='POST_PASE_ORCHESTRATOR' and archived_at is null) then
    raise exception 'BLOCK_POST_PASE_ORCHESTRATOR_ALREADY_MATERIALIZED';
  end if;
end
$pre$;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,
  estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
  source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values (
  'POST_PASE_ORCHESTRATOR','POST_PASE_ORCHESTRATOR_V1','ORCHESTRATOR','POST_PASE_SEQUENTIAL_DISPATCHER',
  'GITHUB_CONTRACT','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','BLOQUEADO','1.0.0-candidate',
  'sandbox/lf_contract_gate_test/post_pase_orchestrator/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','POST_PASE_ORCHESTRATOR_20261001',1,
  jsonb_build_object(
    'solution_code','POST_PASE_ORCHESTRATOR_V1',
    'work_code','SADM-PP-L4-020',
    'mode','SEQUENTIAL_IMMUTABLE_PLAN_DISPATCH',
    'applicability_rediscovery',false,
    'control_logic',false,
    'owner_recalculation',false,
    'parallel_dispatch',false,
    'new_receipt_store',false,
    'supabase_applied',false,
    'cutover_authorized',false,
    'runtime_authorized',false,
    'production_authorized',false
  ),
  jsonb_build_object(
    'schema_version','POST_PASE_ORCHESTRATOR_ASSET_METADATA_V1',
    'entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1',
    'plan_schema','LF_POST_PASE_PLAN_V1',
    'execution_contract','CAPABILITY_EXECUTION_CONTRACT_V1',
    'binding_authority','OWNER_RUNNER_CARRIER_AUTHORITY_V1',
    'artifact_transport_policy','PASE_POST_PASE_ARTIFACT_TRANSPORT_NO_ZIP_V1'
  ),
  '8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,
  'EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1',
  'EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1'
) on conflict(codigo_activo) do nothing;

insert into public.lf_activo_relaciones(
  codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values
 ('POST_PASE_ORCHESTRATOR','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative governance root','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,'EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','POST_PASE_ROUTER','DEPENDE_DE','consumes immutable plan only','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,'EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','OWNER_RUNNER_CARRIER_AUTHORITY','DEPENDE_DE','binding resolution remains canonical authority responsibility','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,'EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','CAPABILITY_EXECUTION_CONTRACT','DEPENDE_DE','shared request receipt envelope','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,'EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ORCHESTRATOR','EVIDENCE_LEDGER','DEPENDE_DE','receipt persistence remains canonical ledger responsibility','sandbox/lf_contract_gate_test/post_pase_orchestrator/post_pase_orchestrator_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-020000000001'::uuid,'EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ORCHESTRATOR-SOURCE-PROJECTION-V1')
on conflict do nothing;

commit;
