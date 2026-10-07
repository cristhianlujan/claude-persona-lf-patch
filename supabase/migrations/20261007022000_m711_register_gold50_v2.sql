-- M7.11 REGISTER_SUITE
-- Materialize the 50-case change-impact gold as governed cases inside the existing
-- INPUT_GOVERNANCE_REGRESSION suite. Adjudicated v2 is the expected authority.
-- This migration does not authorize scoped pass, downstream execution, or production.

do $pre$
declare
  v_existing_codes integer;
  v_existing_orders integer;
begin
  if not exists (
    select 1 from public.lf_test_suites
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and module_code='INPUT_GOVERNANCE'
  ) then
    raise exception 'M711_INPUT_GOVERNANCE_REGRESSION_SUITE_MISSING';
  end if;

  select count(*) into v_existing_codes
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and test_code in ('CI-COPY-01','CI-COPY-02','CI-COPY-03','CI-COPY-04','CI-COPY-05','CI-ACT-01','CI-ACT-02','CI-ACT-03','CI-ACT-04','CI-ACT-05','CI-PERM-01','CI-PERM-02','CI-PERM-03','CI-PERM-04','CI-PERM-05','CI-ROUTE-01','CI-ROUTE-02','CI-ROUTE-03','CI-ROUTE-04','CI-ROUTE-05','CI-DESIGN-01','CI-DESIGN-02','CI-DESIGN-03','CI-DESIGN-04','CI-DESIGN-05','CI-FIELD-01','CI-FIELD-02','CI-FIELD-03','CI-FIELD-04','CI-FIELD-05','CI-VAL-01','CI-VAL-02','CI-VAL-03','CI-VAL-04','CI-VAL-05','CI-STATE-01','CI-STATE-02','CI-STATE-03','CI-STATE-04','CI-STATE-05','CI-ERR-01','CI-ERR-02','CI-ERR-03','CI-ERR-04','CI-ERR-05','CI-API-01','CI-API-02','CI-API-03','CI-API-04','CI-API-05');

  if v_existing_codes<>0 then
    raise exception 'M711_GOLD50_TEST_CODES_ALREADY_EXIST:%',v_existing_codes;
  end if;

  select count(*) into v_existing_orders
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and test_order between 711001 and 711050;

  if v_existing_orders<>0 then
    raise exception 'M711_GOLD50_TEST_ORDER_RANGE_OCCUPIED:%',v_existing_orders;
  end if;
end;
$pre$;

insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
values
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-COPY-01',
  711001,
  array[]::text[],
  'M7.11 gold50 v2 — COPY_RECONCILIATION — CI-COPY-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"COPY_RECONCILIATION","mutation":"Artefacto: ''Exportar'' -> nombre canónico ''Exportar historial''; acción, permiso, componente y geometría intactos.","source_anchor":"element:B2B_CARGA001_EXPORT_HISTORY|permission:B2B_LOAD_HISTORY_EXPORT","rationale":"Reconciliación hacia fuente canónica existente.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"COPY_RECONCILIATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-COPY-02',
  711002,
  array[]::text[],
  'M7.11 gold50 v2 — COPY_RECONCILIATION — CI-COPY-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"COPY_RECONCILIATION","mutation":"Artefacto: ''Exportar'' -> ''Eliminar historial'' sin cambiar fuente.","source_anchor":"permission:B2B_LOAD_HISTORY_EXPORT","rationale":"Copy contradice acción/permiso EXPORT.","base_decision":"SCOPED_BLOCK","base_impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_BLOCK","adjudicated_impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_BLOCK","impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"COPY_RECONCILIATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-COPY-03',
  711003,
  array[]::text[],
  'M7.11 gold50 v2 — COPY_RECONCILIATION — CI-COPY-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"COPY_RECONCILIATION","mutation":"Artefacto usa copy ''Exportar evidencia'' de otro permiso existente.","source_anchor":"permission:B2B_LOAD_HISTORY_EXPORT|permission:B2B_EVIDENCE_EXPORT","rationale":"Copy pertenece a otro recurso.","base_decision":"SCOPED_BLOCK","base_impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_BLOCK","adjudicated_impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_BLOCK","impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"COPY_RECONCILIATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-COPY-04',
  711004,
  array[]::text[],
  'M7.11 gold50 v2 — COPY_RECONCILIATION — CI-COPY-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"COPY_RECONCILIATION","mutation":"Copy nueva no respaldada por fuente canónica.","source_anchor":"permission:B2B_LOAD_HISTORY_EXPORT","rationale":"Nueva copy material sin autoridad.","base_decision":"HUMAN_REQUIRED","base_impact_families":["ACTIONS","PERMISSIONS","UI_MESSAGES","VISUAL_EVIDENCE"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["ACTIONS","PERMISSIONS","SOURCE_AUTHORITY_PROVENANCE","UI_MESSAGES","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["ACTIONS","PERMISSIONS","SOURCE_AUTHORITY_PROVENANCE","UI_MESSAGES","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"COPY_RECONCILIATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-COPY-05',
  711005,
  array[]::text[],
  'M7.11 gold50 v2 — COPY_RECONCILIATION — CI-COPY-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"COPY_RECONCILIATION","mutation":"Misma copy canónica; solo whitespace/formatting no visible.","source_anchor":"artifact:B2B-CARGA-001","rationale":"Cambio no semántico.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"COPY_RECONCILIATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ACT-01',
  711006,
  array[]::text[],
  'M7.11 gold50 v2 — ACTION_SEMANTICS — CI-ACT-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ACTION_SEMANTICS","mutation":"EXPORT permanece EXPORT.","source_anchor":"action:EXPORT","rationale":"Control negativo estable.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["ACTIONS"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["ACTIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["ACTIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ACTION_SEMANTICS","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ACT-02',
  711007,
  array[]::text[],
  'M7.11 gold50 v2 — ACTION_SEMANTICS — CI-ACT-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ACTION_SEMANTICS","mutation":"Cambiar action EXPORT -> DELETE.","source_anchor":"element:B2B_CARGA001_EXPORT_HISTORY","rationale":"Cambia capacidad de dominio.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["ACTIONS","PERMISSIONS","SECURITY","API_DATA_CONTRACT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SECURITY"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SECURITY"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ACTION_SEMANTICS","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ACT-03',
  711008,
  array[]::text[],
  'M7.11 gold50 v2 — ACTION_SEMANTICS — CI-ACT-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ACTION_SEMANTICS","mutation":"Eliminar action binding del elemento.","source_anchor":"element:B2B_CARGA001_EXPORT_HISTORY","rationale":"Rompe acción canónica.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["ACTIONS","PERMISSIONS","API_DATA_CONTRACT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ACTION_SEMANTICS","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ACT-04',
  711009,
  array[]::text[],
  'M7.11 gold50 v2 — ACTION_SEMANTICS — CI-ACT-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ACTION_SEMANTICS","mutation":"Agregar segunda action no declarada.","source_anchor":"element:B2B_CARGA001_EXPORT_HISTORY","rationale":"Nueva semántica sin fuente.","base_decision":"HUMAN_REQUIRED","base_impact_families":["ACTIONS","PERMISSIONS","API_DATA_CONTRACT"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SOURCE_AUTHORITY_PROVENANCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SOURCE_AUTHORITY_PROVENANCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ACTION_SEMANTICS","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ACT-05',
  711010,
  array[]::text[],
  'M7.11 gold50 v2 — ACTION_SEMANTICS — CI-ACT-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ACTION_SEMANTICS","mutation":"Cambiar EXPORT por action existente de otro recurso.","source_anchor":"permission:B2B_LOAD_HISTORY_EXPORT","rationale":"Catálogo no implica aplicabilidad.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["ACTIONS","PERMISSIONS","API_DATA_CONTRACT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ACTION_SEMANTICS","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-PERM-01',
  711011,
  array[]::text[],
  'M7.11 gold50 v2 — PERMISSION_BINDING — CI-PERM-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"PERMISSION_BINDING","mutation":"Mantener B2B_LOAD_HISTORY_EXPORT.","source_anchor":"permission:B2B_LOAD_HISTORY_EXPORT","rationale":"Binding estable.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["PERMISSIONS"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["PERMISSIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["PERMISSIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"PERMISSION_BINDING","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-PERM-02',
  711012,
  array[]::text[],
  'M7.11 gold50 v2 — PERMISSION_BINDING — CI-PERM-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"PERMISSION_BINDING","mutation":"Reemplazar por B2B_EVIDENCE_EXPORT.","source_anchor":"permission:B2B_LOAD_HISTORY_EXPORT|permission:B2B_EVIDENCE_EXPORT","rationale":"Cambia recurso protegido.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["PERMISSIONS","ACTIONS","SECURITY"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SECURITY"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SECURITY"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"PERMISSION_BINDING","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-PERM-03',
  711013,
  array[]::text[],
  'M7.11 gold50 v2 — PERMISSION_BINDING — CI-PERM-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"PERMISSION_BINDING","mutation":"Quitar permission ref.","source_anchor":"element:B2B_CARGA001_EXPORT_HISTORY","rationale":"Acción pierde autoridad.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["PERMISSIONS","ACTIONS","SECURITY"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SECURITY"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SECURITY"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"PERMISSION_BINDING","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-PERM-04',
  711014,
  array[]::text[],
  'M7.11 gold50 v2 — PERMISSION_BINDING — CI-PERM-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"PERMISSION_BINDING","mutation":"Mismo permission_code pero action_code EXPORT -> DELETE.","source_anchor":"permission:B2B_LOAD_HISTORY_EXPORT","rationale":"Semántica inconsistente.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["PERMISSIONS","ACTIONS","SECURITY","API_DATA_CONTRACT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SECURITY"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SECURITY"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"PERMISSION_BINDING","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-PERM-05',
  711015,
  array[]::text[],
  'M7.11 gold50 v2 — PERMISSION_BINDING — CI-PERM-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"PERMISSION_BINDING","mutation":"Crear permiso nuevo ad hoc.","source_anchor":"element:B2B_CARGA001_EXPORT_HISTORY","rationale":"No inventar permisos.","base_decision":"HUMAN_REQUIRED","base_impact_families":["PERMISSIONS","SECURITY","ACTIONS"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["ACTIONS","PERMISSIONS","SECURITY","SOURCE_AUTHORITY_PROVENANCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["ACTIONS","PERMISSIONS","SECURITY","SOURCE_AUTHORITY_PROVENANCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"PERMISSION_BINDING","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ROUTE-01',
  711016,
  array[]::text[],
  'M7.11 gold50 v2 — ROUTING_NAVIGATION — CI-ROUTE-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ROUTING_NAVIGATION","mutation":"Mantener B2B_ROUTE_CARGAS_HISTORIAL + SCREEN_ROUTE.","source_anchor":"route:B2B_ROUTE_CARGAS_HISTORIAL","rationale":"Ruta estable.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["ROUTING_NAVIGATION"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["ROUTING_NAVIGATION"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["ROUTING_NAVIGATION"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ROUTING_NAVIGATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ROUTE-02',
  711017,
  array[]::text[],
  'M7.11 gold50 v2 — ROUTING_NAVIGATION — CI-ROUTE-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ROUTING_NAVIGATION","mutation":"Cambiar a otra ruta existente no asociada.","source_anchor":"route:B2B_ROUTE_CARGAS_HISTORIAL","rationale":"Ruta existente no prueba aplicabilidad.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["ROUTING_NAVIGATION","ACTIONS"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ACTIONS","ROUTING_NAVIGATION"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ACTIONS","ROUTING_NAVIGATION"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ROUTING_NAVIGATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ROUTE-03',
  711018,
  array[]::text[],
  'M7.11 gold50 v2 — ROUTING_NAVIGATION — CI-ROUTE-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ROUTING_NAVIGATION","mutation":"Eliminar relación SCREEN_ROUTE.","source_anchor":"route:B2B_ROUTE_CARGAS_HISTORIAL","rationale":"Rompe reachability.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["ROUTING_NAVIGATION"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ROUTING_NAVIGATION"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ROUTING_NAVIGATION"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ROUTING_NAVIGATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ROUTE-04',
  711019,
  array[]::text[],
  'M7.11 gold50 v2 — ROUTING_NAVIGATION — CI-ROUTE-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ROUTING_NAVIGATION","mutation":"Introducir route ref inexistente.","source_anchor":"route:B2B_ROUTE_CARGAS_HISTORIAL","rationale":"Broken ref fail-closed.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["ROUTING_NAVIGATION"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ROUTING_NAVIGATION"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ROUTING_NAVIGATION"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ROUTING_NAVIGATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ROUTE-05',
  711020,
  array[]::text[],
  'M7.11 gold50 v2 — ROUTING_NAVIGATION — CI-ROUTE-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ROUTING_NAVIGATION","mutation":"Crear ruta nueva sin decisión fuente.","source_anchor":"screen:B2B-CARGA-001","rationale":"Nueva ruta requiere autoridad.","base_decision":"HUMAN_REQUIRED","base_impact_families":["ROUTING_NAVIGATION","SOURCE_AUTHORITY_PROVENANCE"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["ROUTING_NAVIGATION","SOURCE_AUTHORITY_PROVENANCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["ROUTING_NAVIGATION","SOURCE_AUTHORITY_PROVENANCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ROUTING_NAVIGATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-DESIGN-01',
  711021,
  array[]::text[],
  'M7.11 gold50 v2 — DESIGN_COMPONENT — CI-DESIGN-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"DESIGN_COMPONENT","mutation":"Mantener download_file_action; solo copy hacia fuente.","source_anchor":"component:download_file_action","rationale":"Componente estable.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["DESIGN_SYSTEM","ASSETS_ICONS","VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["ASSETS_ICONS","DESIGN_SYSTEM","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["ASSETS_ICONS","DESIGN_SYSTEM","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"DESIGN_COMPONENT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-DESIGN-02',
  711022,
  array[]::text[],
  'M7.11 gold50 v2 — DESIGN_COMPONENT — CI-DESIGN-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"DESIGN_COMPONENT","mutation":"Cambiar a otro token existente sin equivalencia demostrada.","source_anchor":"component:download_file_action","rationale":"Token existente no prueba equivalencia.","base_decision":"SCOPED_BLOCK","base_impact_families":["DESIGN_SYSTEM","ASSETS_ICONS","ACCESSIBILITY","VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_BLOCK","adjudicated_impact_families":["ACCESSIBILITY","ASSETS_ICONS","DESIGN_SYSTEM","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_BLOCK","impact_families":["ACCESSIBILITY","ASSETS_ICONS","DESIGN_SYSTEM","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"DESIGN_COMPONENT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-DESIGN-03',
  711023,
  array[]::text[],
  'M7.11 gold50 v2 — DESIGN_COMPONENT — CI-DESIGN-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"DESIGN_COMPONENT","mutation":"Eliminar component_token_id requerido.","source_anchor":"element:B2B_CARGA001_EXPORT_HISTORY","rationale":"Binding irresoluble.","base_decision":"SCOPED_BLOCK","base_impact_families":["DESIGN_SYSTEM","ASSETS_ICONS"],"adjudicated_decision":"SCOPED_BLOCK","adjudicated_impact_families":["ASSETS_ICONS","DESIGN_SYSTEM"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_BLOCK","impact_families":["ASSETS_ICONS","DESIGN_SYSTEM"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"DESIGN_COMPONENT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-DESIGN-04',
  711024,
  array[]::text[],
  'M7.11 gold50 v2 — DESIGN_COMPONENT — CI-DESIGN-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"DESIGN_COMPONENT","mutation":"Usar token DEPRECADO.","source_anchor":"design_system:LF_DS_V1","rationale":"DEPRECADO no válido.","base_decision":"SCOPED_BLOCK","base_impact_families":["DESIGN_SYSTEM","ASSETS_ICONS","VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_BLOCK","adjudicated_impact_families":["ASSETS_ICONS","DESIGN_SYSTEM","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_BLOCK","impact_families":["ASSETS_ICONS","DESIGN_SYSTEM","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"DESIGN_COMPONENT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-DESIGN-05',
  711025,
  array[]::text[],
  'M7.11 gold50 v2 — DESIGN_COMPONENT — CI-DESIGN-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"DESIGN_COMPONENT","mutation":"Crear token nuevo para acomodar pedido.","source_anchor":"design_system:LF_DS_V1","rationale":"No crear token sin autoridad.","base_decision":"HUMAN_REQUIRED","base_impact_families":["DESIGN_SYSTEM","SOURCE_AUTHORITY_PROVENANCE"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["DESIGN_SYSTEM","SOURCE_AUTHORITY_PROVENANCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["DESIGN_SYSTEM","SOURCE_AUTHORITY_PROVENANCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"DESIGN_COMPONENT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-FIELD-01',
  711026,
  array[]::text[],
  'M7.11 gold50 v2 — FIELD_CONTRACT — CI-FIELD-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"FIELD_CONTRACT","mutation":"Mantener B2B_FLD_SEARCH_QUERY.","source_anchor":"field:B2B_FLD_SEARCH_QUERY","rationale":"Field estable.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["FIELDS"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["FIELDS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["FIELDS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"FIELD_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-FIELD-02',
  711027,
  array[]::text[],
  'M7.11 gold50 v2 — FIELD_CONTRACT — CI-FIELD-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"FIELD_CONTRACT","mutation":"data_type text -> integer.","source_anchor":"field:B2B_FLD_SEARCH_QUERY","rationale":"Cambia contrato de entrada.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["FIELDS","VALIDATIONS","API_DATA_CONTRACT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["API_DATA_CONTRACT","FIELDS","VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["API_DATA_CONTRACT","FIELDS","VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"FIELD_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-FIELD-03',
  711028,
  array[]::text[],
  'M7.11 gold50 v2 — FIELD_CONTRACT — CI-FIELD-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"FIELD_CONTRACT","mutation":"required false -> true.","source_anchor":"field:B2B_FLD_SEARCH_QUERY","rationale":"Cambia aceptación y request.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["FIELDS","VALIDATIONS","UI_MESSAGES","API_DATA_CONTRACT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["API_DATA_CONTRACT","FIELDS","UI_MESSAGES","VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["API_DATA_CONTRACT","FIELDS","UI_MESSAGES","VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"FIELD_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-FIELD-04',
  711029,
  array[]::text[],
  'M7.11 gold50 v2 — FIELD_CONTRACT — CI-FIELD-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"FIELD_CONTRACT","mutation":"Agregar filtro nuevo.","source_anchor":"screen:B2B-CARGA-001","rationale":"Nuevo campo requiere definición.","base_decision":"HUMAN_REQUIRED","base_impact_families":["FIELDS","VALIDATIONS","API_DATA_CONTRACT","DESIGN_SYSTEM"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["API_DATA_CONTRACT","DESIGN_SYSTEM","FIELDS","SOURCE_AUTHORITY_PROVENANCE","VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["API_DATA_CONTRACT","DESIGN_SYSTEM","FIELDS","SOURCE_AUTHORITY_PROVENANCE","VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"FIELD_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-FIELD-05',
  711030,
  array[]::text[],
  'M7.11 gold50 v2 — FIELD_CONTRACT — CI-FIELD-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"FIELD_CONTRACT","mutation":"Cambiar sensitive/PII classification.","source_anchor":"field:B2B_FLD_SEARCH_QUERY","rationale":"Cambia privacidad/logging.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["FIELDS","PRIVACY_PII","SECURITY","AUDIT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["AUDIT","FIELDS","PRIVACY_PII","SECURITY"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["AUDIT","FIELDS","PRIVACY_PII","SECURITY"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"FIELD_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-VAL-01',
  711031,
  array[]::text[],
  'M7.11 gold50 v2 — VALIDATION — CI-VAL-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"VALIDATION","mutation":"Mantener 10 validaciones y 0 required editable sin validar.","source_anchor":"screen:B2B-CARGA-001:validation_count=10","rationale":"Validaciones estables.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["VALIDATIONS"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"VALIDATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-VAL-02',
  711032,
  array[]::text[],
  'M7.11 gold50 v2 — VALIDATION — CI-VAL-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"VALIDATION","mutation":"Eliminar validación de USER editable requerido.","source_anchor":"screen:B2B-CARGA-001:required_editable=2","rationale":"Input requerido queda sin validación.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["VALIDATIONS","FIELDS","API_DATA_CONTRACT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["API_DATA_CONTRACT","FIELDS","VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["API_DATA_CONTRACT","FIELDS","VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"VALIDATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-VAL-03',
  711033,
  array[]::text[],
  'M7.11 gold50 v2 — VALIDATION — CI-VAL-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"VALIDATION","mutation":"warning no bloqueante -> error bloqueante.","source_anchor":"screen:B2B-CARGA-001","rationale":"Cambia outcome.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["VALIDATIONS","UI_MESSAGES","OBJECTIVE_OUTCOMES"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["OBJECTIVE_OUTCOMES","UI_MESSAGES","VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["OBJECTIVE_OUTCOMES","UI_MESSAGES","VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"VALIDATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-VAL-04',
  711034,
  array[]::text[],
  'M7.11 gold50 v2 — VALIDATION — CI-VAL-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"VALIDATION","mutation":"Modificar min/max sin fuente.","source_anchor":"screen:B2B-CARGA-001","rationale":"Parámetro funcional nuevo.","base_decision":"HUMAN_REQUIRED","base_impact_families":["VALIDATIONS","FIELDS","SOURCE_AUTHORITY_PROVENANCE"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["FIELDS","SOURCE_AUTHORITY_PROVENANCE","VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["FIELDS","SOURCE_AUTHORITY_PROVENANCE","VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"VALIDATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-VAL-05',
  711035,
  array[]::text[],
  'M7.11 gold50 v2 — VALIDATION — CI-VAL-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"VALIDATION","mutation":"Agregar validación a SYSTEM/readonly para coverage.","source_anchor":"screen:B2B-CARGA-001","rationale":"Readonly no requiere input validation.","base_decision":"SCOPED_BLOCK","base_impact_families":["VALIDATIONS","FIELDS"],"adjudicated_decision":"SCOPED_BLOCK","adjudicated_impact_families":["FIELDS","VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_BLOCK","impact_families":["FIELDS","VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"VALIDATION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-STATE-01',
  711036,
  array[]::text[],
  'M7.11 gold50 v2 — STATE_TRANSITION — CI-STATE-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"STATE_TRANSITION","mutation":"Mantener 14 estados + 16 transiciones UPLOAD_BATCH.","source_anchor":"state_set:UPLOAD_BATCH","rationale":"Máquina estable.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["STATES","TRANSITIONS"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["STATES","TRANSITIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["STATES","TRANSITIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"STATE_TRANSITION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-STATE-02',
  711037,
  array[]::text[],
  'M7.11 gold50 v2 — STATE_TRANSITION — CI-STATE-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"STATE_TRANSITION","mutation":"Cambiar origen/destino de transición.","source_anchor":"state_set:UPLOAD_BATCH","rationale":"Cambia lifecycle.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["STATES","TRANSITIONS","ACTIONS"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ACTIONS","STATES","TRANSITIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ACTIONS","STATES","TRANSITIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"STATE_TRANSITION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-STATE-03',
  711038,
  array[]::text[],
  'M7.11 gold50 v2 — STATE_TRANSITION — CI-STATE-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"STATE_TRANSITION","mutation":"Eliminar permission guard de transición.","source_anchor":"state_set:UPLOAD_BATCH","rationale":"Amplía capacidad.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["TRANSITIONS","PERMISSIONS","SECURITY"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["PERMISSIONS","SECURITY","TRANSITIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["PERMISSIONS","SECURITY","TRANSITIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"STATE_TRANSITION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-STATE-04',
  711039,
  array[]::text[],
  'M7.11 gold50 v2 — STATE_TRANSITION — CI-STATE-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"STATE_TRANSITION","mutation":"Agregar estado/transición.","source_anchor":"state_set:UPLOAD_BATCH","rationale":"Nueva semántica.","base_decision":"HUMAN_REQUIRED","base_impact_families":["STATES","TRANSITIONS","ACTIONS"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["ACTIONS","SOURCE_AUTHORITY_PROVENANCE","STATES","TRANSITIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["ACTIONS","SOURCE_AUTHORITY_PROVENANCE","STATES","TRANSITIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"STATE_TRANSITION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-STATE-05',
  711040,
  array[]::text[],
  'M7.11 gold50 v2 — STATE_TRANSITION — CI-STATE-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"STATE_TRANSITION","mutation":"Referencia estado de otra pantalla.","source_anchor":"state_set:UPLOAD_BATCH","rationale":"Cross-screen ref inválida.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["STATES","TRANSITIONS"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["STATES","TRANSITIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["STATES","TRANSITIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"STATE_TRANSITION","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ERR-01',
  711041,
  array[]::text[],
  'M7.11 gold50 v2 — ERROR_UI_MESSAGE — CI-ERR-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ERROR_UI_MESSAGE","mutation":"Artefacto reconcilia mensaje al canónico LF-B2B-AUTH-001.","source_anchor":"error:LF-B2B-AUTH-001","rationale":"Copy de error ya definida.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["ERRORS","UI_MESSAGES","VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["ERRORS","UI_MESSAGES","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["ERRORS","UI_MESSAGES","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ERROR_UI_MESSAGE","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ERR-02',
  711042,
  array[]::text[],
  'M7.11 gold50 v2 — ERROR_UI_MESSAGE — CI-ERR-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ERROR_UI_MESSAGE","mutation":"HTTP 403 -> 200 manteniendo no autorizado.","source_anchor":"error:LF-B2B-AUTH-001","rationale":"Potencial fail-open.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["ERRORS","SECURITY","API_DATA_CONTRACT"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["API_DATA_CONTRACT","ERRORS","SECURITY"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["API_DATA_CONTRACT","ERRORS","SECURITY"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ERROR_UI_MESSAGE","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ERR-03',
  711043,
  array[]::text[],
  'M7.11 gold50 v2 — ERROR_UI_MESSAGE — CI-ERR-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ERROR_UI_MESSAGE","mutation":"retryable false -> true en autorización.","source_anchor":"error:LF-B2B-AUTH-001","rationale":"Cambia recuperación.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["ERRORS","SECURITY","TIMEOUT_RETRY"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["ERRORS","SECURITY","TIMEOUT_RETRY"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["ERRORS","SECURITY","TIMEOUT_RETRY"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ERROR_UI_MESSAGE","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ERR-04',
  711044,
  array[]::text[],
  'M7.11 gold50 v2 — ERROR_UI_MESSAGE — CI-ERR-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ERROR_UI_MESSAGE","mutation":"Mensaje divulga detalle sensible.","source_anchor":"error:LF-B2B-AUTH-001","rationale":"Disclosure no autorizado.","base_decision":"SCOPED_BLOCK","base_impact_families":["ERRORS","UI_MESSAGES","SECURITY"],"adjudicated_decision":"SCOPED_BLOCK","adjudicated_impact_families":["ERRORS","SECURITY","UI_MESSAGES"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_BLOCK","impact_families":["ERRORS","SECURITY","UI_MESSAGES"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ERROR_UI_MESSAGE","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-ERR-05',
  711045,
  array[]::text[],
  'M7.11 gold50 v2 — ERROR_UI_MESSAGE — CI-ERR-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"ERROR_UI_MESSAGE","mutation":"Crear error nuevo no definido.","source_anchor":"screen:B2B-CARGA-001","rationale":"No inventar catálogo.","base_decision":"HUMAN_REQUIRED","base_impact_families":["ERRORS","UI_MESSAGES","SOURCE_AUTHORITY_PROVENANCE"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["ERRORS","SOURCE_AUTHORITY_PROVENANCE","UI_MESSAGES"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["ERRORS","SOURCE_AUTHORITY_PROVENANCE","UI_MESSAGES"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"ERROR_UI_MESSAGE","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-API-01',
  711046,
  array[]::text[],
  'M7.11 gold50 v2 — API_DATA_CONTRACT — CI-API-01',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"API_DATA_CONTRACT","mutation":"Pedido artifact-only de copy con API_DATA_CONTRACT global abierto.","source_anchor":"api:API_CONTRACT_RESOLUTION_V1:no_behavioral_contract","rationale":"CORE: gap API no relacionado no debe convertirse automáticamente en dependencia del delta.","base_decision":"SCOPED_CANDIDATE","base_impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"adjudicated_decision":"SCOPED_CANDIDATE","adjudicated_impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"SCOPED_CANDIDATE","impact_families":["ACTIONS","PERMISSIONS","VISUAL_EVIDENCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"API_DATA_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-API-02',
  711047,
  array[]::text[],
  'M7.11 gold50 v2 — API_DATA_CONTRACT — CI-API-02',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"API_DATA_CONTRACT","mutation":"Cambiar comportamiento de filtros/query.","source_anchor":"api:API_CONTRACT_RESOLUTION_V1:no_behavioral_contract","rationale":"Toca API directamente.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["API_DATA_CONTRACT","FIELDS","VALIDATIONS","OBJECTIVE_OUTCOMES"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["API_DATA_CONTRACT","FIELDS","OBJECTIVE_OUTCOMES","VALIDATIONS"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["API_DATA_CONTRACT","FIELDS","OBJECTIVE_OUTCOMES","VALIDATIONS"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"API_DATA_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-API-03',
  711048,
  array[]::text[],
  'M7.11 gold50 v2 — API_DATA_CONTRACT — CI-API-03',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"API_DATA_CONTRACT","mutation":"Cambiar paginación.","source_anchor":"api:API_CONTRACT_RESOLUTION_V1:no_behavioral_contract","rationale":"Requiere contrato.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["API_DATA_CONTRACT","FIELDS","OBJECTIVE_OUTCOMES"],"adjudicated_decision":"GLOBAL_ESCALATE","adjudicated_impact_families":["API_DATA_CONTRACT","FIELDS","OBJECTIVE_OUTCOMES"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"GLOBAL_ESCALATE","impact_families":["API_DATA_CONTRACT","FIELDS","OBJECTIVE_OUTCOMES"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"API_DATA_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-API-04',
  711049,
  array[]::text[],
  'M7.11 gold50 v2 — API_DATA_CONTRACT — CI-API-04',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"API_DATA_CONTRACT","mutation":"Cambiar payload/formato de exportación.","source_anchor":"permission:B2B_LOAD_HISTORY_EXPORT|api:API_CONTRACT_RESOLUTION_V1","rationale":"Cambia integración.","base_decision":"GLOBAL_ESCALATE","base_impact_families":["API_DATA_CONTRACT","ACTIONS","PERMISSIONS"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SOURCE_AUTHORITY_PROVENANCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["ACTIONS","API_DATA_CONTRACT","PERMISSIONS","SOURCE_AUTHORITY_PROVENANCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"API_DATA_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'CI-API-05',
  711050,
  array[]::text[],
  'M7.11 gold50 v2 — API_DATA_CONTRACT — CI-API-05',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  '["Use the adjudicated v2 decision and impact families as expected authority","Preserve base gold mutation/source anchor/rationale as fixture provenance","No scoped pass, downstream execution, or production authorization is implied"]'::jsonb,
  '{"schema_version":"M711_CHANGE_IMPACT_GOLD50_FIXTURE_V2","case_family":"API_DATA_CONTRACT","mutation":"Inventar endpoint/schema para cerrar blocker.","source_anchor":"api:API_CONTRACT_RESOLUTION_V1:no_behavioral_contract","rationale":"Autocanonicalization prohibida.","base_decision":"HUMAN_REQUIRED","base_impact_families":["API_DATA_CONTRACT","SOURCE_AUTHORITY_PROVENANCE"],"adjudicated_decision":"HUMAN_REQUIRED","adjudicated_impact_families":["API_DATA_CONTRACT","SOURCE_AUTHORITY_PROVENANCE"],"screen_code":"B2B-CARGA-001","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11"}'::jsonb,
  '{"decision":"HUMAN_REQUIRED","impact_families":["API_DATA_CONTRACT","SOURCE_AUTHORITY_PROVENANCE"],"oracle_version":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2"}'::jsonb,
  '{"decision_drift":true,"impact_family_drift":true,"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}'::jsonb,
  'CANDIDATO',
  '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.11","work_code":"PAULO-064","checkpoint_code":"REGISTER_SUITE","case_family":"API_DATA_CONTRACT","benchmark":"INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1","adjudication_schema":"INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2","source_commit_sha":"5fa5e98d0c8400d4d685c378043557d8f1f308a0","source_base_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql","source_adjudicated_path":"sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json","source_base_blob_sha":"cfe2731c872e334d95523a3c7f085c31f92a6f70","source_adjudicated_blob_sha":"32ec59b23a70e09b77245579145233a5ee462c11","authorization":{"scoped_pass_authorized":false,"downstream_authorized":false,"production_authorized":false}}'::jsonb,
  'CHATGPT-IG-M711-GOLD50-V2-20261007',
  'CHATGPT-IG-M711-GOLD50-V2-20261007'
);

update public.lf_test_suites
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'm7_11_change_impact_l3c_gold50_v2',
      jsonb_build_object(
        'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
        'unit_code','M7.11',
        'work_code','PAULO-064',
        'checkpoint_code','REGISTER_SUITE',
        'case_count',50,
        'family_count',10,
        'cases_per_family',5,
        'base_benchmark','INPUT_GOV_CHANGE_IMPACT_L3C_GOLD50_V1',
        'base_blob_sha','cfe2731c872e334d95523a3c7f085c31f92a6f70',
        'adjudication_schema','INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2',
        'adjudicated_blob_sha','32ec59b23a70e09b77245579145233a5ee462c11',
        'source_commit_sha','5fa5e98d0c8400d4d685c378043557d8f1f308a0',
        'decision_distribution','{"SCOPED_CANDIDATE":11,"SCOPED_BLOCK":7,"HUMAN_REQUIRED":11,"GLOBAL_ESCALATE":21}'::jsonb,
        'authorization',jsonb_build_object(
          'scoped_pass_authorized',false,
          'downstream_authorized',false,
          'production_authorized',false
        )
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-M711-GOLD50-V2-20261007'
where suite_code='INPUT_GOVERNANCE_REGRESSION';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'REGISTER_SUITE',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','REGISTER_SUITE',
      'checkpoint_title','Registrar suite gobernada (o casos dentro de INPUT_GOVERNANCE_REGRESSION) vía migración Git (R16)',
      'action_kind','MATERIALIZE_DECLARED_DELIVERABLE',
      'recipe_mode','GIT_FIRST_OR_VERSIONED_CONTRACT',
      'precision','EXPLICIT_M711_GOLD50_V2_MATERIALIZATION',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'requires_material_execution',true,
      'mutation_policy','ONLY_DECLARED_TARGETS',
      'expected','Materialize exactly 50 adjudicated change-impact gold cases inside INPUT_GOVERNANCE_REGRESSION: 10 families x 5 cases, expected decisions and impact families bound to adjudicated v2, with no authorization escalation.',
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'public.lf_test_suites',
          'public.lf_test_suite_cases'
        ),
        'declared_artifacts',jsonb_build_array(
          jsonb_build_object(
            'path','cristhianlujan/claude-persona-lf-patch@5fa5e98d0c8400d4d685c378043557d8f1f308a0:sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql',
            'role','BASE_GOLD_EVIDENCE'
          ),
          jsonb_build_object(
            'path','cristhianlujan/claude-persona-lf-patch@5fa5e98d0c8400d4d685c378043557d8f1f308a0:sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json',
            'role','ADJUDICATED_EXPECTED_AUTHORITY'
          )
        ),
        'declared_assets',jsonb_build_array('TEST_SUITE_INPUT_GOVERNANCE_REGRESSION_V1'),
        'declared_events','[]'::jsonb,
        'mutation_artifacts',jsonb_build_array(
          jsonb_build_object(
            'path','github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007022000_m711_register_gold50_v2.sql',
            'role','GIT_FIRST_MIGRATION'
          )
        )
      ),
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'case_count_exact',true,
          'unique_case_count_exact',true,
          'family_count_exact',true,
          'families_exact_5',true,
          'source_blobs_exact',true,
          'adjudicated_decisions_bound',true,
          'adjudicated_impacts_bound',true,
          'api04_correction_present',true,
          'authorization_remains_false',true
        )
      ),
      'verification_queries',jsonb_build_array(
$q$
with c as (
  select *
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and metadata->>'unit_code'='M7.11'
    and metadata->>'checkpoint_code'='REGISTER_SUITE'
), fam as (
  select metadata->>'case_family' case_family,count(*) n
  from c
  group by 1
)
select
  count(*)=50 as case_count_exact,
  count(distinct test_code)=50 as unique_case_count_exact,
  count(distinct metadata->>'case_family')=10 as family_count_exact,
  not exists(select 1 from fam where n<>5) as families_exact_5,
  bool_and(metadata->>'source_base_blob_sha'='cfe2731c872e334d95523a3c7f085c31f92a6f70')
    and bool_and(metadata->>'source_adjudicated_blob_sha'='32ec59b23a70e09b77245579145233a5ee462c11')
    as source_blobs_exact,
  bool_and(expected_output->>'decision'=input_payload->>'adjudicated_decision')
    as adjudicated_decisions_bound,
  bool_and(expected_output->'impact_families'=input_payload->'adjudicated_impact_families')
    as adjudicated_impacts_bound,
  count(*) filter(
    where test_code='CI-API-04'
      and expected_output->>'decision'='HUMAN_REQUIRED'
  )=1 as api04_correction_present,
  bool_and((prohibited_output->>'scoped_pass_authorized')::boolean=false)
    and bool_and((prohibited_output->>'downstream_authorized')::boolean=false)
    and bool_and((prohibited_output->>'production_authorized')::boolean=false)
    as authorization_remains_false
from c
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'CREATE_PARALLEL_TEST_SUITE',
        'USE_BASE_DECISION_WHEN_ADJUDICATED_V2_DIFFERS',
        'AUTHORIZE_SCOPED_PASS',
        'AUTHORIZE_DOWNSTREAM',
        'AUTHORIZE_PRODUCTION',
        'MUTATE_UNDECLARED_TARGET',
        'SYNTHETIC_PASS'
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M7.11'
  and disposition='ASSIGNED';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-M711-GOLD50-GOVERNED-MATERIALIZATION-001',
  'INPUT_GOVERNANCE',
  'Adjudicated Gold50 must be materialized as governed suite cases before execution',
  'M7.11 uses the existing INPUT_GOVERNANCE_REGRESSION suite and materializes exactly 50 change-impact gold cases. Fixture provenance comes from GOLD50 V1 while expected decision and impact-family authority come from ADJUDICATED_GOLD_V2. The v2 adjudication preserves 50 case IDs, changes impact families in eight cases, and changes CI-API-04 from GLOBAL_ESCALATE to HUMAN_REQUIRED.',
  'The sandbox gold and adjudication existed as evidence but the 50 cases were not registered in lf_test_suite_cases.',
  'SANDBOX_GOLD_EXISTS_WITHOUT_GOVERNED_CASE_MATERIALIZATION',
  'Register the exact 50 cases Git-first in the existing suite; bind expected decision/impact to adjudicated v2; preserve base mutation/source/rationale only as fixture provenance; never infer authorization from SCOPED_CANDIDATE.',
  'PASS when 50 unique cases exist, 10 families have exactly 5 cases each, source blob SHAs match, expected decision/impact equal adjudicated v2, CI-API-04 is HUMAN_REQUIRED, and all authorization flags remain false.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007022000_m711_register_gold50_v2.sql; github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_adjudicated_gold_v2.json',
  'EXECUTION',
  array['INPUT_GOVERNANCE','ENGINEERING_SCHEDULER']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M7.11 REGISTER_SUITE',
  'supabase://public.lf_test_suite_cases'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();

do $post$
declare
  v_count integer;
  v_families integer;
begin
  select count(*),count(distinct metadata->>'case_family')
    into v_count,v_families
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and metadata->>'unit_code'='M7.11'
    and metadata->>'checkpoint_code'='REGISTER_SUITE';

  if v_count<>50 or v_families<>10 then
    raise exception 'M711_GOLD50_POSTCHECK_CARDINALITY cases=% families=%',v_count,v_families;
  end if;

  if not exists (
    select 1
    from public.lf_test_suite_cases
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and test_code='CI-API-04'
      and expected_output->>'decision'='HUMAN_REQUIRED'
  ) then
    raise exception 'M711_GOLD50_API04_ADJUDICATION_MISSING';
  end if;
end;
$post$;
