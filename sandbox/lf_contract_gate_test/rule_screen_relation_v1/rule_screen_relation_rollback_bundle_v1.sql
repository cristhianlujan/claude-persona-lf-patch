-- RULE_SCREEN_RELATION_SANDBOX_V1
-- Independent shared capability candidate. No dependency on PR #746 or rule-exploration bridge.
-- Entire bundle is rollback-only: executing this file must leave zero durable residue.

begin;

insert into public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id
) values (
  'EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR','VINCULACION_REGLA_PANTALLA_LF','IN_PROGRESS',
  '{"mode":"RULE_SCREEN_RELATION_SANDBOX_V1","governance_bootstrap":true,"bootstrap_operation_code":"VINCULACION_REGLA_PANTALLA_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","rollback_only":true,"depends_on_pr746":false,"production_allowed":false,"runtime_activation":false}'::jsonb,
  'EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001',
  'EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001'
);

insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,created_by_execution_id
) values (
  'VINCULACION_REGLA_PANTALLA_LF','v0.1-sandbox','SANDBOX_ACTIVE','GOVERNED_DB_OPERATION',
  'cristhianlujan/claude-persona-lf-patch',
  '["lf_ops.reglas","lf_ops.pantallas","lf_ops.reglas_pantallas","public.lf_regla_pantalla_link_v1"]'::jsonb,
  'Independent idempotent rule-screen relation capability. No router binding, no delete, no mutation of rule/screen assets.',
  'RELATION_OPERATIONS','RULE_SCREEN_RELATION_GOVERNANCE','CREATE_RELATION','REGLA_PANTALLA_RELATION',
  'EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001'
);

insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,
  required_after_write,status,created_by_execution_id
) values (
  'VINCULACION_REGLA_PANTALLA_LF','CONTRACT-VINCULACION_REGLA_PANTALLA_LF-v0.1-sandbox',
  'sandbox://rule_screen_relation_v1/VINCULACION_REGLA_PANTALLA_LF',null,
  '["ekb_preflight","execution_bound","exact_rule_identity","exact_screen_identity","unique_relation_guard"]'::jsonb,
  '{"destination":"lf_ops.reglas_pantallas","idempotent_insert":true,"accepted_observed_rule_states":["CANDIDATO","VIGENTE"],"observe_screen_active_without_new_restriction":true,"rule_mutation":false,"screen_mutation":false}'::jsonb,
  '{"relation_delete":true,"rule_mutation":true,"screen_mutation":true,"rule_promotion":true,"runtime_activation":true,"production_promotion":true,"automatic_consumer_integration":true}'::jsonb,
  '["exact_relation_readback","rule_unchanged","screen_unchanged","single_relation","no_delete","no_promotion"]'::jsonb,
  'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001'
);

with s(step_order,step_id,evidence,next_step) as (values
  (10,'preflight','ekb_refs,execution_binding','resolve_rule'),
  (20,'resolve_rule','rule_code,rule_id,rule_state','resolve_screen'),
  (30,'resolve_screen','pantalla_id,screen_code,screen_active','relation_write'),
  (40,'relation_write','rule_id,pantalla_id,write_result','readback'),
  (50,'readback','relation_row,rule_unchanged,screen_unchanged,no_delete',null)
)
insert into public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
  active,execution_order,created_by_execution_id
)
select 'VINCULACION_REGLA_PANTALLA_LF',step_order,step_id,true,evidence,
       'sandbox://rule_screen_relation_v1/'||step_id,null,true,step_order,
       'EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001'
from s;

with s(step_order,step_id,keys,next_step) as (values
  (10,'preflight','["ekb_refs","execution_binding"]'::jsonb,'resolve_rule'),
  (20,'resolve_rule','["rule_code","rule_id","rule_state"]'::jsonb,'resolve_screen'),
  (30,'resolve_screen','["pantalla_id","screen_code","screen_active"]'::jsonb,'relation_write'),
  (40,'relation_write','["rule_id","pantalla_id","write_result"]'::jsonb,'readback'),
  (50,'readback','["relation_row","rule_unchanged","screen_unchanged","no_delete"]'::jsonb,null)
)
insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,
  resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,
  required_evidence_keys,next_if_pass,next_if_blocked,status,notes,execution_sql,fail_condition,
  created_by_execution_id
)
select 'VINCULACION_REGLA_PANTALLA_LF',step_id,step_order,step_order,
       'CONTRACT-VINCULACION_REGLA_PANTALLA_LF-v0.1-sandbox',
       step_id||' independent relation-governance step.','{}'::jsonb,
       'RULE_SCREEN_RELATION_DETERMINISTIC',keys,
       '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,
       'BLOCK_VINCULACION_REGLA_PANTALLA_'||upper(step_id),
       'MINI_JUDGE_VINCULACION_REGLA_PANTALLA_LF_V1',keys,next_step,'readback',
       'ACTIVE_ENFORCEMENT','Rollback-only sandbox candidate.',null,'{}'::jsonb,
       'EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001'
from s;

insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id
) values (
  'VINCULACION_REGLA_PANTALLA_LF','MINI_JUDGE_VINCULACION_REGLA_PANTALLA_LF_V1',
  'sandbox://rule_screen_relation_v1/MINI_JUDGE_VINCULACION_REGLA_PANTALLA_LF_V1',null,
  '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,
  '["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]'::jsonb,
  'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001'
);

with s(step_order,step_id,keys) as (values
  (10,'preflight','["ekb_refs","execution_binding"]'::jsonb),
  (20,'resolve_rule','["rule_code","rule_id","rule_state"]'::jsonb),
  (30,'resolve_screen','["pantalla_id","screen_code","screen_active"]'::jsonb),
  (40,'relation_write','["rule_id","pantalla_id","write_result"]'::jsonb),
  (50,'readback','["relation_row","rule_unchanged","screen_unchanged","no_delete"]'::jsonb)
)
insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,
  return_result_value,required_evidence_keys,status,created_by_execution_id
)
select 'VINCULACION_REGLA_PANTALLA_LF',step_order,step_id,
       'MINI_JUDGE_VINCULACION_REGLA_PANTALLA_LF_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT',
       'RETURN_TO_WORKER',keys,'ACTIVE_ENFORCEMENT',
       'EXEC-BOOTSTRAP-VINCULACION-REGLA-PANTALLA-LF-20260913-001'
from s;

create or replace function public.lf_regla_pantalla_link_v1(
  p_execution_id text,
  p_regla_codigo text,
  p_pantalla_id integer,
  p_nota text default null
) returns jsonb
language plpgsql
security invoker
set search_path=pg_catalog,public,lf_ops
as $f$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_rule lf_ops.reglas%rowtype;
  v_screen lf_ops.pantallas%rowtype;
  v_rule_after lf_ops.reglas%rowtype;
  v_screen_after lf_ops.pantallas%rowtype;
  v_rel lf_ops.reglas_pantallas%rowtype;
  v_inserted boolean:=false;
  v_count integer;
  v_expected_target text;
begin
  if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_regla_codigo,''))='' or p_pantalla_id is null then
    raise exception 'LF_RULE_SCREEN_RELATION_REQUIRED_INPUT_MISSING';
  end if;

  v_expected_target:=p_regla_codigo||'@'||p_pantalla_id::text;
  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then raise exception 'LF_RULE_SCREEN_RELATION_EXECUTION_NOT_FOUND:%',p_execution_id; end if;
  if v_exec.operation_code<>'VINCULACION_REGLA_PANTALLA_LF'
     or v_exec.status<>'IN_PROGRESS'
     or v_exec.target_type<>'REGLA_PANTALLA_RELATION'
     or v_exec.target_code<>v_expected_target then
    raise exception 'LF_RULE_SCREEN_RELATION_EXECUTION_BINDING_MISMATCH';
  end if;

  select * into v_rule from lf_ops.reglas where codigo=p_regla_codigo;
  if not found then raise exception 'LF_RULE_SCREEN_RULE_NOT_FOUND:%',p_regla_codigo; end if;
  if v_rule.estado not in ('CANDIDATO','VIGENTE') then
    raise exception 'LF_RULE_SCREEN_RULE_STATE_NOT_SUPPORTED:%:%',p_regla_codigo,v_rule.estado;
  end if;

  select * into v_screen from lf_ops.pantallas where id=p_pantalla_id;
  if not found then raise exception 'LF_RULE_SCREEN_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
  values(v_rule.id,v_screen.id,nullif(btrim(coalesce(p_nota,'')),''))
  on conflict(regla_id,pantalla_id) do nothing
  returning * into v_rel;

  if v_rel.id is not null then
    v_inserted:=true;
  else
    select * into v_rel
    from lf_ops.reglas_pantallas
    where regla_id=v_rule.id and pantalla_id=v_screen.id;
  end if;

  if v_rel.id is null then raise exception 'LF_RULE_SCREEN_RELATION_READBACK_MISSING'; end if;
  select count(*) into v_count from lf_ops.reglas_pantallas where regla_id=v_rule.id and pantalla_id=v_screen.id;
  if v_count<>1 then raise exception 'LF_RULE_SCREEN_RELATION_CARDINALITY_INVALID:%',v_count; end if;

  select * into v_rule_after from lf_ops.reglas where id=v_rule.id;
  select * into v_screen_after from lf_ops.pantallas where id=v_screen.id;
  if to_jsonb(v_rule_after) is distinct from to_jsonb(v_rule) then raise exception 'LF_RULE_SCREEN_RULE_MUTATED'; end if;
  if to_jsonb(v_screen_after) is distinct from to_jsonb(v_screen) then raise exception 'LF_RULE_SCREEN_SCREEN_MUTATED'; end if;

  return jsonb_build_object(
    'result',case when v_inserted then 'RULE_SCREEN_RELATION_CREATED' else 'RULE_SCREEN_RELATION_ALREADY_EXISTS' end,
    'operation_code','VINCULACION_REGLA_PANTALLA_LF',
    'execution_id',p_execution_id,
    'rule_code',v_rule.codigo,
    'rule_id',v_rule.id,
    'rule_state',v_rule.estado,
    'pantalla_id',v_screen.id,
    'screen_code',v_screen.codigo,
    'screen_active',v_screen.activa,
    'relation_row',to_jsonb(v_rel),
    'relation_count',v_count,
    'rule_unchanged',true,
    'screen_unchanged',true,
    'no_delete',true,
    'production_authorized',false,
    'runtime_activation',false,
    'promotion_authorized',false
  );
end $f$;

revoke all on function public.lf_regla_pantalla_link_v1(text,text,integer,text) from public,anon,authenticated;
grant execute on function public.lf_regla_pantalla_link_v1(text,text,integer,text) to service_role;

do $canary$
declare
  v_pair record;
  v_exec text;
  v_sha text;
  v_result jsonb;
  v_replay jsonb;
  v_base jsonb:=jsonb_build_object(
    'assertions_checked',jsonb_build_array('required_evidence_present'),
    'hard_fails_checked','[]'::jsonb,
    'blocking_findings','[]'::jsonb,
    'return_to_worker_reasons','[]'::jsonb
  );
  v_rule jsonb;
  v_screen jsonb;
  v_relation_count integer;
  v_test_index integer:=0;
  v_err text;
begin
  if exists(select 1 from public.lf_router_action_registry where operation_code='VINCULACION_REGLA_PANTALLA_LF') then
    raise exception 'LF_RULE_SCREEN_SANDBOX_ROUTER_BINDING_FORBIDDEN';
  end if;

  if position('delete from lf_ops.reglas_pantallas' in lower(pg_get_functiondef('public.lf_regla_pantalla_link_v1(text,text,integer,text)'::regprocedure)))>0 then
    raise exception 'LF_RULE_SCREEN_SANDBOX_DELETE_PATH_PRESENT';
  end if;
  if position('materializacion_regla_explorada_lf' in lower(pg_get_functiondef('public.lf_regla_pantalla_link_v1(text,text,integer,text)'::regprocedure)))>0
     or position('lf_rule_exploration' in lower(pg_get_functiondef('public.lf_regla_pantalla_link_v1(text,text,integer,text)'::regprocedure)))>0 then
    raise exception 'LF_RULE_SCREEN_SANDBOX_PR746_COUPLING_PRESENT';
  end if;

  for v_pair in
    (select r.codigo rule_code,r.id rule_id,r.estado rule_state,p.id pantalla_id,p.codigo screen_code,p.activa screen_active
     from lf_ops.reglas r cross join lf_ops.pantallas p
     where r.estado='CANDIDATO'
       and not exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=r.id and rp.pantalla_id=p.id)
     order by r.id,p.id limit 1)
    union all
    (select r.codigo rule_code,r.id rule_id,r.estado rule_state,p.id pantalla_id,p.codigo screen_code,p.activa screen_active
     from lf_ops.reglas r cross join lf_ops.pantallas p
     where r.estado='VIGENTE'
       and not exists(select 1 from lf_ops.reglas_pantallas rp where rp.regla_id=r.id and rp.pantalla_id=p.id)
     order by r.id,p.id limit 1)
  loop
    v_test_index:=v_test_index+1;
    v_exec:='EXEC-CANARY-RULE-SCREEN-'||v_pair.rule_state||'-20260913-'||lpad(v_test_index::text,3,'0');
    v_sha:=encode(extensions.digest(convert_to(v_pair.rule_code||'@'||v_pair.pantalla_id::text,'UTF8'),'sha256'),'hex');

    perform public.fn_lf_operation_reserve_execution_v1(
      v_exec,'VINCULACION_REGLA_PANTALLA_LF','REGLA_PANTALLA_RELATION',
      v_pair.rule_code||'@'||v_pair.pantalla_id::text,
      'RULE_SCREEN_RELATION_CANARY:'||v_pair.rule_state||':'||v_test_index::text,
      v_sha,v_exec,null,null,
      jsonb_build_object('mode','RULE_SCREEN_RELATION_SANDBOX_V1','rollback_only',true,'depends_on_pr746',false,'production_allowed',false,'runtime_activation',false)
    );

    select to_jsonb(r) into v_rule from lf_ops.reglas r where r.id=v_pair.rule_id;
    select to_jsonb(p) into v_screen from lf_ops.pantallas p where p.id=v_pair.pantalla_id;

    insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id) values
      (v_exec,10,'preflight','PASS_CLEAN','RULE_SCREEN_CANARY/PRE',v_base||jsonb_build_object('ekb_refs',jsonb_build_array('GOV-010','AUD-018'),'execution_binding',v_exec),v_exec),
      (v_exec,20,'resolve_rule','PASS_CLEAN','RULE_SCREEN_CANARY/RULE',v_base||jsonb_build_object('rule_code',v_pair.rule_code,'rule_id',v_pair.rule_id,'rule_state',v_pair.rule_state),v_exec),
      (v_exec,30,'resolve_screen','PASS_CLEAN','RULE_SCREEN_CANARY/SCREEN',v_base||jsonb_build_object('pantalla_id',v_pair.pantalla_id,'screen_code',v_pair.screen_code,'screen_active',v_pair.screen_active),v_exec);

    v_result:=public.lf_regla_pantalla_link_v1(v_exec,v_pair.rule_code,v_pair.pantalla_id,'rollback canary');
    if v_result->>'result'<>'RULE_SCREEN_RELATION_CREATED' then raise exception 'LF_RULE_SCREEN_CANARY_CREATE_FAILED:%',v_result; end if;
    if coalesce((v_result->>'rule_unchanged')::boolean,false) is not true or coalesce((v_result->>'screen_unchanged')::boolean,false) is not true then
      raise exception 'LF_RULE_SCREEN_CANARY_ASSET_MUTATION:%',v_result;
    end if;

    insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id) values
      (v_exec,40,'relation_write','PASS_CLEAN','RULE_SCREEN_CANARY/WRITE',v_base||jsonb_build_object('rule_id',v_pair.rule_id,'pantalla_id',v_pair.pantalla_id,'write_result',v_result->>'result'),v_exec),
      (v_exec,50,'readback','PASS_CLEAN','RULE_SCREEN_CANARY/READ',v_base||jsonb_build_object('relation_row',v_result->'relation_row','rule_unchanged',true,'screen_unchanged',true,'no_delete',true),v_exec);

    v_replay:=public.lf_regla_pantalla_link_v1(v_exec,v_pair.rule_code,v_pair.pantalla_id,'different replay note ignored');
    if v_replay->>'result'<>'RULE_SCREEN_RELATION_ALREADY_EXISTS' then raise exception 'LF_RULE_SCREEN_CANARY_REPLAY_FAILED:%',v_replay; end if;
    select count(*) into v_relation_count from lf_ops.reglas_pantallas where regla_id=v_pair.rule_id and pantalla_id=v_pair.pantalla_id;
    if v_relation_count<>1 then raise exception 'LF_RULE_SCREEN_CANARY_IDEMPOTENCY_FAILED:%',v_relation_count; end if;
    if (select to_jsonb(r) from lf_ops.reglas r where r.id=v_pair.rule_id) is distinct from v_rule then raise exception 'LF_RULE_SCREEN_CANARY_RULE_CHANGED'; end if;
    if (select to_jsonb(p) from lf_ops.pantallas p where p.id=v_pair.pantalla_id) is distinct from v_screen then raise exception 'LF_RULE_SCREEN_CANARY_SCREEN_CHANGED'; end if;
  end loop;

  if v_test_index<>2 then raise exception 'LF_RULE_SCREEN_CANARY_STATE_COVERAGE_INCOMPLETE:%',v_test_index; end if;

  -- Missing rule must fail closed.
  v_exec:='EXEC-CANARY-RULE-SCREEN-MISSING-RULE-20260913-001';
  v_sha:=encode(extensions.digest(convert_to('NO_SUCH_RULE_CANARY@1','UTF8'),'sha256'),'hex');
  perform public.fn_lf_operation_reserve_execution_v1(v_exec,'VINCULACION_REGLA_PANTALLA_LF','REGLA_PANTALLA_RELATION','NO_SUCH_RULE_CANARY@1','RULE_SCREEN_RELATION_CANARY:MISSING_RULE',v_sha,v_exec,null,null,'{"rollback_only":true,"production_allowed":false}'::jsonb);
  begin
    perform public.lf_regla_pantalla_link_v1(v_exec,'NO_SUCH_RULE_CANARY',1,null);
    raise exception 'LF_RULE_SCREEN_CANARY_MISSING_RULE_DID_NOT_BLOCK';
  exception when others then
    v_err:=sqlerrm;
    if position('LF_RULE_SCREEN_RULE_NOT_FOUND:' in v_err)<>1 then raise; end if;
  end;

  -- Missing screen must fail closed.
  select codigo into v_err from lf_ops.reglas where estado in ('CANDIDATO','VIGENTE') order by id limit 1;
  v_exec:='EXEC-CANARY-RULE-SCREEN-MISSING-SCREEN-20260913-001';
  v_sha:=encode(extensions.digest(convert_to(v_err||'@2147483000','UTF8'),'sha256'),'hex');
  perform public.fn_lf_operation_reserve_execution_v1(v_exec,'VINCULACION_REGLA_PANTALLA_LF','REGLA_PANTALLA_RELATION',v_err||'@2147483000','RULE_SCREEN_RELATION_CANARY:MISSING_SCREEN',v_sha,v_exec,null,null,'{"rollback_only":true,"production_allowed":false}'::jsonb);
  begin
    perform public.lf_regla_pantalla_link_v1(v_exec,v_err,2147483000,null);
    raise exception 'LF_RULE_SCREEN_CANARY_MISSING_SCREEN_DID_NOT_BLOCK';
  exception when others then
    if position('LF_RULE_SCREEN_SCREEN_NOT_FOUND:' in sqlerrm)<>1 then raise; end if;
  end;
end $canary$;

rollback;

select jsonb_build_object(
  'operation_residue',(select count(*) from public.lf_operation_registry where operation_code='VINCULACION_REGLA_PANTALLA_LF'),
  'function_residue',to_regprocedure('public.lf_regla_pantalla_link_v1(text,text,integer,text)') is not null,
  'router_binding_residue',(select count(*) from public.lf_router_action_registry where operation_code='VINCULACION_REGLA_PANTALLA_LF')
) as rollback_readback;
