-- Governed by ACT-0001 -> FUNCTION/UPDATE -> ACTUALIZACION_DB_LF v0.1.
-- Backlog: WORKING-CONTEXT-RETRIEVAL-NULL-SHAPE-GUARD-001 (id 113).
-- Minimal source-first repair: SQL NULL selected_payload must not bypass canonical JSONB shape validation.

create or replace function programacion.fn_guard_retrieval_run_insert()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'programacion'
as $function$
declare v_payload jsonb; v_digest text; v_bad integer;
begin
  perform programacion.fn_v09_assert_execution_head(new.execution_id, new.head_sha);
  if new.status not in ('PASS', 'BLOCKED') then raise exception 'retrieval status invalid: %', new.status; end if;
  if jsonb_typeof(new.query) <> 'object'
     or coalesce(jsonb_typeof(new.selected_payload),'null') <> 'array'
     or jsonb_typeof(new.missing_critical_context) <> 'array'
     or jsonb_typeof(new.filtered_counts) <> 'object' then
    raise exception 'retrieval canonical payload shape invalid';
  end if;
  select count(*) into v_bad
  from jsonb_array_elements(new.selected_payload) as f(value)
  where jsonb_typeof(f.value) <> 'object'
     or jsonb_typeof(f.value->'source') <> 'string'
     or jsonb_typeof(f.value->'record_id') <> 'string'
     or jsonb_typeof(f.value->'title') <> 'string'
     or jsonb_typeof(f.value->'content') <> 'string'
     or jsonb_typeof(f.value->'score') <> 'number'
     or jsonb_typeof(f.value->'reasons') <> 'array'
     or jsonb_typeof(f.value->'provenance') <> 'object'
     or coalesce(f.value->>'content_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(f.value->'provenance'->>'snapshot_sha256','') !~ '^[0-9a-f]{64}$'
     or programacion.fn_v09_sha256_jsonb(jsonb_build_object(
          'source', f.value->'source','record_id', f.value->'record_id','title', f.value->'title',
          'content', f.value->'content','provenance', f.value->'provenance')) <> f.value->>'content_sha256';
  if v_bad <> 0 then raise exception 'retrieval selected payload contains % invalid fragment(s)', v_bad; end if;
  if exists (
    select 1 from (
      select f.value->>'source' source, f.value->>'record_id' record_id, count(*) c
      from jsonb_array_elements(new.selected_payload) f(value)
      group by 1,2 having count(*) > 1
    ) d
  ) then raise exception 'retrieval selected payload contains duplicate source/record_id'; end if;
  v_payload := jsonb_build_object(
    'schema_version', 1,'status', new.status,'query', new.query,'selected', new.selected_payload,
    'missing_critical_context', new.missing_critical_context,'filtered_counts', new.filtered_counts);
  v_digest := programacion.fn_v09_sha256_jsonb(v_payload);
  if new.context_sha256 is distinct from v_digest then raise exception 'retrieval context digest mismatch'; end if;
  if new.status = 'PASS' then
    if jsonb_array_length(new.missing_critical_context) <> 0 then raise exception 'retrieval PASS cannot contain missing critical context'; end if;
    if jsonb_typeof(new.query->'required_sources') <> 'array' or jsonb_array_length(new.query->'required_sources') = 0 then
      raise exception 'retrieval PASS requires required_sources';
    end if;
    if exists (
      select 1 from jsonb_array_elements_text(new.query->'required_sources') req(source)
      where not exists (select 1 from jsonb_array_elements(new.selected_payload) f(value) where f.value->>'source' = req.source)
    ) then raise exception 'retrieval PASS missing required source'; end if;
    if new.query ? 'required_record_ids' and jsonb_typeof(new.query->'required_record_ids') <> 'array' then
      raise exception 'required_record_ids must be array';
    end if;
    if exists (
      select 1 from jsonb_array_elements_text(coalesce(new.query->'required_record_ids','[]'::jsonb)) req(record_id)
      where not exists (select 1 from jsonb_array_elements(new.selected_payload) f(value) where f.value->>'record_id' = req.record_id)
    ) then raise exception 'retrieval PASS missing required record'; end if;
  end if;
  return new;
end;
$function$;
