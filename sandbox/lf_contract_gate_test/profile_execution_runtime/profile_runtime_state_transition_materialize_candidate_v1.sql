-- Strategy 26 / backlog #55
-- MATERIALIZATION CANDIDATE ONLY. Source-first artifact; not a migration yet.
-- It registers a bounded candidate operation and state tuple in LF Supabase
-- sandbox, but MUST NOT change any profile state and MUST NOT add a write
-- executor or Router action mapping.
-- Source contract blob: 78f83eb86195b04cf56ee308302f511064e29f13

begin;

-- Fail closed on current Strategy26 target drift.
do $$
declare v public.v_lf_fuente_operativa%rowtype;
begin
  select * into v from public.v_lf_fuente_operativa where codigo_activo='PERFIL-UI-ARCHITECT' limit 1;
  if not found
     or v.estado_documental <> 'CANDIDATO'
     or v.estado_operativo <> 'READ_ONLY'
     or v.runtime_estado <> 'NO_HABILITADO'
     or v.impacto_automatico <> 'BLOQUEADO' then
    raise exception 'S26_GA_TARGET_PROFILE_STATE_DRIFT:%',to_jsonb(v);
  end if;
end;
$$;

insert into public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id
)
values (
  'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR',
  'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','IN_PROGRESS',
  '{"mode":"STRATEGY26_CANDIDATE_MATERIALIZATION","router":"ACT-0001","scope":"materialize candidate metadata only for bounded profile runtime-state transition","no_new_agents":true,"no_new_tables":true,"profile_state_change":false,"write_executor":false,"router_action_mapping":false,"validated_allowed":false,"production_allowed":false,"governance_bootstrap":true,"bootstrap_operation_code":"TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE"}'::jsonb,
  'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001',
  'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'
)
on conflict (execution_id) do nothing;

do $$
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id='EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'
      and operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
      and status='IN_PROGRESS'
      and coalesce((manifest->>'governance_bootstrap')::boolean,false)
      and manifest->>'bootstrap_operation_code'='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
      and manifest->>'bootstrap_status_ceiling'='SANDBOX_ACTIVE'
  ) then raise exception 'S26_GA_BOOTSTRAP_PROVENANCE_NOT_EXACT'; end if;
end;
$$;

insert into public.cat_estado_normalizacion_lf(
  estado_original,estado_documental,estado_operativo,nivel_control,
  runtime_estado,impacto_automatico,accion_recomendada,migration_blocker,notas
)
values (
  'CANDIDATO_CONTROLADO_READ_ONLY','CANDIDATO','READ_ONLY','CONTROLADO',
  'CANDIDATE_READ_ONLY','BLOQUEADO','MIGRAR_READ_ONLY',false,
  'Strategy26 bounded profile canary posture. No automatic impact or production promotion.'
)
on conflict (estado_original) do nothing;

do $$
begin
  if not exists (
    select 1 from public.cat_estado_normalizacion_lf
    where estado_original='CANDIDATO_CONTROLADO_READ_ONLY'
      and estado_documental='CANDIDATO' and estado_operativo='READ_ONLY'
      and nivel_control='CONTROLADO' and runtime_estado='CANDIDATE_READ_ONLY'
      and impacto_automatico='BLOQUEADO' and migration_blocker=false
  ) then raise exception 'S26_GA_TARGET_STATE_CATALOG_CONFLICT'; end if;
end;
$$;

insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,created_by_execution_id
)
values (
  'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','v0.1-candidate','CANDIDATO_READ_ONLY',
  'GIT_FIRST_SANDBOX_CONTRACT','cristhianlujan/claude-persona-lf-patch',
  '["sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json"]'::jsonb,
  'Strategy26 #55 metadata-only candidate. Single profile, reversible, NO_HABILITADO -> CANDIDATE_READ_ONLY preserving CANDIDATO/READ_ONLY/BLOQUEADO. No write executor, Router mapping, production, automatic impact, promotion or R4 claim.',
  'PROFILE_OPERATIONS','PROFILE_RUNTIME_STATE','STATE_TRANSITION_PROTOCOL','PERFIL',
  'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'
)
on conflict (operation_code) do nothing;

insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,required_before_write,
  allowed,blocked,required_after_write,status,created_by_execution_id
)
values (
  'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',
  'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate',
  'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json',
  '78f83eb86195b04cf56ee308302f511064e29f13',
  '["router_read","exact_profile_resolved","source_state_read","target_state_catalog_match"]'::jsonb,
  '{"asset_type":"PERFIL","single_target":true,"from":{"estado_documental":"CANDIDATO","estado_operativo":"READ_ONLY","runtime_estado":"NO_HABILITADO","impacto_automatico":"BLOQUEADO"},"to":{"estado_documental":"CANDIDATO","estado_operativo":"READ_ONLY","runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"},"github_write":false,"production_enablement":false,"automatic_impact":false,"promotion":false,"reversible":true}'::jsonb,
  '["profile_not_found","ambiguous_profile","source_state_drift","target_state_unregistered","mass_transition","impact_change","production_enablement","runtime_operativo_target","github_write","automatic_promotion","r4_self_attestation"]'::jsonb,
  '["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked","no_production_promotion","single_target_receipt"]'::jsonb,
  'CANDIDATO_READ_ONLY','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'
)
on conflict (operation_code,contract_code) do nothing;

insert into public.lf_operation_steps(operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,created_by_execution_id)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',10,'router',true,'router_read,profile_code','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,10,'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',20,'source_state_read',true,'source_state','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,20,'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',30,'target_state_validate',true,'target_state_catalog_match','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,30,'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',40,'controlled_write',true,'transition_receipt,before_state,after_state','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,40,'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',50,'readback',true,'exact_state_readback,router_post_transition_readback,automatic_impact_still_blocked','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,50,'EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001')
on conflict (operation_code,step_order) do nothing;

insert into public.lf_operation_step_contracts(operation_code,step_id,step_order,execution_order,contract_code,purpose,resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,created_by_execution_id)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','router',10,10,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Resolve ACT-0001 and exactly one profile.','public.v_lf_fuente_operativa.ACT-0001','["router_read","profile_code"]','{"router":"ACT-0001","single_profile_resolved":true}','{"ambiguous_profile":true,"missing_profile":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_ROUTER_NOT_CLEAN','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_ROUTER_V1','["router_read","profile_code"]','source_state_read','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','Deterministic source gate.','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','source_state_read',20,20,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Read exact four-dimensional source state.','public.v_lf_fuente_operativa','["source_state"]','{"source_state_equals_contract_from":true}','{"source_state_drift":true,"unknown_state_dimension":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_MISMATCH','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_V1','["source_state"]','target_state_validate','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','Never infer permission from one state dimension.','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','target_state_validate',30,30,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Require exactly one canonical target tuple.','public.cat_estado_normalizacion_lf','["target_state_catalog_match"]','{"target_state_equals_contract_to":true,"catalog_row_exactly_one":true}','{"target_state_unregistered":true,"target_state_ambiguous":true,"impact_change":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_NOT_CANONICAL','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_V1','["target_state_catalog_match"]','controlled_write','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','Candidate catalog tuple only.','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','controlled_write',40,40,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Bound single-profile transition preserving CANDIDATO/READ_ONLY/BLOQUEADO.','DETERMINISTIC_SUPABASE_STATE_TRANSITION_CANDIDATE','["transition_receipt","before_state","after_state"]','{"single_target":true,"only_runtime_state_delta":true,"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}','{"mass_transition":true,"impact_change":true,"production_enablement":true,"runtime_operativo_target":true,"unbound_target":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_WRITE_NOT_BOUNDED','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_CONTROLLED_WRITE_V1','["transition_receipt","before_state","after_state"]','readback','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','execution_sql intentionally NULL.','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','readback',50,50,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Verify exact target state and blocked automatic impact.','public.v_lf_fuente_operativa','["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"]','{"same_target":true,"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}','{"readback_mismatch":true,"automatic_impact_enabled":true,"production_promotion":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_READBACK_FAILED','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_READBACK_V1','["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"]',null,'RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','R4 remains separate.','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001')
on conflict (operation_code,step_id) do nothing;

insert into public.lf_operation_judges(operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_ROUTER_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"router","must_have_evidence":["router_read","profile_code"],"router":"ACT-0001"}','{"wrong_step_id":true,"missing_evidence":true,"ambiguous_profile":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"source_state_read","must_have_evidence":["source_state"],"source_state_equals_contract_from":true}','{"wrong_step_id":true,"missing_evidence":true,"source_state_drift":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"target_state_validate","must_have_evidence":["target_state_catalog_match"],"catalog_row_exactly_one":true}','{"wrong_step_id":true,"missing_evidence":true,"target_state_unregistered":true,"impact_change":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_CONTROLLED_WRITE_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"controlled_write","must_have_evidence":["transition_receipt","before_state","after_state"],"single_target":true,"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}','{"wrong_step_id":true,"missing_evidence":true,"mass_transition":true,"impact_change":true,"production_enablement":true,"runtime_operativo_target":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_READBACK_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"readback","must_have_evidence":["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"],"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}','{"wrong_step_id":true,"missing_evidence":true,"readback_mismatch":true,"automatic_impact_enabled":true,"production_promotion":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001')
on conflict (operation_code,judge_code) do nothing;

insert into public.lf_operation_step_judge_bindings(operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys,status,created_by_execution_id)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',10,'router','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_ROUTER_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["router_read","profile_code"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',20,'source_state_read','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["source_state"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',30,'target_state_validate','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["target_state_catalog_match"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',40,'controlled_write','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_CONTROLLED_WRITE_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["transition_receipt","before_state","after_state"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',50,'readback','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_READBACK_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001')
on conflict (operation_code,step_order,step_id) do nothing;

insert into public.lf_operation_policy_bindings(operation_code,policy_code,policy_role,required,distribution_modes,binding_status,created_by_execution_id)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','POL-LF-OPERATION-LIFECYCLE','GOVERNANCE_LIFECYCLE',true,ARRAY['ROUTER']::text[],'ACTIVE','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','POL-LF-STATE-MODEL','STATE_MODEL',true,ARRAY['ROUTER']::text[],'ACTIVE','EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001')
on conflict (operation_code,policy_code,policy_role) do nothing;

-- Exact topology and safety assertions.
do $$
declare v_policy_count integer;
begin
  if (select count(*) from public.lf_operation_steps where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF') <> 5 then raise exception 'S26_GA_MATERIALIZE_STEPS_NOT_5'; end if;
  if (select count(*) from public.lf_operation_step_contracts where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF') <> 5 then raise exception 'S26_GA_MATERIALIZE_STEP_CONTRACTS_NOT_5'; end if;
  if (select count(*) from public.lf_operation_judges where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF') <> 5 then raise exception 'S26_GA_MATERIALIZE_JUDGES_NOT_5'; end if;
  if (select count(*) from public.lf_operation_step_judge_bindings where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF') <> 5 then raise exception 'S26_GA_MATERIALIZE_BINDINGS_NOT_5'; end if;
  if exists(select 1 from public.lf_operation_step_contracts where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' and execution_sql is not null) then raise exception 'S26_GA_MATERIALIZE_WRITE_EXECUTOR_PRESENT'; end if;
  if exists(select 1 from public.lf_router_action_registry where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' and status='ACTIVE') then raise exception 'S26_GA_MATERIALIZE_ROUTER_MAPPING_FORBIDDEN'; end if;
  select count(*) into v_policy_count from public.v_lf_operation_policy_snapshot where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' and policy_code in ('POL-LF-OPERATION-LIFECYCLE','POL-LF-STATE-MODEL') and required and policy_sha is not null;
  if v_policy_count <> 2 then raise exception 'S26_GA_MATERIALIZE_POLICIES_NOT_2:%',v_policy_count; end if;
  if not exists(select 1 from public.v_lf_fuente_operativa where codigo_activo='PERFIL-UI-ARCHITECT' and estado_documental='CANDIDATO' and estado_operativo='READ_ONLY' and runtime_estado='NO_HABILITADO' and impacto_automatico='BLOQUEADO') then raise exception 'S26_GA_PROFILE_CHANGED_DURING_METADATA_MATERIALIZATION'; end if;
end;
$$;

update public.lf_operation_execution
set status='COMPLETED',completed_at=now(),
    manifest=manifest||'{"materialization_result":"CANDIDATE_METADATA_ONLY_PASS","profile_state_changed":false,"write_executor":false,"router_action_mapping":false}'::jsonb,
    updated_at=now(),updated_by_execution_id='EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001'
where execution_id='EXEC-S26-GA-MATERIALIZE-CANDIDATE-20260905-001';

commit;
