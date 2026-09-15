-- APP_SHELL lifecycle governance candidate v1
-- Scope: rollback-only canary for CREATE/UPDATE governance. Does NOT create the privileged Admin shell.
-- Source-first execution: EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001

begin;

-- Baseline must still have no APP_SHELL lifecycle before this candidate is materialized.
do $baseline$
declare c integer;
begin
  select count(*) into c
  from public.lf_router_action_registry
  where asset_type='APP_SHELL' and action_code in ('APP_SHELL_CREATE','APP_SHELL_UPDATE');
  if c<>0 then raise exception 'LF_APP_SHELL_BASELINE_ROUTE_ALREADY_EXISTS:%',c; end if;
end;
$baseline$;

with o(operation_code,op_type) as (values
  ('CREACION_APP_SHELL_LF','CREATE_CANDIDATE'),
  ('ACTUALIZACION_APP_SHELL_LF','UPDATE_CANDIDATE')
)
insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,updated_by_execution_id
)
select operation_code,'v0.1','SANDBOX_ACTIVE','GOVERNED_DB_OPERATION',
  'cristhianlujan/claude-persona-lf-patch',
  '["public.lf_router_resolve_v1","public.lf_router_action_registry","lf_ops.app_shells","lf_design.design_systems","public.lf_app_shell_candidate_write_v1"]'::jsonb,
  'Sandbox-only APP_SHELL candidate lifecycle; CANDIDATO only; no promotion or production activation.',
  'APP_SHELL_OPERATIONS','APP_SHELL_GOVERNANCE',op_type,'APP_SHELL',
  'EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001'
from o;

with o(operation_code) as (values ('CREACION_APP_SHELL_LF'),('ACTUALIZACION_APP_SHELL_LF'))
insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,
  required_before_write,allowed,blocked,required_after_write,status,
  created_by_execution_id,updated_by_execution_id
)
select operation_code,'CONTRACT-'||operation_code||'-v0.1',
  'supabase://public/lf_operation_contracts/'||operation_code||'/v0.1',null,
  '["router_read","ekb_read","shell_inventory_read","design_system_resolved","execution_bound","rollback_plan"]'::jsonb,
  '{"destination":"lf_ops.app_shells","write_state":"CANDIDATO","single_shell":true,"automatic_promotion":false,"production_allowed":false,"direct_write_allowed":false}'::jsonb,
  '["production_promotion","vigente_direct_update","duplicate_create","missing_update_target","direct_write_bypass","cross_shell_mutation"]'::jsonb,
  '["exact_shell_readback","estado_CANDIDATO","execution_trace","no_promotion"]'::jsonb,
  'ACTIVE_ENFORCEMENT','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001'
from o;

with o(operation_code) as (values ('CREACION_APP_SHELL_LF'),('ACTUALIZACION_APP_SHELL_LF')),
s(step_order,step_id,evidence,next_step) as (values
  (10,'preflight','router_binding,ekb_refs,shell_inventory,rollback_plan','classify'),
  (20,'classify','app_shell_code,design_system_code,candidate_classification','existing_check'),
  (30,'existing_check','app_shell_code,existing_count,expected_existence','destination_validate'),
  (40,'destination_validate','destination_schema,destination_table,design_system_resolved','candidate_write'),
  (50,'candidate_write','execution_id,app_shell_code,write_result,status','readback'),
  (60,'readback','app_shell_code,readback_row,status','trace_close'),
  (70,'trace_close','execution_id,operation_code,trace_ref,no_promotion',null)
)
insert into public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,
  created_by_execution_id,updated_by_execution_id
)
select o.operation_code,s.step_order,s.step_id,true,s.evidence,
  'supabase://public/lf_operation_step_contracts/'||o.operation_code||'/'||s.step_id,null,true,s.step_order,
  'EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001'
from o cross join s;

with o(operation_code) as (values ('CREACION_APP_SHELL_LF'),('ACTUALIZACION_APP_SHELL_LF')),
s(step_order,step_id,keys,next_step) as (values
  (10,'preflight','["router_binding","ekb_refs","shell_inventory","rollback_plan"]'::jsonb,'classify'),
  (20,'classify','["app_shell_code","design_system_code","candidate_classification"]'::jsonb,'existing_check'),
  (30,'existing_check','["app_shell_code","existing_count","expected_existence"]'::jsonb,'destination_validate'),
  (40,'destination_validate','["destination_schema","destination_table","design_system_resolved"]'::jsonb,'candidate_write'),
  (50,'candidate_write','["execution_id","app_shell_code","write_result","status"]'::jsonb,'readback'),
  (60,'readback','["app_shell_code","readback_row","status"]'::jsonb,'trace_close'),
  (70,'trace_close','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb,null)
)
insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,
  output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,
  next_if_pass,next_if_blocked,status,notes,execution_sql,fail_condition,
  created_by_execution_id,updated_by_execution_id
)
select o.operation_code,s.step_id,s.step_order,s.step_order,
  'CONTRACT-'||o.operation_code||'-v0.1',s.step_id||' deterministic APP_SHELL governance step.',
  '{}'::jsonb,'APP_SHELL_OPERATION_DETERMINISTIC',s.keys,
  '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,
  'BLOCK_'||o.operation_code||'_'||upper(s.step_id),'MINI_JUDGE_'||o.operation_code||'_V1',s.keys,
  s.next_step,'trace_close','ACTIVE_ENFORCEMENT','Fail-closed sandbox APP_SHELL governance step.',null,'{}'::jsonb,
  'EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001'
from o cross join s;

with o(operation_code) as (values ('CREACION_APP_SHELL_LF'),('ACTUALIZACION_APP_SHELL_LF'))
insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
  created_by_execution_id,updated_by_execution_id
)
select operation_code,'MINI_JUDGE_'||operation_code||'_V1',
  'supabase://public/lf_operation_judges/'||operation_code,null,
  '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,
  '["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]'::jsonb,'ACTIVE_ENFORCEMENT',
  'EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001'
from o;

with o(operation_code) as (values ('CREACION_APP_SHELL_LF'),('ACTUALIZACION_APP_SHELL_LF')),
s(step_order,step_id,keys) as (values
  (10,'preflight','["router_binding","ekb_refs","shell_inventory","rollback_plan"]'::jsonb),
  (20,'classify','["app_shell_code","design_system_code","candidate_classification"]'::jsonb),
  (30,'existing_check','["app_shell_code","existing_count","expected_existence"]'::jsonb),
  (40,'destination_validate','["destination_schema","destination_table","design_system_resolved"]'::jsonb),
  (50,'candidate_write','["execution_id","app_shell_code","write_result","status"]'::jsonb),
  (60,'readback','["app_shell_code","readback_row","status"]'::jsonb),
  (70,'trace_close','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb)
)
insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
)
select o.operation_code,s.step_order,s.step_id,'MINI_JUDGE_'||o.operation_code||'_V1',
  'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',s.keys,'ACTIVE_ENFORCEMENT',
  'EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001'
from o cross join s;

insert into public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,requires_existing_target,requires_missing_target,
  write_allowed,status,notes,created_by_execution_id,updated_by_execution_id
) values
('APP_SHELL','APP_SHELL_CREATE','CREACION_APP_SHELL_LF','STATIC',false,false,true,'ACTIVE',
 'Existence is resolved inside governed APP_SHELL operation against lf_ops.app_shells.app_shell_code; CANDIDATO only.',
 'EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001'),
('APP_SHELL','APP_SHELL_UPDATE','ACTUALIZACION_APP_SHELL_LF','STATIC',false,false,true,'ACTIVE',
 'Only an existing CANDIDATO APP_SHELL can be updated; VIGENTE direct update is blocked.',
 'EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001','EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001');

create or replace function public.lf_app_shell_candidate_write_v1(
  p_execution_id text,
  p_action_code text,
  p_app_shell_code text,
  p_design_system_code text,
  p_name text,
  p_description text default null,
  p_version text default 'v0.1',
  p_source_decision_id text default null,
  p_source_decision_number bigint default null
) returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,public,lf_ops,lf_design
as $fn$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_expected text;
  v_before lf_ops.app_shells%rowtype;
  v_after lf_ops.app_shells%rowtype;
  v_ds_id bigint;
  v_next_id bigint;
begin
  if upper(coalesce(p_action_code,'')) not in ('APP_SHELL_CREATE','APP_SHELL_UPDATE') then
    raise exception 'LF_APP_SHELL_ACTION_INVALID:%',p_action_code;
  end if;
  if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_app_shell_code,''))='' or
     btrim(coalesce(p_design_system_code,''))='' or btrim(coalesce(p_name,''))='' then
    raise exception 'LF_APP_SHELL_REQUIRED_INPUT_MISSING';
  end if;

  v_expected:=case upper(p_action_code)
    when 'APP_SHELL_CREATE' then 'CREACION_APP_SHELL_LF'
    else 'ACTUALIZACION_APP_SHELL_LF' end;

  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then raise exception 'LF_APP_SHELL_EXECUTION_NOT_FOUND:%',p_execution_id; end if;
  if v_exec.operation_code<>v_expected or v_exec.status<>'IN_PROGRESS' or
     v_exec.target_type<>'APP_SHELL' or v_exec.target_code<>p_app_shell_code then
    raise exception 'LF_APP_SHELL_EXECUTION_BINDING_MISMATCH';
  end if;

  select design_system_id into v_ds_id
  from lf_design.design_systems
  where design_system_code=p_design_system_code;
  if v_ds_id is null then raise exception 'LF_APP_SHELL_DESIGN_SYSTEM_NOT_FOUND:%',p_design_system_code; end if;

  select * into v_before from lf_ops.app_shells where app_shell_code=p_app_shell_code;

  if upper(p_action_code)='APP_SHELL_CREATE' then
    if found then raise exception 'LF_APP_SHELL_CREATE_DUPLICATE:%',p_app_shell_code; end if;

    -- Numeric identity is legacy/manual today. Serialize governed writers before allocating the next id.
    perform pg_advisory_xact_lock(hashtextextended('lf_ops.app_shells.app_shell_id',0));
    select coalesce(max(app_shell_id),0)+1 into v_next_id from lf_ops.app_shells;

    insert into lf_ops.app_shells(
      app_shell_id,app_shell_code,design_system_code,design_system_id,name,description,version,status,
      source_decision_id,source_decision_number
    ) values (
      v_next_id,p_app_shell_code,p_design_system_code,v_ds_id,p_name,p_description,
      coalesce(nullif(btrim(p_version),''),'v0.1'),'CANDIDATO',p_source_decision_id,p_source_decision_number
    ) returning * into v_after;
  else
    if not found then raise exception 'LF_APP_SHELL_UPDATE_NOT_FOUND:%',p_app_shell_code; end if;
    if v_before.status<>'CANDIDATO' then
      raise exception 'LF_APP_SHELL_UPDATE_REQUIRES_CANDIDATO:%:%',p_app_shell_code,v_before.status;
    end if;

    update lf_ops.app_shells
    set design_system_code=p_design_system_code,
        design_system_id=v_ds_id,
        name=p_name,
        description=p_description,
        version=coalesce(nullif(btrim(p_version),''),version),
        status='CANDIDATO',
        source_decision_id=coalesce(p_source_decision_id,source_decision_id),
        source_decision_number=coalesce(p_source_decision_number,source_decision_number)
    where app_shell_code=p_app_shell_code
    returning * into v_after;
  end if;

  return jsonb_build_object(
    'result',case when upper(p_action_code)='APP_SHELL_CREATE' then 'APP_SHELL_CANDIDATE_CREATED' else 'APP_SHELL_CANDIDATE_UPDATED' end,
    'operation_code',v_expected,'execution_id',p_execution_id,
    'before',case when upper(p_action_code)='APP_SHELL_UPDATE' then to_jsonb(v_before) else null end,
    'after',to_jsonb(v_after)
  );
end;
$fn$;

revoke all on function public.lf_app_shell_candidate_write_v1(text,text,text,text,text,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.lf_app_shell_candidate_write_v1(text,text,text,text,text,text,text,text,bigint) to service_role;

-- Canary: explicit Router actions must resolve, generic recorder must accept the lifecycle, writer must create/update only CANDIDATO.
do $canary$
declare
  r jsonb;
  step_r jsonb;
  wr jsonb;
  c integer;
begin
  r:=public.lf_router_resolve_v1('create governed APP_SHELL candidate','TEST_ADMIN_PRIV_SHELL','APP_SHELL_CREATE','APP_SHELL','ROUTER');
  if r->>'status'<>'READY_TO_EXECUTE' or r->>'operation_code'<>'CREACION_APP_SHELL_LF' then
    raise exception 'LF_APP_SHELL_CREATE_ROUTER_CANARY_FAIL:%',r;
  end if;

  r:=public.fn_lf_operation_reserve_execution_v1(
    'EXEC-CANARY-APP-SHELL-CREATE-001','CREACION_APP_SHELL_LF','APP_SHELL','TEST_ADMIN_PRIV_SHELL',
    'CANARY:APP_SHELL:CREATE:001',repeat('1',64),'EXEC-CANARY-APP-SHELL-CREATE-001',null,null,
    '{"sandbox_canary":true,"production":false}'::jsonb
  );
  if r->>'result'<>'RESERVED_NEW_EXECUTION' then raise exception 'LF_APP_SHELL_RESERVE_CANARY_FAIL:%',r; end if;

  step_r:=public.lf_record_operation_step_core_v1(
    'EXEC-CANARY-APP-SHELL-CREATE-001','preflight','canary://app-shell/preflight',
    '{"router_binding":"READY_TO_EXECUTE","ekb_refs":["RULE-LIFECYCLE-ROUTER-WRITE-GAP-001"],"shell_inventory":{"existing":2},"rollback_plan":"ROLLBACK"}'::jsonb,
    'EXEC-CANARY-APP-SHELL-CREATE-001','CREACION_APP_SHELL_LF','APP_SHELL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    '{"valid":true,"server_assertions":["required_evidence_present"],"server_hard_fails":[]}'::jsonb,
    false,'APP_SHELL_SANDBOX_CANARY'
  );
  if step_r->>'outcome'<>'STEP_RECORDED' then raise exception 'LF_APP_SHELL_RECORDER_CANARY_FAIL:%',step_r; end if;

  wr:=public.lf_app_shell_candidate_write_v1(
    'EXEC-CANARY-APP-SHELL-CREATE-001','APP_SHELL_CREATE','TEST_ADMIN_PRIV_SHELL','LF_DS_V1',
    'Canary Admin Shell','Rollback-only synthetic shell','v0.1',null,null
  );
  if wr->>'result'<>'APP_SHELL_CANDIDATE_CREATED' then raise exception 'LF_APP_SHELL_CREATE_WRITER_CANARY_FAIL:%',wr; end if;

  select count(*) into c from lf_ops.app_shells where app_shell_code='TEST_ADMIN_PRIV_SHELL' and status='CANDIDATO';
  if c<>1 then raise exception 'LF_APP_SHELL_CREATE_READBACK_FAIL:%',c; end if;

  r:=public.lf_router_resolve_v1('update governed APP_SHELL candidate','TEST_ADMIN_PRIV_SHELL','APP_SHELL_UPDATE','APP_SHELL','ROUTER');
  if r->>'status'<>'READY_TO_EXECUTE' or r->>'operation_code'<>'ACTUALIZACION_APP_SHELL_LF' then
    raise exception 'LF_APP_SHELL_UPDATE_ROUTER_CANARY_FAIL:%',r;
  end if;

  r:=public.fn_lf_operation_reserve_execution_v1(
    'EXEC-CANARY-APP-SHELL-UPDATE-001','ACTUALIZACION_APP_SHELL_LF','APP_SHELL','TEST_ADMIN_PRIV_SHELL',
    'CANARY:APP_SHELL:UPDATE:001',repeat('2',64),'EXEC-CANARY-APP-SHELL-UPDATE-001',null,null,
    '{"sandbox_canary":true,"production":false}'::jsonb
  );

  wr:=public.lf_app_shell_candidate_write_v1(
    'EXEC-CANARY-APP-SHELL-UPDATE-001','APP_SHELL_UPDATE','TEST_ADMIN_PRIV_SHELL','LF_DS_V1',
    'Canary Admin Shell v2','Rollback-only synthetic shell','v0.2',null,null
  );
  if wr#>>'{after,name}'<>'Canary Admin Shell v2' then raise exception 'LF_APP_SHELL_UPDATE_WRITER_CANARY_FAIL:%',wr; end if;

  -- VIGENTE shell must not be updateable by the candidate lifecycle.
  r:=public.fn_lf_operation_reserve_execution_v1(
    'EXEC-CANARY-APP-SHELL-VIGENTE-BLOCK-001','ACTUALIZACION_APP_SHELL_LF','APP_SHELL','CLIENT_APP_SHELL',
    'CANARY:APP_SHELL:VIGENTE:001',repeat('3',64),'EXEC-CANARY-APP-SHELL-VIGENTE-BLOCK-001',null,null,
    '{"sandbox_canary":true,"production":false}'::jsonb
  );
  begin
    perform public.lf_app_shell_candidate_write_v1(
      'EXEC-CANARY-APP-SHELL-VIGENTE-BLOCK-001','APP_SHELL_UPDATE','CLIENT_APP_SHELL','LF_DS_V1',
      'MUST NOT WRITE',null,'v9.9',null,null
    );
    raise exception 'LF_APP_SHELL_VIGENTE_NEGATIVE_DID_NOT_BLOCK';
  exception when others then
    if position('LF_APP_SHELL_UPDATE_REQUIRES_CANDIDATO' in sqlerrm)=0 then raise; end if;
  end;
end;
$canary$;

rollback;
