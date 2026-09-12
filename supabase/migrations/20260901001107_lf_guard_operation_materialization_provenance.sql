create or replace function public.fn_lf_operation_provenance_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_created_operation text;
  v_updated_operation text;
  v_validate_created boolean;
  v_validate_updated boolean;
begin
  if tg_op = 'UPDATE' and new.operation_code is distinct from old.operation_code then
    raise exception 'LF_OPERATION_PROVENANCE_OPERATION_CODE_IMMUTABLE:%:%', old.operation_code, new.operation_code
      using errcode = '23514';
  end if;

  v_validate_created := tg_op = 'INSERT'
    or (tg_op = 'UPDATE' and new.created_by_execution_id is distinct from old.created_by_execution_id);
  v_validate_updated := tg_op = 'INSERT'
    or (tg_op = 'UPDATE' and new.updated_by_execution_id is distinct from old.updated_by_execution_id);

  if v_validate_created then
    if new.created_by_execution_id is null or btrim(new.created_by_execution_id) = '' or new.created_by_execution_id = 'UNKNOWN' then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_EXECUTION_REQUIRED'
        using errcode = '23514';
    end if;

    select e.operation_code
      into v_created_operation
    from public.lf_operation_execution e
    where e.execution_id = new.created_by_execution_id;

    if v_created_operation is null then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:%', new.created_by_execution_id
        using errcode = '23503';
    end if;

    if v_created_operation <> new.operation_code then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_SCOPE_MISMATCH:%:%:%', new.created_by_execution_id, v_created_operation, new.operation_code
        using errcode = '23514';
    end if;
  end if;

  if v_validate_updated and new.updated_by_execution_id is not null and btrim(new.updated_by_execution_id) <> '' then
    select e.operation_code
      into v_updated_operation
    from public.lf_operation_execution e
    where e.execution_id = new.updated_by_execution_id;

    if v_updated_operation is null then
      raise exception 'LF_OPERATION_PROVENANCE_UPDATED_EXECUTION_MISSING:%', new.updated_by_execution_id
        using errcode = '23503';
    end if;

    if v_updated_operation <> new.operation_code then
      raise exception 'LF_OPERATION_PROVENANCE_UPDATED_SCOPE_MISMATCH:%:%:%', new.updated_by_execution_id, v_updated_operation, new.operation_code
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.fn_lf_operation_provenance_guard_v1() is
'Fail-closed guard for new/changed operation materialization provenance. Legacy unchanged created_by values remain readable/updatable while any newly supplied execution id must resolve to public.lf_operation_execution and match operation_code.';

do $$
declare
  v_table text;
  v_trigger text;
begin
  foreach v_table in array array[
    'lf_operation_registry',
    'lf_operation_steps',
    'lf_operation_step_contracts',
    'lf_operation_judges',
    'lf_operation_step_judge_bindings',
    'lf_operation_policy_bindings'
  ] loop
    v_trigger := 'trg_' || v_table || '_provenance_guard_v1';
    execute format('drop trigger if exists %I on public.%I', v_trigger, v_table);
    execute format(
      'create trigger %I before insert or update of operation_code, created_by_execution_id, updated_by_execution_id on public.%I for each row execute function public.fn_lf_operation_provenance_guard_v1()',
      v_trigger,
      v_table
    );
  end loop;
end;
$$;
