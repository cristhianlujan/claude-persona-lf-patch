create or replace function programacion.fn_input_source_ref_eligibility_v1(p_run_id bigint)
returns jsonb
language sql
stable security definer
set search_path to pg_catalog,programacion
as $$
  with refs as (
    select e.value ref
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(coalesce(a.source_refs,'[]'::jsonb)) e(value)
    where a.run_id=p_run_id
  )
  select jsonb_build_object(
    'schema_version','INPUT_SOURCE_REF_ELIGIBILITY_V1',
    'run_id',p_run_id,
    'total_refs',count(*),
    'structured_refs',count(*) filter(where jsonb_typeof(ref)='object' and coalesce(ref->>'kind','')<>''),
    'legacy_unstructured_refs',count(*) filter(where jsonb_typeof(ref)<>'object' or coalesce(ref->>'kind','')=''),
    'eligible_for_current_manifest',count(*) filter(where jsonb_typeof(ref)<>'object' or coalesce(ref->>'kind','')='')=0
  )
  from refs;
$$;

create or replace function programacion.fn_input_build_source_manifest_safe_v1(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,public,programacion
as $$
declare
  v_pantalla_id integer;
  v_version_id bigint;
  v_manifest jsonb;
  v_graph jsonb;
  v_graph_ref jsonb:=jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH');
  v_graph_receipt jsonb;
  v_archive_contract jsonb:=jsonb_build_object(
    'capability_code','EVIDENCE_LEDGER',
    'producer_capability_code','SOURCE_RESOLUTION_POLICY',
    'resolver_id','LF_SUPABASE_READBACK_V1',
    'verification_method','SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
    'archive_api','programacion.fn_input_archive_source_observation_v1',
    'state','GOVERNED_EXECUTION_REQUIRED'
  );
begin
  select pantalla_id,version_id into v_pantalla_id,v_version_id
  from programacion.input_readiness_runs where id=p_run_id;

  if v_pantalla_id is null then
    raise exception 'INPUT_READINESS_RUN_NOT_FOUND:%',p_run_id;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
  v_graph_receipt:=jsonb_build_object(
    'schema_version','IG_SOURCE_RECEIPT_V1','ref',v_graph_ref,
    'authority','CANONICAL_COMPOSITE_GRAPH',
    'lifecycle',programacion.fn_input_source_lifecycle_receipt_v1(v_graph_ref,v_graph),
    'observed_sha256',programacion.fn_v09_sha256_jsonb(v_graph),
    'archive_contract',v_archive_contract
  );

  with refs as (
    select distinct e.ref
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(a.source_refs) e(ref)
    where a.run_id=p_run_id
      and jsonb_typeof(e.ref)='object'
      and coalesce(e.ref->>'kind','')<>''
      and coalesce(e.ref->>'kind','')<>'SCREEN_CANONICAL_GRAPH'
  ), full_receipts as (
    select r.ref,programacion.fn_input_resolve_source_ref(r.ref,v_pantalla_id,v_version_id) full_receipt
    from refs r
  ), resolved as (
    select ref,jsonb_build_object(
      'schema_version','IG_SOURCE_RECEIPT_V1',
      'ref',ref,
      'authority',programacion.fn_input_source_authority_class(ref),
      'lifecycle',programacion.fn_input_source_lifecycle_receipt_v1(ref,full_receipt->'observed'),
      'observed_sha256',coalesce(nullif(full_receipt->>'observed_sha256',''),
        programacion.fn_v09_sha256_jsonb(full_receipt->'observed')),
      'archive_contract',v_archive_contract
    ) receipt
    from full_receipts
  ), all_receipts as (
    select ref::text sort_key,receipt from resolved
    union all
    select '{"kind":"SCREEN_CANONICAL_GRAPH"}'::text,v_graph_receipt
  )
  select coalesce(jsonb_agg(receipt order by sort_key),'[]'::jsonb)
    into v_manifest
  from all_receipts;

  if jsonb_array_length(v_manifest)=0 then
    raise exception 'SOURCE_MANIFEST_EMPTY:%',p_run_id;
  end if;
  if exists(select 1 from jsonb_array_elements(v_manifest) e(value) where e.value ? 'observed') then
    raise exception 'SOURCE_MANIFEST_FULL_OBSERVED_PAYLOAD_FORBIDDEN:%',p_run_id;
  end if;

  return v_manifest;
end; $$;

create or replace function programacion.fn_input_build_source_manifest(p_run_id bigint)
returns jsonb
language sql
security definer
set search_path to pg_catalog,public,programacion
as $$
  select programacion.fn_input_build_source_manifest_safe_v1(p_run_id);
$$;