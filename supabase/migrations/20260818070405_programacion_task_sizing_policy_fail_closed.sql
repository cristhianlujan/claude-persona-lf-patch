insert into programacion.gates(
  version_id, gate_codigo, fase, tipo, nombre, descripcion,
  ejecutor_componente_id, modo_verificacion, reintentos_max,
  bloqueante, evidencia_requerida, configuracion, estado
)
select
  v.id,
  'G_TASK_SIZING_MIN',
  'preparation',
  'hard',
  'Agent Task sizing calibration policy',
  'Fail-closed sizing policy. Observable task metrics and Worker execution budgets require empirical calibration; no universal numeric threshold is embedded in code.',
  null,
  'deterministic',
  0,
  true,
  true,
  jsonb_build_object(
    'threshold_status','TO_CALIBRATE',
    'required_metrics',jsonb_build_array('files_expected_count','dependency_count','platform_count','interface_count','unknown_count'),
    'required_execution_budgets',jsonb_build_array('max_attempts','max_patch_bytes','max_changed_files','max_context_bytes'),
    'no_universal_defaults',true
  ),
  'defined'
from programacion.versiones_agente v
where v.version_codigo='v0.9-roadmap-complete'
  and not exists (
    select 1 from programacion.gates g
    where g.version_id=v.id and g.gate_codigo='G_TASK_SIZING_MIN'
  );

alter table programacion.agent_tasks
  alter column max_attempts drop default,
  alter column max_attempts drop not null,
  alter column max_patch_bytes drop default,
  alter column max_patch_bytes drop not null,
  alter column max_changed_files drop default,
  alter column max_changed_files drop not null,
  alter column max_context_bytes drop default,
  alter column max_context_bytes drop not null;

create or replace function programacion.fn_guard_agent_task()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public','programacion'
as $$
declare
  v_f public.lf_functional_versions%rowtype;
  v_sup programacion.agent_tasks%rowtype;
  v_payload jsonb;
  v_digest text;
  v_dep_ids bigint[];
  v_metrics jsonb;
  v_ac text[];
  v_inv text[];
  v_neg text[];
  v_sizing_cfg jsonb;
  v_dep_count integer;
  v_max_files integer;
  v_max_deps integer;
  v_max_platforms integer;
  v_max_interfaces integer;
  v_cfg_max_attempts integer;
  v_cfg_max_patch_bytes integer;
  v_cfg_max_changed_files integer;
  v_cfg_max_context_bytes integer;
begin
  if tg_op='DELETE' then raise exception 'agent tasks are append-only'; end if;
  if tg_op='UPDATE' and old.definition_status='SEALED' then raise exception 'sealed agent task % is immutable; create a superseding task version',old.id; end if;
  if tg_op='INSERT' and new.definition_status<>'DRAFT' then raise exception 'agent task must be born DRAFT'; end if;
  if length(btrim(new.task_code))=0 or length(btrim(new.objective))=0 then raise exception 'task_code/objective required'; end if;

  select * into v_f from public.lf_functional_versions where id=new.functional_version_id;
  if v_f.id is null or v_f.status<>'SEALED' then raise exception 'agent task requires SEALED functional version'; end if;

  if not programacion.fn_p0_array_is_canonical(new.acceptance_refs,false)
     or not programacion.fn_p0_array_is_canonical(new.invariant_refs,false)
     or not programacion.fn_p0_array_is_canonical(new.negative_refs,false)
  then raise exception 'AC/INV/NEG refs must be sorted unique non-empty'; end if;

  v_ac:=programacion.fn_p0_json_codes(v_f.acceptance_criteria,'AC');
  v_inv:=programacion.fn_p0_json_codes(v_f.invariants,'INV');
  v_neg:=programacion.fn_p0_json_codes(v_f.negative_controls,'NEG');
  if exists(select 1 from unnest(new.acceptance_refs) x where not x=any(v_ac)) then raise exception 'acceptance_refs contain code outside functional version'; end if;
  if exists(select 1 from unnest(new.invariant_refs) x where not x=any(v_inv)) then raise exception 'invariant_refs contain code outside functional version'; end if;
  if exists(select 1 from unnest(new.negative_refs) x where not x=any(v_neg)) then raise exception 'negative_refs contain code outside functional version'; end if;

  if not programacion.fn_p0_path_array_is_canonical(new.context_path_patterns,false)
     or not programacion.fn_p0_path_array_is_canonical(new.write_path_patterns,false)
     or not programacion.fn_p0_path_array_is_canonical(new.protected_path_patterns,false)
     or not programacion.fn_p0_path_array_is_canonical(new.files_expected,false)
  then raise exception 'path arrays must be canonical sorted unique non-empty'; end if;
  if not programacion.fn_p0_array_is_canonical(new.platform_refs,true)
     or not programacion.fn_p0_array_is_canonical(new.interface_refs,true)
     or not programacion.fn_p0_array_is_canonical(new.unknown_refs,true)
  then raise exception 'platform/interface/unknown refs must be canonical sorted unique arrays'; end if;

  if new.supersedes_task_id is null then
    if new.task_version<>1 then raise exception 'initial task version must be 1'; end if;
  else
    select * into v_sup from programacion.agent_tasks where id=new.supersedes_task_id;
    if v_sup.id is null or v_sup.definition_status<>'SEALED' or v_sup.task_code<>new.task_code or new.task_version<>v_sup.task_version+1 then
      raise exception 'supersedes_task_id must reference previous SEALED task version with same task_code';
    end if;
    if v_sup.functional_version_id<>new.functional_version_id and v_f.supersedes_version_id is distinct from v_sup.functional_version_id then
      raise exception 'superseding task may change functional version only to its exact superseding functional version';
    end if;
  end if;

  if new.definition_status='DRAFT' then
    if new.task_sha256 is not null or new.sealed_at is not null then raise exception 'DRAFT task cannot carry seal'; end if;
  else
    if tg_op<>'UPDATE' or old.definition_status<>'DRAFT' then raise exception 'SEALED task requires DRAFT -> SEALED transition'; end if;
    if cardinality(new.unknown_refs)>0 then raise exception 'task sizing BLOCKED: unknown_refs must be resolved before seal'; end if;

    select g.configuracion into v_sizing_cfg
    from programacion.gates g
    join programacion.versiones_agente v on v.id=g.version_id
    where v.version_codigo='v0.9-roadmap-complete'
      and g.gate_codigo='G_TASK_SIZING_MIN'
      and g.estado in ('defined','active')
    order by g.id desc
    limit 1;

    if v_sizing_cfg is null
       or v_sizing_cfg->>'threshold_status'<>'CALIBRATED'
       or coalesce(v_sizing_cfg->>'max_files_expected','') !~ '^[0-9]+$'
       or coalesce(v_sizing_cfg->>'max_dependency_count','') !~ '^[0-9]+$'
       or coalesce(v_sizing_cfg->>'max_platform_count','') !~ '^[0-9]+$'
       or coalesce(v_sizing_cfg->>'max_interface_count','') !~ '^[0-9]+$'
       or coalesce(v_sizing_cfg->>'max_attempts','') !~ '^[0-9]+$'
       or coalesce(v_sizing_cfg->>'max_patch_bytes','') !~ '^[0-9]+$'
       or coalesce(v_sizing_cfg->>'max_changed_files','') !~ '^[0-9]+$'
       or coalesce(v_sizing_cfg->>'max_context_bytes','') !~ '^[0-9]+$'
    then
      raise exception 'BLOCKED_POLICY_MISSING: G_TASK_SIZING_MIN requires calibrated metrics and execution budgets';
    end if;

    v_max_files:=(v_sizing_cfg->>'max_files_expected')::integer;
    v_max_deps:=(v_sizing_cfg->>'max_dependency_count')::integer;
    v_max_platforms:=(v_sizing_cfg->>'max_platform_count')::integer;
    v_max_interfaces:=(v_sizing_cfg->>'max_interface_count')::integer;
    v_cfg_max_attempts:=(v_sizing_cfg->>'max_attempts')::integer;
    v_cfg_max_patch_bytes:=(v_sizing_cfg->>'max_patch_bytes')::integer;
    v_cfg_max_changed_files:=(v_sizing_cfg->>'max_changed_files')::integer;
    v_cfg_max_context_bytes:=(v_sizing_cfg->>'max_context_bytes')::integer;

    if v_max_files<1 or v_max_deps<0 or v_max_platforms<0 or v_max_interfaces<0
       or v_cfg_max_attempts<1 or v_cfg_max_attempts>5
       or v_cfg_max_patch_bytes<1 or v_cfg_max_patch_bytes>1000000
       or v_cfg_max_changed_files<1 or v_cfg_max_changed_files>100
       or v_cfg_max_context_bytes<1024 or v_cfg_max_context_bytes>2000000
    then
      raise exception 'BLOCKED_POLICY_MISSING: G_TASK_SIZING_MIN calibrated values are invalid';
    end if;

    select count(*) into v_dep_count from programacion.task_dependencies where task_id=new.id;
    if cardinality(new.files_expected)>v_max_files
       or v_dep_count>v_max_deps
       or cardinality(new.platform_refs)>v_max_platforms
       or cardinality(new.interface_refs)>v_max_interfaces
    then
      raise exception 'DECOMPOSE_REQUIRED: task sizing exceeds calibrated G_TASK_SIZING_MIN';
    end if;

    new.max_attempts:=v_cfg_max_attempts;
    new.max_patch_bytes:=v_cfg_max_patch_bytes;
    new.max_changed_files:=v_cfg_max_changed_files;
    new.max_context_bytes:=v_cfg_max_context_bytes;

    v_metrics:=programacion.fn_task_dag_metrics(new.functional_version_id);
    if coalesce((v_metrics->>'pure_chain')::boolean,false) then
      raise exception 'RECOMBINE_REQUIRED: pure task chain of length %',v_metrics->>'max_chain_length';
    end if;

    select coalesce(array_agg(depends_on_task_id order by depends_on_task_id),'{}'::bigint[])
      into v_dep_ids from programacion.task_dependencies where task_id=new.id;

    v_payload:=jsonb_build_object(
      'schema_version',1,
      'task_code',new.task_code,
      'task_version',new.task_version,
      'functional_version_id',new.functional_version_id,
      'functional_sha256',v_f.content_sha256,
      'supersedes_task_id',new.supersedes_task_id,
      'objective',new.objective,
      'acceptance_refs',to_jsonb(new.acceptance_refs),
      'invariant_refs',to_jsonb(new.invariant_refs),
      'negative_refs',to_jsonb(new.negative_refs),
      'context_path_patterns',to_jsonb(new.context_path_patterns),
      'write_path_patterns',to_jsonb(new.write_path_patterns),
      'protected_path_patterns',to_jsonb(new.protected_path_patterns),
      'files_expected',to_jsonb(new.files_expected),
      'platform_refs',to_jsonb(new.platform_refs),
      'interface_refs',to_jsonb(new.interface_refs),
      'unknown_refs',to_jsonb(new.unknown_refs),
      'max_attempts',new.max_attempts,
      'max_patch_bytes',new.max_patch_bytes,
      'max_changed_files',new.max_changed_files,
      'max_context_bytes',new.max_context_bytes,
      'allow_deletions',new.allow_deletions,
      'dependency_task_ids',to_jsonb(v_dep_ids)
    );
    v_digest:=programacion.fn_v09_sha256_jsonb(v_payload);
    if new.task_sha256 is not null and new.task_sha256<>v_digest then raise exception 'agent task digest mismatch'; end if;
    new.task_sha256:=v_digest;
    new.sealed_at:=coalesce(new.sealed_at,now());
  end if;
  return new;
end;
$$;

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
  v_sizing_cfg jsonb;
  v_policy_ok boolean:=false;
  v_dep_count integer;
begin
  select * into t from programacion.agent_tasks where id=p_task_id;
  if t.id is null then raise exception 'agent task % not found',p_task_id; end if;
  select * into f from public.lf_functional_versions where id=t.functional_version_id;
  select * into tc from programacion.test_contracts where task_id=t.id and status='SEALED';
  v_metrics:=programacion.fn_task_dag_metrics(t.functional_version_id);
  v_rule_authority:=programacion.fn_source_rule_authority(f.source_rule_codes);
  select count(*) into v_dep_count from programacion.task_dependencies where task_id=t.id;

  select g.configuracion into v_sizing_cfg
  from programacion.gates g
  join programacion.versiones_agente v on v.id=g.version_id
  where v.version_codigo='v0.9-roadmap-complete'
    and g.gate_codigo='G_TASK_SIZING_MIN'
    and g.estado in ('defined','active')
  order by g.id desc
  limit 1;

  v_policy_ok := v_sizing_cfg is not null
    and v_sizing_cfg->>'threshold_status'='CALIBRATED'
    and coalesce(v_sizing_cfg->>'max_files_expected','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_dependency_count','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_platform_count','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_interface_count','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_attempts','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_patch_bytes','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_changed_files','') ~ '^[0-9]+$'
    and coalesce(v_sizing_cfg->>'max_context_bytes','') ~ '^[0-9]+$';

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
  end if;

  if not v_policy_ok then
    v_ready:=false;
    v_sizing:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SIZING_POLICY_MISSING','owner_type','HUMAN_PLAN','required_action','CALIBRATE_G_TASK_SIZING_MIN','source_ref','gate://G_TASK_SIZING_MIN'));
  elsif cardinality(t.unknown_refs)=0 and (
       cardinality(t.files_expected)>(v_sizing_cfg->>'max_files_expected')::integer
       or v_dep_count>(v_sizing_cfg->>'max_dependency_count')::integer
       or cardinality(t.platform_refs)>(v_sizing_cfg->>'max_platform_count')::integer
       or cardinality(t.interface_refs)>(v_sizing_cfg->>'max_interface_count')::integer
  ) then
    v_ready:=false;
    v_sizing:='DECOMPOSE_REQUIRED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SIZING_DECOMPOSE_REQUIRED','owner_type','TASK_PREPARATION','required_action','SPLIT_OR_REDUCE_SCOPE','source_ref','agent-task://'||t.id));
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
       or not exists(select 1 from programacion.agent_tasks x where x.id=d.depends_on_task_id and x.definition_status='SEALED')
    then
      v_ready:=false;
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DEPENDENCY_TASK_NOT_CURRENT_SEALED','owner_type','TASK_PREPARATION','required_action','RESOLVE_DEPENDENCY_TASK','source_ref','agent-task://'||d.depends_on_task_id));
    end if;
    if not exists(
      select 1 from programacion.v_ejecucion_autoridad ea
      join programacion.ejecuciones ex on ex.id=ea.execution_id
      where ex.request_ref='agent-task://'||d.depends_on_task_id and ea.effective_verdict='PASS'
    ) then
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
      'dependency_count',v_dep_count,
      'platform_count',cardinality(t.platform_refs),
      'interface_count',cardinality(t.interface_refs),
      'unknown_count',cardinality(t.unknown_refs)
    ),
    'sizing_policy_status',case when v_policy_ok then 'CALIBRATED' else coalesce(v_sizing_cfg->>'threshold_status','MISSING') end,
    'dag',v_metrics,
    'source_rule_authority',v_rule_authority,
    'blockers',v_blockers,
    'waiting_on_task_ids',v_waiting
  );
end;
$$;