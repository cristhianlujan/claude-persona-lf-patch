begin;

-- Patch only inside rollback: exact policy/politica inference for REGLA.
do $patch$
declare
  v_def text;
  v_old_create text := $old_create$    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; else v_action:='CREATE'; end if;$old_create$;
  v_new_create text := $new_create$    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; elsif v_type_hint='REGLA' and v_req ~ '(^| )(policy|politica)( |$)' then v_action:='POLICY_CREATE'; else v_action:='CREATE'; end if;$new_create$;
  v_old_update text := $old_update$    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE'; elsif v_type_hint='REGLA' then v_action:='RULE_UPDATE'; else v_action:='UPDATE'; end if;$old_update$;
  v_new_update text := $new_update$    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE'; elsif v_type_hint='REGLA' and v_req ~ '(^| )(policy|politica)( |$)' then v_action:='POLICY_UPDATE'; elsif v_type_hint='REGLA' then v_action:='RULE_UPDATE'; else v_action:='UPDATE'; end if;$new_update$;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) into v_def;
  if length(v_def)-length(replace(v_def,v_old_create,'')) <> length(v_old_create) then raise exception 'S30_V3_CREATE_ANCHOR_NOT_EXACTLY_ONCE'; end if;
  if length(v_def)-length(replace(v_def,v_old_update,'')) <> length(v_old_update) then raise exception 'S30_V3_UPDATE_ANCHOR_NOT_EXACTLY_ONCE'; end if;
  execute replace(replace(v_def,v_old_create,v_new_create),v_old_update,v_new_update);
end;
$patch$;

insert into public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id)
values
('EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003','VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_CODE','CREACION_POLITICA_LF','IN_PROGRESS',jsonb_build_object('governance_bootstrap',true,'bootstrap_operation_code','CREACION_POLITICA_LF','bootstrap_status_ceiling','SANDBOX_ACTIVE','claim_ceiling','ROLLBACK_ONLY_NATURAL_ROUTER_E2E'),'EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003'),
('EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003','VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_CODE','ACTUALIZACION_POLITICA_LF','IN_PROGRESS',jsonb_build_object('governance_bootstrap',true,'bootstrap_operation_code','ACTUALIZACION_POLITICA_LF','bootstrap_status_ceiling','SANDBOX_ACTIVE','claim_ceiling','ROLLBACK_ONLY_NATURAL_ROUTER_E2E'),'EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003');

insert into public.lf_operation_registry(operation_code,version,status,source_model,source_repo,source_paths,operation_family,operation_domain,operation_type,applies_to_asset_type,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','v0.2','CANDIDATO_READ_ONLY','GIT_FIRST_YAML','cristhianlujan/claude-persona-lf-patch','["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml"]'::jsonb,'GOVERNANCE','POLICY_LIFECYCLE','CREATION_PROTOCOL','REGLA','EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003','EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003'),
('ACTUALIZACION_POLITICA_LF','v0.2','CANDIDATO_READ_ONLY','GIT_FIRST_YAML','cristhianlujan/claude-persona-lf-patch','["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml"]'::jsonb,'GOVERNANCE','POLICY_LIFECYCLE','UPDATE_PROTOCOL','REGLA','EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003','EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003');

insert into public.lf_operation_contracts(operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','CONTRACT-CREACION-POLITICA-LF-v0.1','sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209','["router_read","ekb_read","schema_contract","execution_binding"]'::jsonb,'{"candidate_only":true}'::jsonb,'["automatic_promotion","production_enable"]'::jsonb,'["readback"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003','EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003'),
('ACTUALIZACION_POLITICA_LF','CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operation_runtime_package.yaml','c0f1e38463d578a3ac1374424c8bb9f6ef6eb209','["router_read","ekb_read","schema_contract","execution_binding"]'::jsonb,'{"candidate_only":true,"successor_only":true}'::jsonb,'["prior_version_overwrite","premature_supersession","automatic_promotion"]'::jsonb,'["readback","prior_version_unchanged"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003','EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003');

insert into public.lf_operation_step_contracts(operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','preflight',10,10,'CONTRACT-CREACION-POLITICA-LF-v0.1','Router/EKB/schema preflight','["router_binding","ekb_refs","schema_contract"]'::jsonb,'SUPABASE_MCP','["preflight_pass"]'::jsonb,'{"preflight_pass":true}'::jsonb,'{"blocked":true}'::jsonb,'BLOCK_POLICY_CREATE_PREFLIGHT','JUDGE-CREACION-POLITICA-LF-v0.1','["router_binding","ekb_refs","schema_contract"]'::jsonb,null,null,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003','EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003'),
('ACTUALIZACION_POLITICA_LF','preflight',10,10,'CONTRACT-ACTUALIZACION-POLITICA-LF-v0.1','Router/EKB/schema preflight','["router_binding","ekb_refs","schema_contract"]'::jsonb,'SUPABASE_MCP','["preflight_pass"]'::jsonb,'{"preflight_pass":true}'::jsonb,'{"blocked":true}'::jsonb,'BLOCK_POLICY_UPDATE_PREFLIGHT','JUDGE-ACTUALIZACION-POLITICA-LF-v0.1','["router_binding","ekb_refs","schema_contract"]'::jsonb,null,null,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003','EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003');

insert into public.lf_router_action_registry(asset_type,action_code,operation_code,operation_resolution,requires_existing_target,requires_missing_target,write_allowed,status,notes,created_by_execution_id,updated_by_execution_id)
values
('REGLA','POLICY_CREATE','CREACION_POLITICA_LF','STATIC',false,true,true,'ACTIVE','ROLLBACK ONLY','EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003','EXEC-S30-POLICY-CREATE-NATURAL-E2E-20260909-003'),
('REGLA','POLICY_UPDATE','ACTUALIZACION_POLITICA_LF','STATIC',true,false,true,'ACTIVE','ROLLBACK ONLY','EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003','EXEC-S30-POLICY-UPDATE-NATURAL-E2E-20260909-003');

do $e2e$
declare c jsonb; u jsonb;
begin
  c := public.lf_router_resolve_v1('Crear politica nueva LF','POL-S30-CANARY-NONEXISTENT',null,'REGLA','ROUTER');
  if c->>'status'<>'READY_TO_EXECUTE' or c->>'action_code'<>'POLICY_CREATE' or c->>'operation_code'<>'CREACION_POLITICA_LF' then raise exception 'S30_V3_CREATE_NOT_READY:%',c; end if;
  u := public.lf_router_resolve_v1('Actualizar politica existente LF','POL-STRATEGY-CREATION-001',null,'REGLA','ROUTER');
  if u->>'status'<>'READY_TO_EXECUTE' or u->>'action_code'<>'POLICY_UPDATE' or u->>'operation_code'<>'ACTUALIZACION_POLITICA_LF' then raise exception 'S30_V3_UPDATE_NOT_READY:%',u; end if;
end;
$e2e$;

rollback;
