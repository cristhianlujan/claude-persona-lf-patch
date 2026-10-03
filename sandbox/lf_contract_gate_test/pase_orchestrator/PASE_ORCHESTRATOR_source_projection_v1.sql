-- PASE-ATOM-F05-010 PASE_ORCHESTRATOR_V1 source-only materialization candidate.
-- DO NOT APPLY as part of F05. Candidate/read-only only; no capability registration,
-- current pointer, binding, operation registration, cutover, runtime or production activation.

begin;

do $pre$
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then
    raise exception 'BLOCK_PASE_ORCHESTRATOR_LF_GOVERNANCE_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CURRENTNESS_AUTHORITY' and archived_at is null) then
    raise exception 'BLOCK_PASE_ORCHESTRATOR_CURRENTNESS_AUTHORITY_NOT_MATERIALIZED';
  end if;
  if exists(select 1 from public.lf_activos where codigo_activo='PASE_ORCHESTRATOR' and archived_at is null) then
    raise exception 'BLOCK_PASE_ORCHESTRATOR_ALREADY_MATERIALIZED';
  end if;
end
$pre$;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,
  estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
  source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values (
  'PASE_ORCHESTRATOR','PASE_ORCHESTRATOR_V1','ORCHESTRATOR','PASE_SEQUENTIAL_DISPATCH_PLANNER',
  'GITHUB_CONTRACT','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','BLOQUEADO','1.0.0-candidate',
  'sandbox/lf_contract_gate_test/pase_orchestrator/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','PASE_ORCHESTRATOR_F05_010',1,
  jsonb_build_object(
    'solution_code','PASE_ORCHESTRATOR_V1',
    'work_code','PASE-ATOM-F05-010',
    'mode','SEQUENTIAL_DELEGATION_PLAN_ONLY',
    'input_schema','lf-ci-execution-plan/v2',
    'output_schema','lf-pase-dispatch-plan/v1',
    'applicability_authority','CHANGESET_GOVERNANCE_LF_V1',
    'applicability_reclassification',false,
    'owner_recalculation',false,
    'domain_control_execution',false,
    'supabase_applied',false,
    'capability_registered',false,
    'current_pointer_created',false,
    'binding_created',false,
    'operation_registered',false,
    'cutover_authorized',false,
    'runtime_authorized',false,
    'production_authorized',false
  ),
  jsonb_build_object(
    'schema_version','PASE_ORCHESTRATOR_ASSET_METADATA_V1',
    'source_module','sandbox/lf_contract_gate_test/pase_orchestrator/pase_orchestrator_v1.py',
    'deterministic_test','sandbox/lf_contract_gate_test/pase_orchestrator/test_pase_orchestrator_v1.py',
    'materialization_contract','sandbox/lf_contract_gate_test/pase_orchestrator/pase_orchestrator_materialization_contract_v1.json',
    'carrier_registry','sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json',
    'currentness_authority','CURRENTNESS_AUTHORITY',
    'artifact_transport_policy','NO_ZIP_AUTHORITY'
  ),
  '8c1d2f6c-4a1c-4f80-9d3d-050000000010'::uuid,
  'EXEC-PASE-ORCHESTRATOR-SOURCE-PROJECTION-F05-010',
  'EXEC-PASE-ORCHESTRATOR-SOURCE-PROJECTION-F05-010'
) on conflict(codigo_activo) do nothing;

insert into public.lf_activo_relaciones(
  codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values
 ('PASE_ORCHESTRATOR','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative governance root; applicability remains upstream','sandbox/lf_contract_gate_test/pase_orchestrator/pase_orchestrator_materialization_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-050000000010'::uuid,'EXEC-PASE-ORCHESTRATOR-SOURCE-PROJECTION-F05-010','EXEC-PASE-ORCHESTRATOR-SOURCE-PROJECTION-F05-010'),
 ('PASE_ORCHESTRATOR','CURRENTNESS_AUTHORITY','DEPENDE_DE','candidate source currentness is checked before any future promotion','sandbox/lf_contract_gate_test/pase_orchestrator/pase_orchestrator_materialization_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-050000000010'::uuid,'EXEC-PASE-ORCHESTRATOR-SOURCE-PROJECTION-F05-010','EXEC-PASE-ORCHESTRATOR-SOURCE-PROJECTION-F05-010')
on conflict do nothing;

commit;
