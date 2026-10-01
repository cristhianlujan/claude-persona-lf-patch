-- SADM-PP-L4-019 POST_PASE_ROUTER source-only candidate.
-- DO NOT APPLY in Phase 03. Applicability-only consumer; no control execution/cutover/runtime/production.

begin;

do $pre$
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_LF_GOVERNANCE_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CURRENTNESS_AUTHORITY' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_CURRENTNESS_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='GITHUB_RECONCILIATION' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_GITHUB_RECONCILIATION_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='AUTHORITY_READBACK' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_AUTHORITY_READBACK_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='RUNTIME_DEPLOY_VERIFICATION' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_RUNTIME_VERIFY_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='FINAL_EVIDENCE' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_FINAL_EVIDENCE_NOT_MATERIALIZED'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CLOSURE_GATE' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_CLOSURE_GATE_NOT_MATERIALIZED'; end if;
  if exists(select 1 from public.lf_activos where codigo_activo='POST_PASE_ROUTER' and archived_at is null) then raise exception 'BLOCK_POST_PASE_ROUTER_ALREADY_MATERIALIZED'; end if;
end
$pre$;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,estado_original,estado_documental,
  estado_operativo,impacto_automatico,version,ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
  source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,created_by_execution_id,updated_by_execution_id
) values (
  'POST_PASE_ROUTER','POST_PASE_ROUTER_V1','ROUTER','POST_PASE_APPLICABILITY_ROUTER',
  'GITHUB_CONTRACT','CANDIDATE_READ_ONLY','CANDIDATO','READ_ONLY','BLOQUEADO','1.0.0-candidate',
  'sandbox/lf_contract_gate_test/post_pase_router/README.md','LF_GOVERNANCE','NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','POST_PASE_ROUTER_20261001',1,
  jsonb_build_object('solution_code','POST_PASE_ROUTER_V1','work_code','SADM-PP-L4-019','target_set_event_id',19549,'mode','APPLICABILITY_ONLY_IMMUTABLE_PLAN','control_execution',false,'control_logic',false,'owner_recalculation',false,'supabase_applied',false,'cutover_authorized',false,'runtime_authorized',false,'production_authorized',false),
  jsonb_build_object('schema_version','POST_PASE_ROUTER_ASSET_METADATA_V1','entry_guard','ORCHESTRATOR_EXECUTION_GUARD_V1','currentness_authority','CURRENTNESS_AUTHORITY','plan_schema','LF_POST_PASE_PLAN_V1','target_capability_count',5),
  '8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,'EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1'
) on conflict(codigo_activo) do nothing;

insert into public.lf_activo_relaciones(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id) values
 ('POST_PASE_ROUTER','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative governance root','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,'EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ROUTER','CURRENTNESS_AUTHORITY','DEPENDE_DE','source currentness before immutable plan','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,'EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ROUTER','GITHUB_RECONCILIATION','RELACIONADO_CAPACIDADES','selects bounded reconciliation scope only','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,'EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ROUTER','AUTHORITY_READBACK','RELACIONADO_CAPACIDADES','selects declared authority scopes only','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,'EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ROUTER','RUNTIME_DEPLOY_VERIFICATION','RELACIONADO_CAPACIDADES','selects verification only when effect scope exists','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,'EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ROUTER','FINAL_EVIDENCE','RELACIONADO_CAPACIDADES','terminal evidence manifest control','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,'EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1'),
 ('POST_PASE_ROUTER','CLOSURE_GATE','RELACIONADO_CAPACIDADES','terminal closure verdict control','sandbox/lf_contract_gate_test/post_pase_router/post_pase_router_contract_v1.json','8c1d2f6c-4a1c-4f80-9d3d-019000000001'::uuid,'EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1','EXEC-POST-PASE-ROUTER-SOURCE-PROJECTION-V1')
on conflict do nothing;

commit;
