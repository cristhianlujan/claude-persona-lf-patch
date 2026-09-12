create or replace function programacion.fn_p0_path_array_is_canonical(p_arr text[], p_allow_empty boolean default false)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, programacion
as $$
declare v text; seg text;
begin
  if not programacion.fn_p0_array_is_canonical(p_arr, p_allow_empty) then return false; end if;
  foreach v in array p_arr loop
    if octet_length(v)>1024 or v ~ '[[:cntrl:]]' or position(chr(92) in v)>0 or v ~ '^/' or v ~ '/$' or v ~ '//' then return false; end if;
    foreach seg in array string_to_array(v,'/') loop
      if seg in ('','.','..','.git') then return false; end if;
      if position('[' in seg)>0 or position(']' in seg)>0 or position('{' in seg)>0 or position('}' in seg)>0 then return false; end if;
      if position('**' in seg)>0 and seg <> '**' then return false; end if;
    end loop;
  end loop;
  return true;
end;
$$;

create or replace function programacion.fn_guard_agent_task_worker_compat()
returns trigger
language plpgsql
set search_path = pg_catalog, programacion
as $$
begin
  if new.task_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$' then
    raise exception 'task_code must be WorkerTaskSpec-compatible and <=120 chars';
  end if;
  if octet_length(new.objective)>20000 then raise exception 'task objective exceeds WorkerTaskSpec 20000-byte limit'; end if;
  return new;
end;
$$;

create trigger trg_agent_tasks_worker_compat
before insert or update on programacion.agent_tasks
for each row execute function programacion.fn_guard_agent_task_worker_compat();

create or replace function programacion.fn_agent_task_execution_bundle(p_task_id bigint, p_base_head_sha text, p_source_snapshot_sha256 text)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, programacion
as $$
declare t programacion.agent_tasks%rowtype; f public.lf_functional_versions%rowtype; tc programacion.test_contracts%rowtype; r jsonb; v_spec jsonb;
begin
  if p_base_head_sha !~ '^[0-9a-f]{40}$' or p_source_snapshot_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'invalid source identity'; end if;
  r:=programacion.fn_task_readiness(p_task_id);
  if not coalesce((r->>'ready_for_development')::boolean,false) then raise exception 'TASK_NOT_READY: %',r->'blockers'; end if;
  if not coalesce((r->>'executable_now')::boolean,false) then raise exception 'TASK_WAITING_DEPENDENCIES: %',r->'waiting_on_task_ids'; end if;
  select * into t from programacion.agent_tasks where id=p_task_id;
  select * into f from public.lf_functional_versions where id=t.functional_version_id;
  select * into tc from programacion.test_contracts where task_id=t.id and status='SEALED';
  v_spec:=jsonb_build_object(
    'schema_version',1,
    'task_id',t.task_code||'.v'||t.task_version,
    'objective',t.objective,
    'base_head_sha',p_base_head_sha,
    'source_snapshot_sha256',p_source_snapshot_sha256,
    'context_path_patterns',to_jsonb(t.context_path_patterns),
    'write_path_patterns',to_jsonb(t.write_path_patterns),
    'protected_path_patterns',to_jsonb(t.protected_path_patterns),
    'acceptance_commands',tc.visible_commands,
    'max_attempts',t.max_attempts,
    'max_patch_bytes',t.max_patch_bytes,
    'max_changed_files',t.max_changed_files,
    'max_context_bytes',t.max_context_bytes,
    'allow_deletions',t.allow_deletions
  );
  return jsonb_build_object(
    'request_ref','agent-task://'||t.id,
    'worker_task_spec',v_spec,
    'hidden_oracle_ref',tc.hidden_oracle_ref,
    'hidden_oracle_sha256',tc.hidden_oracle_sha256,
    'functional_version_sha256',f.content_sha256,
    'task_sha256',t.task_sha256,
    'test_contract_sha256',tc.contract_sha256,
    'readiness',r
  );
end;
$$;

revoke execute on function programacion.fn_guard_agent_task_worker_compat() from public, anon, authenticated;