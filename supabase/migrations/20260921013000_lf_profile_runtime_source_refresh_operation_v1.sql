begin;

-- Generic, profile-agnostic runtime source refresh after ACTUALIZACION_PERFIL_LF.
-- This operation deploys exact canonical main to the existing Hetzner runtime only
-- when runtime implementation code is unchanged and only the target profile changed
-- under profiles/. It preserves profile lifecycle/impact state and supports rollback.

do $pre$
begin
  if exists (
    select 1 from public.lf_operation_registry
    where operation_code='REFRESCO_RUNTIME_PERFIL_LF'
  ) then
    raise exception 'PROFILE_RUNTIME_REFRESH_OPERATION_ALREADY_EXISTS';
  end if;
  if exists (
    select 1 from public.lf_router_action_registry
    where asset_type='PERFIL' and action_code='PROFILE_RUNTIME_REFRESH'
  ) then
    raise exception 'PROFILE_RUNTIME_REFRESH_ROUTE_ALREADY_EXISTS';
  end if;
end
$pre$;

insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  lifecycle_state_code,created_by_execution_id,updated_by_execution_id
) values (
  'REFRESCO_RUNTIME_PERFIL_LF','v1.0','PRODUCCION_CONTROLADA',
  'SUPABASE_OPERATIONAL_AUTHORITY_WITH_GIT_MIRROR',
  'cristhianlujan/claude-persona-lf-patch',
  jsonb_build_array(
    'supabase/migrations/20260921013000_lf_profile_runtime_source_refresh_operation_v1.sql',
    'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json',
    'sandbox/lf_contract_gate_test/transversal_assets/profile_runtime_source_refresh/README.md',
    'services/profile_runtime_api/scripts/install.sh'
  ),
  'Transversal exact-main source refresh for an existing profile runtime. Blocks if runtime implementation code changed or another profile changed; preserves profile state and automatic impact; no automatic promotion.',
  'PROFILE_OPERATIONS','PROFILE_RUNTIME_SOURCE','RUNTIME_SOURCE_REFRESH','PERFIL',
  'OP_OPERATIONAL','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001',
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'
);

insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,
  required_before_write,allowed,blocked,required_after_write,status,
  created_by_execution_id,updated_by_execution_id
) values (
  'REFRESCO_RUNTIME_PERFIL_LF',
  'CONTRACT-REFRESCO-RUNTIME-PERFIL-LF-v1',
  'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json',
  '44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',
  jsonb_build_object(
    'exact_profile_required',true,
    'source_currentness_required',true,
    'runtime_implementation_delta_zero',true,
    'other_profile_delta_zero',true,
    'rollback_release_required',true,
    'pre_refresh_binding_required',true
  ),
  jsonb_build_object(
    'canonical_deploy_surface','services/profile_runtime_api/scripts/install.sh',
    'deployment_source','EXACT_CURRENT_MAIN',
    'restart_service','lf-profile-runtime-api.service',
    'automatic_promotion',false
  ),
  jsonb_build_array(
    'RUNTIME_IMPLEMENTATION_DELTA_PRESENT',
    'OTHER_PROFILE_DELTA_PRESENT',
    'SOURCE_NOT_CURRENT_MAIN',
    'PROFILE_SOURCE_HASH_MISMATCH',
    'SERVICE_HEALTH_FAILED',
    'STATE_DRIFT',
    'ROLLBACK_TARGET_MISSING'
  ),
  jsonb_build_object(
    'health_readback_required',true,
    'runtime_source_sha_readback_required',true,
    'profile_source_hash_readback_required',true,
    'state_preservation_required',true
  ),
  'ACTIVE_ENFORCEMENT',
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001',
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'
);

insert into public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,
  requires_existing_target,requires_missing_target,write_allowed,status,notes,
  created_by_execution_id,updated_by_execution_id
) values (
  'PERFIL','PROFILE_RUNTIME_REFRESH','REFRESCO_RUNTIME_PERFIL_LF','STATIC',
  true,false,true,'ACTIVE',
  'Refresh exact profile runtime source after governed source update; never changes profile authority or automatic impact.',
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001',
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'
);

insert into public.lf_operation_policy_bindings(
  operation_code,policy_code,policy_role,required,distribution_modes,binding_status,
  created_by_execution_id,updated_by_execution_id
) values
('REFRESCO_RUNTIME_PERFIL_LF','POL-LF-OPERATION-LIFECYCLE','GOVERNANCE_LIFECYCLE',true,array['ROUTER','DIRECT'],'ACTIVE','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF','POL-LF-POLICY-CONSUMPTION','POLICY_CONSUMPTION',true,array['ROUTER','DIRECT'],'ACTIVE','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF','POL-LF-SOURCE-RESOLUTION','SOURCE_RESOLUTION',true,array['ROUTER','DIRECT'],'ACTIVE','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF','POL-LF-STATE-MODEL','STATE_MODEL',true,array['ROUTER','DIRECT'],'ACTIVE','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001');

insert into public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
  active,execution_order,created_by_execution_id,updated_by_execution_id
) values
('REFRESCO_RUNTIME_PERFIL_LF',0,'init_execution',true,'execution_id_created,target_code,target_path','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,0,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',10,'router',true,'router_read,action','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,10,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',20,'profile_resolve',true,'profile_code,repo_path,entrypoint_sha,manifest_sha,exact_profile_resolved','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,20,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',30,'source_currentness',true,'main_sha,profile_source_merge_sha,expected_entrypoint_sha,expected_manifest_sha,source_current','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,30,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',40,'runtime_baseline',true,'runtime_source_sha_before,release_path_before,service_active_before,health_before,profile_entrypoint_sha_before,profile_manifest_sha_before,rollback_source_sha','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,40,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',50,'refresh_plan',true,'deploy_source_sha,install_script_ref,runtime_code_delta_count,other_profile_delta_count,rollback_source_sha,restart_required,no_auto_promotion','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,50,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',60,'pre_refresh_binding_gate',true,'execution_id,target_code,target_path,bound_main_sha,bound_runtime_source_sha,pre_refresh_gate_passed','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,60,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',70,'runtime_refresh',true,'deploy_source_sha,release_path_after,symlink_switched,service_restarted,install_exit_zero,rollback_performed,runtime_implementation_changed,other_profile_changed','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,70,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',80,'health_readback',true,'service_active_after,health_status,runtime_endpoint_source_sha,runtime_version,listener_loopback','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,80,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',90,'source_readback',true,'deployed_entrypoint_sha,deployed_manifest_sha,expected_entrypoint_sha,expected_manifest_sha,exact_source_match','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,90,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',100,'state_preservation',true,'runtime_estado_before,runtime_estado_after,estado_operativo_before,estado_operativo_after,impacto_automatico_before,impacto_automatico_after,no_auto_promotion','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,100,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',105,'asset_reconcile',true,'runtime_source_sha,runtime_release_ref,runtime_source_refresh_execution_id,post_refresh_next_gate,asset_readback_match','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,105,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',110,'close',true,'all_required_steps_clean,open_blockers,runtime_refresh_verified,rollback_ready,no_auto_promotion','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,110,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'),
('REFRESCO_RUNTIME_PERFIL_LF',120,'report_output',true,'result,exact_head,runtime_source_sha,evidence_refs,open_blockers,next_gate','sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json','44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',true,120,'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001','EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001');

insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,
  output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,
  next_if_pass,next_if_blocked,status,notes,created_by_execution_id,updated_by_execution_id
)
select
  'REFRESCO_RUNTIME_PERFIL_LF',x.step_id,x.step_order,x.step_order,
  'CONTRACT-REFRESCO-RUNTIME-PERFIL-LF-v1',x.purpose,'[]'::jsonb,
  case when x.step_id='router' then 'SUPABASE_ROUTER_ACT0001'
       else 'DETERMINISTIC_PROFILE_RUNTIME_REFRESH_V1' end,
  x.required_keys,
  jsonb_build_object('must_not_be_generic',true,'must_match_step_purpose',true),
  jsonb_build_object('missing_required_evidence',true,'server_validation_failed',true),
  'BLOCKED_REFRESCO_RUNTIME_PERFIL_LF_'||upper(x.step_id)||'_NOT_CLEAN',
  'MINI_JUDGE_PROFILE_RUNTIME_REFRESH_'||upper(x.step_id)||'_V1',
  x.required_keys,
  x.next_if_pass,'RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT',
  'Profile-agnostic deterministic runtime source refresh step.',
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001',
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'
from (
  values
  (0,'init_execution','Create governed execution before any host mutation.','["execution_id_created","target_code","target_path"]'::jsonb,'router'),
  (10,'router','Resolve ACT-0001 action PROFILE_RUNTIME_REFRESH for an exact existing profile.','["router_read","action"]'::jsonb,'profile_resolve'),
  (20,'profile_resolve','Resolve exact profile source identity and hashes from operational authority.','["profile_code","repo_path","entrypoint_sha","manifest_sha","exact_profile_resolved"]'::jsonb,'source_currentness'),
  (30,'source_currentness','Bind refresh to exact canonical main and the post-merge profile source receipt.','["main_sha","profile_source_merge_sha","expected_entrypoint_sha","expected_manifest_sha","source_current"]'::jsonb,'runtime_baseline'),
  (40,'runtime_baseline','Capture deployed release, service health, target profile hashes and rollback source before mutation.','["runtime_source_sha_before","release_path_before","service_active_before","health_before","profile_entrypoint_sha_before","profile_manifest_sha_before","rollback_source_sha"]'::jsonb,'refresh_plan'),
  (50,'refresh_plan','Prove refresh is source-only: runtime implementation delta zero, no other profile delta, canonical installer and rollback.','["deploy_source_sha","install_script_ref","runtime_code_delta_count","other_profile_delta_count","rollback_source_sha","restart_required","no_auto_promotion"]'::jsonb,'pre_refresh_binding_gate'),
  (60,'pre_refresh_binding_gate','Bind exact execution, target, main and deployed runtime revision before host write.','["execution_id","target_code","target_path","bound_main_sha","bound_runtime_source_sha","pre_refresh_gate_passed"]'::jsonb,'runtime_refresh'),
  (70,'runtime_refresh','Apply atomic canonical release switch and restart without runtime implementation or other-profile changes.','["deploy_source_sha","release_path_after","symlink_switched","service_restarted","install_exit_zero","rollback_performed","runtime_implementation_changed","other_profile_changed"]'::jsonb,'health_readback'),
  (80,'health_readback','Verify service active, loopback health and runtime endpoint source SHA after refresh.','["service_active_after","health_status","runtime_endpoint_source_sha","runtime_version","listener_loopback"]'::jsonb,'source_readback'),
  (90,'source_readback','Verify deployed target profile entrypoint and manifest exact hashes.','["deployed_entrypoint_sha","deployed_manifest_sha","expected_entrypoint_sha","expected_manifest_sha","exact_source_match"]'::jsonb,'state_preservation'),
  (100,'state_preservation','Prove profile lifecycle/operational/automatic-impact state was preserved.','["runtime_estado_before","runtime_estado_after","estado_operativo_before","estado_operativo_after","impacto_automatico_before","impacto_automatico_after","no_auto_promotion"]'::jsonb,'asset_reconcile'),
  (105,'asset_reconcile','Persist exact deployed runtime source currentness into the existing profile asset without changing lifecycle or automatic impact.','["runtime_source_sha","runtime_release_ref","runtime_source_refresh_execution_id","post_refresh_next_gate","asset_readback_match"]'::jsonb,'close'),
  (110,'close','Close only after all prior gates, refresh readback, rollback readiness and no promotion are clean.','["all_required_steps_clean","open_blockers","runtime_refresh_verified","rollback_ready","no_auto_promotion"]'::jsonb,'report_output'),
  (120,'report_output','Emit exact-head runtime refresh receipt and next gate.','["result","exact_head","runtime_source_sha","evidence_refs","open_blockers","next_gate"]'::jsonb,null)
) as x(step_order,step_id,purpose,required_keys,next_if_pass);

do $judges$
declare s record; jc text;
begin
  for s in
    select st.step_order,st.step_id,c.required_evidence_keys
    from public.lf_operation_steps st
    join public.lf_operation_step_contracts c
      on c.operation_code=st.operation_code and c.step_id=st.step_id
     and c.step_order=st.step_order and c.status='ACTIVE_ENFORCEMENT'
    where st.operation_code='REFRESCO_RUNTIME_PERFIL_LF'
    order by st.step_order
  loop
    jc:='MINI_JUDGE_PROFILE_RUNTIME_REFRESH_'||upper(s.step_id)||'_V1';
    insert into public.lf_operation_judges(
      operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
      created_by_execution_id,updated_by_execution_id
    ) values(
      'REFRESCO_RUNTIME_PERFIL_LF',jc,
      'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_runtime_source_refresh_contract_v1.json',
      '44f878fed208e8a2b8a64457da45452b1c54c8a227f9bc428d440839b974a665',
      '["server_validated"]'::jsonb,'["server_validation_failed"]'::jsonb,
      jsonb_build_array('STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER'),
      'ACTIVE_ENFORCEMENT',
      'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001',
      'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'
    );
    insert into public.lf_operation_step_judge_bindings(
      operation_code,step_order,step_id,judge_code,
      clean_result_value,blocked_result_value,return_result_value,
      required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
    ) values(
      'REFRESCO_RUNTIME_PERFIL_LF',s.step_order,s.step_id,jc,
      'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
      s.required_evidence_keys,'ACTIVE_ENFORCEMENT',
      'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001',
      'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'
    );
  end loop;
end
$judges$;

create or replace function public.lf_profile_runtime_refresh_trust_validation_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  a public.lf_activos%rowtype;
  hard jsonb := '[]'::jsonb;
  expected_main text;
  expected_entry text;
  expected_manifest text;
  base_state jsonb;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_step_id,'')),'') is null
     or p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_RUNTIME_REFRESH_TRUST_INPUT_INVALID',
      'details','{}'::jsonb,'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or e.operation_code<>'REFRESCO_RUNTIME_PERFIL_LF'
     or e.target_type<>'PERFIL'
     or e.status<>'IN_PROGRESS' then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_RUNTIME_REFRESH_EXECUTION_BINDING_INVALID',
      'details',jsonb_build_object('execution_id',p_execution_id),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  select * into a
  from public.lf_activos
  where codigo_activo=e.target_code
    and tipo_activo='PERFIL'
    and archived_at is null;

  if not found then
    hard:=hard||jsonb_build_array('profile_not_found');
  end if;

  expected_main:=e.manifest->>'expected_main_sha';
  expected_entry:=coalesce(a.metadata->>'entrypoint_sha',a.raw_payload->>'skill_sha');
  expected_manifest:=a.metadata->>'manifest_sha';
  base_state:=e.manifest->'profile_state_baseline';

  if coalesce(expected_main,'') !~ '^[0-9a-f]{40}$' then
    hard:=hard||jsonb_build_array('expected_main_sha_invalid');
  end if;

  if p_step_id='router' then
    if p_evidence_payload->>'action' is distinct from 'PROFILE_RUNTIME_REFRESH'
       or not exists (
         select 1 from public.lf_router_action_registry
         where asset_type='PERFIL'
           and action_code='PROFILE_RUNTIME_REFRESH'
           and operation_code='REFRESCO_RUNTIME_PERFIL_LF'
           and status='ACTIVE'
           and write_allowed
       ) then
      hard:=hard||jsonb_build_array('router_binding_invalid');
    end if;

  elsif p_step_id='profile_resolve' then
    if p_evidence_payload->>'profile_code' is distinct from e.target_code
       or p_evidence_payload->>'repo_path' is distinct from coalesce(a.metadata->>'repo_path','')
       or p_evidence_payload->>'entrypoint_sha' is distinct from expected_entry
       or p_evidence_payload->>'manifest_sha' is distinct from expected_manifest
       or coalesce((p_evidence_payload->>'exact_profile_resolved')::boolean,false) is not true then
      hard:=hard||jsonb_build_array('profile_resolution_not_exact');
    end if;

  elsif p_step_id='source_currentness' then
    if p_evidence_payload->>'main_sha' is distinct from expected_main
       or p_evidence_payload->>'expected_entrypoint_sha' is distinct from expected_entry
       or p_evidence_payload->>'expected_manifest_sha' is distinct from expected_manifest
       or p_evidence_payload->>'profile_source_merge_sha' is distinct from coalesce(a.metadata->>'last_governed_merge_sha','')
       or coalesce((p_evidence_payload->>'source_current')::boolean,false) is not true
       or a.metadata->>'post_merge_next_gate' is distinct from 'PROFILE_RUNTIME_REFRESH_REQUIRED' then
      hard:=hard||jsonb_build_array('source_currentness_not_bound');
    end if;

  elsif p_step_id='runtime_baseline' then
    if coalesce(p_evidence_payload->>'runtime_source_sha_before','') !~ '^[0-9a-f]{40}$'
       or coalesce(p_evidence_payload->>'rollback_source_sha','') !~ '^[0-9a-f]{40}$'
       or p_evidence_payload->>'runtime_source_sha_before' is distinct from p_evidence_payload->>'rollback_source_sha'
       or coalesce(p_evidence_payload->>'release_path_before','') !~ '^/opt/lf-profile-runtime-api/releases/[0-9a-f]{40}$'
       or coalesce((p_evidence_payload->>'service_active_before')::boolean,false) is not true
       or lower(coalesce(p_evidence_payload->>'health_before','')) not in ('pass','healthy','ok')
       or coalesce(p_evidence_payload->>'profile_entrypoint_sha_before','') !~ '^[0-9a-f]{40}$'
       or coalesce(p_evidence_payload->>'profile_manifest_sha_before','') !~ '^[0-9a-f]{40}$' then
      hard:=hard||jsonb_build_array('runtime_baseline_invalid');
    end if;

  elsif p_step_id='refresh_plan' then
    if p_evidence_payload->>'deploy_source_sha' is distinct from expected_main
       or p_evidence_payload->>'install_script_ref' is distinct from 'services/profile_runtime_api/scripts/install.sh'
       or coalesce(p_evidence_payload->>'runtime_code_delta_count','') !~ '^[0-9]+$'
       or (case when coalesce(p_evidence_payload->>'runtime_code_delta_count','') ~ '^[0-9]+$'
                then (p_evidence_payload->>'runtime_code_delta_count')::integer else -1 end)<>0
       or coalesce(p_evidence_payload->>'other_profile_delta_count','') !~ '^[0-9]+$'
       or (case when coalesce(p_evidence_payload->>'other_profile_delta_count','') ~ '^[0-9]+$'
                then (p_evidence_payload->>'other_profile_delta_count')::integer else -1 end)<>0
       or coalesce(p_evidence_payload->>'rollback_source_sha','') !~ '^[0-9a-f]{40}$'
       or coalesce((p_evidence_payload->>'restart_required')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'no_auto_promotion')::boolean,false) is not true then
      hard:=hard||jsonb_build_array('refresh_plan_not_source_only');
    end if;

  elsif p_step_id='pre_refresh_binding_gate' then
    if p_evidence_payload->>'execution_id' is distinct from p_execution_id
       or p_evidence_payload->>'target_code' is distinct from e.target_code
       or p_evidence_payload->>'target_path' is distinct from coalesce(e.target_path,'')
       or p_evidence_payload->>'bound_main_sha' is distinct from expected_main
       or coalesce(p_evidence_payload->>'bound_runtime_source_sha','') !~ '^[0-9a-f]{40}$'
       or coalesce((p_evidence_payload->>'pre_refresh_gate_passed')::boolean,false) is not true then
      hard:=hard||jsonb_build_array('pre_refresh_binding_invalid');
    end if;

  elsif p_step_id='runtime_refresh' then
    if p_evidence_payload->>'deploy_source_sha' is distinct from expected_main
       or p_evidence_payload->>'release_path_after' is distinct from '/opt/lf-profile-runtime-api/releases/'||expected_main
       or coalesce((p_evidence_payload->>'symlink_switched')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'service_restarted')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'install_exit_zero')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'rollback_performed')::boolean,true) is not false
       or coalesce((p_evidence_payload->>'runtime_implementation_changed')::boolean,true) is not false
       or coalesce((p_evidence_payload->>'other_profile_changed')::boolean,true) is not false then
      hard:=hard||jsonb_build_array('runtime_refresh_not_exact');
    end if;

  elsif p_step_id='health_readback' then
    if coalesce((p_evidence_payload->>'service_active_after')::boolean,false) is not true
       or lower(coalesce(p_evidence_payload->>'health_status','')) not in ('pass','healthy','ok')
       or p_evidence_payload->>'runtime_endpoint_source_sha' is distinct from expected_main
       or nullif(btrim(coalesce(p_evidence_payload->>'runtime_version','')),'') is null
       or coalesce((p_evidence_payload->>'listener_loopback')::boolean,false) is not true then
      hard:=hard||jsonb_build_array('runtime_health_readback_failed');
    end if;

  elsif p_step_id='source_readback' then
    if p_evidence_payload->>'expected_entrypoint_sha' is distinct from expected_entry
       or p_evidence_payload->>'expected_manifest_sha' is distinct from expected_manifest
       or p_evidence_payload->>'deployed_entrypoint_sha' is distinct from expected_entry
       or p_evidence_payload->>'deployed_manifest_sha' is distinct from expected_manifest
       or coalesce((p_evidence_payload->>'exact_source_match')::boolean,false) is not true then
      hard:=hard||jsonb_build_array('deployed_profile_source_mismatch');
    end if;

  elsif p_step_id='state_preservation' then
    if base_state is null or jsonb_typeof(base_state)<>'object'
       or p_evidence_payload->>'runtime_estado_before' is distinct from base_state->>'runtime_estado'
       or p_evidence_payload->>'runtime_estado_after' is distinct from base_state->>'runtime_estado'
       or p_evidence_payload->>'estado_operativo_before' is distinct from base_state->>'estado_operativo'
       or p_evidence_payload->>'estado_operativo_after' is distinct from base_state->>'estado_operativo'
       or p_evidence_payload->>'impacto_automatico_before' is distinct from base_state->>'impacto_automatico'
       or p_evidence_payload->>'impacto_automatico_after' is distinct from base_state->>'impacto_automatico'
       or coalesce((p_evidence_payload->>'no_auto_promotion')::boolean,false) is not true then
      hard:=hard||jsonb_build_array('profile_state_not_preserved');
    end if;

  elsif p_step_id='asset_reconcile' then
    if p_evidence_payload->>'runtime_source_sha' is distinct from expected_main
       or p_evidence_payload->>'runtime_release_ref' is distinct from '/opt/lf-profile-runtime-api/releases/'||expected_main
       or p_evidence_payload->>'runtime_source_refresh_execution_id' is distinct from p_execution_id
       or p_evidence_payload->>'post_refresh_next_gate' is distinct from 'PROFILE_RUNTIME_CANARY_REQUIRED'
       or coalesce((p_evidence_payload->>'asset_readback_match')::boolean,false) is not true
       or a.metadata->>'runtime_source_sha' is distinct from expected_main
       or a.metadata->>'runtime_source_refresh_execution_id' is distinct from p_execution_id
       or a.metadata->>'post_merge_next_gate' is distinct from 'PROFILE_RUNTIME_CANARY_REQUIRED' then
      hard:=hard||jsonb_build_array('asset_runtime_source_reconcile_mismatch');
    end if;

  elsif p_step_id='close' then
    if coalesce((p_evidence_payload->>'all_required_steps_clean')::boolean,false) is not true
       or jsonb_typeof(p_evidence_payload->'open_blockers')<>'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or coalesce((p_evidence_payload->>'runtime_refresh_verified')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'rollback_ready')::boolean,false) is not true
       or coalesce((p_evidence_payload->>'no_auto_promotion')::boolean,false) is not true then
      hard:=hard||jsonb_build_array('close_contract_not_clean');
    end if;

  elsif p_step_id='report_output' then
    if nullif(btrim(coalesce(p_evidence_payload->>'result','')),'') is null
       or p_evidence_payload->>'exact_head' is distinct from expected_main
       or p_evidence_payload->>'runtime_source_sha' is distinct from expected_main
       or jsonb_typeof(p_evidence_payload->'evidence_refs')<>'array'
       or jsonb_array_length(p_evidence_payload->'evidence_refs')=0
       or jsonb_typeof(p_evidence_payload->'open_blockers')<>'array'
       or jsonb_array_length(p_evidence_payload->'open_blockers')<>0
       or nullif(btrim(coalesce(p_evidence_payload->>'next_gate','')),'') is null then
      hard:=hard||jsonb_build_array('report_output_not_clean');
    end if;
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_RUNTIME_REFRESH_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,'code','PROFILE_RUNTIME_REFRESH_SERVER_VALIDATED',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id,'target_code',e.target_code),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$fn$;

create or replace function public.lf_profile_runtime_refresh_reconcile_asset_v1(
  p_execution_id text,
  p_runtime_release_ref text,
  p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  a public.lf_activos%rowtype;
  before_runtime text;
  before_operational text;
  before_impact text;
  before_document text;
  prior_missing integer;
  prior_bad integer;
  expected_main text;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_runtime_release_ref,'')),'') is null
     or nullif(btrim(coalesce(p_actor_execution_id,'')),'') is null then
    raise exception 'PROFILE_RUNTIME_REFRESH_RECONCILE_INPUT_INVALID';
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;

  if not found
     or e.operation_code<>'REFRESCO_RUNTIME_PERFIL_LF'
     or e.target_type<>'PERFIL'
     or e.status<>'IN_PROGRESS' then
    raise exception 'PROFILE_RUNTIME_REFRESH_RECONCILE_EXECUTION_INVALID';
  end if;

  expected_main:=e.manifest->>'expected_main_sha';
  if coalesce(expected_main,'') !~ '^[0-9a-f]{40}$'
     or p_runtime_release_ref is distinct from '/opt/lf-profile-runtime-api/releases/'||expected_main then
    raise exception 'PROFILE_RUNTIME_REFRESH_RECONCILE_SOURCE_INVALID';
  end if;

  select count(*) into prior_missing
  from public.lf_operation_steps s
  where s.operation_code='REFRESCO_RUNTIME_PERFIL_LF'
    and s.required and s.active
    and coalesce(s.execution_order,s.step_order)<105
    and not exists(
      select 1 from public.lf_operation_execution_steps es
      where es.execution_id=p_execution_id
        and es.step_order=s.step_order
        and es.step_id=s.step_id
    );

  select count(*) into prior_bad
  from public.lf_operation_steps s
  join public.lf_operation_execution_steps es
    on es.execution_id=p_execution_id
   and es.step_order=s.step_order
   and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings b
    on b.operation_code=s.operation_code
   and b.step_order=s.step_order
   and b.step_id=s.step_id
   and b.status='ACTIVE_ENFORCEMENT'
  where s.operation_code='REFRESCO_RUNTIME_PERFIL_LF'
    and s.required and s.active
    and coalesce(s.execution_order,s.step_order)<105
    and (b.clean_result_value is null or es.status<>b.clean_result_value);

  if prior_missing>0 or prior_bad>0 then
    raise exception 'PROFILE_RUNTIME_REFRESH_RECONCILE_PRIOR_STEPS_NOT_CLEAN missing=% bad=%',
      prior_missing,prior_bad;
  end if;

  select * into a
  from public.lf_activos
  where codigo_activo=e.target_code
    and tipo_activo='PERFIL'
    and archived_at is null
  for update;

  if not found then
    raise exception 'PROFILE_RUNTIME_REFRESH_RECONCILE_PROFILE_NOT_FOUND';
  end if;

  before_runtime:=a.runtime_estado;
  before_operational:=a.estado_operativo;
  before_impact:=a.impacto_automatico;
  before_document:=a.estado_documental;

  update public.lf_activos
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'runtime_source_sha',expected_main,
        'runtime_release_ref',p_runtime_release_ref,
        'runtime_source_refresh_execution_id',p_execution_id,
        'runtime_source_refreshed_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'post_merge_next_gate','PROFILE_RUNTIME_CANARY_REQUIRED',
        'runtime_source_currentness_reason','GOVERNED_PROFILE_RUNTIME_SOURCE_REFRESH'
      ),
      updated_by_execution_id=p_actor_execution_id,
      updated_at=clock_timestamp()
  where codigo_activo=e.target_code
    and tipo_activo='PERFIL'
    and archived_at is null;

  select * into a
  from public.lf_activos
  where codigo_activo=e.target_code
    and tipo_activo='PERFIL'
    and archived_at is null;

  if a.runtime_estado is distinct from before_runtime
     or a.estado_operativo is distinct from before_operational
     or a.impacto_automatico is distinct from before_impact
     or a.estado_documental is distinct from before_document then
    raise exception 'PROFILE_RUNTIME_REFRESH_RECONCILE_STATE_DRIFT';
  end if;

  if a.metadata->>'runtime_source_sha' is distinct from expected_main
     or a.metadata->>'runtime_release_ref' is distinct from p_runtime_release_ref
     or a.metadata->>'runtime_source_refresh_execution_id' is distinct from p_execution_id
     or a.metadata->>'post_merge_next_gate' is distinct from 'PROFILE_RUNTIME_CANARY_REQUIRED' then
    raise exception 'PROFILE_RUNTIME_REFRESH_RECONCILE_READBACK_FAILED';
  end if;

  return jsonb_build_object(
    'outcome','RECONCILED',
    'execution_id',p_execution_id,
    'target_code',e.target_code,
    'runtime_source_sha',expected_main,
    'runtime_release_ref',p_runtime_release_ref,
    'runtime_source_refresh_execution_id',p_execution_id,
    'post_refresh_next_gate','PROFILE_RUNTIME_CANARY_REQUIRED',
    'runtime_state_preserved',a.runtime_estado is not distinct from before_runtime,
    'operational_state_preserved',a.estado_operativo is not distinct from before_operational,
    'automatic_impact_preserved',a.impacto_automatico is not distinct from before_impact,
    'document_state_preserved',a.estado_documental is not distinct from before_document,
    'automatic_promotion',false
  );
end
$fn$;

create or replace function public.lf_record_profile_runtime_refresh_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare v_trust jsonb;
begin
  v_trust:=public.lf_profile_runtime_refresh_trust_validation_v1(
    p_execution_id,p_step_id,p_evidence_payload
  );
  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'REFRESCO_RUNTIME_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,true,'lf_record_profile_runtime_refresh_step_v1'
  );
end
$fn$;

create or replace function public.lf_profile_runtime_refresh_begin_v1(
  p_execution_id text,
  p_profile_code text,
  p_expected_main_sha text,
  p_idempotency_key text,
  p_request_sha256 text,
  p_actor_execution_id text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare
  a public.lf_activos%rowtype;
  r jsonb;
  b public.lf_operation_step_judge_bindings%rowtype;
  repo_path text;
begin
  if nullif(btrim(coalesce(p_profile_code,'')),'') is null
     or coalesce(p_expected_main_sha,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'PROFILE_RUNTIME_REFRESH_BEGIN_INPUT_INVALID';
  end if;

  select * into a
  from public.lf_activos
  where codigo_activo=p_profile_code
    and tipo_activo='PERFIL'
    and archived_at is null;

  if not found then
    raise exception 'PROFILE_RUNTIME_REFRESH_PROFILE_NOT_FOUND';
  end if;

  if a.metadata->>'post_merge_next_gate' is distinct from 'PROFILE_RUNTIME_REFRESH_REQUIRED' then
    raise exception 'PROFILE_RUNTIME_REFRESH_NOT_REQUIRED_FOR_PROFILE';
  end if;

  repo_path:=a.metadata->>'repo_path';
  if nullif(btrim(coalesce(repo_path,'')),'') is null then
    raise exception 'PROFILE_RUNTIME_REFRESH_REPO_PATH_MISSING';
  end if;

  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'REFRESCO_RUNTIME_PERFIL_LF',
    'PERFIL',p_profile_code,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,
    'cristhianlujan/claude-persona-lf-patch',repo_path,
    coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object(
      'profile_runtime_refresh_governed',true,
      'expected_main_sha',p_expected_main_sha,
      'profile_state_baseline',jsonb_build_object(
        'runtime_estado',a.runtime_estado,
        'estado_operativo',a.estado_operativo,
        'impacto_automatico',a.impacto_automatico
      ),
      'expected_entrypoint_sha',coalesce(a.metadata->>'entrypoint_sha',a.raw_payload->>'skill_sha'),
      'expected_manifest_sha',a.metadata->>'manifest_sha',
      'automatic_promotion',false
    )
  );

  select * into b
  from public.lf_operation_step_judge_bindings
  where operation_code='REFRESCO_RUNTIME_PERFIL_LF'
    and step_id='init_execution'
    and status='ACTIVE_ENFORCEMENT';

  if r->>'result'='RESERVED_NEW_EXECUTION' then
    insert into public.lf_operation_execution_steps(
      execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
    ) values(
      r->>'execution_id',0,'init_execution',b.clean_result_value,
      'supabase://public.lf_operation_execution/'||(r->>'execution_id'),
      jsonb_build_object(
        'execution_id_created',true,
        'target_code',p_profile_code,
        'target_path',repo_path,
        'step_result',b.clean_result_value,
        'blocking_codes','[]'::jsonb,
        'mini_judge_code',b.judge_code,
        'mini_judge_result',b.clean_result_value,
        'assertions_checked',jsonb_build_array('server_validated'),
        'hard_fails_checked','[]'::jsonb,
        'blocking_findings','[]'::jsonb,
        'return_to_worker_reasons','[]'::jsonb,
        'trust_validation',jsonb_build_object(
          'valid',true,
          'code','PROFILE_RUNTIME_REFRESH_INIT_SERVER_VALIDATED',
          'server_assertions',jsonb_build_array('server_validated'),
          'server_hard_fails','[]'::jsonb
        ),
        'recorded_by_rpc','lf_profile_runtime_refresh_begin_v1'
      ),
      'Profile runtime refresh init materialized after canonical idempotent reserve.',
      p_actor_execution_id
    );
  end if;

  return r||jsonb_build_object(
    'init_materialized',true,
    'target_code',p_profile_code,
    'target_path',repo_path,
    'expected_main_sha',p_expected_main_sha
  );
end
$fn$;

revoke all on function public.lf_profile_runtime_refresh_trust_validation_v1(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.lf_profile_runtime_refresh_reconcile_asset_v1(text,text,text) from public,anon,authenticated;
revoke all on function public.lf_record_profile_runtime_refresh_step_v1(text,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.lf_profile_runtime_refresh_begin_v1(text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.lf_profile_runtime_refresh_trust_validation_v1(text,text,jsonb) to service_role;
grant execute on function public.lf_profile_runtime_refresh_reconcile_asset_v1(text,text,text) to service_role;
grant execute on function public.lf_record_profile_runtime_refresh_step_v1(text,text,text,jsonb,text) to service_role;
grant execute on function public.lf_profile_runtime_refresh_begin_v1(text,text,text,text,text,text,jsonb) to service_role;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
  formato_nativo,linea_codigo,estado_original,estado_documental,estado_operativo,
  nivel_control,runtime_estado,impacto_automatico,accion_migracion,version,
  ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
  migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
) values (
  'PROFILE_RUNTIME_SOURCE_REFRESH',
  'PROFILE_RUNTIME_SOURCE_REFRESH',
  'CAPABILITY',
  'TRANSVERSAL_DEPLOYMENT_GUARD',
  'SQL+SHELL+SYSTEMD',
  'PROFILE_RUNTIME_GOVERNANCE',
  'ACTIVE_SHARED_ENFORCEMENT',
  'VIGENTE',
  'ACTIVO',
  'TRANSVERSAL',
  'HOST_BOUND',
  'BLOQUEADO',
  'REGISTER_TRANSVERSAL_CAPABILITY',
  'v1.0',
  'sandbox/lf_contract_gate_test/transversal_assets/profile_runtime_source_refresh/README.md',
  'supabase://public/lf_operation_registry/REFRESCO_RUNTIME_PERFIL_LF',
  'LF_GOVERNANCE',
  '2026-09-21',
  'Generic exact-main source refresh for existing profile runtimes; separate from runtime implementation update and profile promotion.',
  'NATIVE_SUPABASE',
  'LF_TRANSVERSAL_CAPABILITY_INVENTORY',
  'PROFILE_RUNTIME_SOURCE_REFRESH_20260921',
  1,
  gen_random_uuid(),
  jsonb_build_object(
    'operation_code','REFRESCO_RUNTIME_PERFIL_LF',
    'router_action','PROFILE_RUNTIME_REFRESH',
    'canonical_installer','services/profile_runtime_api/scripts/install.sh'
  ),
  jsonb_build_object(
    'source_kind','GITHUB_SOURCE_PLUS_SUPABASE_REGISTRY',
    'transversal_inventory',jsonb_build_object(
      'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
      'logical_key','PROFILE_RUNTIME_SOURCE_REFRESH',
      'class','RUNTIME_DEPLOYMENT_GUARD',
      'inventory_status','ACTIVE_SHARED_ENFORCEMENT',
      'lookup_rule','ASSET_INVENTORY_FIRST_THEN_CURRENTNESS_THEN_EXPAND_SEARCH',
      'no_duplicate_engine',true,
      'consumers_known',jsonb_build_array('ACTUALIZACION_PERFIL_LF','REFRESCO_RUNTIME_PERFIL_LF'),
      'documentation',jsonb_build_object(
        'status','SOURCE_FIRST_BOUND',
        'repo','cristhianlujan/claude-persona-lf-patch',
        'readme_ref','sandbox/lf_contract_gate_test/transversal_assets/profile_runtime_source_refresh/README.md',
        'contract_version','lf-transversal-readme-contract/v3'
      ),
      'physical_assets',jsonb_build_array(
        'services/profile_runtime_api/scripts/install.sh',
        '/opt/lf-profile-runtime-api/releases/<source_sha>',
        '/opt/lf-profile-runtime-api/current',
        'lf-profile-runtime-api.service',
        'public.lf_operation_registry/REFRESCO_RUNTIME_PERFIL_LF',
        'public.lf_router_action_registry/PERFIL/PROFILE_RUNTIME_REFRESH'
      ),
      'gap','CLOSED_BY_GENERIC_PROFILE_RUNTIME_REFRESH_OPERATION'
    )
  ),
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001',
  'EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'
);

update public.lf_operation_registry
set notes=coalesce(notes,'')||
  ' | Runtime source refresh handoff is routed by PERFIL/PROFILE_RUNTIME_REFRESH -> REFRESCO_RUNTIME_PERFIL_LF; refresh is separate from source update and automatic promotion.',
    updated_at=now(),
    updated_by_execution_id='EXEC-PROFILE-RUNTIME-REFRESH-TRANSVERSAL-20260921-001'
where operation_code='ACTUALIZACION_PERFIL_LF';

do $post$
declare c int;
begin
  select count(*) into c
  from public.lf_operation_steps
  where operation_code='REFRESCO_RUNTIME_PERFIL_LF' and active;
  if c<>14 then raise exception 'PROFILE_RUNTIME_REFRESH_STEP_COUNT:%',c; end if;

  select count(*) into c
  from public.lf_operation_step_contracts
  where operation_code='REFRESCO_RUNTIME_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>14 then raise exception 'PROFILE_RUNTIME_REFRESH_CONTRACT_COUNT:%',c; end if;

  select count(*) into c
  from public.lf_operation_judges
  where operation_code='REFRESCO_RUNTIME_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>14 then raise exception 'PROFILE_RUNTIME_REFRESH_JUDGE_COUNT:%',c; end if;

  select count(*) into c
  from public.lf_operation_step_judge_bindings
  where operation_code='REFRESCO_RUNTIME_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>14 then raise exception 'PROFILE_RUNTIME_REFRESH_BINDING_COUNT:%',c; end if;

  if not exists(
    select 1 from public.lf_router_action_registry
    where asset_type='PERFIL'
      and action_code='PROFILE_RUNTIME_REFRESH'
      and operation_code='REFRESCO_RUNTIME_PERFIL_LF'
      and status='ACTIVE'
      and write_allowed
  ) then raise exception 'PROFILE_RUNTIME_REFRESH_ROUTE_READBACK_FAILED'; end if;

  if not exists(
    select 1 from public.lf_activos
    where codigo_activo='PROFILE_RUNTIME_SOURCE_REFRESH'
      and tipo_activo='CAPABILITY'
      and estado_operativo='ACTIVO'
      and archived_at is null
      and metadata #>> '{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
  ) then raise exception 'PROFILE_RUNTIME_REFRESH_ASSET_READBACK_FAILED'; end if;

  if exists(
    select 1 from public.lf_operation_step_contracts
    where operation_code='REFRESCO_RUNTIME_PERFIL_LF'
      and execution_sql is not null
  ) then raise exception 'PROFILE_RUNTIME_REFRESH_DB_EXECUTOR_FORBIDDEN'; end if;
end
$post$;

commit;
