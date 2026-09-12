create or replace function programacion.fn_source_rule_authority(p_rule_codes text[])
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public','programacion'
as $$
declare
  v_total integer;
  v_authoritative integer;
  v_problems jsonb;
begin
  if p_rule_codes is null or cardinality(p_rule_codes)=0 then
    return jsonb_build_object(
      'authoritative', false,
      'required_statuses', jsonb_build_array('APROBADO','VIGENTE'),
      'problems', jsonb_build_array(jsonb_build_object('code','SOURCE_RULES_EMPTY'))
    );
  end if;

  with src as (
    select code as rule_code from unnest(p_rule_codes) as code
  ), evaluated as (
    select
      src.rule_code,
      r.status as rule_status,
      r.rule_set_code,
      s.status as rule_set_status,
      s.is_current,
      (
        r.rule_code is not null
        and r.status in ('APROBADO','VIGENTE')
        and s.rule_set_code is not null
        and s.is_current is true
        and s.status in ('APROBADO','VIGENTE')
      ) as ok,
      case
        when r.rule_code is null then 'RULE_NOT_FOUND'
        when r.status not in ('APROBADO','VIGENTE') then 'RULE_NOT_AUTHORIZED'
        when s.rule_set_code is null then 'RULE_SET_NOT_FOUND'
        when s.is_current is not true then 'RULE_SET_NOT_CURRENT'
        when s.status not in ('APROBADO','VIGENTE') then 'RULE_SET_NOT_AUTHORIZED'
        else null
      end as problem_code
    from src
    left join public.lf_product_rules r on r.rule_code=src.rule_code
    left join public.lf_product_rule_sets s on s.rule_set_code=r.rule_set_code
  )
  select
    count(*),
    count(*) filter(where ok),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rule_code',rule_code,
          'problem_code',problem_code,
          'rule_status',rule_status,
          'rule_set_code',rule_set_code,
          'rule_set_status',rule_set_status,
          'rule_set_current',is_current
        ) order by rule_code
      ) filter(where not ok),
      '[]'::jsonb
    )
  into v_total,v_authoritative,v_problems
  from evaluated;

  return jsonb_build_object(
    'authoritative',v_total=cardinality(p_rule_codes) and v_authoritative=v_total,
    'required_statuses',jsonb_build_array('APROBADO','VIGENTE'),
    'problems',v_problems
  );
end;
$$;

revoke all on function programacion.fn_source_rule_authority(text[]) from public,anon,authenticated;
grant execute on function programacion.fn_source_rule_authority(text[]) to programacion_builder,programacion_auditor,programacion_human_authority,programacion_verifier,service_role;

create or replace function programacion.fn_guard_functional_rule_authority()
returns trigger
language plpgsql
security invoker
set search_path to 'pg_catalog','public','programacion'
as $$
declare v_authority jsonb;
begin
  if old.status='DRAFT' and new.status='SEALED' then
    v_authority:=programacion.fn_source_rule_authority(new.source_rule_codes);
    if coalesce((v_authority->>'authoritative')::boolean,false) is not true then
      raise exception 'SOURCE_RULE_AUTHORITY_BLOCKED: %',v_authority->'problems';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function programacion.fn_guard_functional_rule_authority() from public,anon,authenticated;

drop trigger if exists trg_lf_functional_versions_00_rule_authority on public.lf_functional_versions;
create trigger trg_lf_functional_versions_00_rule_authority
before update of status on public.lf_functional_versions
for each row execute function programacion.fn_guard_functional_rule_authority();

create or replace function programacion.fn_task_readiness(p_task_id bigint)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public','programacion'
as $$
declare
  t programacion.agent_tasks%rowtype;
  f public.lf_functional_versions%rowtype;
  tc programacion.test_contracts%rowtype;
  b record;
  d record;
  v_ready boolean:=true;
  v_exec boolean:=true;
  v_sizing text:='EXECUTABLE';
  v_blockers jsonb:='[]'::jsonb;
  v_waiting jsonb:='[]'::jsonb;
  v_metrics jsonb;
  v_rule_authority jsonb;
begin
  select * into t from programacion.agent_tasks where id=p_task_id;
  if t.id is null then raise exception 'agent task % not found',p_task_id; end if;
  select * into f from public.lf_functional_versions where id=t.functional_version_id;
  select * into tc from programacion.test_contracts where task_id=t.id and status='SEALED';
  v_metrics:=programacion.fn_task_dag_metrics(t.functional_version_id);
  v_rule_authority:=programacion.fn_source_rule_authority(f.source_rule_codes);

  if exists(select 1 from programacion.agent_tasks n where n.supersedes_task_id=t.id) then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TASK_SUPERSEDED','owner_type','TASK_PREPARATION','required_action','USE_CURRENT_TASK_VERSION','source_ref','agent-task://'||t.id));
  end if;
  if f.status<>'SEALED' then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','FUNCTIONAL_VERSION_NOT_SEALED','owner_type','FUNCTIONAL_OWNER','required_action','SEAL_FUNCTIONAL_VERSION','source_ref','functional-version://'||t.functional_version_id));
  end if;
  if coalesce((v_rule_authority->>'authoritative')::boolean,false) is not true then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SOURCE_RULE_AUTHORITY_BLOCKED','owner_type','FUNCTIONAL_RULE_OWNER','required_action','PROMOTE_SOURCE_RULES_TO_APROBADO_OR_VIGENTE','source_ref','functional-version://'||t.functional_version_id,'details',v_rule_authority->'problems'));
  end if;
  if t.definition_status<>'SEALED' then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TASK_NOT_SEALED','owner_type','TASK_PREPARATION','required_action','SEAL_AGENT_TASK','source_ref','agent-task://'||t.id));
  end if;
  if tc.id is null then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','TEST_CONTRACT_NOT_SEALED','owner_type','TEST_CONTRACT_GENERATOR','required_action','GENERATE_AND_SEAL_BLIND_TEST_CONTRACT','source_ref','agent-task://'||t.id));
  end if;
  if cardinality(t.unknown_refs)>0 then
    v_ready:=false;
    v_sizing:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','UNKNOWN_SCOPE_REFS','owner_type','TASK_PREPARATION','required_action','RESOLVE_UNKNOWNS','source_ref','agent-task://'||t.id));
  elsif cardinality(t.files_expected)>t.max_changed_files then
    v_ready:=false;
    v_sizing:='REVIEW_SPLIT';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SIZING_REVIEW_SPLIT','owner_type','TASK_PREPARATION','required_action','SPLIT_OR_REDUCE_SCOPE','source_ref','agent-task://'||t.id));
  end if;
  if coalesce((v_metrics->>'task_count')::integer,0)>1 and v_metrics->>'pure_chain_policy_status'='MISSING' then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DAG_POLICY_MISSING','owner_type','HUMAN_PLAN','required_action','CALIBRATE_G_TASK_DAG_MAX_PURE_CHAIN_LENGTH','source_ref','gate://G_TASK_DAG'));
  elsif coalesce((v_metrics->>'pure_chain')::boolean,false) then
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','PURE_CHAIN_RECOMBINE_REQUIRED','owner_type','TASK_PREPARATION','required_action','RECOMBINE_TASKS','source_ref','functional-version://'||t.functional_version_id));
  end if;
  for b in select * from programacion.task_blockers where task_id=t.id and status='OPEN' loop
    v_ready:=false;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code',b.blocker_code,'owner_type',b.owner_type,'owner_ref',b.owner_ref,'required_action',b.required_action,'source_ref',b.source_ref));
  end loop;
  for d in select depends_on_task_id from programacion.task_dependencies where task_id=t.id order by depends_on_task_id loop
    if exists(select 1 from programacion.agent_tasks n where n.supersedes_task_id=d.depends_on_task_id)
       or not exists(select 1 from programacion.agent_tasks x where x.id=d.depends_on_task_id and x.definition_status='SEALED') then
      v_ready:=false;
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DEPENDENCY_TASK_NOT_CURRENT_SEALED','owner_type','TASK_PREPARATION','required_action','RESOLVE_DEPENDENCY_TASK','source_ref','agent-task://'||d.depends_on_task_id));
    end if;
    if not exists(select 1 from programacion.v_ejecucion_autoridad ea join programacion.ejecuciones ex on ex.id=ea.execution_id where ex.request_ref='agent-task://'||d.depends_on_task_id and ea.effective_verdict='PASS') then
      v_exec:=false;
      v_waiting:=v_waiting||jsonb_build_array(d.depends_on_task_id);
    end if;
  end loop;
  if not v_ready then v_exec:=false; end if;
  return jsonb_build_object(
    'task_id',t.id,
    'task_code',t.task_code,
    'task_version',t.task_version,
    'ready_for_development',v_ready,
    'executable_now',v_exec,
    'sizing',v_sizing,
    'sizing_metrics',jsonb_build_object(
      'files_expected',cardinality(t.files_expected),
      'dependency_count',(select count(*) from programacion.task_dependencies where task_id=t.id),
      'platform_count',cardinality(t.platform_refs),
      'interface_count',cardinality(t.interface_refs),
      'unknown_count',cardinality(t.unknown_refs)
    ),
    'dag',v_metrics,
    'source_rule_authority',v_rule_authority,
    'blockers',v_blockers,
    'waiting_on_task_ids',v_waiting
  );
end;
$$;