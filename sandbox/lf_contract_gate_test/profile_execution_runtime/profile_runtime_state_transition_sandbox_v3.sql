-- Strategy 26 / backlog #55
-- ROLLBACK-ONLY sandbox V3. Must leave zero durable rows.
-- Exact source contract blob: 78f83eb86195b04cf56ee308302f511064e29f13
-- V2 discovered that a newly materialized operation resolves lifecycle only;
-- this V3 references the existing STATE_MODEL mother policy explicitly as a
-- binding, without copying policy content.

begin;

insert into public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id
)
values (
  'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR',
  'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','IN_PROGRESS',
  '{"mode":"STRATEGY26_SANDBOX","router":"ACT-0001","scope":"rollback-only profile runtime-state transition candidate with exact source, judges, bindings, lifecycle and state-model policy references","no_new_agents":true,"no_new_tables":true,"validated_allowed":false,"production_allowed":false,"governance_bootstrap":true,"bootstrap_operation_code":"TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE"}'::jsonb,
  'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001',
  'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'
);

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

insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id
)
values (
  'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','v0.1-candidate','CANDIDATO_READ_ONLY',
  'GIT_FIRST_SANDBOX_CONTRACT','cristhianlujan/claude-persona-lf-patch',
  '["sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json"]'::jsonb,
  'Strategy26 #55. Single-profile reversible transition NO_HABILITADO -> CANDIDATE_READ_ONLY preserving CANDIDATO/READ_ONLY/BLOQUEADO. No production, automatic impact, promotion, or R4 claim.',
  'PROFILE_OPERATIONS','PROFILE_RUNTIME_STATE','STATE_TRANSITION_PROTOCOL','PERFIL',
  'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'
);

insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,
  required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id
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
  'CANDIDATO_READ_ONLY','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'
);

insert into public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,created_by_execution_id
)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',10,'router',true,'router_read,profile_code','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,10,'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',20,'source_state_read',true,'source_state','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,20,'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',30,'target_state_validate',true,'target_state_catalog_match','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,30,'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',40,'controlled_write',true,'transition_receipt,before_state,after_state','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,40,'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',50,'readback',true,'exact_state_readback,router_post_transition_readback,automatic_impact_still_blocked','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13',true,50,'EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001');

insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,resolver_ref,
  output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,
  required_evidence_keys,next_if_pass,next_if_blocked,status,notes,created_by_execution_id
)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','router',10,10,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Resolve ACT-0001 and exactly one profile.','public.v_lf_fuente_operativa.ACT-0001','["router_read","profile_code"]','{"router":"ACT-0001","single_profile_resolved":true}','{"ambiguous_profile":true,"missing_profile":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_ROUTER_NOT_CLEAN','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_ROUTER_V1','["router_read","profile_code"]','source_state_read','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','Deterministic source gate.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','source_state_read',20,20,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Read exact four-dimensional source state.','public.v_lf_fuente_operativa','["source_state"]','{"source_state_equals_contract_from":true}','{"source_state_drift":true,"unknown_state_dimension":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_MISMATCH','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_V1','["source_state"]','target_state_validate','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','Never infer permission from one state dimension.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','target_state_validate',30,30,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Require exactly one canonical target tuple.','public.cat_estado_normalizacion_lf','["target_state_catalog_match"]','{"target_state_equals_contract_to":true,"catalog_row_exactly_one":true}','{"target_state_unregistered":true,"target_state_ambiguous":true,"impact_change":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_NOT_CANONICAL','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_V1','["target_state_catalog_match"]','controlled_write','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','Candidate catalog tuple only.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','controlled_write',40,40,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Bound single-profile transition preserving CANDIDATO/READ_ONLY/BLOQUEADO.','DETERMINISTIC_SUPABASE_STATE_TRANSITION_CANDIDATE','["transition_receipt","before_state","after_state"]','{"single_target":true,"only_runtime_state_delta":true,"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}','{"mass_transition":true,"impact_change":true,"production_enablement":true,"runtime_operativo_target":true,"unbound_target":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_WRITE_NOT_BOUNDED','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_CONTROLLED_WRITE_V1','["transition_receipt","before_state","after_state"]','readback','RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','execution_sql intentionally NULL until controlled authorization.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','readback',50,50,'CONTRACT-TRANSICION-RUNTIME-PERFIL-READ-ONLY-LF-v0.1-candidate','Verify exact target state and blocked automatic impact.','public.v_lf_fuente_operativa','["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"]','{"same_target":true,"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}','{"readback_mismatch":true,"automatic_impact_enabled":true,"production_promotion":true}','BLOCK_PROFILE_RUNTIME_TRANSITION_READBACK_FAILED','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_READBACK_V1','["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"]',null,'RETURN_TO_ROUTER','CANDIDATO_READ_ONLY','R4 remains a separate later gate.','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001');

insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id
)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_ROUTER_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"router","must_have_evidence":["router_read","profile_code"],"router":"ACT-0001"}','{"wrong_step_id":true,"missing_evidence":true,"ambiguous_profile":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"source_state_read","must_have_evidence":["source_state"],"source_state_equals_contract_from":true}','{"wrong_step_id":true,"missing_evidence":true,"source_state_drift":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"target_state_validate","must_have_evidence":["target_state_catalog_match"],"catalog_row_exactly_one":true}','{"wrong_step_id":true,"missing_evidence":true,"target_state_unregistered":true,"impact_change":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_CONTROLLED_WRITE_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"controlled_write","must_have_evidence":["transition_receipt","before_state","after_state"],"single_target":true,"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}','{"wrong_step_id":true,"missing_evidence":true,"mass_transition":true,"impact_change":true,"production_enablement":true,"runtime_operativo_target":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_READBACK_V1','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_state_transition_contract_v1.json','78f83eb86195b04cf56ee308302f511064e29f13','{"step_id":"readback","must_have_evidence":["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"],"runtime_estado":"CANDIDATE_READ_ONLY","impacto_automatico":"BLOQUEADO"}','{"wrong_step_id":true,"missing_evidence":true,"readback_mismatch":true,"automatic_impact_enabled":true,"production_promotion":true}','["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001');

insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,
  return_result_value,required_evidence_keys,status,created_by_execution_id
)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',10,'router','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_ROUTER_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["router_read","profile_code"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',20,'source_state_read','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["source_state"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',30,'target_state_validate','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_TARGET_STATE_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["target_state_catalog_match"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',40,'controlled_write','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_CONTROLLED_WRITE_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["transition_receipt","before_state","after_state"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',50,'readback','MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_READBACK_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER','["exact_state_readback","router_post_transition_readback","automatic_impact_still_blocked"]','ACTIVE_ENFORCEMENT','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001');

-- Reference the existing mother policies; do not duplicate policy payloads.
insert into public.lf_operation_policy_bindings(
  operation_code,policy_code,policy_role,required,distribution_modes,binding_status,created_by_execution_id
)
values
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','POL-LF-OPERATION-LIFECYCLE','GOVERNANCE_LIFECYCLE',true,ARRAY['ROUTER']::text[],'ACTIVE','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001'),
('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','POL-LF-STATE-MODEL','STATE_MODEL',true,ARRAY['ROUTER']::text[],'ACTIVE','EXEC-S26-GA-BOOTSTRAP-SANDBOX-V3-20260905-001');

-- Shared deterministic predicate used by positive and negative fixtures.
create temporary table _s26_transition_temp_marker(x integer);
create or replace function pg_temp.s26_profile_runtime_transition_allowed(
  p_src_doc text,p_src_op text,p_src_runtime text,p_src_impact text,
  p_dst_doc text,p_dst_op text,p_dst_runtime text,p_dst_impact text,
  p_target_catalog_count integer,p_selected_target_count integer
) returns boolean
language sql immutable
as $$
  select
    p_src_doc='CANDIDATO' and p_src_op='READ_ONLY'
    and p_src_runtime='NO_HABILITADO' and p_src_impact='BLOQUEADO'
    and p_dst_doc='CANDIDATO' and p_dst_op='READ_ONLY'
    and p_dst_runtime='CANDIDATE_READ_ONLY' and p_dst_impact='BLOQUEADO'
    and p_target_catalog_count=1 and p_selected_target_count=1
$$;

do $$
declare
  v_route jsonb;
  v_policy_count integer;
  v_bad integer;
begin
  if (select count(*) from public.lf_operation_steps where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF') <> 5 then raise exception 'S26_GA_OPERATION_STEPS_NOT_5'; end if;
  if (select count(*) from public.lf_operation_step_contracts where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF') <> 5 then raise exception 'S26_GA_STEP_CONTRACTS_NOT_5'; end if;
  if (select count(*) from public.lf_operation_judges where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' and status='ACTIVE_ENFORCEMENT') <> 5 then raise exception 'S26_GA_JUDGES_NOT_5'; end if;
  if (select count(*) from public.lf_operation_step_judge_bindings where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' and status='ACTIVE_ENFORCEMENT') <> 5 then raise exception 'S26_GA_BINDINGS_NOT_5'; end if;
  if exists(select 1 from public.lf_operation_step_contracts where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' and step_id='controlled_write' and execution_sql is not null) then raise exception 'S26_GA_WRITE_EXECUTOR_MUST_BE_ABSENT'; end if;

  select count(*) into v_policy_count
  from public.v_lf_operation_policy_snapshot
  where operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
    and policy_code in ('POL-LF-OPERATION-LIFECYCLE','POL-LF-STATE-MODEL')
    and required and policy_sha is not null;
  if v_policy_count <> 2 then raise exception 'S26_GA_REQUIRED_POLICIES_NOT_RESOLVED:%',v_policy_count; end if;

  v_route := public.lf_router_resolve_v1('Ejecuta UI Architect read-only','PERFIL-UI-ARCHITECT','PROFILE_EXECUTION','PERFIL','ROUTER');
  if v_route->>'blocking_code' <> 'BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED' then raise exception 'S26_GA_ROUTER_MUST_STILL_BLOCK_NO_HABILITADO:%',v_route; end if;

  with cases(name,src_doc,src_op,src_runtime,src_impact,dst_doc,dst_op,dst_runtime,dst_impact,catalog_count,target_count,expected) as (
    values
      ('POSITIVE','CANDIDATO','READ_ONLY','NO_HABILITADO','BLOQUEADO','CANDIDATO','READ_ONLY','CANDIDATE_READ_ONLY','BLOQUEADO',1,1,true),
      ('WRONG_SOURCE_STATE','CANDIDATO','READ_ONLY','CANDIDATE_READ_ONLY','BLOQUEADO','CANDIDATO','READ_ONLY','CANDIDATE_READ_ONLY','BLOQUEADO',1,1,false),
      ('UNREGISTERED_TARGET_STATE','CANDIDATO','READ_ONLY','NO_HABILITADO','BLOQUEADO','CANDIDATO','READ_ONLY','CANDIDATE_READ_ONLY','BLOQUEADO',0,1,false),
      ('MASS_TRANSITION','CANDIDATO','READ_ONLY','NO_HABILITADO','BLOQUEADO','CANDIDATO','READ_ONLY','CANDIDATE_READ_ONLY','BLOQUEADO',1,2,false),
      ('IMPACT_CHANGE','CANDIDATO','READ_ONLY','NO_HABILITADO','BLOQUEADO','CANDIDATO','READ_ONLY','CANDIDATE_READ_ONLY','REQUIERE_APROBACION',1,1,false),
      ('PRODUCTION_READ_ONLY_TARGET','CANDIDATO','READ_ONLY','NO_HABILITADO','BLOQUEADO','VIGENTE','READ_ONLY','PRODUCCION_CONTROLADA_READ_ONLY','BLOQUEADO',1,1,false),
      ('RUNTIME_OPERATIVO_TARGET','CANDIDATO','READ_ONLY','NO_HABILITADO','BLOQUEADO','VIGENTE','ACTIVO','RUNTIME_OPERATIVO','CONTROLADO',1,1,false)
  ), evaluated as (
    select name,expected,pg_temp.s26_profile_runtime_transition_allowed(src_doc,src_op,src_runtime,src_impact,dst_doc,dst_op,dst_runtime,dst_impact,catalog_count,target_count) observed
    from cases
  )
  select count(*) into v_bad from evaluated where observed is distinct from expected;
  if v_bad <> 0 then raise exception 'S26_GA_NEGATIVE_MATRIX_MISMATCH_COUNT:%',v_bad; end if;
end;
$$;

rollback;
