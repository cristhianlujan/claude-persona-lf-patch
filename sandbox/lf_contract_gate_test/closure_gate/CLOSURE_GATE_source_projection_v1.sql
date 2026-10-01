-- SADM-PP-L3-017 CLOSURE_GATE source-only candidate.
-- DO NOT APPLY in Phase 03. No lifecycle mutation, promotion, runtime or production.

begin;

do $pre$
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_CLOSURE_GATE_LF_GOVERNANCE_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then raise exception 'BLOCK_CLOSURE_GATE_EXECUTION_CONTRACT_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='PLAN_AUTHORITY_DRIFT_GUARD' and archived_at is null) then raise exception 'BLOCK_CLOSURE_GATE_PLAN_AUTHORITY_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='FINAL_EVIDENCE' and archived_at is null) then raise exception 'BLOCK_CLOSURE_GATE_FINAL_EVIDENCE_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='WAIVER_AUTHORITY' and archived_at is null) then raise exception 'BLOCK_CLOSURE_GATE_WAIVER_AUTHORITY_NOT_MATERIALIZED'; end if;
  if exists(select 1 from public.lf_capability_registry where capability_code='CLOSURE_GATE') then raise exception 'BLOCK_CLOSURE_GATE_PREMATURE_EXECUTABLE_REGISTRATION'; end if;
end
$pre$;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,
  estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
  source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values (
  'CLOSURE_GATE','TRANSVERSAL_POST_PASE_CLOSURE_GATE','CAPABILITY','TRANSVERSAL_DETERMINISTIC_CLOSURE_GATE',
  'GITHUB_CONTRACT','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','BLOQUEADO','1.0.0-candidate',
  'sandbox/lf_contract_gate_test/closure_gate/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','CLOSURE_GATE_20261001',1,
  jsonb_build_object('solution_code','POST_PASE_CLOSURE_GATE_V1','work_code','SADM-PP-L3-017','verdict_count',4,'evidence_collection',false,'control_execution',false,'supabase_applied',false,'cutover_authorized',false,'runtime_authorized',false,'production_authorized',false),
  jsonb_build_object('schema_version','CLOSURE_GATE_ASSET_METADATA_V1','entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1','final_evidence','FINAL_EVIDENCE','waiver_authority','WAIVER_AUTHORITY','plan_authority','PLAN_AUTHORITY_DRIFT_GUARD','terminal_verdict_only',true),
  '8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,'EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1','EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1'
) on conflict(codigo_activo) do nothing;

insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id) values
 ('CLOSURE_GATE','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative owner','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,'EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1','EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1'),
 ('CLOSURE_GATE','PLAN_AUTHORITY_DRIFT_GUARD','DEPENDE_DE','authorized plan identity and control set','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,'EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1','EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1'),
 ('CLOSURE_GATE','FINAL_EVIDENCE','DEPENDE_DE','bounded manifest and terminal outcomes','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,'EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1','EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1'),
 ('CLOSURE_GATE','WAIVER_AUTHORITY','DEPENDE_DE','exact one-use waiver receipt for failed controls only','sandbox/lf_contract_gate_test/closure_gate/closure_gate_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-017000000001'::uuid,'EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1','EXEC-CLOSURE-GATE-SOURCE-PROJECTION-V1')
on conflict do nothing;

commit;
