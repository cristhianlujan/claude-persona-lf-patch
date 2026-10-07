-- PROGRAMMING_SIMPLE_EXECUTOR_V1
-- Small executor for atomic Programming plans.
-- It reuses the canonical plan/work/checkpoint ledger but not the IG bootstrap,
-- action-spec inference, repair prepasses, or inherited PASS state.

create table if not exists programacion.programming_validation_registry (
  validation_code text primary key,
  rule_code text not null,
  rule_mode text not null check (
    rule_mode in ('BLOCKING_AUTOMATIC','HUMAN_DECISION','CHECK_ONLY')
  ),
  description text not null,
  input_contract jsonb not null default '{}'::jsonb,
  validator_handler text not null,
  pass_condition jsonb not null default '{}'::jsonb,
  fail_condition jsonb not null default '{}'::jsonb,
  deterministic boolean not null default false,
  positive_test_ref text,
  negative_test_ref text,
  version integer not null default 1 check (version > 0),
  status text not null default 'PROPOSED' check (
    status in ('PROPOSED','PROVEN','ACTIVE','RETIRED')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by text not null default 'PROGRAMMING_SIMPLE_EXECUTOR_V1',
  check (
    status <> 'ACTIVE'
    or (
      deterministic
      and nullif(btrim(validator_handler),'') is not null
      and nullif(btrim(positive_test_ref),'') is not null
      and nullif(btrim(negative_test_ref),'') is not null
      and jsonb_typeof(input_contract)='object'
      and jsonb_typeof(pass_condition)='object'
      and jsonb_typeof(fail_condition)='object'
    )
  )
);

create table if not exists programacion.programming_resolver_registry (
  resolver_code text primary key,
  validation_code text not null
    references programacion.programming_validation_registry(validation_code),
  failure_code text not null,
  resolver_handler text not null,
  preconditions jsonb not null default '{}'::jsonb,
  post_validation_code text not null
    references programacion.programming_validation_registry(validation_code),
  deterministic boolean not null default false,
  resolver_test_ref text,
  post_validation_test_ref text,
  version integer not null default 1 check (version > 0),
  status text not null default 'PROPOSED' check (
    status in ('PROPOSED','PROVEN','ACTIVE','RETIRED')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by text not null default 'PROGRAMMING_SIMPLE_EXECUTOR_V1',
  check (
    status <> 'ACTIVE'
    or (
      deterministic
      and nullif(btrim(resolver_handler),'') is not null
      and nullif(btrim(resolver_test_ref),'') is not null
      and nullif(btrim(post_validation_test_ref),'') is not null
      and jsonb_typeof(preconditions)='object'
    )
  )
);

create unique index if not exists programming_resolver_registry_one_active_family_uq
  on programacion.programming_resolver_registry(validation_code,failure_code)
  where status='ACTIVE';

create table if not exists programacion.programming_checkpoint_bindings (
  plan_code text not null,
  unit_code text not null,
  checkpoint_code text not null,
  validation_code text not null
    references programacion.programming_validation_registry(validation_code),
  failure_code text not null default 'VALIDATION_FAILED',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  created_by text not null default 'PROGRAMMING_SIMPLE_EXECUTOR_V1',
  primary key (plan_code,unit_code,checkpoint_code)
);

create table if not exists programacion.programming_simple_runs (
  id bigserial primary key,
  plan_code text not null,
  status text not null default 'RUNNING' check (
    status in ('RUNNING','COMPLETE','FAILED')
  ),
  max_lanes integer not null default 4 check (max_lanes between 1 and 16),
  actor text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  summary jsonb not null default '{}'::jsonb
);

create table if not exists programacion.programming_simple_run_units (
  id bigserial primary key,
  run_id bigint not null
    references programacion.programming_simple_runs(id) on delete cascade,
  lane_no integer not null check (lane_no > 0),
  turn_no integer not null check (turn_no > 0),
  plan_code text not null,
  unit_code text not null,
  status text not null default 'RUNNING' check (
    status in ('RUNNING','DONE','YIELDED','FAILED')
  ),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  result jsonb not null default '{}'::jsonb,
  unique (run_id,lane_no,turn_no),
  unique (run_id,unit_code)
);

create unique index if not exists programming_simple_run_units_one_active_unit_uq
  on programacion.programming_simple_run_units(plan_code,unit_code)
  where status='RUNNING';

create or replace function programacion.fn_programming_dag_validate_edges_v1(
  p_edges jsonb
)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_cycle text[];
  v_bad jsonb;
  v_edge_count integer;
begin
  if p_edges is null or jsonb_typeof(p_edges) <> 'array' then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_DAG_VALIDATION_V1',
      'valid',false,
      'reason','EDGES_ARRAY_REQUIRED'
    );
  end if;

  select e
    into v_bad
  from jsonb_array_elements(p_edges) e
  where jsonb_typeof(e) <> 'object'
     or nullif(btrim(coalesce(e->>'from','')),'') is null
     or nullif(btrim(coalesce(e->>'to','')),'') is null
  limit 1;

  if v_bad is not null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_DAG_VALIDATION_V1',
      'valid',false,
      'reason','EDGE_FROM_TO_REQUIRED',
      'edge',v_bad
    );
  end if;

  select count(*) into v_edge_count
  from jsonb_array_elements(p_edges);

  if exists (
    select 1
    from jsonb_array_elements(p_edges) e
    where e->>'from'=e->>'to'
  ) then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_DAG_VALIDATION_V1',
      'valid',false,
      'reason','SELF_DEPENDENCY'
    );
  end if;

  with recursive edges as (
    select distinct e->>'from' as src, e->>'to' as dst
    from jsonb_array_elements(p_edges) e
  ),
  walk as (
    select
      e.src as start_node,
      e.dst as current_node,
      array[e.src,e.dst]::text[] as path,
      e.dst=e.src as cycle
    from edges e

    union all

    select
      w.start_node,
      e.dst,
      w.path || e.dst,
      e.dst = any(w.path)
    from walk w
    join edges e on e.src=w.current_node
    where not w.cycle
      and cardinality(w.path) < 1000
  )
  select path
    into v_cycle
  from walk
  where cycle
  limit 1;

  if v_cycle is not null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_DAG_VALIDATION_V1',
      'valid',false,
      'reason','CIRCULAR_DEPENDENCY',
      'cycle_path',to_jsonb(v_cycle),
      'edge_count',v_edge_count
    );
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_DAG_VALIDATION_V1',
    'valid',true,
    'reason','DAG_VALID',
    'edge_count',v_edge_count
  );
end;
$function$;

create or replace function programacion.fn_programming_plan_validate_dag_v1(
  p_plan_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_external jsonb;
  v_unsupported jsonb;
  v_edges jsonb;
  v_result jsonb;
begin
  if nullif(btrim(coalesce(p_plan_code,'')),'') is null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_PLAN_DAG_V1',
      'valid',false,
      'reason','PLAN_CODE_REQUIRED'
    );
  end if;

  select jsonb_agg(jsonb_build_object(
    'unit_code',pu.unit_code,
    'dependency_work_item_id',d.depends_on_work_item_id
  ))
  into v_external
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_dependencies d
    on d.work_item_id=pu.work_item_id
   and d.relation_type='REQUIRES'
  left join programacion.engineering_plan_units dep
    on dep.plan_code=pu.plan_code
   and dep.work_item_id=d.depends_on_work_item_id
   and dep.disposition='ASSIGNED'
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED'
    and dep.id is null;

  if v_external is not null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_PLAN_DAG_V1',
      'valid',false,
      'reason','CROSS_PLAN_OR_UNMAPPED_REQUIREMENT',
      'details',v_external
    );
  end if;

  select jsonb_agg(jsonb_build_object(
    'unit_code',pu.unit_code,
    'relation_type',d.relation_type,
    'depends_on_work_item_id',d.depends_on_work_item_id
  ))
  into v_unsupported
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_dependencies d
    on d.work_item_id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED'
    and d.relation_type<>'REQUIRES';

  if v_unsupported is not null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_PLAN_DAG_V1',
      'valid',false,
      'reason','UNSUPPORTED_DEPENDENCY_RELATION',
      'supported_relation','REQUIRES',
      'details',v_unsupported
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object('from',pu.unit_code,'to',dep.unit_code)
      order by pu.unit_code,dep.unit_code
    ),
    '[]'::jsonb
  )
  into v_edges
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_dependencies d
    on d.work_item_id=pu.work_item_id
   and d.relation_type='REQUIRES'
  join programacion.engineering_plan_units dep
    on dep.plan_code=pu.plan_code
   and dep.work_item_id=d.depends_on_work_item_id
   and dep.disposition='ASSIGNED'
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED';

  v_result:=programacion.fn_programming_dag_validate_edges_v1(v_edges);

  return jsonb_build_object(
    'schema_version','PROGRAMMING_PLAN_DAG_V1',
    'plan_code',p_plan_code,
    'valid',coalesce((v_result->>'valid')::boolean,false),
    'graph',v_result
  );
end;
$function$;

create or replace function programacion.fn_programming_rule_admission_v1(
  p_validation_code text,
  p_failure_code text default 'VALIDATION_FAILED'
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','pg_catalog'
as $function$
declare
  v programacion.programming_validation_registry%rowtype;
  r programacion.programming_resolver_registry%rowtype;
  pv programacion.programming_validation_registry%rowtype;
begin
  select * into v
  from programacion.programming_validation_registry
  where validation_code=p_validation_code;

  if not found then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
      'admitted',false,
      'reason','VALIDATION_NOT_REGISTERED',
      'validation_code',p_validation_code
    );
  end if;

  if v.status<>'ACTIVE'
     or not v.deterministic
     or nullif(btrim(v.validator_handler),'') is null
     or nullif(btrim(coalesce(v.positive_test_ref,'')),'') is null
     or nullif(btrim(coalesce(v.negative_test_ref,'')),'') is null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
      'admitted',false,
      'reason','VALIDATION_NOT_ACTIVE_PROVEN_DETERMINISTIC',
      'validation_code',v.validation_code,
      'validation_status',v.status,
      'deterministic',v.deterministic
    );
  end if;

  if v.rule_mode='BLOCKING_AUTOMATIC' then
    select * into r
    from programacion.programming_resolver_registry
    where validation_code=v.validation_code
      and failure_code=p_failure_code
      and status='ACTIVE';

    if not found then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
        'admitted',false,
        'reason','ACTIVE_RESOLVER_REQUIRED',
        'validation_code',v.validation_code,
        'failure_code',p_failure_code
      );
    end if;

    if not r.deterministic
       or nullif(btrim(r.resolver_handler),'') is null
       or nullif(btrim(coalesce(r.resolver_test_ref,'')),'') is null
       or nullif(btrim(coalesce(r.post_validation_test_ref,'')),'') is null then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
        'admitted',false,
        'reason','RESOLVER_NOT_PROVEN_DETERMINISTIC',
        'resolver_code',r.resolver_code
      );
    end if;

    select * into pv
    from programacion.programming_validation_registry
    where validation_code=r.post_validation_code;

    if not found
       or pv.status<>'ACTIVE'
       or not pv.deterministic
       or nullif(btrim(coalesce(pv.positive_test_ref,'')),'') is null
       or nullif(btrim(coalesce(pv.negative_test_ref,'')),'') is null then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
        'admitted',false,
        'reason','POST_VALIDATION_NOT_ACTIVE_PROVEN',
        'post_validation_code',r.post_validation_code
      );
    end if;

    return jsonb_build_object(
      'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
      'admitted',true,
      'validation_code',v.validation_code,
      'rule_code',v.rule_code,
      'rule_mode',v.rule_mode,
      'validator_handler',v.validator_handler,
      'resolver',jsonb_build_object(
        'resolver_code',r.resolver_code,
        'resolver_handler',r.resolver_handler,
        'preconditions',r.preconditions,
        'post_validation_code',r.post_validation_code
      ),
      'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
    );
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_RULE_ADMISSION_V1',
    'admitted',true,
    'validation_code',v.validation_code,
    'rule_code',v.rule_code,
    'rule_mode',v.rule_mode,
    'validator_handler',v.validator_handler,
    'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
  );
end;
$function$;

create or replace function programacion.fn_programming_simple_plan_admission_v1(
  p_plan_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_dag jsonb;
  v_missing jsonb;
  v_orphan jsonb;
  v_check_only jsonb;
  v_invalid_rules jsonb:='[]'::jsonb;
  x record;
  a jsonb;
begin
  v_dag:=programacion.fn_programming_plan_validate_dag_v1(p_plan_code);

  if not coalesce((v_dag->>'valid')::boolean,false) then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_PLAN_ADMISSION_V1',
      'admitted',false,
      'reason','DEPENDENCY_GRAPH_REJECTED',
      'dag',v_dag
    );
  end if;

  select jsonb_agg(jsonb_build_object(
    'unit_code',pu.unit_code,
    'checkpoint_code',c.checkpoint_code
  ))
  into v_missing
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c
    on c.work_item_id=pu.work_item_id
   and c.required
  left join programacion.programming_checkpoint_bindings b
    on b.plan_code=pu.plan_code
   and b.unit_code=pu.unit_code
   and b.checkpoint_code=c.checkpoint_code
   and b.enabled
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED'
    and b.validation_code is null;

  if v_missing is not null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_PLAN_ADMISSION_V1',
      'admitted',false,
      'reason','REQUIRED_CHECKPOINT_WITHOUT_VALIDATION_BINDING',
      'details',v_missing
    );
  end if;

  select jsonb_agg(jsonb_build_object(
    'unit_code',b.unit_code,
    'checkpoint_code',b.checkpoint_code,
    'validation_code',b.validation_code
  ))
  into v_orphan
  from programacion.programming_checkpoint_bindings b
  left join programacion.engineering_plan_units pu
    on pu.plan_code=b.plan_code
   and pu.unit_code=b.unit_code
   and pu.disposition='ASSIGNED'
  left join programacion.engineering_work_checkpoints c
    on c.work_item_id=pu.work_item_id
   and c.checkpoint_code=b.checkpoint_code
  where b.plan_code=p_plan_code
    and b.enabled
    and (pu.id is null or c.id is null);

  if v_orphan is not null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_PLAN_ADMISSION_V1',
      'admitted',false,
      'reason','ORPHAN_CHECKPOINT_BINDING',
      'details',v_orphan
    );
  end if;

  select jsonb_agg(jsonb_build_object(
    'unit_code',b.unit_code,
    'checkpoint_code',b.checkpoint_code,
    'validation_code',b.validation_code
  ))
  into v_check_only
  from programacion.programming_checkpoint_bindings b
  join programacion.engineering_plan_units pu
    on pu.plan_code=b.plan_code
   and pu.unit_code=b.unit_code
   and pu.disposition='ASSIGNED'
  join programacion.engineering_work_checkpoints c
    on c.work_item_id=pu.work_item_id
   and c.checkpoint_code=b.checkpoint_code
   and c.required
  join programacion.programming_validation_registry v
    on v.validation_code=b.validation_code
  where b.plan_code=p_plan_code
    and b.enabled
    and v.rule_mode='CHECK_ONLY';

  if v_check_only is not null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_PLAN_ADMISSION_V1',
      'admitted',false,
      'reason','CHECK_ONLY_CANNOT_BACK_REQUIRED_CHECKPOINT',
      'details',v_check_only
    );
  end if;

  for x in
    select distinct b.validation_code,b.failure_code
    from programacion.programming_checkpoint_bindings b
    where b.plan_code=p_plan_code
      and b.enabled
  loop
    a:=programacion.fn_programming_rule_admission_v1(
      x.validation_code,x.failure_code
    );
    if not coalesce((a->>'admitted')::boolean,false) then
      v_invalid_rules:=v_invalid_rules || jsonb_build_array(a);
    end if;
  end loop;

  if jsonb_array_length(v_invalid_rules)>0 then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_PLAN_ADMISSION_V1',
      'admitted',false,
      'reason','RULE_ADMISSION_FAILED',
      'details',v_invalid_rules
    );
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_SIMPLE_PLAN_ADMISSION_V1',
    'admitted',true,
    'plan_code',p_plan_code,
    'dag',v_dag,
    'policy',jsonb_build_object(
      'dependency_relation','REQUIRES_ONLY',
      'cross_plan_dependencies','FORBIDDEN',
      'historical_pass_reuse','FORBIDDEN',
      'resolver_can_close_checkpoint',false
    )
  );
end;
$function$;

create or replace function programacion.fn_programming_simple_ready_units_v1(
  p_plan_code text,
  p_limit integer default 4
)
returns table(
  unit_code text,
  work_item_id bigint,
  priority text
)
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  a jsonb;
begin
  a:=programacion.fn_programming_simple_plan_admission_v1(p_plan_code);
  if not coalesce((a->>'admitted')::boolean,false) then
    raise exception 'PROGRAMMING_SIMPLE_PLAN_NOT_ADMITTED:%',a::text;
  end if;

  return query
  select pu.unit_code,w.id,w.priority
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED'
    and w.status in ('BACKLOG','READY','IN_PROGRESS')
    and not exists (
      select 1
      from programacion.engineering_work_dependencies d
      join programacion.engineering_plan_units dep
        on dep.plan_code=pu.plan_code
       and dep.work_item_id=d.depends_on_work_item_id
      join programacion.engineering_work_items dw
        on dw.id=dep.work_item_id
      where d.work_item_id=w.id
        and d.relation_type='REQUIRES'
        and dw.status<>'DONE'
    )
    and not exists (
      select 1
      from programacion.programming_simple_run_units ru
      where ru.plan_code=p_plan_code
        and ru.unit_code=pu.unit_code
        and ru.status='RUNNING'
    )
  order by
    case w.priority
      when 'P0' then 0
      when 'P1' then 1
      when 'P2' then 2
      when 'P3' then 3
      else 9
    end,
    pu.id
  limit greatest(1,least(coalesce(p_limit,4),16));
end;
$function$;

create or replace function programacion.fn_programming_simple_unit_bootstrap_v1(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_work_status text;
  c record;
  b programacion.programming_checkpoint_bindings%rowtype;
  a jsonb;
  r jsonb;
begin
  select pu.work_item_id,w.status
    into v_work_item_id,v_work_status
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'terminal_action','STOP_UNIT_NOT_FOUND'
    );
  end if;

  if v_work_status='DONE' then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'terminal_action','UNIT_DONE'
    );
  end if;

  select *
    into c
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_item_id
    and required
    and status not in ('DONE','NOT_APPLICABLE')
  order by sequence_no
  limit 1;

  if not found then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'plan_code',p_plan_code,
      'unit_code',p_unit_code,
      'terminal_action','UNIT_CLOSE_REQUIRED',
      'reason','NO_OPEN_REQUIRED_CHECKPOINTS'
    );
  end if;

  select *
    into b
  from programacion.programming_checkpoint_bindings
  where plan_code=p_plan_code
    and unit_code=p_unit_code
    and checkpoint_code=c.checkpoint_code
    and enabled;

  if not found then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'terminal_action','STOP_RULE_NOT_ADMISSIBLE',
      'reason','CHECKPOINT_BINDING_MISSING',
      'checkpoint_code',c.checkpoint_code
    );
  end if;

  a:=programacion.fn_programming_rule_admission_v1(
    b.validation_code,b.failure_code
  );

  if not coalesce((a->>'admitted')::boolean,false) then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
      'terminal_action','STOP_RULE_NOT_ADMISSIBLE',
      'checkpoint_code',c.checkpoint_code,
      'rule_admission',a
    );
  end if;

  r:=c.assertion_receipt;

  if jsonb_typeof(r)='object'
     and r->>'schema_version'='PROGRAMMING_VALIDATION_RECEIPT_V1'
     and r->>'validation_code'=b.validation_code
     and r->>'checkpoint_code'=c.checkpoint_code
     and r->>'unit_code'=p_unit_code
     and r->>'plan_code'=p_plan_code
     and nullif(r->>'run_id','')::bigint=p_run_id then

    if r->>'result'='PASS' then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',c.checkpoint_code,
        'terminal_action','TRANSITION_CURRENT_CHECKPOINT',
        'validation_code',b.validation_code,
        'validation_receipt',r,
        'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
      );
    end if;

    if r->>'result'='FAIL'
       and a->>'rule_mode'='BLOCKING_AUTOMATIC' then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',c.checkpoint_code,
        'terminal_action','RESOLVE_CURRENT_CHECKPOINT',
        'validation_code',b.validation_code,
        'resolver',a->'resolver',
        'validation_receipt',r,
        'post_condition','RERUN_VALIDATOR; RESOLVER_NEVER_GRANTS_PASS'
      );
    end if;

    if r->>'result'='FAIL'
       and a->>'rule_mode'='HUMAN_DECISION' then
      return jsonb_build_object(
        'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
        'plan_code',p_plan_code,
        'unit_code',p_unit_code,
        'checkpoint_code',c.checkpoint_code,
        'terminal_action','HUMAN_DECISION_REQUIRED',
        'validation_code',b.validation_code,
        'validation_receipt',r
      );
    end if;
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_SIMPLE_UNIT_BOOTSTRAP_V1',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',c.checkpoint_code,
    'checkpoint_title',c.title,
    'terminal_action','VALIDATE_CURRENT_CHECKPOINT',
    'validation_code',b.validation_code,
    'failure_code',b.failure_code,
    'validator_handler',a->>'validator_handler',
    'rule_mode',a->>'rule_mode',
    'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
  );
end;
$function$;

create or replace function programacion.fn_programming_validation_record_v1(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_validation_code text,
  p_result text,
  p_evidence_ref text,
  p_actor text default 'PROGRAMMING_SIMPLE_EXECUTOR_V1',
  p_detail jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','extensions','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_current text;
  b programacion.programming_checkpoint_bindings%rowtype;
  a jsonb;
  v_receipt jsonb;
  v_sha text;
begin
  if p_result not in ('PASS','FAIL') then
    raise exception 'PROGRAMMING_VALIDATION_RESULT_UNSUPPORTED:%',p_result;
  end if;

  if nullif(btrim(coalesce(p_evidence_ref,'')),'') is null then
    raise exception 'PROGRAMMING_VALIDATION_EVIDENCE_REQUIRED';
  end if;

  if not exists (
    select 1
    from programacion.programming_simple_run_units ru
    where ru.run_id=p_run_id
      and ru.plan_code=p_plan_code
      and ru.unit_code=p_unit_code
      and ru.status='RUNNING'
  ) then
    raise exception 'PROGRAMMING_VALIDATION_ACTIVE_RUN_UNIT_REQUIRED';
  end if;

  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  select c.checkpoint_code into v_current
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current is distinct from p_checkpoint_code then
    raise exception 'PROGRAMMING_VALIDATION_NOT_CURRENT:% current=%',
      p_checkpoint_code,coalesce(v_current,'(none)');
  end if;

  select * into b
  from programacion.programming_checkpoint_bindings
  where plan_code=p_plan_code
    and unit_code=p_unit_code
    and checkpoint_code=p_checkpoint_code
    and enabled;

  if not found or b.validation_code<>p_validation_code then
    raise exception 'PROGRAMMING_VALIDATION_BINDING_MISMATCH';
  end if;

  a:=programacion.fn_programming_rule_admission_v1(
    b.validation_code,b.failure_code
  );

  if not coalesce((a->>'admitted')::boolean,false) then
    raise exception 'PROGRAMMING_RULE_NOT_ADMITTED:%',a::text;
  end if;

  v_receipt:=jsonb_build_object(
    'schema_version','PROGRAMMING_VALIDATION_RECEIPT_V1',
    'run_id',p_run_id,
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',p_checkpoint_code,
    'validation_code',p_validation_code,
    'result',p_result,
    'evidence_ref',p_evidence_ref,
    'detail',coalesce(p_detail,'{}'::jsonb),
    'observed_at',now(),
    'actor',coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1'),
    'historical_pass_reused',false
  );

  v_sha:=encode(
    extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),
    'hex'
  );

  update programacion.engineering_work_checkpoints
     set status='IN_PROGRESS',
         assertion_receipt=v_receipt,
         assertion_receipt_sha256=v_sha,
         assertion_recorded_at=now(),
         assertion_recorded_by=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1'),
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
   where work_item_id=v_work_item_id
     and checkpoint_code=p_checkpoint_code;

  update programacion.engineering_work_items
     set status='IN_PROGRESS',
         started_at=coalesce(started_at,now()),
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
   where id=v_work_item_id
     and status not in ('DONE','CANCELLED');

  return programacion.fn_programming_simple_unit_bootstrap_v1(
    p_run_id,p_plan_code,p_unit_code
  ) || jsonb_build_object(
    'validation_recorded',true,
    'validation_result',p_result,
    'receipt_sha256',v_sha
  );
end;
$function$;

create or replace function programacion.fn_programming_simple_checkpoint_transition_v1(
  p_run_id bigint,
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_actor text default 'PROGRAMMING_SIMPLE_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_current text;
  v_remaining integer;
  b programacion.programming_checkpoint_bindings%rowtype;
  r jsonb;
begin
  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  select c.checkpoint_code into v_current
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no
  limit 1;

  if v_current is distinct from p_checkpoint_code then
    raise exception 'PROGRAMMING_TRANSITION_NOT_CURRENT:% current=%',
      p_checkpoint_code,coalesce(v_current,'(none)');
  end if;

  select * into b
  from programacion.programming_checkpoint_bindings
  where plan_code=p_plan_code
    and unit_code=p_unit_code
    and checkpoint_code=p_checkpoint_code
    and enabled;

  select assertion_receipt into r
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_item_id
    and checkpoint_code=p_checkpoint_code
  for update;

  if jsonb_typeof(r)<>'object'
     or r->>'schema_version'<>'PROGRAMMING_VALIDATION_RECEIPT_V1'
     or r->>'result'<>'PASS'
     or r->>'validation_code'<>b.validation_code
     or r->>'checkpoint_code'<>p_checkpoint_code
     or r->>'unit_code'<>p_unit_code
     or r->>'plan_code'<>p_plan_code
     or nullif(r->>'run_id','')::bigint is distinct from p_run_id then
    raise exception 'PROGRAMMING_TRANSITION_CURRENT_PASS_REQUIRED';
  end if;

  update programacion.engineering_work_checkpoints
     set status='DONE',
         evidence_ref=coalesce(nullif(r->>'evidence_ref',''),evidence_ref),
         completed_at=coalesce(completed_at,now()),
         updated_at=now(),
         updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
   where work_item_id=v_work_item_id
     and checkpoint_code=p_checkpoint_code;

  select count(*) into v_remaining
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_item_id
    and required
    and status not in ('DONE','NOT_APPLICABLE');

  if v_remaining=0 then
    update programacion.engineering_work_items
       set status='DONE',
           completed_at=coalesce(completed_at,now()),
           started_at=coalesce(started_at,now()),
           updated_at=now(),
           updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
     where id=v_work_item_id
       and status<>'CANCELLED';
  end if;

  return programacion.fn_programming_simple_unit_bootstrap_v1(
    p_run_id,p_plan_code,p_unit_code
  ) || jsonb_build_object(
    'transition',jsonb_build_object(
      'status','APPLIED',
      'checkpoint_code',p_checkpoint_code,
      'new_status','DONE',
      'remaining_required_checkpoints',v_remaining
    )
  );
end;
$function$;

create or replace function programacion.fn_programming_simple_executor_start_v1(
  p_plan_code text,
  p_max_lanes integer default 4,
  p_actor text default 'PROGRAMMING_SIMPLE_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  a jsonb;
  v_run_id bigint;
  v_lane integer:=0;
  u record;
  v_units jsonb:='[]'::jsonb;
  v_limit integer:=greatest(1,least(coalesce(p_max_lanes,4),16));
begin
  a:=programacion.fn_programming_simple_plan_admission_v1(p_plan_code);

  if not coalesce((a->>'admitted')::boolean,false) then
    return jsonb_build_object(
      'schema_version','PROGRAMMING_SIMPLE_EXECUTOR_V1',
      'status','PLAN_NOT_ADMITTED',
      'plan_code',p_plan_code,
      'admission',a
    );
  end if;

  insert into programacion.programming_simple_runs(
    plan_code,status,max_lanes,actor
  ) values (
    p_plan_code,'RUNNING',v_limit,
    coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
  )
  returning id into v_run_id;

  for u in
    select pu.unit_code,w.id as work_item_id,w.priority
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code=p_plan_code
      and pu.disposition='ASSIGNED'
      and w.status in ('BACKLOG','READY','IN_PROGRESS')
      and not exists (
        select 1
        from programacion.engineering_work_dependencies d
        join programacion.engineering_plan_units dep
          on dep.plan_code=pu.plan_code
         and dep.work_item_id=d.depends_on_work_item_id
        join programacion.engineering_work_items dw
          on dw.id=dep.work_item_id
        where d.work_item_id=w.id
          and d.relation_type='REQUIRES'
          and dw.status<>'DONE'
      )
      and not exists (
        select 1
        from programacion.programming_simple_run_units ru
        where ru.plan_code=p_plan_code
          and ru.unit_code=pu.unit_code
          and ru.status='RUNNING'
      )
    order by
      case w.priority
        when 'P0' then 0
        when 'P1' then 1
        when 'P2' then 2
        when 'P3' then 3
        else 9
      end,
      pu.id
    for update of w skip locked
    limit v_limit
  loop
    v_lane:=v_lane+1;

    insert into programacion.programming_simple_run_units(
      run_id,lane_no,turn_no,plan_code,unit_code,status
    ) values (
      v_run_id,v_lane,1,p_plan_code,u.unit_code,'RUNNING'
    );

    update programacion.engineering_work_items
       set status='IN_PROGRESS',
           started_at=coalesce(started_at,now()),
           updated_at=now(),
           updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
     where id=u.work_item_id
       and status not in ('DONE','CANCELLED');

    v_units:=v_units||jsonb_build_array(
      jsonb_build_object(
        'lane_no',v_lane,
        'turn_no',1,
        'unit_code',u.unit_code,
        'bootstrap',programacion.fn_programming_simple_unit_bootstrap_v1(
          v_run_id,p_plan_code,u.unit_code
        )
      )
    );
  end loop;

  if v_lane=0 then
    update programacion.programming_simple_runs
       set status='COMPLETE',
           finished_at=now(),
           summary=jsonb_build_object('reason','NO_READY_UNITS')
     where id=v_run_id;
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_SIMPLE_EXECUTOR_V1',
    'status',case when v_lane=0 then 'COMPLETE' else 'RUNNING' end,
    'run_id',v_run_id,
    'plan_code',p_plan_code,
    'max_lanes',v_limit,
    'active_lanes',v_lane,
    'units',v_units,
    'execution_scope','UNIT_TO_TERMINAL_OR_LOCAL_YIELD',
    'dependency_policy','SAME_PLAN_REQUIRES_DAG_ONLY',
    'reuse_policy','REUSE_PROCEDURE_NOT_PASS'
  );
end;
$function$;

create or replace function programacion.fn_programming_simple_executor_complete_and_refill_v1(
  p_run_id bigint,
  p_unit_code text,
  p_outcome text,
  p_result jsonb default '{}'::jsonb,
  p_actor text default 'PROGRAMMING_SIMPLE_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_run programacion.programming_simple_runs%rowtype;
  v_lane programacion.programming_simple_run_units%rowtype;
  v_turn integer;
  u record;
  v_work_status text;
  v_refill jsonb;
  v_running integer;
begin
  if p_outcome not in ('DONE','YIELDED','FAILED') then
    raise exception 'PROGRAMMING_SIMPLE_OUTCOME_UNSUPPORTED:%',p_outcome;
  end if;

  select * into v_run
  from programacion.programming_simple_runs
  where id=p_run_id
  for update;

  if not found or v_run.status<>'RUNNING' then
    raise exception 'PROGRAMMING_SIMPLE_RUNNING_RUN_REQUIRED';
  end if;

  select * into v_lane
  from programacion.programming_simple_run_units
  where run_id=p_run_id
    and unit_code=p_unit_code
    and status='RUNNING'
  for update;

  if not found then
    raise exception 'PROGRAMMING_SIMPLE_RUNNING_UNIT_REQUIRED';
  end if;

  select w.status into v_work_status
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=v_run.plan_code
    and pu.unit_code=p_unit_code;

  if p_outcome='DONE' and v_work_status<>'DONE' then
    raise exception 'PROGRAMMING_SIMPLE_UNIT_NOT_DONE:% status=%',
      p_unit_code,coalesce(v_work_status,'(missing)');
  end if;

  update programacion.programming_simple_run_units
     set status=p_outcome,
         finished_at=now(),
         result=coalesce(p_result,'{}'::jsonb)
   where id=v_lane.id;

  if p_outcome in ('YIELDED','FAILED') then
    update programacion.engineering_work_items w
       set status='BLOCKED',
           updated_at=now(),
           updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
      from programacion.engineering_plan_units pu
     where pu.plan_code=v_run.plan_code
       and pu.unit_code=p_unit_code
       and pu.work_item_id=w.id
       and w.status not in ('DONE','CANCELLED');
  end if;

  select coalesce(max(turn_no),0)+1
    into v_turn
  from programacion.programming_simple_run_units
  where run_id=p_run_id
    and lane_no=v_lane.lane_no;

  select pu.unit_code,w.id as work_item_id,w.priority
    into u
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=v_run.plan_code
    and pu.disposition='ASSIGNED'
    and w.status in ('BACKLOG','READY','IN_PROGRESS')
    and not exists (
      select 1
      from programacion.engineering_work_dependencies d
      join programacion.engineering_plan_units dep
        on dep.plan_code=pu.plan_code
       and dep.work_item_id=d.depends_on_work_item_id
      join programacion.engineering_work_items dw
        on dw.id=dep.work_item_id
      where d.work_item_id=w.id
        and d.relation_type='REQUIRES'
        and dw.status<>'DONE'
    )
    and not exists (
      select 1
      from programacion.programming_simple_run_units ru
      where ru.plan_code=v_run.plan_code
        and ru.unit_code=pu.unit_code
        and ru.status='RUNNING'
    )
    and not exists (
      select 1
      from programacion.programming_simple_run_units ru
      where ru.run_id=p_run_id
        and ru.unit_code=pu.unit_code
    )
  order by
    case w.priority
      when 'P0' then 0
      when 'P1' then 1
      when 'P2' then 2
      when 'P3' then 3
      else 9
    end,
    pu.id
  for update of w skip locked
  limit 1;

  if found then
    insert into programacion.programming_simple_run_units(
      run_id,lane_no,turn_no,plan_code,unit_code,status
    ) values (
      p_run_id,v_lane.lane_no,v_turn,v_run.plan_code,u.unit_code,'RUNNING'
    );

    update programacion.engineering_work_items
       set status='IN_PROGRESS',
           started_at=coalesce(started_at,now()),
           updated_at=now(),
           updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
     where id=u.work_item_id
       and status not in ('DONE','CANCELLED');

    v_refill:=jsonb_build_object(
      'lane_no',v_lane.lane_no,
      'turn_no',v_turn,
      'unit_code',u.unit_code,
      'bootstrap',programacion.fn_programming_simple_unit_bootstrap_v1(
        p_run_id,v_run.plan_code,u.unit_code
      )
    );
  end if;

  select count(*) into v_running
  from programacion.programming_simple_run_units
  where run_id=p_run_id
    and status='RUNNING';

  if v_running=0 and v_refill is null then
    update programacion.programming_simple_runs
       set status='COMPLETE',
           finished_at=now(),
           summary=summary||jsonb_build_object(
             'reason','NO_MORE_READY_UNITS',
             'completed_at',now()
           )
     where id=p_run_id;
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_SIMPLE_EXECUTOR_REFILL_V1',
    'run_id',p_run_id,
    'completed_unit',p_unit_code,
    'outcome',p_outcome,
    'refill',v_refill,
    'run_status',case
      when v_running=0 and v_refill is null then 'COMPLETE'
      else 'RUNNING'
    end
  );
end;
$function$;

create or replace function programacion.fn_programming_simple_executor_status_v1(
  p_run_id bigint
)
returns jsonb
language sql
stable
set search_path to 'programacion','pg_catalog'
as $function$
select jsonb_build_object(
  'schema_version','PROGRAMMING_SIMPLE_EXECUTOR_STATUS_V1',
  'run_id',r.id,
  'plan_code',r.plan_code,
  'status',r.status,
  'max_lanes',r.max_lanes,
  'started_at',r.started_at,
  'finished_at',r.finished_at,
  'summary',r.summary,
  'units',coalesce((
    select jsonb_agg(jsonb_build_object(
      'lane_no',u.lane_no,
      'turn_no',u.turn_no,
      'unit_code',u.unit_code,
      'status',u.status,
      'started_at',u.started_at,
      'finished_at',u.finished_at,
      'result',u.result
    ) order by u.lane_no,u.turn_no)
    from programacion.programming_simple_run_units u
    where u.run_id=r.id
  ),'[]'::jsonb)
)
from programacion.programming_simple_runs r
where r.id=p_run_id;
$function$;

comment on table programacion.programming_validation_registry is
'PROGRAMMING_SIMPLE_EXECUTOR_V1 validation registry. ACTIVE means deterministic and backed by positive+negative proof; historical PASS never satisfies a current checkpoint.';

comment on table programacion.programming_resolver_registry is
'PROGRAMMING_SIMPLE_EXECUTOR_V1 resolver registry. Resolver repairs a validation FAIL but never grants PASS; the validator/post-validator must execute again.';

comment on table programacion.programming_checkpoint_bindings is
'Explicit checkpoint->validation binding for Programming simple plans. No title inference.';

comment on function programacion.fn_programming_plan_validate_dag_v1(text) is
'Validates that a Programming simple plan uses same-plan REQUIRES-only dependencies and contains no cycle.';

comment on function programacion.fn_programming_rule_admission_v1(text,text) is
'Admits a rule only when validation is ACTIVE/proven/deterministic; automatic blocking rules additionally require an ACTIVE/proven/deterministic resolver and post-validator.';

comment on function programacion.fn_programming_simple_executor_start_v1(text,integer,text) is
'Starts PROGRAMMING_SIMPLE_EXECUTOR_V1 with configurable lanes after plan admission. A lane owns one unit to terminal/local yield; checkpoint count is never a run cap.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values (
  'PROGRAMMING-SIMPLE-EXECUTOR-RULE-ADMISSION-001',
  'PROGRAMMING_GOVERNANCE',
  'Programming rules require deterministic proven validation and coupled resolution before automatic blocking',
  'A programming plan must not inherit controls merely because they exist elsewhere. Required checkpoints bind explicitly to admitted validators. Existing validators/resolvers may be reused as procedures, but historical PASS is never reused as current evidence.',
  'Over-broad plans and inherited controls can convert unrelated historical gaps into runtime blockers and can leave declared controls without executable resolution.',
  'RULE -> CURRENT VALIDATION -> PASS or FAIL -> COUPLED RESOLVER -> CURRENT POST-VALIDATION. Resolver cannot close the checkpoint.',
  'Use PROGRAMMING_SIMPLE_EXECUTOR_V1 admission. Reject circular/cross-plan dependencies. Admit BLOCKING_AUTOMATIC only when validator, resolver and post-validation are deterministic and proven. Reuse procedure, never PASS.',
  'fn_programming_dag_validate_edges_v1 rejects A->B->A; fn_programming_rule_admission_v1 requires ACTIVE proof and resolver for automatic blockers; checkpoint transition requires a PASS receipt tied to the current run/unit/checkpoint.',
  'HIGH',
  'ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/docs/programming/PROGRAMMING_SIMPLE_EXECUTOR_V1.md',
  now()
)
on conflict (codigo) do update
set titulo=excluded.titulo,
    descripcion=excluded.descripcion,
    causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,
    prevencion=excluded.prevencion,
    validacion=excluded.validacion,
    severidad=excluded.severidad,
    estado=excluded.estado,
    source_ref=excluded.source_ref,
    updated_at=excluded.updated_at;
