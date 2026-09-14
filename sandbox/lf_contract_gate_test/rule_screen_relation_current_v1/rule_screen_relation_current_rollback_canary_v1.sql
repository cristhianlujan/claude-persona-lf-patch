-- RULE_SCREEN_RELATION_CURRENT_ROLLBACK_CANARY_V1
-- Current-state regression only. No operation/bootstrap/router/contract mutation.
-- All canary writes occur inside this transaction and are rolled back.

begin;

do $preflight$
declare
  v_version text;
  v_status text;
  v_active_contract_count integer;
  v_active_contract text;
  v_router_count integer;
  v_helper text;
begin
  select version,status
    into v_version,v_status
  from public.lf_operation_registry
  where operation_code='VINCULACION_REGLA_PANTALLA_LF';

  if not found then
    raise exception 'LF_RULE_SCREEN_CURRENT_OPERATION_MISSING';
  end if;
  if v_status is distinct from 'PRODUCCION_CONTROLADA' then
    raise exception 'LF_RULE_SCREEN_CURRENT_OPERATION_STATUS_INVALID:%:%',v_version,v_status;
  end if;

  select count(*),min(contract_code)
    into v_active_contract_count,v_active_contract
  from public.lf_operation_contracts
  where operation_code='VINCULACION_REGLA_PANTALLA_LF'
    and status='ACTIVE_ENFORCEMENT';

  if v_active_contract_count<>1
     or v_active_contract is distinct from 'CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0' then
    raise exception 'LF_RULE_SCREEN_CURRENT_ACTIVE_CONTRACT_INVALID:%:%',v_active_contract_count,v_active_contract;
  end if;

  select count(*) into v_router_count
  from public.lf_router_action_registry
  where asset_type='REGLA_PANTALLA_RELATION'
    and action_code='REGLA_PANTALLA_LINK'
    and operation_code='VINCULACION_REGLA_PANTALLA_LF'
    and status='ACTIVE'
    and write_allowed=true;

  if v_router_count<>1 then
    raise exception 'LF_RULE_SCREEN_CURRENT_ROUTER_BINDING_INVALID:%',v_router_count;
  end if;

  if to_regprocedure('public.lf_regla_pantalla_link_v1(text,text,integer,text)') is null then
    raise exception 'LF_RULE_SCREEN_CURRENT_HELPER_MISSING';
  end if;

  v_helper:=lower(pg_get_functiondef('public.lf_regla_pantalla_link_v1(text,text,integer,text)'::regprocedure));
  if position('delete from lf_ops.reglas_pantallas' in v_helper)>0 then
    raise exception 'LF_RULE_SCREEN_CURRENT_DELETE_PATH_PRESENT';
  end if;
  if position('materializacion_regla_explorada_lf' in v_helper)>0
     or position('lf_rule_exploration' in v_helper)>0 then
    raise exception 'LF_RULE_SCREEN_CURRENT_RULE_EXPLORATION_COUPLING_PRESENT';
  end if;
end
$preflight$;

do $canary$
declare
  v_pair record;
  v_exec text;
  v_result jsonb;
  v_replay jsonb;
  v_rule_before jsonb;
  v_rule_after jsonb;
  v_screen_before jsonb;
  v_screen_after jsonb;
  v_count integer;
  v_index integer:=0;
  v_error text;
begin
  if exists(
    select 1 from public.lf_operation_execution
    where execution_id like 'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-%'
  ) then
    raise exception 'LF_RULE_SCREEN_CURRENT_STALE_CANARY_EXECUTION_PRESENT';
  end if;

  for v_pair in
    (select r.id rule_id,r.codigo rule_code,r.estado rule_state,
            p.id pantalla_id,p.codigo screen_code
       from lf_ops.reglas r
       cross join lf_ops.pantallas p
      where r.estado='CANDIDATO'
        and not exists(
          select 1 from lf_ops.reglas_pantallas rp
          where rp.regla_id=r.id and rp.pantalla_id=p.id
        )
      order by r.id,p.id
      limit 1)
    union all
    (select r.id rule_id,r.codigo rule_code,r.estado rule_state,
            p.id pantalla_id,p.codigo screen_code
       from lf_ops.reglas r
       cross join lf_ops.pantallas p
      where r.estado='VIGENTE'
        and not exists(
          select 1 from lf_ops.reglas_pantallas rp
          where rp.regla_id=r.id and rp.pantalla_id=p.id
        )
      order by r.id,p.id
      limit 1)
  loop
    v_index:=v_index+1;
    v_exec:='EXEC-CANARY-RULE-SCREEN-CURRENT-V1-'||v_pair.rule_state||'-'||lpad(v_index::text,3,'0');

    select to_jsonb(r) into v_rule_before
    from lf_ops.reglas r where r.id=v_pair.rule_id;
    select to_jsonb(p) into v_screen_before
    from lf_ops.pantallas p where p.id=v_pair.pantalla_id;

    insert into public.lf_operation_execution(
      execution_id,operation_code,target_type,target_code,status,manifest,
      created_by_execution_id,updated_by_execution_id
    ) values (
      v_exec,
      'VINCULACION_REGLA_PANTALLA_LF',
      'REGLA_PANTALLA_RELATION',
      v_pair.rule_code||'@'||v_pair.pantalla_id::text,
      'IN_PROGRESS',
      jsonb_build_object(
        'mode','RULE_SCREEN_RELATION_CURRENT_ROLLBACK_CANARY_V1',
        'rollback_only',true,
        'rule_state',v_pair.rule_state,
        'production_promotion',false,
        'runtime_activation',false
      ),
      v_exec,
      v_exec
    );

    v_result:=public.lf_regla_pantalla_link_v1(
      v_exec,v_pair.rule_code,v_pair.pantalla_id,'rollback-only current-state regression'
    );
    v_replay:=public.lf_regla_pantalla_link_v1(
      v_exec,v_pair.rule_code,v_pair.pantalla_id,'rollback-only current-state regression'
    );

    if v_result->>'operation_code' is distinct from 'VINCULACION_REGLA_PANTALLA_LF'
       or v_result->>'rule_state' is distinct from v_pair.rule_state
       or coalesce((v_result->>'relation_count')::integer,0)<>1 then
      raise exception 'LF_RULE_SCREEN_CURRENT_FIRST_CALL_INVALID:%',v_result;
    end if;

    if v_replay->>'result' is distinct from 'RULE_SCREEN_RELATION_ALREADY_EXISTS'
       or coalesce((v_replay->>'relation_count')::integer,0)<>1 then
      raise exception 'LF_RULE_SCREEN_CURRENT_REPLAY_INVALID:%',v_replay;
    end if;

    select count(*) into v_count
    from lf_ops.reglas_pantallas
    where regla_id=v_pair.rule_id and pantalla_id=v_pair.pantalla_id;
    if v_count<>1 then
      raise exception 'LF_RULE_SCREEN_CURRENT_CARDINALITY_INVALID:%',v_count;
    end if;

    select to_jsonb(r) into v_rule_after
    from lf_ops.reglas r where r.id=v_pair.rule_id;
    select to_jsonb(p) into v_screen_after
    from lf_ops.pantallas p where p.id=v_pair.pantalla_id;

    if v_rule_after is distinct from v_rule_before then
      raise exception 'LF_RULE_SCREEN_CURRENT_RULE_MUTATED:%',v_pair.rule_code;
    end if;
    if v_screen_after is distinct from v_screen_before then
      raise exception 'LF_RULE_SCREEN_CURRENT_SCREEN_MUTATED:%',v_pair.pantalla_id;
    end if;
  end loop;

  if v_index<>2 then
    raise exception 'LF_RULE_SCREEN_CURRENT_REQUIRED_RULE_STATES_NOT_COVERED:%',v_index;
  end if;

  -- Missing rule must fail closed under an exact execution binding.
  insert into public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,status,manifest,
    created_by_execution_id,updated_by_execution_id
  )
  select
    'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-MISSING-RULE',
    'VINCULACION_REGLA_PANTALLA_LF','REGLA_PANTALLA_RELATION',
    '__LF_RULE_SCREEN_MISSING_RULE__@'||p.id::text,'IN_PROGRESS',
    '{"mode":"RULE_SCREEN_RELATION_CURRENT_ROLLBACK_CANARY_V1","negative":"missing_rule","rollback_only":true}'::jsonb,
    'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-MISSING-RULE',
    'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-MISSING-RULE'
  from lf_ops.pantallas p order by p.id limit 1;

  begin
    perform public.lf_regla_pantalla_link_v1(
      'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-MISSING-RULE',
      '__LF_RULE_SCREEN_MISSING_RULE__',
      (select id from lf_ops.pantallas order by id limit 1),
      null
    );
    raise exception 'LF_RULE_SCREEN_CURRENT_MISSING_RULE_DID_NOT_BLOCK';
  exception when others then
    v_error:=sqlerrm;
    if v_error not like 'LF_RULE_SCREEN_RULE_NOT_FOUND:%' then
      raise exception 'LF_RULE_SCREEN_CURRENT_MISSING_RULE_WRONG_ERROR:%',v_error;
    end if;
  end;

  -- Missing screen must fail closed under an exact execution binding.
  insert into public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,status,manifest,
    created_by_execution_id,updated_by_execution_id
  )
  select
    'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-MISSING-SCREEN',
    'VINCULACION_REGLA_PANTALLA_LF','REGLA_PANTALLA_RELATION',
    r.codigo||'@-2147483648','IN_PROGRESS',
    '{"mode":"RULE_SCREEN_RELATION_CURRENT_ROLLBACK_CANARY_V1","negative":"missing_screen","rollback_only":true}'::jsonb,
    'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-MISSING-SCREEN',
    'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-MISSING-SCREEN'
  from lf_ops.reglas r
  where r.estado in ('CANDIDATO','VIGENTE')
  order by r.id limit 1;

  begin
    perform public.lf_regla_pantalla_link_v1(
      'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-MISSING-SCREEN',
      (select codigo from lf_ops.reglas where estado in ('CANDIDATO','VIGENTE') order by id limit 1),
      -2147483648,
      null
    );
    raise exception 'LF_RULE_SCREEN_CURRENT_MISSING_SCREEN_DID_NOT_BLOCK';
  exception when others then
    v_error:=sqlerrm;
    if v_error not like 'LF_RULE_SCREEN_SCREEN_NOT_FOUND:%' then
      raise exception 'LF_RULE_SCREEN_CURRENT_MISSING_SCREEN_WRONG_ERROR:%',v_error;
    end if;
  end;
end
$canary$;

rollback;

-- Post-rollback residue guard. Read-only.
do $residue$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.lf_operation_execution
  where execution_id like 'EXEC-CANARY-RULE-SCREEN-CURRENT-V1-%';
  if v_count<>0 then
    raise exception 'LF_RULE_SCREEN_CURRENT_EXECUTION_RESIDUE:%',v_count;
  end if;
end
$residue$;

select 'PASS_RULE_SCREEN_RELATION_CURRENT_ROLLBACK_CANARY_V1' as result;