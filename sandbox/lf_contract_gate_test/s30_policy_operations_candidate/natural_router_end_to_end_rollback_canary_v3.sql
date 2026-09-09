begin;

-- Isolated inference probe: patch ACT-0001 only inside this rollback transaction.
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
  if length(v_def)-length(replace(v_def,v_old_create,'')) <> length(v_old_create) then raise exception 'S30_INFERENCE_ISOLATED_CREATE_ANCHOR_NOT_EXACTLY_ONCE'; end if;
  if length(v_def)-length(replace(v_def,v_old_update,'')) <> length(v_old_update) then raise exception 'S30_INFERENCE_ISOLATED_UPDATE_ANCHOR_NOT_EXACTLY_ONCE'; end if;
  execute replace(replace(v_def,v_old_create,v_new_create),v_old_update,v_new_update);
end;
$patch$;

insert into public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id)
values
('EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003','VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_CODE','CREACION_POLITICA_LF','IN_PROGRESS',jsonb_build_object('governance_bootstrap',true,'bootstrap_operation_code','CREACION_POLITICA_LF','bootstrap_status_ceiling','SANDBOX_ACTIVE','source_branch','lf/s30-policy-inference-isolated-20260909','source_blob','34591615e9e7ce7d0d2515d8b69afa72d3fc2287','cross_lane_branch_dependency_allowed',false,'claim_ceiling','ROLLBACK_ONLY_NATURAL_ROUTER_E2E'),'EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003'),
('EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003','VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_CODE','ACTUALIZACION_POLITICA_LF','IN_PROGRESS',jsonb_build_object('governance_bootstrap',true,'bootstrap_operation_code','ACTUALIZACION_POLITICA_LF','bootstrap_status_ceiling','SANDBOX_ACTIVE','source_branch','lf/s30-policy-inference-isolated-20260909','source_blob','34591615e9e7ce7d0d2515d8b69afa72d3fc2287','cross_lane_branch_dependency_allowed',false,'claim_ceiling','ROLLBACK_ONLY_NATURAL_ROUTER_E2E'),'EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003');

insert into public.lf_operation_registry(operation_code,version,status,source_model,source_repo,source_paths,operation_family,operation_domain,operation_type,applies_to_asset_type,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','v0.3-inference-isolated','CANDIDATO_READ_ONLY','GIT_FIRST_YAML','cristhianlujan/claude-persona-lf-patch','["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/router_policy_action_inference_patch_v1.sql","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/natural_router_end_to_end_rollback_canary_v3.sql"]'::jsonb,'GOVERNANCE','POLICY_LIFECYCLE','CREATION_PROTOCOL','REGLA','EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003','EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003'),
('ACTUALIZACION_POLITICA_LF','v0.3-inference-isolated','CANDIDATO_READ_ONLY','GIT_FIRST_YAML','cristhianlujan/claude-persona-lf-patch','["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/router_policy_action_inference_patch_v1.sql","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/natural_router_end_to_end_rollback_canary_v3.sql"]'::jsonb,'GOVERNANCE','POLICY_LIFECYCLE','UPDATE_PROTOCOL','REGLA','EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003','EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003');

insert into public.lf_operation_contracts(operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','CONTRACT-CREACION-POLITICA-LF-INFERENCE-v0.1','github://cristhianlujan/claude-persona-lf-patch/lf/s30-policy-inference-isolated-20260909/sandbox/lf_contract_gate_test/s30_policy_operations_candidate/router_policy_action_inference_patch_v1.sql','34591615e9e7ce7d0d2515d8b69afa72d3fc2287','["router_read","exact_anchor","rollback_scope"]'::jsonb,'{"candidate_only":true,"generic_rule_behavior_preserved":true,"cross_lane_branch_dependency":false}'::jsonb,'["ambiguous_anchor","generic_rule_behavior_change","durable_router_change","production_enable"]'::jsonb,'["natural_policy_create_ready","natural_policy_update_ready","generic_rule_create_preserved","generic_rule_update_preserved","rollback_readback"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003','EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003'),
('ACTUALIZACION_POLITICA_LF','CONTRACT-ACTUALIZACION-POLITICA-LF-INFERENCE-v0.1','github://cristhianlujan/claude-persona-lf-patch/lf/s30-policy-inference-isolated-20260909/sandbox/lf_contract_gate_test/s30_policy_operations_candidate/router_policy_action_inference_patch_v1.sql','34591615e9e7ce7d0d2515d8b69afa72d3fc2287','["router_read","exact_anchor","rollback_scope"]'::jsonb,'{"candidate_only":true,"generic_rule_behavior_preserved":true,"cross_lane_branch_dependency":false}'::jsonb,'["ambiguous_anchor","generic_rule_behavior_change","durable_router_change","production_enable"]'::jsonb,'["natural_policy_create_ready","natural_policy_update_ready","generic_rule_create_preserved","generic_rule_update_preserved","rollback_readback"]'::jsonb,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003','EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003');

insert into public.lf_operation_step_contracts(operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,created_by_execution_id,updated_by_execution_id)
values
('CREACION_POLITICA_LF','inference_probe',10,10,'CONTRACT-CREACION-POLITICA-LF-INFERENCE-v0.1','Natural-language Router inference probe','["exact_anchor","policy_term"]'::jsonb,'SUPABASE_MCP','["action_code","operation_code"]'::jsonb,'{"ready":true}'::jsonb,'{"blocked":true}'::jsonb,'BLOCK_POLICY_CREATE_INFERENCE','JUDGE-S30-POLICY-INFERENCE','["action_code","operation_code","rollback_scope"]'::jsonb,null,null,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003','EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003'),
('ACTUALIZACION_POLITICA_LF','inference_probe',10,10,'CONTRACT-ACTUALIZACION-POLITICA-LF-INFERENCE-v0.1','Natural-language Router inference probe','["exact_anchor","policy_term"]'::jsonb,'SUPABASE_MCP','["action_code","operation_code"]'::jsonb,'{"ready":true}'::jsonb,'{"blocked":true}'::jsonb,'BLOCK_POLICY_UPDATE_INFERENCE','JUDGE-S30-POLICY-INFERENCE','["action_code","operation_code","rollback_scope"]'::jsonb,null,null,'ACTIVE_ENFORCEMENT','EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003','EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003');

insert into public.lf_router_action_registry(asset_type,action_code,operation_code,operation_resolution,requires_existing_target,requires_missing_target,write_allowed,status,notes,created_by_execution_id,updated_by_execution_id)
values
('REGLA','POLICY_CREATE','CREACION_POLITICA_LF','STATIC',false,true,true,'ACTIVE','ROLLBACK ONLY - isolated inference probe','EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003','EXEC-S30-POLICY-CREATE-INFERENCE-ISOLATED-20260909-003'),
('REGLA','POLICY_UPDATE','ACTUALIZACION_POLITICA_LF','STATIC',true,false,true,'ACTIVE','ROLLBACK ONLY - isolated inference probe','EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003','EXEC-S30-POLICY-UPDATE-INFERENCE-ISOLATED-20260909-003');

do $e2e$
declare c jsonb; u jsonb; gc jsonb; gu jsonb;
begin
  c := public.lf_router_resolve_v1('Crear politica nueva LF','POL-S30-CANARY-NONEXISTENT',null,'REGLA','ROUTER');
  if c->>'status'<>'READY_TO_EXECUTE' or c->>'action_code'<>'POLICY_CREATE' or c->>'operation_code'<>'CREACION_POLITICA_LF' then raise exception 'S30_INFERENCE_ISOLATED_CREATE_NOT_READY:%',c; end if;
  u := public.lf_router_resolve_v1('Actualizar politica existente LF','POL-STRATEGY-CREATION-001',null,'REGLA','ROUTER');
  if u->>'status'<>'READY_TO_EXECUTE' or u->>'action_code'<>'POLICY_UPDATE' or u->>'operation_code'<>'ACTUALIZACION_POLITICA_LF' then raise exception 'S30_INFERENCE_ISOLATED_UPDATE_NOT_READY:%',u; end if;

  gc := public.lf_router_resolve_v1('Crear regla nueva LF','REGLA-S30-CANARY-NONEXISTENT',null,'REGLA','ROUTER');
  if gc->>'status'<>'BLOCKED' or gc->>'blocking_code'<>'BLOCK_OPERATION_NOT_REGISTERED' or gc->>'action_code'<>'CREATE' then raise exception 'S30_INFERENCE_ISOLATED_GENERIC_CREATE_CHANGED:%',gc; end if;
  gu := public.lf_router_resolve_v1('Actualizar regla existente LF','POL-STRATEGY-CREATION-001',null,'REGLA','ROUTER');
  if gu->>'status'<>'BLOCKED' or gu->>'blocking_code'<>'BLOCK_OPERATION_NOT_REGISTERED' or gu->>'action_code'<>'RULE_UPDATE' then raise exception 'S30_INFERENCE_ISOLATED_GENERIC_UPDATE_CHANGED:%',gu; end if;
end;
$e2e$;

rollback;
