-- SADM-PP-L3-016 FINAL_EVIDENCE source-only candidate.
-- DO NOT APPLY inside L3-016. No store, no current-pointer promotion, no cutover/runtime/production.

begin;

do $pre$
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_FINAL_EVIDENCE_LF_GOVERNANCE_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT' and archived_at is null) then raise exception 'BLOCK_FINAL_EVIDENCE_EXECUTION_CONTRACT_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='PLAN_AUTHORITY_DRIFT_GUARD' and archived_at is null) then raise exception 'BLOCK_FINAL_EVIDENCE_PLAN_AUTHORITY_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_capability_registry where capability_code='EVIDENCE_LEDGER' and status='ACTIVE') then raise exception 'BLOCK_FINAL_EVIDENCE_LEDGER_NOT_REGISTERED'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_LEDGER') then raise exception 'BLOCK_FINAL_EVIDENCE_LEDGER_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='EVIDENCE_RESOLVER_REGISTRY' and version='1.0.0') then raise exception 'BLOCK_FINAL_EVIDENCE_RESOLVER_NOT_CURRENT'; end if;
  if not exists(select 1 from public.lf_capability_current where capability_code='TYPED_EVIDENCE_REGISTRY' and version='3.0.0') then raise exception 'BLOCK_FINAL_EVIDENCE_TYPED_REGISTRY_NOT_CURRENT'; end if;
  if exists(select 1 from public.lf_capability_registry where capability_code='FINAL_EVIDENCE') then raise exception 'BLOCK_FINAL_EVIDENCE_PREMATURE_EXECUTABLE_REGISTRATION'; end if;
end
$pre$;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,
  estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
  source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values (
  'FINAL_EVIDENCE','TRANSVERSAL_POST_PASE_FINAL_EVIDENCE','CAPABILITY','TRANSVERSAL_DETERMINISTIC_EVIDENCE_MANIFEST',
  'GITHUB_CONTRACT','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','BLOQUEADO','1.0.0-candidate',
  'sandbox/lf_contract_gate_test/post_pase_final_evidence/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','FINAL_EVIDENCE_20261001',1,
  jsonb_build_object('solution_code','POST_PASE_FINAL_EVIDENCE_V1','work_code','SADM-PP-L3-016','manifest_schema','LF_POST_PASE_FINAL_EVIDENCE_MANIFEST_V1','new_store_created',false,'control_reexecution',false,'supabase_applied',false,'cutover_authorized',false,'runtime_authorized',false,'production_authorized',false),
  jsonb_build_object('schema_version','FINAL_EVIDENCE_ASSET_METADATA_V1','entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1','closure_verdict_owner','CLOSURE_GATE','raw_evidence_copy_forbidden',true,'receipt_source','EVIDENCE_LEDGER','manifest_mode','BOUNDED_DETERMINISTIC_RECEIPT_REFS_ONLY'),
  '8c1d2f6c-4a1c-4f80-9d3d-016000000001'::uuid,'EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1','EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1'
) on conflict(codigo_activo) do nothing;

insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id) values
 ('FINAL_EVIDENCE','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative owner','sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-016000000001'::uuid,'EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1','EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1'),
 ('FINAL_EVIDENCE','PLAN_AUTHORITY_DRIFT_GUARD','DEPENDE_DE','authorized plan/control set','sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-016000000001'::uuid,'EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1','EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1'),
 ('FINAL_EVIDENCE','EVIDENCE_LEDGER','DEPENDE_DE','verified receipt refs','sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-016000000001'::uuid,'EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1','EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1'),
 ('FINAL_EVIDENCE','EVIDENCE_RESOLVER_REGISTRY','DEPENDE_DE','trusted resolver identity','sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-016000000001'::uuid,'EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1','EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1'),
 ('FINAL_EVIDENCE','TYPED_EVIDENCE_REGISTRY','DEPENDE_DE','typed receipt schemas','sandbox/lf_contract_gate_test/post_pase_final_evidence/final_evidence_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-016000000001'::uuid,'EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1','EXEC-FINAL-EVIDENCE-SOURCE-PROJECTION-V1')
on conflict do nothing;

commit;
