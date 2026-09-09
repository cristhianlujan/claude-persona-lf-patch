begin;

do $preflight$
begin
  if exists (select 1 from public.lf_operation_registry where operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF')) then
    raise exception 'S30_POLICY_V2_TARGET_OPERATION_ALREADY_EXISTS';
  end if;
  if exists (select 1 from public.lf_router_action_registry where asset_type='REGLA' and action_code in ('POLICY_CREATE','POLICY_UPDATE')) then
    raise exception 'S30_POLICY_V2_TARGET_ROUTE_ALREADY_EXISTS';
  end if;
  if not exists (select 1 from public.lf_activos where codigo_activo='POL-STRATEGY-CREATION-001' and tipo_activo='REGLA' and archived_at is null) then
    raise exception 'S30_POLICY_V2_UPDATE_POSITIVE_TARGET_MISSING';
  end if;
end;
$preflight$;

insert into public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id)
values
('EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_CODE','CREACION_POLITICA_LF','IN_PROGRESS',
 jsonb_build_object('governance_bootstrap',true,'bootstrap_operation_code','CREACION_POLITICA_LF','bootstrap_status_ceiling','SANDBOX_ACTIVE','source_branch','lf/s30-policy-operations-candidate-20260909','source_blob','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209','claim_ceiling','ROLLBACK_ONLY_ROUTER_READY_CANARY'),
 'EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002'),
('EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_CODE','ACTUALIZACION_POLITICA_LF','IN_PROGRESS',
 jsonb_build_object('governance_bootstrap',true,'bootstrap_operation_code','ACTUALIZACION_POLITICA_LF','bootstrap_status_ceiling','SANDBOX_ACTIVE','source_branch','lf/s30-policy-operations-candidate-20260909','source_blob','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209','claim_ceiling','ROLLBACK_ONLY_ROUTER_READY_CANARY'),
 'EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002');

insert into public.lf_operation_registry(operation_code,version,status,source_model,source_repo,source_paths,notes,operation_family,operation_domain,operation_type,applies_to_asset_type,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','v0.2','CANDIDATO_READ_ONLY','GIT_FIRST_YAML','cristhianlujan/claude-persona-lf-patch','["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/validate_policy_operation_runtime_package.py","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/test_policy_operation_runtime_package.py","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/router_ready_rollback_canary_v2.sql"]'::jsonb,'Rollback-only Router READY candidate; no durable activation.','GOVERNANCE','POLICY_LIFECYCLE','CREATION_PROTOCOL','REGLA','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002'),
('ACTUALIZACION_POLITICA_LF','v0.2','CANDIDATO_READ_ONLY','GIT_FIRST_YAML','cristhianlujan/claude-persona-lf-patch','["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/validate_policy_operation_runtime_package.py","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/test_policy_operation_runtime_package.py","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/router_ready_rollback_canary_v2.sql"]'::jsonb,'Rollback-only Router READY candidate; successor-only update, no overwrite/supersession.','GOVERNANCE','POLICY_LIFECYCLE','UPDATE_PROTOCOL','REGLA','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002');

insert into public.lf_operation_contracts(operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','CONTRACT-CREACION-POLITICA-LF-v0.1','github://cristhianlujan/claude-persona-lf-patch/lf/s30-policy-operations-candidate-20260909/sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209','["router_read","ekb_read","schema_contract","target_missing","source_exact","payload_sha256","execution_binding"]'::jsonb,'{"asset_type":"REGLA","subtype_prefix":"POLICY_","candidate_only":true,"first_version_status":"CANDIDATE"}'::jsonb,'["direct_write_without_router","unsupported_policy_status","automatic_promotion","runtime_enable","production_enable"]'::jsonb,'["independent_readback","sha_readback","no_runtime_change","no_production_change","next_gate"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002'),
('ACTUALIZACION_POLITICA_LF','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','github://cristhianlujan/claude-persona-lf-patch/lf/s30-policy-operations-candidate-20260909/sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209','["router_read","ekb_read","schema_contract","target_existing","current_version","successor_missing","affected_consumers","source_exact","payload_sha256","execution_binding"]'::jsonb,'{"asset_type":"REGLA","subtype_prefix":"POLICY_","candidate_only":true,"successor_new_row_only":true}'::jsonb,'["direct_write_without_router","prior_version_overwrite","premature_supersession","automatic_promotion","runtime_enable","production_enable"]'::jsonb,'["successor_readback","prior_version_unchanged","no_supersession","no_runtime_change","no_production_change","next_gate"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002');

insert into public.lf_operation_judges(operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','JUDGE-CREACION-POLITICA-LF-v0.1','github://cristhianlujan/claude-persona-lf-patch/lf/s30-policy-operations-candidate-20260909/sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209','["all_required_evidence_present","target_semantics_match_operation","state_ceiling_preserved","independent_readback_passes"]'::jsonb,'["missing_required_evidence","unsupported_policy_status","runtime_or_production_enabled","automatic_promotion_attempted"]'::jsonb,'["PASS","FAIL","BLOCKED"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002'),
('ACTUALIZACION_POLITICA_LF','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1','github://cristhianlujan/claude-persona-lf-patch/lf/s30-policy-operations-candidate-20260909/sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209','["all_required_evidence_present","target_semantics_match_operation","state_ceiling_preserved","independent_readback_passes"]'::jsonb,'["missing_required_evidence","unsupported_policy_status","prior_version_overwritten","premature_supersession","runtime_or_production_enabled","automatic_promotion_attempted"]'::jsonb,'["PASS","FAIL","BLOCKED"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002');

with defs(operation_code,exec_id,contract_code,judge_code,step_order,step_id,evidence_required,purpose,input_required,output_payload,blocking_code,next_if_pass) as (
 values
 ('CREACION_POLITICA_LF','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','CONTRACT-CREACION-POLITICA-LF-v0.1','JUDGE-CREACION-POLITICA-LF-v0.1',10,'preflight','router_binding;ekb_refs;schema_contract;target_missing_readback;source_ref;payload_sha256','Resolver Router/EKB/schema/source/target/hash','["router_binding","ekb_refs","schema_contract","exact_policy_code","exact_policy_version","source_ref","payload_sha256"]'::jsonb,'["preflight_pass"]'::jsonb,'BLOCK_POLICY_CREATE_PREFLIGHT','materialize_candidate'),
 ('CREACION_POLITICA_LF','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','CONTRACT-CREACION-POLITICA-LF-v0.1','JUDGE-CREACION-POLITICA-LF-v0.1',20,'materialize_candidate','asset_insert_receipt;candidate_version_insert_receipt','Crear REGLA/POLICY_* y primera version CANDIDATE','["preflight_pass","exact_policy_code","exact_policy_version","payload_sha256"]'::jsonb,'["candidate_write_receipt"]'::jsonb,'BLOCK_POLICY_CREATE_MATERIALIZATION','verify'),
 ('CREACION_POLITICA_LF','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','CONTRACT-CREACION-POLITICA-LF-v0.1','JUDGE-CREACION-POLITICA-LF-v0.1',30,'verify','asset_readback;version_readback;sha_readback;no_runtime_change;no_production_change','Readback independiente y state ceiling','["candidate_write_receipt"]'::jsonb,'["verified"]'::jsonb,'BLOCK_POLICY_CREATE_VERIFY','close'),
 ('CREACION_POLITICA_LF','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','CONTRACT-CREACION-POLITICA-LF-v0.1','JUDGE-CREACION-POLITICA-LF-v0.1',40,'close','claim_ceiling;next_gate;no_automatic_promotion','Cerrar solo candidato','["verified"]'::jsonb,'["candidate_closed"]'::jsonb,'BLOCK_POLICY_CREATE_CLOSE',null),
 ('ACTUALIZACION_POLITICA_LF','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1',10,'preflight','router_binding;ekb_refs;schema_contract;current_version_readback;successor_missing_readback;affected_consumers;source_ref;payload_sha256','Resolver target/version/consumidores/source/hash','["router_binding","ekb_refs","schema_contract","exact_policy_code","current_version","successor_version","affected_consumers","source_ref","payload_sha256"]'::jsonb,'["preflight_pass"]'::jsonb,'BLOCK_POLICY_UPDATE_PREFLIGHT','materialize_successor'),
 ('ACTUALIZACION_POLITICA_LF','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1',20,'materialize_successor','successor_insert_receipt;prior_version_fingerprint_before','Insertar successor CANDIDATE sin mutar prior','["preflight_pass","successor_version","payload_sha256"]'::jsonb,'["successor_write_receipt"]'::jsonb,'BLOCK_POLICY_UPDATE_SUCCESSOR','verify'),
 ('ACTUALIZACION_POLITICA_LF','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1',30,'verify','successor_readback;prior_version_fingerprint_after;prior_version_unchanged;no_supersession;no_runtime_change;no_production_change','Readback successor y prueba prior intacta','["successor_write_receipt"]'::jsonb,'["verified"]'::jsonb,'BLOCK_POLICY_UPDATE_VERIFY','close'),
 ('ACTUALIZACION_POLITICA_LF','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1',40,'close','claim_ceiling;next_gate;no_premature_supersession;no_automatic_promotion','Cerrar successor solo candidato','["verified"]'::jsonb,'["candidate_closed"]'::jsonb,'BLOCK_POLICY_UPDATE_CLOSE',null)
)
insert into public.lf_operation_steps(operation_code,step_order,execution_order,step_id,required,evidence_required,source_path,source_sha,active,created_by_execution_id,updated_by_execution_id)
select operation_code,step_order,step_order,step_id,true,evidence_required,'sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209',true,exec_id,exec_id from defs;

with defs(operation_code,exec_id,contract_code,judge_code,step_order,step_id,evidence_required,purpose,input_required,output_payload,blocking_code,next_if_pass) as (
 values
 ('CREACION_POLITICA_LF','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','CONTRACT-CREACION-POLITICA-LF-v0.1','JUDGE-CREACION-POLITICA-LF-v0.1',10,'preflight','router_binding;ekb_refs;schema_contract;target_missing_readback;source_ref;payload_sha256','Resolver Router/EKB/schema/source/target/hash','["router_binding","ekb_refs","schema_contract","exact_policy_code","exact_policy_version","source_ref","payload_sha256"]'::jsonb,'["preflight_pass"]'::jsonb,'BLOCK_POLICY_CREATE_PREFLIGHT','materialize_candidate'),
 ('CREACION_POLITICA_LF','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','CONTRACT-CREACION-POLITICA-LF-v0.1','JUDGE-CREACION-POLITICA-LF-v0.1',20,'materialize_candidate','asset_insert_receipt;candidate_version_insert_receipt','Crear REGLA/POLICY_* y primera version CANDIDATE','["preflight_pass","exact_policy_code","exact_policy_version","payload_sha256"]'::jsonb,'["candidate_write_receipt"]'::jsonb,'BLOCK_POLICY_CREATE_MATERIALIZATION','verify'),
 ('CREACION_POLITICA_LF','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','CONTRACT-CREACION-POLITICA-LF-v0.1','JUDGE-CREACION-POLITICA-LF-v0.1',30,'verify','asset_readback;version_readback;sha_readback;no_runtime_change;no_production_change','Readback independiente y state ceiling','["candidate_write_receipt"]'::jsonb,'["verified"]'::jsonb,'BLOCK_POLICY_CREATE_VERIFY','close'),
 ('CREACION_POLITICA_LF','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','CONTRACT-CREACION-POLITICA-LF-v0.1','JUDGE-CREACION-POLITICA-LF-v0.1',40,'close','claim_ceiling;next_gate;no_automatic_promotion','Cerrar solo candidato','["verified"]'::jsonb,'["candidate_closed"]'::jsonb,'BLOCK_POLICY_CREATE_CLOSE',null),
 ('ACTUALIZACION_POLITICA_LF','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1',10,'preflight','router_binding;ekb_refs;schema_contract;current_version_readback;successor_missing_readback;affected_consumers;source_ref;payload_sha256','Resolver target/version/consumidores/source/hash','["router_binding","ekb_refs","schema_contract","exact_policy_code","current_version","successor_version","affected_consumers","source_ref","payload_sha256"]'::jsonb,'["preflight_pass"]'::jsonb,'BLOCK_POLICY_UPDATE_PREFLIGHT','materialize_successor'),
 ('ACTUALIZACION_POLITICA_LF','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1',20,'materialize_successor','successor_insert_receipt;prior_version_fingerprint_before','Insertar successor CANDIDATE sin mutar prior','["preflight_pass","successor_version","payload_sha256"]'::jsonb,'["successor_write_receipt"]'::jsonb,'BLOCK_POLICY_UPDATE_SUCCESSOR','verify'),
 ('ACTUALIZACION_POLITICA_LF','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1',30,'verify','successor_readback;prior_version_fingerprint_after;prior_version_unchanged;no_supersession;no_runtime_change;no_production_change','Readback successor y prueba prior intacta','["successor_write_receipt"]'::jsonb,'["verified"]'::jsonb,'BLOCK_POLICY_UPDATE_VERIFY','close'),
 ('ACTUALIZACION_POLITICA_LF','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1',40,'close','claim_ceiling;next_gate;no_premature_supersession;no_automatic_promotion','Cerrar successor solo candidato','["verified"]'::jsonb,'["candidate_closed"]'::jsonb,'BLOCK_POLICY_UPDATE_CLOSE',null)
)
insert into public.lf_operation_step_contracts(operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,created_by_execution_id,updated_by_execution_id)
select operation_code,step_id,step_order,step_order,contract_code,purpose,input_required,'SUPABASE_MCP',output_payload,'{"evidence_complete":true,"state_ceiling_preserved":true}'::jsonb,'{"blocked":true}'::jsonb,blocking_code,judge_code,to_jsonb(string_to_array(evidence_required,';')),next_if_pass,'close','ACTIVE_ENFORCEMENT','S30 policy operation rollback-only candidate.',exec_id,exec_id from defs;

insert into public.lf_operation_step_judge_bindings(operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys,status,created_by_execution_id,updated_by_execution_id)
select s.operation_code,s.step_order,s.step_id,j.judge_code,'PASS','BLOCKED','FAIL',c.required_evidence_keys,'ACTIVE_ENFORCEMENT',s.created_by_execution_id,s.created_by_execution_id
from public.lf_operation_steps s
join public.lf_operation_step_contracts c on c.operation_code=s.operation_code and c.step_id=s.step_id
join public.lf_operation_judges j on j.operation_code=s.operation_code
where s.operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF');

insert into public.lf_router_action_registry(asset_type,action_code,operation_code,operation_resolution,requires_existing_target,requires_missing_target,write_allowed,status,notes,created_by_execution_id,updated_by_execution_id)
values
('REGLA','POLICY_CREATE','CREACION_POLITICA_LF','STATIC',false,true,true,'ACTIVE','TEMPORARY ACTIVE INSIDE ROLLBACK ONLY; durable candidate remains CANDIDATE_SANDBOX.','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002','EXEC-S30-POLICY-CREATE-ROUTER-CANARY-20260909-002'),
('REGLA','POLICY_UPDATE','ACTUALIZACION_POLITICA_LF','STATIC',true,false,true,'ACTIVE','TEMPORARY ACTIVE INSIDE ROLLBACK ONLY; durable candidate remains CANDIDATE_SANDBOX.','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002','EXEC-S30-POLICY-UPDATE-ROUTER-CANARY-20260909-002');

do $assert_stack$
declare v integer;
begin
  select count(*) into v from public.lf_operation_contracts where operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF') and status='ACTIVE_ENFORCEMENT'; if v<>2 then raise exception 'S30_POLICY_V2_CONTRACT_COUNT:%',v; end if;
  select count(*) into v from public.lf_operation_steps where operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF') and active; if v<>8 then raise exception 'S30_POLICY_V2_STEP_COUNT:%',v; end if;
  select count(*) into v from public.lf_operation_step_contracts where operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF') and status='ACTIVE_ENFORCEMENT'; if v<>8 then raise exception 'S30_POLICY_V2_STEP_CONTRACT_COUNT:%',v; end if;
  select count(*) into v from public.lf_operation_judges where operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF') and status='ACTIVE_ENFORCEMENT'; if v<>2 then raise exception 'S30_POLICY_V2_JUDGE_COUNT:%',v; end if;
  select count(*) into v from public.lf_operation_step_judge_bindings where operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF') and status='ACTIVE_ENFORCEMENT'; if v<>8 then raise exception 'S30_POLICY_V2_JUDGE_BIND_COUNT:%',v; end if;
end;
$assert_stack$;

do $router_positive$
declare c jsonb; u jsonb;
begin
  c := public.lf_router_resolve_v1('Crear politica candidata LF','POL-S30-CANARY-NONEXISTENT','POLICY_CREATE','REGLA','ROUTER');
  if c->>'status'<>'READY_TO_EXECUTE' or c->>'operation_code'<>'CREACION_POLITICA_LF' or (c->>'contract_count')::int<1 or (c->>'step_count')::int<>4 or (c->>'required_policy_count')::int<>(c->>'resolved_policy_count')::int then
    raise exception 'S30_POLICY_V2_CREATE_ROUTER_NOT_READY:%',c;
  end if;
  u := public.lf_router_resolve_v1('Actualizar politica existente LF','POL-STRATEGY-CREATION-001','POLICY_UPDATE','REGLA','ROUTER');
  if u->>'status'<>'READY_TO_EXECUTE' or u->>'operation_code'<>'ACTUALIZACION_POLITICA_LF' or (u->>'contract_count')::int<1 or (u->>'step_count')::int<>4 or (u->>'required_policy_count')::int<>(u->>'resolved_policy_count')::int then
    raise exception 'S30_POLICY_V2_UPDATE_ROUTER_NOT_READY:%',u;
  end if;
end;
$router_positive$;

do $natural_inference_fail_closed$
declare c jsonb; u jsonb;
begin
  c := public.lf_router_resolve_v1('Crear politica nueva LF','POL-S30-CANARY-NONEXISTENT',null,'REGLA','ROUTER');
  if c->>'status'<>'BLOCKED' or c->>'blocking_code'<>'BLOCK_OPERATION_NOT_REGISTERED' then raise exception 'S30_POLICY_V2_NATURAL_CREATE_UNEXPECTED:%',c; end if;
  u := public.lf_router_resolve_v1('Actualizar politica existente LF','POL-STRATEGY-CREATION-001',null,'REGLA','ROUTER');
  if u->>'status'<>'BLOCKED' or u->>'blocking_code'<>'BLOCK_OPERATION_NOT_REGISTERED' then raise exception 'S30_POLICY_V2_NATURAL_UPDATE_UNEXPECTED:%',u; end if;
end;
$natural_inference_fail_closed$;

rollback;
