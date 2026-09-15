-- S30 OPERATION_BOOTSTRAP_LF source candidate.
-- NON-MIGRATION / DO NOT APPLY FROM THIS BRANCH.
-- Canonical migration generation, exact-version apply and live cutover require a later governed gate.

create table if not exists public.lf_operation_bootstrap_policy (
  operation_code text primary key references public.lf_operation_registry(operation_code) on delete cascade,
  bootstrap_mode text not null check (bootstrap_mode in ('GENERIC','WRAPPER_REQUIRED','DISABLED')),
  expected_target_type text not null,
  allowed_lifecycle_states text[] not null default array['OP_OPERATIONAL']::text[],
  require_parent_in_progress boolean not null default true,
  require_operation_qualification boolean not null default true,
  require_init_step_contract boolean not null default true,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','SUPERSEDED','DISABLED')),
  notes text,
  created_by_execution_id text not null,
  updated_by_execution_id text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

alter table public.lf_operation_bootstrap_policy enable row level security;
revoke all on table public.lf_operation_bootstrap_policy from public, anon, authenticated;
grant select, insert, update, delete on table public.lf_operation_bootstrap_policy to service_role;

create or replace function public.lf_operation_bootstrap_core_v1(
  p_execution_id text,
  p_operation_code text,
  p_target_type text,
  p_target_code text,
  p_target_repo text,
  p_target_path text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb default '{}'::jsonb,
  p_wrapper_authorized boolean default false
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  pol public.lf_operation_bootstrap_policy%rowtype;
  reg public.lf_operation_registry%rowtype;
  actor public.lf_operation_execution%rowtype;
  x public.lf_operation_execution%rowtype;
  st public.lf_operation_steps%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  r jsonb;
  ep jsonb;
  init_step_count int;
  init_contract_count int;
  init_binding_count int;
  init_judge_count int;
  non_init_step_count int;
begin
  if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_operation_code,''))=''
     or btrim(coalesce(p_target_type,''))='' or btrim(coalesce(p_target_code,''))=''
     or btrim(coalesce(p_idempotency_key,''))='' or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_actor_execution_id,''))='' or p_manifest is null or jsonb_typeof(p_manifest)<>'object' then
    raise exception 'LF_OPERATION_BOOTSTRAP_INPUT_INVALID';
  end if;

  select * into pol
  from public.lf_operation_bootstrap_policy
  where operation_code=p_operation_code and status='ACTIVE';
  if not found then raise exception 'LF_OPERATION_BOOTSTRAP_POLICY_NOT_ACTIVE:%',p_operation_code; end if;
  if pol.bootstrap_mode='DISABLED' then raise exception 'LF_OPERATION_BOOTSTRAP_DISABLED:%',p_operation_code; end if;
  if pol.bootstrap_mode='WRAPPER_REQUIRED' and p_wrapper_authorized is not true then
    raise exception 'LF_OPERATION_BOOTSTRAP_WRAPPER_REQUIRED:%',p_operation_code;
  end if;
  if pol.bootstrap_mode='GENERIC' and p_wrapper_authorized is true then
    raise exception 'LF_OPERATION_BOOTSTRAP_GENERIC_WRAPPER_FLAG_INVALID:%',p_operation_code;
  end if;

  select * into reg from public.lf_operation_registry where operation_code=p_operation_code;
  if not found then raise exception 'LF_OPERATION_BOOTSTRAP_OPERATION_MISSING:%',p_operation_code; end if;
  if reg.applies_to_asset_type is distinct from p_target_type or pol.expected_target_type is distinct from p_target_type then
    raise exception 'LF_OPERATION_BOOTSTRAP_TARGET_TYPE_MISMATCH:%:%:%',p_operation_code,reg.applies_to_asset_type,p_target_type;
  end if;
  if not (reg.lifecycle_state_code = any(pol.allowed_lifecycle_states)) then
    raise exception 'LF_OPERATION_BOOTSTRAP_LIFECYCLE_NOT_ALLOWED:%:%',p_operation_code,reg.lifecycle_state_code;
  end if;

  if pol.require_parent_in_progress then
    select * into actor from public.lf_operation_execution where execution_id=p_actor_execution_id;
    if not found or actor.status<>'IN_PROGRESS' then
      raise exception 'LF_OPERATION_BOOTSTRAP_PARENT_EXECUTION_INVALID:%',p_actor_execution_id;
    end if;
  end if;

  select count(*) into init_step_count
  from public.lf_operation_steps
  where operation_code=p_operation_code and step_id='init_execution' and active=true;
  if init_step_count<>1 then raise exception 'LF_OPERATION_BOOTSTRAP_INIT_STEP_NOT_EXACT:%:%',p_operation_code,init_step_count; end if;
  select * into st from public.lf_operation_steps
  where operation_code=p_operation_code and step_id='init_execution' and active=true;

  if pol.require_init_step_contract then
    select count(*) into init_contract_count
    from public.lf_operation_step_contracts
    where operation_code=p_operation_code and step_id='init_execution' and step_order=st.step_order and status='ACTIVE_ENFORCEMENT';
    if init_contract_count<>1 then
      raise exception 'LF_OPERATION_BOOTSTRAP_INIT_CONTRACT_NOT_EXACT:%:%',p_operation_code,init_contract_count;
    end if;
  end if;

  select count(*) into init_binding_count
  from public.lf_operation_step_judge_bindings
  where operation_code=p_operation_code and step_id='init_execution' and step_order=st.step_order and status='ACTIVE_ENFORCEMENT';
  if init_binding_count<>1 then raise exception 'LF_OPERATION_BOOTSTRAP_INIT_BINDING_NOT_EXACT:%:%',p_operation_code,init_binding_count; end if;
  select * into b from public.lf_operation_step_judge_bindings
  where operation_code=p_operation_code and step_id='init_execution' and step_order=st.step_order and status='ACTIVE_ENFORCEMENT';

  select count(*) into init_judge_count
  from public.lf_operation_judges
  where operation_code=p_operation_code and judge_code=b.judge_code and status='ACTIVE_ENFORCEMENT';
  if init_judge_count<>1 then raise exception 'LF_OPERATION_BOOTSTRAP_INIT_JUDGE_NOT_EXACT:%:%',p_operation_code,init_judge_count; end if;

  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,p_operation_code,p_target_type,p_target_code,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,p_target_repo,p_target_path,
    p_manifest || jsonb_build_object('bootstrap_contract','LF_OPERATION_BOOTSTRAP_CONTRACT_V1','bootstrap_mode',pol.bootstrap_mode)
  );

  select * into x from public.lf_operation_execution where execution_id=r->>'execution_id' for update;
  if not found or x.operation_code is distinct from p_operation_code or x.target_type is distinct from p_target_type
     or x.target_code is distinct from p_target_code or x.target_repo is distinct from p_target_repo
     or x.target_path is distinct from p_target_path or x.status<>'IN_PROGRESS' then
    raise exception 'LF_OPERATION_BOOTSTRAP_EXECUTION_BINDING_MISMATCH';
  end if;

  if pol.require_operation_qualification then
    perform public.lf_operation_execution_qualification_guard_v1(p_operation_code,x.started_at);
  end if;

  select count(*) into non_init_step_count
  from public.lf_operation_execution_steps
  where execution_id=x.execution_id and step_id<>'init_execution';
  if non_init_step_count>0 then
    raise exception 'LF_OPERATION_BOOTSTRAP_EXECUTION_ALREADY_MATERIALIZED:%',non_init_step_count;
  end if;

  select * into existing
  from public.lf_operation_execution_steps
  where execution_id=x.execution_id and step_order=st.step_order;
  if found then
    if existing.step_id='init_execution' and existing.status=b.clean_result_value then
      return r || jsonb_build_object('init_step','ALREADY_RECORDED_IDEMPOTENT','bootstrap_mode',pol.bootstrap_mode,'next_step','router');
    end if;
    raise exception 'LF_OPERATION_BOOTSTRAP_INIT_STEP_CONFLICT:%:%',existing.step_id,existing.status;
  end if;

  ep:=jsonb_build_object(
    'execution_id',x.execution_id,
    'operation_code',x.operation_code,
    'target_type',x.target_type,
    'target_code',x.target_code,
    'target_repo',x.target_repo,
    'target_path',x.target_path,
    'idempotency_key',x.idempotency_key,
    'request_sha256',x.request_sha256,
    'bootstrap_mode',pol.bootstrap_mode,
    'bootstrap_contract','LF_OPERATION_BOOTSTRAP_CONTRACT_V1',
    'server_assertions',jsonb_build_array('execution_binding_exact','operation_registry_target_exact','bootstrap_policy_active','init_topology_exact','qualification_current_if_required'),
    'assertions_checked',jsonb_build_array('execution_binding_exact','operation_registry_target_exact','bootstrap_policy_active','init_topology_exact','qualification_current_if_required'),
    'hard_fails_checked','[]'::jsonb,
    'blocking_findings','[]'::jsonb,
    'blocking_codes','[]'::jsonb,
    'return_to_worker_reasons','[]'::jsonb,
    'step_result',b.clean_result_value,
    'derived_result',b.clean_result_value,
    'derived_by_judge',b.judge_code,
    'mini_judge_code',b.judge_code,
    'mini_judge_result',b.clean_result_value,
    'attempt_history','[]'::jsonb,
    'recorded_by_rpc','lf_operation_bootstrap_core_v1'
  );

  insert into public.lf_operation_execution_steps(
    execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
  ) values(
    x.execution_id,st.step_order,'init_execution',b.clean_result_value,
    format('supabase://public/lf_operation_execution/%s',x.execution_id),ep,
    'Initialized transactionally by OPERATION_BOOTSTRAP_LF core.',p_actor_execution_id
  );

  select * into existing
  from public.lf_operation_execution_steps
  where execution_id=x.execution_id and step_order=st.step_order and step_id='init_execution';
  if not found or existing.status<>b.clean_result_value
     or existing.evidence_payload->>'derived_result'<>b.clean_result_value then
    raise exception 'LF_OPERATION_BOOTSTRAP_READBACK_FAILED';
  end if;

  return r || jsonb_build_object('init_step','RECORDED','bootstrap_mode',pol.bootstrap_mode,'next_step','router');
end
$function$;

create or replace function public.lf_operation_begin_v1(
  p_execution_id text,
  p_operation_code text,
  p_target_type text,
  p_target_code text,
  p_target_repo text,
  p_target_path text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
begin
  return public.lf_operation_bootstrap_core_v1(
    p_execution_id,p_operation_code,p_target_type,p_target_code,p_target_repo,p_target_path,
    p_request_sha256,p_idempotency_key,p_actor_execution_id,p_manifest,false
  );
end
$function$;

revoke all on function public.lf_operation_bootstrap_core_v1(text,text,text,text,text,text,text,text,text,jsonb,boolean) from public, anon, authenticated;
revoke all on function public.lf_operation_begin_v1(text,text,text,text,text,text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_operation_bootstrap_core_v1(text,text,text,text,text,text,text,text,text,jsonb,boolean) to service_role;
grant execute on function public.lf_operation_begin_v1(text,text,text,text,text,text,text,text,text,jsonb) to service_role;

-- No policy rows are seeded by this source candidate. Each operation must be admitted
-- explicitly after its init topology, target semantics and qualification dependencies are proven.
