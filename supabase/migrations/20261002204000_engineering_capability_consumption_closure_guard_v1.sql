-- LF_ENGINEERING_CAPABILITY_CONSUMPTION_CLOSURE_GUARD_V1
-- owner=SUPER_ADMIN
-- scope=generic engineering work closure; no capability-specific engine
-- authority=engineering_plan_units.unit_metadata.capability_consumption_v1
-- activation=Git-first; apply only after governed migration parity/merge/apply flow

create or replace function programacion.fn_guard_engineering_capability_closure_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, programacion
as $$
declare
  v_unit record;
  v_entry jsonb;
  v_mode text;
  v_capability text;
  v_required jsonb;
  v_checkpoint text;
  v_missing text[];
begin
  -- Existing terminal rows are not retroactively re-adjudicated by unrelated updates.
  if new.status <> 'DONE' then
    return new;
  end if;
  if old.status = 'DONE' then
    return new;
  end if;

  for v_unit in
    select u.plan_code, u.unit_code, u.unit_metadata
    from programacion.engineering_plan_units u
    where u.work_item_id = new.id
  loop
    if not (coalesce(v_unit.unit_metadata, '{}'::jsonb) ? 'capability_consumption_v1') then
      continue;
    end if;

    if jsonb_typeof(v_unit.unit_metadata->'capability_consumption_v1') is distinct from 'array' then
      raise exception 'CAPABILITY_CONSUMPTION_DECLARATION_INVALID work_code=% plan=% unit=%',
        new.work_code, v_unit.plan_code, v_unit.unit_code;
    end if;

    for v_entry in
      select value
      from jsonb_array_elements(v_unit.unit_metadata->'capability_consumption_v1')
    loop
      if jsonb_typeof(v_entry) is distinct from 'object' then
        raise exception 'CAPABILITY_CONSUMPTION_ENTRY_INVALID work_code=% plan=% unit=%',
          new.work_code, v_unit.plan_code, v_unit.unit_code;
      end if;

      v_mode := upper(coalesce(v_entry->>'mode', ''));
      v_capability := btrim(coalesce(v_entry->>'capability_code', ''));

      if v_capability = '' then
        raise exception 'CAPABILITY_CONSUMPTION_CAPABILITY_MISSING work_code=% plan=% unit=%',
          new.work_code, v_unit.plan_code, v_unit.unit_code;
      end if;

      if v_mode not in ('PREFLIGHT_ONLY', 'CLOSURE_REQUIRED') then
        raise exception 'CAPABILITY_CONSUMPTION_MODE_INVALID work_code=% capability=% mode=%',
          new.work_code, v_capability, v_mode;
      end if;

      -- PREFLIGHT_ONLY can never satisfy closure and intentionally adds no terminal evidence gate.
      if v_mode = 'PREFLIGHT_ONLY' then
        if jsonb_typeof(v_entry->'closure_satisfying') is distinct from 'boolean'
           or (v_entry->>'closure_satisfying')::boolean is distinct from false then
          raise exception 'CAPABILITY_PREFLIGHT_CANNOT_SATISFY_CLOSURE work_code=% capability=%',
            new.work_code, v_capability;
        end if;
        continue;
      end if;

      -- CLOSURE_REQUIRED must be explicit and must name durable evidence checkpoints.
      if jsonb_typeof(v_entry->'closure_satisfying') is distinct from 'boolean'
         or (v_entry->>'closure_satisfying')::boolean is distinct from true then
        raise exception 'CAPABILITY_CLOSURE_DECLARATION_NOT_SATISFYING work_code=% capability=%',
          new.work_code, v_capability;
      end if;

      v_required := v_entry->'required_checkpoints';
      if jsonb_typeof(v_required) is distinct from 'array'
         or jsonb_array_length(v_required) = 0 then
        raise exception 'CAPABILITY_CLOSURE_REQUIRED_CHECKPOINTS_MISSING work_code=% capability=%',
          new.work_code, v_capability;
      end if;

      v_missing := array[]::text[];
      for v_checkpoint in select jsonb_array_elements_text(v_required)
      loop
        if btrim(coalesce(v_checkpoint, '')) = '' then
          raise exception 'CAPABILITY_CLOSURE_CHECKPOINT_CODE_INVALID work_code=% capability=%',
            new.work_code, v_capability;
        end if;

        if not exists (
          select 1
          from programacion.engineering_work_checkpoints c
          where c.work_item_id = new.id
            and c.checkpoint_code = v_checkpoint
            and c.required is true
            and c.status = 'DONE'
            and c.completed_at is not null
            and nullif(btrim(coalesce(c.evidence_ref, '')), '') is not null
        ) then
          v_missing := array_append(v_missing, v_checkpoint);
        end if;
      end loop;

      if cardinality(v_missing) > 0 then
        raise exception 'CAPABILITY_CLOSURE_REQUIRED_EVIDENCE_MISSING work_code=% capability=% missing=%',
          new.work_code, v_capability, array_to_string(v_missing, ',');
      end if;
    end loop;
  end loop;

  return new;
end;
$$;

comment on function programacion.fn_guard_engineering_capability_closure_v1() is
'Generic fail-closed guard for engineering work items. capability_consumption_v1/PREFLIGHT_ONLY never satisfies closure; CLOSURE_REQUIRED requires every declared checkpoint DONE with durable evidence_ref before transition to DONE.';

drop trigger if exists trg_engineering_capability_closure_guard_v1 on programacion.engineering_work_items;
create trigger trg_engineering_capability_closure_guard_v1
before update of status on programacion.engineering_work_items
for each row
execute function programacion.fn_guard_engineering_capability_closure_v1();
