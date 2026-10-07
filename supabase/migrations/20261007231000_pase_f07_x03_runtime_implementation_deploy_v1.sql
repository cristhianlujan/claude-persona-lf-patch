begin;
-- PASE-ATOM-F07-X03, D4: governed registration only; no deploy, activation, or canary.
-- Train source-first draft. REFRESCO_RUNTIME_PERFIL_LF is unchanged.
do $guard$
begin
 if exists (select 1 from public.lf_operation_registry where operation_code='DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF') then
  raise exception 'X03_OPERATION_ALREADY_REGISTERED';
 end if;
 if not exists (select 1 from public.lf_operation_registry where operation_code='REFRESCO_RUNTIME_PERFIL_LF') then
  raise exception 'X03_REFRESCO_CARRIER_AUTHORITY_MISSING';
 end if;
end $guard$;
insert into public.lf_operation_registry
 (operation_code,version,status,source_model,source_repo,source_paths,notes,
 operation_family,operation_domain,operation_type,applies_to_asset_type,
 lifecycle_state_code,created_by_execution_id,updated_by_execution_id)
values
 ('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','v1.0','CANDIDATO_READ_ONLY',
 'SUPABASE_OPERATIONAL_AUTHORITY_WITH_GIT_MIRROR',
 'cristhianlujan/claude-persona-lf-patch',jsonb_build_array('supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql',
 'services/profile_runtime_api/scripts/install.sh'),
 'D4 separate runtime implementation deploy. Same governed VPS owner-runner carrier and canonical install.sh as REFRESCO; registration only, no new runner. Worker-only restart: lf-profile-runtime-queue-worker; retain 90-log-churn-mitigation.conf by default, removal requires T3.2 human gate. Canary runs only after deploy as next gate.',
 'PROFILE_OPERATIONS','PROFILE_RUNTIME_IMPLEMENTATION','RUNTIME_IMPLEMENTATION_DEPLOY','PERFIL',
 'OP_CANDIDATE','EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007');
insert into public.lf_operation_contracts
 (operation_code,contract_code,contract_path,contract_sha,required_before_write,
 allowed,blocked,required_after_write,status,created_by_execution_id,updated_by_execution_id)
values (
 'DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','CONTRACT-PASE-F07-X03-v1','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql',
 'DRAFT_SOURCE_FIRST_NOT_APPLIED',
 jsonb_build_object('exact_head_required',true,'allowed_delta_prefix','services/profile_runtime_api/','runtime_code_delta_count_min',1,'previous_release_required',true,'authorization_required',true,'carrier_reuse','REFRESCO_RUNTIME_PERFIL_LF'),
 jsonb_build_object('canonical_installer','services/profile_runtime_api/scripts/install.sh','carrier','EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','worker_only_restart_unit','lf-profile-runtime-queue-worker','mitigation_dropin','90-log-churn-mitigation.conf','mitigation_default','PRESERVE','mitigation_removal_gate','T3.2_HUMAN_APPROVAL','automatic_promotion',false),
 jsonb_build_array('SOURCE_OUTSIDE_ALLOWED_SCOPE','SHA_MISMATCH','WRONG_RELEASE','SERVICE_HEALTH_FAILED','ROLLBACK_RELEASE_MISSING','MITIGATION_REMOVAL_UNAUTHORIZED','NO_RUNTIME_CODE_DELTA','RUNTIME_RECEIPT_UNATTESTED'),
 jsonb_build_object('verifier','RUNTIME_DEPLOY_VERIFICATION','receipt_schema','LF_RUNTIME_IMPL_DEPLOY_RECEIPT_V1','runtime_sha_must_equal_receipt_sha',true,'failure_status','GOVERNANCE_DRIFT','step_90_closes','PASE-ATOM-F07-X02-R01','next_gate','POST_DEPLOY_WORKER_QUEUE_REAL_JOB_CANARY','canary_binding',jsonb_build_array('exact_head','runtime_sha','job_id','queue_result'),'verifier_read_only',true),
 'ACTIVE_ENFORCEMENT','EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007');
insert into public.lf_operation_steps
 (operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,created_by_execution_id,updated_by_execution_id)
values
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',0,'init_execution',true,'execution_id_created,target_code,target_path','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,0,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',10,'router',true,'router_read,action,authorization_scope','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,10,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',20,'runtime_resolve',true,'service_path,runtime_identity,release_target,exact_runtime_resolved','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,20,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',30,'source_currentness',true,'exact_head,source_revision,main_sha,source_current','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,30,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',40,'runtime_baseline',true,'runtime_sha_before,release_path_before,service_active_before,health_before,previous_release_path,previous_runtime_sha','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,40,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',50,'deploy_plan',true,'runtime_code_delta_count,changed_paths,allowed_scope_only,artifact_sha,install_script_ref,restart_unit,worker_only_delta,mitigation_dropin,mitigation_action,mitigation_removal_human_gate,rollback_plan,no_auto_promotion','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,50,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',60,'pre_deploy_binding_gate',true,'execution_id,bound_head,bound_artifact_sha,target_path,authorization_receipt,gate_result','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,60,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',70,'runtime_deploy',true,'release_path_after,deploy_exit_zero,symlink_switched,service_restarted,rollback_performed,deployed_artifact_sha,carrier_execution_ref','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,70,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',80,'health_readback',true,'service_active_after,health_status,runtime_version,listener_loopback,health_probe_ref','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,80,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',90,'runtime_sha_readback',true,'runtime_sha,receipt_sha,source_revision,exact_runtime_match,attestation_ref,readback_observed_at','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,90,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',100,'state_preservation',true,'runtime_estado_before,runtime_estado_after,estado_operativo_before,estado_operativo_after,impacto_automatico_before,impacto_automatico_after,no_auto_promotion','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,100,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',105,'asset_reconcile',true,'runtime_source_sha,runtime_release_ref,deploy_execution_id,asset_readback_match,post_deploy_next_gate','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,105,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',110,'close',true,'all_required_steps_clean,open_blockers,runtime_deploy_verified,rollback_ready,no_auto_promotion','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,110,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF',120,'report_output',true,'result,exact_head,runtime_sha,receipt_sha,release_path,previous_release_path,evidence_refs,next_gate','supabase/migrations/20261007231000_pase_f07_x03_runtime_implementation_deploy_v1.sql','DRAFT_SOURCE_FIRST_NOT_APPLIED',true,120,'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007');
insert into public.lf_operation_step_contracts
 (operation_code,step_id,step_order,execution_order,contract_code,purpose,
 input_required,resolver_ref,output_payload,pass_condition,block_condition,blocking_code,
 mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,
 created_by_execution_id,updated_by_execution_id)
values
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','init_execution',0,0,'CONTRACT-PASE-F07-X03-v1','Guarded X03 init_execution','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["execution_id_created","target_code","target_path"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_INIT_EXECUTION','MINI_JUDGE_X03_INIT_EXECUTION_V1',
'["execution_id_created","target_code","target_path"]'::jsonb,'router',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','router',10,10,'CONTRACT-PASE-F07-X03-v1','Guarded X03 router','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["router_read","action","authorization_scope"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_ROUTER','MINI_JUDGE_X03_ROUTER_V1',
'["router_read","action","authorization_scope"]'::jsonb,'runtime_resolve',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','runtime_resolve',20,20,'CONTRACT-PASE-F07-X03-v1','Guarded X03 runtime_resolve','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["service_path","runtime_identity","release_target","exact_runtime_resolved"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_RUNTIME_RESOLVE','MINI_JUDGE_X03_RUNTIME_RESOLVE_V1',
'["service_path","runtime_identity","release_target","exact_runtime_resolved"]'::jsonb,'source_currentness',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','source_currentness',30,30,'CONTRACT-PASE-F07-X03-v1','Guarded X03 source_currentness','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["exact_head","source_revision","main_sha","source_current"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_SOURCE_CURRENTNESS','MINI_JUDGE_X03_SOURCE_CURRENTNESS_V1',
'["exact_head","source_revision","main_sha","source_current"]'::jsonb,'runtime_baseline',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','runtime_baseline',40,40,'CONTRACT-PASE-F07-X03-v1','Guarded X03 runtime_baseline','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["runtime_sha_before","release_path_before","service_active_before","health_before","previous_release_path","previous_runtime_sha"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_RUNTIME_BASELINE','MINI_JUDGE_X03_RUNTIME_BASELINE_V1',
'["runtime_sha_before","release_path_before","service_active_before","health_before","previous_release_path","previous_runtime_sha"]'::jsonb,'deploy_plan',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','deploy_plan',50,50,'CONTRACT-PASE-F07-X03-v1','Guarded X03 deploy_plan','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["runtime_code_delta_count","changed_paths","allowed_scope_only","artifact_sha","install_script_ref","restart_unit","worker_only_delta","mitigation_dropin","mitigation_action","mitigation_removal_human_gate","rollback_plan","no_auto_promotion"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_DEPLOY_PLAN','MINI_JUDGE_X03_DEPLOY_PLAN_V1',
'["runtime_code_delta_count","changed_paths","allowed_scope_only","artifact_sha","install_script_ref","restart_unit","worker_only_delta","mitigation_dropin","mitigation_action","mitigation_removal_human_gate","rollback_plan","no_auto_promotion"]'::jsonb,'pre_deploy_binding_gate',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','pre_deploy_binding_gate',60,60,'CONTRACT-PASE-F07-X03-v1','Guarded X03 pre_deploy_binding_gate','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["execution_id","bound_head","bound_artifact_sha","target_path","authorization_receipt","gate_result"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_PRE_DEPLOY_BINDING_GATE','MINI_JUDGE_X03_PRE_DEPLOY_BINDING_GATE_V1',
'["execution_id","bound_head","bound_artifact_sha","target_path","authorization_receipt","gate_result"]'::jsonb,'runtime_deploy',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','runtime_deploy',70,70,'CONTRACT-PASE-F07-X03-v1','Guarded X03 runtime_deploy','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["release_path_after","deploy_exit_zero","symlink_switched","service_restarted","rollback_performed","deployed_artifact_sha","carrier_execution_ref"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_RUNTIME_DEPLOY','MINI_JUDGE_X03_RUNTIME_DEPLOY_V1',
'["release_path_after","deploy_exit_zero","symlink_switched","service_restarted","rollback_performed","deployed_artifact_sha","carrier_execution_ref"]'::jsonb,'health_readback',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','health_readback',80,80,'CONTRACT-PASE-F07-X03-v1','Guarded X03 health_readback','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["service_active_after","health_status","runtime_version","listener_loopback","health_probe_ref"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_HEALTH_READBACK','MINI_JUDGE_X03_HEALTH_READBACK_V1',
'["service_active_after","health_status","runtime_version","listener_loopback","health_probe_ref"]'::jsonb,'runtime_sha_readback',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','runtime_sha_readback',90,90,'CONTRACT-PASE-F07-X03-v1','Guarded X03 runtime_sha_readback','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["runtime_sha","receipt_sha","source_revision","exact_runtime_match","attestation_ref","readback_observed_at"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_RUNTIME_SHA_READBACK','MINI_JUDGE_X03_RUNTIME_SHA_READBACK_V1',
'["runtime_sha","receipt_sha","source_revision","exact_runtime_match","attestation_ref","readback_observed_at"]'::jsonb,'state_preservation',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','state_preservation',100,100,'CONTRACT-PASE-F07-X03-v1','Guarded X03 state_preservation','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["runtime_estado_before","runtime_estado_after","estado_operativo_before","estado_operativo_after","impacto_automatico_before","impacto_automatico_after","no_auto_promotion"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_STATE_PRESERVATION','MINI_JUDGE_X03_STATE_PRESERVATION_V1',
'["runtime_estado_before","runtime_estado_after","estado_operativo_before","estado_operativo_after","impacto_automatico_before","impacto_automatico_after","no_auto_promotion"]'::jsonb,'asset_reconcile',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','asset_reconcile',105,105,'CONTRACT-PASE-F07-X03-v1','Guarded X03 asset_reconcile','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["runtime_source_sha","runtime_release_ref","deploy_execution_id","asset_readback_match","post_deploy_next_gate"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_ASSET_RECONCILE','MINI_JUDGE_X03_ASSET_RECONCILE_V1',
'["runtime_source_sha","runtime_release_ref","deploy_execution_id","asset_readback_match","post_deploy_next_gate"]'::jsonb,'close',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','close',110,110,'CONTRACT-PASE-F07-X03-v1','Guarded X03 close','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["all_required_steps_clean","open_blockers","runtime_deploy_verified","rollback_ready","no_auto_promotion"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_CLOSE','MINI_JUDGE_X03_CLOSE_V1',
'["all_required_steps_clean","open_blockers","runtime_deploy_verified","rollback_ready","no_auto_promotion"]'::jsonb,'report_output',
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007'),
('DEPLOY_RUNTIME_IMPLEMENTACION_PERFIL_LF','report_output',120,120,'CONTRACT-PASE-F07-X03-v1','Guarded X03 report_output','[]'::jsonb,
'EXISTING_REFRESCO_OWNER_RUNNER_VPS_CARRIER','["result","exact_head","runtime_sha","receipt_sha","release_path","previous_release_path","evidence_refs","next_gate"]'::jsonb,
'{"all_required_keys_present":true,"governed_readback":true}'::jsonb,
'{"missing_required_evidence":true,"governance_drift":true}'::jsonb,
'BLOCKED_X03_REPORT_OUTPUT','MINI_JUDGE_X03_REPORT_OUTPUT_V1',
'["result","exact_head","runtime_sha","receipt_sha","release_path","previous_release_path","evidence_refs","next_gate"]'::jsonb,null,
'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT','No host commands from migration; worker-only restart and T3.2 mitigation controls enforced by receipt validator.',
'EXEC-PASE-F07-X03-DRAFT-20261007','EXEC-PASE-F07-X03-DRAFT-20261007');
-- Read-only validator used by the runtime verification consumer; no effect on REFRESCO.
create or replace function public.lf_runtime_impl_deploy_receipt_check_v1(p jsonb)
returns text language plpgsql immutable set search_path to 'pg_catalog'
as $fn$
declare changed jsonb; path text; worker_only boolean; unit text;
begin
 if p is null or jsonb_typeof(p)<>'object' then return 'GOVERNANCE_DRIFT'; end if;
 if coalesce(p->>'exact_head','') !~ '^[0-9a-f]{40}$'
    or p->>'source_revision' is distinct from p->>'exact_head'
    or coalesce(p->>'runtime_sha','')=''
    or p->>'runtime_sha' is distinct from p->>'receipt_sha'
    or coalesce(p->>'attestation_ref','')=''
 then return 'GOVERNANCE_DRIFT'; end if;
 if coalesce(p->>'release_path','')='' or coalesce(p->>'previous_release_path','')=''
    or p->>'release_path'=p->>'previous_release_path'
    or coalesce(p->>'release_manifest_matches','false')<>'true'
 then return 'BLOCKED_WRONG_RELEASE_OR_ROLLBACK'; end if;
 if coalesce(p->>'health_status','')<>'HEALTHY'
    or coalesce(p->>'service_active_after','false')<>'true'
 then return 'BLOCKED_HEALTH_READBACK'; end if;
 changed:=p->'changed_paths';
 if jsonb_typeof(changed) is distinct from 'array' or jsonb_array_length(changed)=0
    or coalesce((p->>'runtime_code_delta_count')::int,0)<1
 then return 'BLOCKED_RUNTIME_DELTA_SCOPE'; end if;
 for path in select jsonb_array_elements_text(changed) loop
   if path !~ '^services/profile_runtime_api/[A-Za-z0-9_./-]+$'
      or path like '%/../%' or path like '%//%'
   then return 'BLOCKED_RUNTIME_DELTA_SCOPE'; end if;
 end loop;
 worker_only:=coalesce((p->>'worker_only_delta')::boolean,false);
 unit:=p->>'restart_unit';
 if worker_only and unit <> 'lf-profile-runtime-queue-worker'
 then return 'BLOCKED_WRONG_RESTART_UNIT'; end if;
 if coalesce(p->>'mitigation_action','PRESERVE')='REMOVE'
    and coalesce(p->>'t32_human_authorized','false')<>'true'
 then return 'BLOCKED_MITIGATION_HUMAN_GATE'; end if;
 if coalesce(p->>'mitigation_action','PRESERVE') not in ('PRESERVE','REMOVE')
 then return 'BLOCKED_MITIGATION_HUMAN_GATE'; end if;
 if p->>'next_gate' is distinct from 'POST_DEPLOY_WORKER_QUEUE_REAL_JOB_CANARY'
 then return 'BLOCKED_NEXT_GATE'; end if;
 return 'VERIFICATION_VERIFIED';
exception when others then
 return 'GOVERNANCE_DRIFT';
end $fn$;
comment on function public.lf_runtime_impl_deploy_receipt_check_v1(jsonb) is
 'RUNTIME_DEPLOY_VERIFICATION read-only adapter for LF_RUNTIME_IMPL_DEPLOY_RECEIPT_V1; independent runtime readback required; step90 attestation closes X02-R01; next gate real queue worker job canary bound to exact_head/runtime_sha. Does not execute deploy or canary.';
commit;
