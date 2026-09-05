create or replace function public.fn_lf_operation_provenance_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_created_operation text;
  v_updated_operation text;
  v_created_status text;
  v_updated_status text;
  v_created_manifest jsonb;
  v_updated_manifest jsonb;
  v_validate_created boolean;
  v_validate_updated boolean;
  v_target_status text;
  v_created_bootstrap_allowed boolean := false;
  v_updated_bootstrap_allowed boolean := false;
begin
  if tg_op = 'UPDATE' and new.operation_code is distinct from old.operation_code then
    raise exception 'LF_OPERATION_PROVENANCE_OPERATION_CODE_IMMUTABLE:%:%', old.operation_code, new.operation_code
      using errcode = '23514';
  end if;

  v_validate_created := tg_op = 'INSERT'
    or (tg_op = 'UPDATE' and new.created_by_execution_id is distinct from old.created_by_execution_id);
  v_validate_updated := tg_op = 'INSERT'
    or (tg_op = 'UPDATE' and new.updated_by_execution_id is distinct from old.updated_by_execution_id);

  if tg_table_name = 'lf_operation_registry' then
    v_target_status := new.status;
  else
    select r.status into v_target_status
    from public.lf_operation_registry r
    where r.operation_code = new.operation_code;
  end if;

  if v_validate_created then
    if new.created_by_execution_id is null or btrim(new.created_by_execution_id) = '' or new.created_by_execution_id = 'UNKNOWN' then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_EXECUTION_REQUIRED'
        using errcode = '23514';
    end if;

    select e.operation_code,e.status,e.manifest
      into v_created_operation,v_created_status,v_created_manifest
    from public.lf_operation_execution e
    where e.execution_id = new.created_by_execution_id;

    if v_created_operation is null then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:%', new.created_by_execution_id
        using errcode = '23503';
    end if;

    v_created_bootstrap_allowed :=
      v_created_operation = 'VULNERABILITY_COVERAGE_REPAIR_LF'
      and v_created_status = 'IN_PROGRESS'
      and coalesce((v_created_manifest->>'governance_bootstrap')::boolean,false) = true
      and v_created_manifest->>'bootstrap_operation_code' = new.operation_code
      and coalesce(v_created_manifest->>'bootstrap_status_ceiling','') = 'SANDBOX_ACTIVE'
      and v_target_status in ('SANDBOX_ACTIVE','CANDIDATO_READ_ONLY');

    if v_created_operation <> new.operation_code and not v_created_bootstrap_allowed then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_SCOPE_MISMATCH:%:%:%', new.created_by_execution_id, v_created_operation, new.operation_code
        using errcode = '23514';
    end if;
  end if;

  if v_validate_updated and new.updated_by_execution_id is not null and btrim(new.updated_by_execution_id) <> '' then
    select e.operation_code,e.status,e.manifest
      into v_updated_operation,v_updated_status,v_updated_manifest
    from public.lf_operation_execution e
    where e.execution_id = new.updated_by_execution_id;

    if v_updated_operation is null then
      raise exception 'LF_OPERATION_PROVENANCE_UPDATED_EXECUTION_MISSING:%', new.updated_by_execution_id
        using errcode = '23503';
    end if;

    v_updated_bootstrap_allowed :=
      v_updated_operation = 'VULNERABILITY_COVERAGE_REPAIR_LF'
      and v_updated_status = 'IN_PROGRESS'
      and coalesce((v_updated_manifest->>'governance_bootstrap')::boolean,false) = true
      and v_updated_manifest->>'bootstrap_operation_code' = new.operation_code
      and coalesce(v_updated_manifest->>'bootstrap_status_ceiling','') = 'SANDBOX_ACTIVE'
      and v_target_status in ('SANDBOX_ACTIVE','CANDIDATO_READ_ONLY');

    if v_updated_operation <> new.operation_code and not v_updated_bootstrap_allowed then
      raise exception 'LF_OPERATION_PROVENANCE_UPDATED_SCOPE_MISMATCH:%:%:%', new.updated_by_execution_id, v_updated_operation, new.operation_code
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.fn_lf_operation_provenance_guard_v1() is
'Fail-closed provenance guard. Exact-scope execution is mandatory, except a tightly bounded VULNERABILITY_COVERAGE_REPAIR_LF IN_PROGRESS governance bootstrap may materialize one explicitly named non-production operation with status ceiling SANDBOX_ACTIVE.';