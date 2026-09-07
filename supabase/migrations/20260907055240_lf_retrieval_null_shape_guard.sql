-- Governed by ACT-0001 -> FUNCTION/UPDATE -> ACTUALIZACION_DB_LF v0.1.
-- Canonical backlog: WORKING-CONTEXT-RETRIEVAL-NULL-SHAPE-GUARD-001 (id 113).
-- Source baseline: Supabase ledger 20260815143320_programacion_prog013_prog014_insert_integrity.
-- Source-first candidate only until governed migration apply + parity + readback.
-- Live isolated probe proved SQL NULL/type bypasses for selected_payload, required fragment fields
-- (source, record_id, title, content, score, reasons) and PASS required_sources.

create or replace function programacion.fn_guard_retrieval_run_insert()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'programacion'
as $function$
declare
  v_payload jsonb;
  v_digest text;
  v_bad integer;
begin
  perform programacion.fn_v09_assert_execution_head(new.execution_id, new.head_sha);

  if new.status not in ('PASS', 'BLOCKED') then
    raise exception 'retrieval status invalid: %', new.status;
  end if;

  if coalesce(jsonb_typeof(new.query), 'null') <> 'object'
     or coalesce(jsonb_typeof(new.selected_payload), 'null') <> 'array'
     or coalesce(jsonb_typeof(new.missing_critical_context), 'null') <> 'array'
     or coalesce(jsonb_typeof(new.filtered_counts), 'null') <> 'object' then
    raise exception 'retrieval canonical payload shape invalid';
  end if;

  select count(*) into v_bad
  from jsonb_array_elements(new.selected_payload) as f(value)
  where coalesce(jsonb_typeof(f.value), 'null') <> 'object'
     or coalesce(jsonb_typeof(f.value->'source'), 'null') <> 'string'
     or coalesce(jsonb_typeof(f.value->'record_id'), 'null') <> 'string'
     or coalesce(jsonb_typeof(f.value->'title'), 'null') <> 'string'
     or coalesce(jsonb_typeof(f.value->'content'), 'null') <> 'string'
     or coalesce(jsonb_typeof(f.value->'score'), 'null') <> 'number'
     or coalesce(jsonb_typeof(f.value->'reasons'), 'null') <> 'array'
     or coalesce(jsonb_typeof(f.value->'provenance'), 'null') <> 'object'
     or coalesce(f.value->>'content_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(f.value->'provenance'->>'snapshot_sha256','') !~ '^[0-9a-f]{64}$'
     or programacion.fn_v09_sha256_jsonb(jsonb_build_object(
          'source', f.value->'source',
          'record_id', f.value->'record_id',
          'title', f.value->'title',
          'content', f.value->'content',
          'provenance', f.value->'provenance'
        )) <> f.value->>'content_sha256';

  if v_bad <> 0 then
    raise exception 'retrieval selected payload contains % invalid fragment(s)', v_bad;
  end if;

  if exists (
    select 1
    from (
      select f.value->>'source' source, f.value->>'record_id' record_id, count(*) c
      from jsonb_array_elements(new.selected_payload) f(value)
      group by 1,2
      having count(*) > 1
    ) d
  ) then
    raise exception 'retrieval selected payload contains duplicate source/record_id';
  end if;

  v_payload := jsonb_build_object(
    'schema_version', 1,
    'status', new.status,
    'query', new.query,
    'selected', new.selected_payload,
    'missing_critical_context', new.missing_critical_context,
    'filtered_counts', new.filtered_counts
  );
  v_digest := programacion.fn_v09_sha256_jsonb(v_payload);

  if new.context_sha256 is distinct from v_digest then
    raise exception 'retrieval context digest mismatch';
  end if;

  if new.status = 'PASS' then
    if jsonb_array_length(new.missing_critical_context) <> 0 then
      raise exception 'retrieval PASS cannot contain missing critical context';
    end if;

    if coalesce(jsonb_typeof(new.query->'required_sources'), 'null') <> 'array'
       or jsonb_array_length(new.query->'required_sources') = 0 then
      raise exception 'retrieval PASS requires required_sources';
    end if;

    if exists (
      select 1
      from jsonb_array_elements_text(new.query->'required_sources') req(source)
      where not exists (
        select 1
        from jsonb_array_elements(new.selected_payload) f(value)
        where f.value->>'source' = req.source
      )
    ) then
      raise exception 'retrieval PASS missing required source';
    end if;

    if new.query ? 'required_record_ids'
       and coalesce(jsonb_typeof(new.query->'required_record_ids'), 'null') <> 'array' then
      raise exception 'required_record_ids must be array';
    end if;

    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(new.query->'required_record_ids','[]'::jsonb)) req(record_id)
      where not exists (
        select 1
        from jsonb_array_elements(new.selected_payload) f(value)
        where f.value->>'record_id' = req.record_id
      )
    ) then
      raise exception 'retrieval PASS missing required record';
    end if;
  end if;

  return new;
end;
$function$;
