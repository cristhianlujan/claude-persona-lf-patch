insert into public.lf_operation_registry (
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,updated_by_execution_id,lifecycle_state_code
)
values (
  'ORQUESTACION_SKILL_LF','v0.1-candidate','CANDIDATO_READ_ONLY','GIT_FIRST_JSON_CONTRACT',
  'cristhianlujan/claude-persona-lf-patch',
  '["sandbox/lf_contract_gate_test/skill_orchestration_runtime/orquestacion_skill_lf_v1.json","sandbox/lf_contract_gate_test/skill_orchestration_runtime/judges/orquestacion_skill_lf.yaml"]'::jsonb,
  'Generic child-dispatch orchestration for delegated Skill steps. Candidate only; no runtime/production activation.',
  'ORCHESTRATION','SKILL_RUNTIME_CONTROL','CHILD_DISPATCH_SUPERVISED','SKILL',
  'EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001','EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001','OP_CANDIDATE'
)
on conflict (operation_code) do nothing;

insert into public.lf_operation_judges (
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
  created_by_execution_id,updated_by_execution_id
)
values (
  'ORQUESTACION_SKILL_LF',
  'JUDGE-ORQUESTACION-SKILL-LF-v0.1',
  'sandbox/lf_contract_gate_test/skill_orchestration_runtime/judges/orquestacion_skill_lf.yaml',
  null,
  '["parent_skill_execution_is_exact_and_in_progress","skill_source_revision_is_current","manifest_step_and_worker_role_are_exact","worker_resolution_is_unique_and_current","child_execution_is_reserved_before_dispatch_receipt","dispatch_receipt_is_real_and_cross_bound","entry_guard_decision_is_ORCHESTRATOR_ENTRY_ACCEPTED","final_task_packet_static_projection_matches_work_digest","worker_result_is_bound_to_same_child_execution","step_judge_is_independent_from_worker"]'::jsonb,
  '["fabricated_or_premature_receipt_or_guard","stale_or_ambiguous_worker_binding","source_revision_drift","child_execution_missing_before_receipt","receipt_consumer_plan_or_capability_mismatch","final_task_packet_static_projection_drift","worker_result_execution_mismatch","self_judging","missing_required_evidence"]'::jsonb,
  '["PASS","FAIL","BLOCKED"]'::jsonb,
  'CANDIDATO_READ_ONLY',
  'EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001',
  'EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001'
)
on conflict (operation_code,judge_code) do nothing;

with step_spec(step_order,step_id,purpose,resolver_ref,required_evidence,next_step) as (
  values
  (0,'init_execution','Create the orchestration execution identity and bind the parent Skill execution.','LF_OPERATION_RUNTIME','["execution_id","parent_execution_id"]'::jsonb,'bind_parent_skill_execution'),
  (10,'bind_parent_skill_execution','Verify exact IN_PROGRESS parent EJECUCION_SKILL_LF, Skill identity and source revision.','public.lf_operation_execution + CURRENTNESS_AUTHORITY','["parent_execution_id","parent_operation_code","skill_code","source_revision"]'::jsonb,'load_next_step_contract'),
  (20,'load_next_step_contract','Read the next manifest step, logical worker role and allowed worker kinds from current Skill authority.','CURRENTNESS_AUTHORITY + SKILL_MANIFEST','["step_id","worker_role","allowed_worker_kinds","step_contract_digest"]'::jsonb,'resolve_worker'),
  (30,'resolve_worker','Resolve exactly one current governed worker from the logical role.','SKILL_WORKER_RESOLVER_V1','["worker_resolution_digest","worker_ref","worker_kind","binding_authority_ref","binding_revision"]'::jsonb,'resolve_task_runtime_binding'),
  (40,'resolve_task_runtime_binding','Resolve exact task-bound Profile material when applicable; otherwise record explicit non-applicability.','PROFILE_TASK_RUNTIME_BINDING_V1','["task_binding_applicability","task_runtime_binding_digest"]'::jsonb,'build_task_packet_seed'),
  (50,'build_task_packet_seed','Build the static Task Packet seed without receipt or accepted guard and compute the work digest.','PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1','["task_packet_work_digest","task_packet_seed_ref"]'::jsonb,'reserve_child_execution'),
  (60,'reserve_child_execution','Reserve the exact child execution before any dispatch receipt is issued.','public.lf_profile_execution_begin_v1 or governed child operation reserve','["child_execution_id","child_request_sha256","child_manifest_digest"]'::jsonb,'issue_dispatch_receipt'),
  (70,'issue_dispatch_receipt','Issue a real orchestrator dispatch receipt cross-bound to child, plan and capability.','public.fn_lf_orchestrator_dispatch_receipt_v1','["dispatch_receipt_ref","dispatch_receipt_sha256","plan_digest"]'::jsonb,'entry_guard_readback'),
  (80,'entry_guard_readback','Execute/read back the mandatory orchestrator entry guard.','public.fn_lf_capability_bind_from_orchestrator_v1','["entry_guard_decision","entry_guard_code","dispatch_receipt_ref"]'::jsonb,'finalize_task_packet'),
  (90,'finalize_task_packet','Materialize the final Task Packet with real receipt/guard and verify static projection equality.','PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1','["final_task_packet_digest","task_packet_work_digest","static_projection_match"]'::jsonb,'dispatch_worker'),
  (100,'dispatch_worker','Dispatch only through an already-governed worker runtime or capability contract.','EJECUCION_PERFIL_LF or CAPABILITY_EXECUTION_CONTRACT_V1','["worker_dispatch_ref","child_execution_id","worker_kind"]'::jsonb,'collect_worker_result'),
  (110,'collect_worker_result','Collect the worker result bound to the same child execution and output digest.','GOVERNED_CHILD_EXECUTION_READBACK','["worker_result_ref","child_execution_id","output_digest"]'::jsonb,'step_judge_handoff'),
  (120,'step_judge_handoff','Hand the output to the independent Skill step judge; orchestrator cannot self-judge.','SKILL_STEP_JUDGE_AUTHORITY','["step_judge_ref","judge_execution_ref","judge_independent"]'::jsonb,'checkpoint_or_close'),
  (130,'checkpoint_or_close','Persist only orchestration checkpoint evidence and advance to the next step or close.','LF_OPERATION_RUNTIME','["checkpoint_digest","next_step_or_close","no_runtime_activation","no_production_activation"]'::jsonb,null)
)
insert into public.lf_operation_steps (
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,
  created_by_execution_id,updated_by_execution_id
)
select
  'ORQUESTACION_SKILL_LF',s.step_order,s.step_id,true,'true',
  'supabase://public/lf_operation_step_contracts/ORQUESTACION_SKILL_LF/'||s.step_id,
  null,true,s.step_order,
  'EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001','EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001'
from step_spec s
on conflict (operation_code,step_order) do nothing;

with step_spec(step_order,step_id,purpose,resolver_ref,required_evidence,next_step) as (
  values
  (0,'init_execution','Create the orchestration execution identity and bind the parent Skill execution.','LF_OPERATION_RUNTIME','["execution_id","parent_execution_id"]'::jsonb,'bind_parent_skill_execution'),
  (10,'bind_parent_skill_execution','Verify exact IN_PROGRESS parent EJECUCION_SKILL_LF, Skill identity and source revision.','public.lf_operation_execution + CURRENTNESS_AUTHORITY','["parent_execution_id","parent_operation_code","skill_code","source_revision"]'::jsonb,'load_next_step_contract'),
  (20,'load_next_step_contract','Read the next manifest step, logical worker role and allowed worker kinds from current Skill authority.','CURRENTNESS_AUTHORITY + SKILL_MANIFEST','["step_id","worker_role","allowed_worker_kinds","step_contract_digest"]'::jsonb,'resolve_worker'),
  (30,'resolve_worker','Resolve exactly one current governed worker from the logical role.','SKILL_WORKER_RESOLVER_V1','["worker_resolution_digest","worker_ref","worker_kind","binding_authority_ref","binding_revision"]'::jsonb,'resolve_task_runtime_binding'),
  (40,'resolve_task_runtime_binding','Resolve exact task-bound Profile material when applicable; otherwise record explicit non-applicability.','PROFILE_TASK_RUNTIME_BINDING_V1','["task_binding_applicability","task_runtime_binding_digest"]'::jsonb,'build_task_packet_seed'),
  (50,'build_task_packet_seed','Build the static Task Packet seed without receipt or accepted guard and compute the work digest.','PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1','["task_packet_work_digest","task_packet_seed_ref"]'::jsonb,'reserve_child_execution'),
  (60,'reserve_child_execution','Reserve the exact child execution before any dispatch receipt is issued.','public.lf_profile_execution_begin_v1 or governed child operation reserve','["child_execution_id","child_request_sha256","child_manifest_digest"]'::jsonb,'issue_dispatch_receipt'),
  (70,'issue_dispatch_receipt','Issue a real orchestrator dispatch receipt cross-bound to child, plan and capability.','public.fn_lf_orchestrator_dispatch_receipt_v1','["dispatch_receipt_ref","dispatch_receipt_sha256","plan_digest"]'::jsonb,'entry_guard_readback'),
  (80,'entry_guard_readback','Execute/read back the mandatory orchestrator entry guard.','public.fn_lf_capability_bind_from_orchestrator_v1','["entry_guard_decision","entry_guard_code","dispatch_receipt_ref"]'::jsonb,'finalize_task_packet'),
  (90,'finalize_task_packet','Materialize the final Task Packet with real receipt/guard and verify static projection equality.','PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1','["final_task_packet_digest","task_packet_work_digest","static_projection_match"]'::jsonb,'dispatch_worker'),
  (100,'dispatch_worker','Dispatch only through an already-governed worker runtime or capability contract.','EJECUCION_PERFIL_LF or CAPABILITY_EXECUTION_CONTRACT_V1','["worker_dispatch_ref","child_execution_id","worker_kind"]'::jsonb,'collect_worker_result'),
  (110,'collect_worker_result','Collect the worker result bound to the same child execution and output digest.','GOVERNED_CHILD_EXECUTION_READBACK','["worker_result_ref","child_execution_id","output_digest"]'::jsonb,'step_judge_handoff'),
  (120,'step_judge_handoff','Hand the output to the independent Skill step judge; orchestrator cannot self-judge.','SKILL_STEP_JUDGE_AUTHORITY','["step_judge_ref","judge_execution_ref","judge_independent"]'::jsonb,'checkpoint_or_close'),
  (130,'checkpoint_or_close','Persist only orchestration checkpoint evidence and advance to the next step or close.','LF_OPERATION_RUNTIME','["checkpoint_digest","next_step_or_close","no_runtime_activation","no_production_activation"]'::jsonb,null)
)
insert into public.lf_operation_step_contracts (
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,
  output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,
  next_if_pass,next_if_blocked,status,notes,created_by_execution_id,updated_by_execution_id
)
select
  'ORQUESTACION_SKILL_LF',s.step_id,s.step_order,s.step_order,
  'CONTRACT-ORQUESTACION-SKILL-LF-'||upper(s.step_id),s.purpose,
  '[]'::jsonb,s.resolver_ref,s.required_evidence,
  jsonb_build_object('must_not_be_generic',true,'must_match_step_purpose',true,'required_evidence_keys',s.required_evidence),
  jsonb_build_object('missing_required_evidence',true,'authority_mismatch',true,'source_or_binding_drift',true),
  'BLOCKED_ORQUESTACION_SKILL_LF_'||upper(s.step_id)||'_NOT_CLEAN',
  'JUDGE-ORQUESTACION-SKILL-LF-v0.1',s.required_evidence,
  s.next_step,'RETURN_TO_ORCHESTRATOR','CANDIDATO_READ_ONLY',
  'Candidate generic Skill orchestration contract. No production/runtime activation.',
  'EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001','EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001'
from step_spec s
on conflict (operation_code,step_id) do nothing;

with step_spec(step_order,step_id,required_evidence) as (
  values
  (0,'init_execution','["execution_id","parent_execution_id"]'::jsonb),
  (10,'bind_parent_skill_execution','["parent_execution_id","parent_operation_code","skill_code","source_revision"]'::jsonb),
  (20,'load_next_step_contract','["step_id","worker_role","allowed_worker_kinds","step_contract_digest"]'::jsonb),
  (30,'resolve_worker','["worker_resolution_digest","worker_ref","worker_kind","binding_authority_ref","binding_revision"]'::jsonb),
  (40,'resolve_task_runtime_binding','["task_binding_applicability","task_runtime_binding_digest"]'::jsonb),
  (50,'build_task_packet_seed','["task_packet_work_digest","task_packet_seed_ref"]'::jsonb),
  (60,'reserve_child_execution','["child_execution_id","child_request_sha256","child_manifest_digest"]'::jsonb),
  (70,'issue_dispatch_receipt','["dispatch_receipt_ref","dispatch_receipt_sha256","plan_digest"]'::jsonb),
  (80,'entry_guard_readback','["entry_guard_decision","entry_guard_code","dispatch_receipt_ref"]'::jsonb),
  (90,'finalize_task_packet','["final_task_packet_digest","task_packet_work_digest","static_projection_match"]'::jsonb),
  (100,'dispatch_worker','["worker_dispatch_ref","child_execution_id","worker_kind"]'::jsonb),
  (110,'collect_worker_result','["worker_result_ref","child_execution_id","output_digest"]'::jsonb),
  (120,'step_judge_handoff','["step_judge_ref","judge_execution_ref","judge_independent"]'::jsonb),
  (130,'checkpoint_or_close','["checkpoint_digest","next_step_or_close","no_runtime_activation","no_production_activation"]'::jsonb)
)
insert into public.lf_operation_step_judge_bindings (
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
)
select
  'ORQUESTACION_SKILL_LF',s.step_order,s.step_id,'JUDGE-ORQUESTACION-SKILL-LF-v0.1',
  'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',s.required_evidence,'CANDIDATO_READ_ONLY',
  'EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001','EXEC-SKILL-ORCHESTRATION-DEFINITION-20261002-001'
from step_spec s
on conflict (operation_code,step_order,step_id) do nothing;

do $$
declare
  v_steps integer;
  v_contracts integer;
  v_bindings integer;
begin
  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='ORQUESTACION_SKILL_LF'
      and operation_family='ORCHESTRATION'
      and lifecycle_state_code='OP_CANDIDATE'
      and status='CANDIDATO_READ_ONLY'
  ) then
    raise exception 'ORQUESTACION_SKILL_LF_REGISTRY_MISMATCH';
  end if;

  select count(*) into v_steps from public.lf_operation_steps where operation_code='ORQUESTACION_SKILL_LF' and active=true;
  select count(*) into v_contracts from public.lf_operation_step_contracts where operation_code='ORQUESTACION_SKILL_LF';
  select count(*) into v_bindings from public.lf_operation_step_judge_bindings where operation_code='ORQUESTACION_SKILL_LF';
  if v_steps<>14 or v_contracts<>14 or v_bindings<>14 then
    raise exception 'ORQUESTACION_SKILL_LF_DEFINITION_INCOMPLETE steps=% contracts=% bindings=%',v_steps,v_contracts,v_bindings;
  end if;
end
$$;
