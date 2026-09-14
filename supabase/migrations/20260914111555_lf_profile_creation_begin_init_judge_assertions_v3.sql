create or replace function public.lf_profile_creation_begin_v1(
  p_execution_id text,
  p_target_code text,
  p_target_repo text,
  p_package_root text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
declare
  r jsonb;
  x public.lf_operation_execution%rowtype;
  actor public.lf_operation_execution%rowtype;
  st public.lf_operation_steps%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  oc public.lf_operation_contracts%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  route_count int;
  primary_count int;
  supplement_count int;
  ep jsonb;
begin
  if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_target_code,''))=''
     or btrim(coalesce(p_target_repo,''))='' or btrim(coalesce(p_package_root,''))=''
     or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_idempotency_key,''))='' or btrim(coalesce(p_actor_execution_id,''))=''
     or p_manifest is null or jsonb_typeof(p_manifest)<>'object' then raise exception 'LF_PROFILE_CREATION_BEGIN_INPUT_INVALID'; end if;
  if p_target_code !~ '^PERFIL-[A-Z0-9-]+-LF$' then raise exception 'LF_PROFILE_CREATION_TARGET_CODE_INVALID:%',p_target_code; end if;
  if p_target_repo <> 'cristhianlujan/claude-persona-lf-patch' then raise exception 'LF_PROFILE_CREATION_REPO_INVALID'; end if;
  if p_package_root !~ '^profiles/[a-z0-9][a-z0-9_/-]*$' or position('..' in p_package_root)>0 then raise exception 'LF_PROFILE_CREATION_PACKAGE_ROOT_INVALID'; end if;

  select * into actor from public.lf_operation_execution where execution_id=p_actor_execution_id;
  if not found or actor.status<>'IN_PROGRESS' then raise exception 'LF_PROFILE_CREATION_PARENT_EXECUTION_INVALID'; end if;

  select count(*) into route_count from public.lf_router_action_registry where asset_type='PERFIL' and action_code='PROFILE_CREATE' and operation_code='CREACION_PERFIL_LF' and status='ACTIVE' and write_allowed is true;
  if route_count<>1 then raise exception 'LF_PROFILE_CREATION_ROUTE_NOT_ACTIVE:%',route_count; end if;
  if not exists(select 1 from public.lf_operation_registry where operation_code='CREACION_PERFIL_LF' and applies_to_asset_type='PERFIL' and lifecycle_state_code='OP_OPERATIONAL') then raise exception 'LF_PROFILE_CREATION_OPERATION_NOT_OPERATIONAL'; end if;

  select count(*) into primary_count from public.lf_operation_contracts where operation_code='CREACION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT' and contract_code='CONTRACT-PROFILE-GENERAL-DEPTH-LF-v0.1';
  select count(*) into supplement_count from public.lf_operation_contracts where operation_code='CREACION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT' and contract_code='CONTRACT-CREACION-PERFIL-LF-NO-CLOSE-IF-REQUIRED-STEP-NOT-CLEAN-PASS-v0.1';
  if primary_count<>1 or supplement_count<>1 then raise exception 'LF_PROFILE_CREATION_CONTRACT_ROLES_INVALID:primary=% supplement=%',primary_count,supplement_count; end if;
  select * into oc from public.lf_operation_contracts where operation_code='CREACION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT' and contract_code='CONTRACT-PROFILE-GENERAL-DEPTH-LF-v0.1';

  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'CREACION_PERFIL_LF','PERFIL',p_target_code,p_idempotency_key,p_request_sha256,p_actor_execution_id,p_target_repo,p_package_root,
    p_manifest || jsonb_build_object('contract_code',oc.contract_code,'contract_sha',oc.contract_sha,'supplemental_contract_code','CONTRACT-CREACION-PERFIL-LF-NO-CLOSE-IF-REQUIRED-STEP-NOT-CLEAN-PASS-v0.1','parent_execution_id',p_actor_execution_id)
  );

  select * into x from public.lf_operation_execution where execution_id=r->>'execution_id' for update;
  if not found or x.operation_code<>'CREACION_PERFIL_LF' or x.target_type<>'PERFIL' or x.target_code is distinct from p_target_code or x.target_repo is distinct from p_target_repo or x.target_path is distinct from p_package_root or x.status<>'IN_PROGRESS' then raise exception 'LF_PROFILE_CREATION_EXECUTION_BINDING_MISMATCH'; end if;
  perform public.lf_operation_execution_qualification_guard_v1('CREACION_PERFIL_LF',x.started_at);

  select * into st from public.lf_operation_steps where operation_code='CREACION_PERFIL_LF' and step_id='init_execution' and active=true;
  if not found then raise exception 'LF_PROFILE_CREATION_INIT_STEP_NOT_ACTIVE'; end if;
  select * into b from public.lf_operation_step_judge_bindings where operation_code='CREACION_PERFIL_LF' and step_id='init_execution' and step_order=st.step_order and status='ACTIVE_ENFORCEMENT';
  if not found then raise exception 'LF_PROFILE_CREATION_INIT_BINDING_NOT_ACTIVE'; end if;

  select * into existing from public.lf_operation_execution_steps where execution_id=x.execution_id and step_order=st.step_order;
  if found then
    if existing.step_id='init_execution' and existing.status=b.clean_result_value then return r || jsonb_build_object('init_step','ALREADY_RECORDED_IDEMPOTENT','next_step','router'); end if;
    raise exception 'LF_PROFILE_CREATION_INIT_STEP_CONFLICT';
  end if;

  ep:=jsonb_build_object(
    'execution_row_created',true,'execution_id',x.execution_id,'operation_code','CREACION_PERFIL_LF','target_type','PERFIL','status',x.status,
    'target_code',p_target_code,'target_repo',p_target_repo,'target_path',p_package_root,'parent_execution_id',p_actor_execution_id,
    'assertions_checked',jsonb_build_array('execution_row_created','operation_code_exact','target_type_perfil','status_in_progress'),
    'hard_fails_checked','[]'::jsonb,'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb,
    'step_result',b.clean_result_value,'blocking_codes','[]'::jsonb,'mini_judge_code',b.judge_code,'mini_judge_result',b.clean_result_value,'recorded_by_rpc','lf_profile_creation_begin_v1'
  );

  insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id)
  values(x.execution_id,st.step_order,'init_execution',b.clean_result_value,format('supabase://public/lf_operation_execution/%s',x.execution_id),ep,'Initialized transactionally by governed Profile Creation begin RPC.',p_actor_execution_id);

  select * into existing from public.lf_operation_execution_steps where execution_id=x.execution_id and step_order=st.step_order and step_id='init_execution';
  if not found or existing.status<>b.clean_result_value then raise exception 'LF_PROFILE_CREATION_BEGIN_READBACK_FAILED'; end if;

  return r || jsonb_build_object('init_step','RECORDED','contract_code',oc.contract_code,'contract_sha',oc.contract_sha,'supplemental_contract_code','CONTRACT-CREACION-PERFIL-LF-NO-CLOSE-IF-REQUIRED-STEP-NOT-CLEAN-PASS-v0.1','next_step','router');
end;
$$;