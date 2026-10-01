-- INV-9.1 - deterministic external-currentness read model + repeatable observation writer
-- Exact-version identity: 20261001221004
-- Transport: EXACT_VERSION_SOURCE_FIRST
-- Architecture: INV-9 A-prime (owner direction lf_eventos #19834)
-- Contract addendum: PR #1442 / main 57303a8be4bd8490eb0b69df01936a105892ab2e
--
-- This migration does NOT execute a detector observation.
-- It creates the bounded DB surfaces used later by the OIDC gateway.

create or replace function inventory.fn_jsonb_canonical_text_v1(p_value jsonb)
returns text
language plpgsql
immutable
strict
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_type text := jsonb_typeof(p_value);
  v_result text;
begin
  if v_type='object' then
    select '{' || coalesce(
      string_agg(
        to_jsonb(e.key)::text || ':' || inventory.fn_jsonb_canonical_text_v1(e.value),
        ',' order by e.key
      ),
      ''
    ) || '}'
    into v_result
    from jsonb_each(p_value) e;
    return v_result;
  elsif v_type='array' then
    select '[' || coalesce(
      string_agg(
        inventory.fn_jsonb_canonical_text_v1(a.value),
        ',' order by a.ordinality
      ),
      ''
    ) || ']'
    into v_result
    from jsonb_array_elements(p_value) with ordinality a(value,ordinality);
    return v_result;
  end if;
  return p_value::text;
end;
$$;

comment on function inventory.fn_jsonb_canonical_text_v1(jsonb) is
'SHA256_CANONICAL_JSON_V1 canonical JSON text helper for INV-9. Object keys sorted, arrays preserve order, no separator whitespace.';

create or replace function inventory.fn_sha256_canonical_json_v1(p_value jsonb)
returns text
language sql
immutable
strict
security invoker
set search_path=inventory,pg_catalog,extensions
as $$
select encode(
  extensions.digest(
    convert_to(inventory.fn_jsonb_canonical_text_v1(p_value),'UTF8'),
    'sha256'
  ),
  'hex'
);
$$;

comment on function inventory.fn_sha256_canonical_json_v1(jsonb) is
'SHA-256 over inventory.fn_jsonb_canonical_text_v1; compatible with detector canonical JSON contract for the bounded JSON shapes used by INV-9.';

create or replace function inventory.fn_external_currentness_read_model_v1()
returns jsonb
language plpgsql
stable
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_repo jsonb;
  v_edge jsonb;
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'object_ref',o.object_ref,
        'active',o.active,
        'git_blob',o.metadata->>'git_blob',
        'source_version',o.source_version,
        'definition_sha256',o.definition_sha256,
        'currentness',o.currentness,
        'observed_at',o.observed_at,
        'observed_main_sha',o.observed_main_sha,
        'source_traceability_state',o.source_traceability_state
      )
      order by o.object_ref
    ),
    '[]'::jsonb
  )
  into v_repo
  from inventory.objects o
  where o.active and o.object_ref like 'repo://%';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'object_ref',o.object_ref,
        'active',o.active,
        'git_blob',null,
        'source_version',o.source_version,
        'definition_sha256',o.definition_sha256,
        'currentness',o.currentness,
        'observed_at',o.observed_at,
        'observed_main_sha',o.observed_main_sha,
        'source_traceability_state',o.source_traceability_state
      )
      order by o.object_ref
    ),
    '[]'::jsonb
  )
  into v_edge
  from inventory.objects o
  where o.active and o.object_ref like 'edge://%';

  return jsonb_build_object(
    'schema_version','LF_EXTERNAL_CURRENTNESS_READ_MODEL_V1',
    'project_ref','mhwmirqcgxxukpctffuv',
    'captured_at',clock_timestamp(),
    'repo_inventory',v_repo,
    'edge_inventory',v_edge,
    'repo_inventory_sha256',inventory.fn_sha256_canonical_json_v1(v_repo),
    'edge_inventory_sha256',inventory.fn_sha256_canonical_json_v1(v_edge),
    'repo_active_count',jsonb_array_length(v_repo),
    'edge_active_count',jsonb_array_length(v_edge)
  );
end;
$$;

comment on function inventory.fn_external_currentness_read_model_v1() is
'INV-9.1 bounded read-model for the OIDC gateway. Returns only active repo:// and edge:// currentness inputs plus deterministic fingerprints. No dependency/tag/business payload exposure.';

create or replace function inventory.fn_apply_external_currentness_observation_v1(
  p_report jsonb,
  p_observed_main_committed_at timestamptz,
  p_observed_at timestamptz
)
returns table(
  outcome text,
  snapshot_id bigint,
  snapshot_code text,
  repo_updated integer,
  edge_updated integer,
  repo_inventory_sha256 text,
  edge_inventory_sha256 text,
  observed_main_sha text,
  observed_at timestamptz
)
language plpgsql
volatile
security invoker
set search_path=inventory,pg_catalog,extensions
as $$
declare
  c_scope_policy_sha256 constant text :=
    '56b9368e260355109c966cd1673cca861f95381ab23283b361b8ca3a12b587f0';
  v_read_model jsonb;
  v_repo_sha text;
  v_edge_sha text;
  v_report_repo_sha text;
  v_report_edge_sha text;
  v_main_sha text;
  v_detector_version text;
  v_scope_policy_hash text;
  v_report_sha text;
  v_identity jsonb;
  v_identity_sha text;
  v_snapshot_code text;
  v_existing inventory.snapshots%rowtype;
  v_latest_commit timestamptz;
  v_latest_completed timestamptz;
  v_has_prior boolean;
  v_repo_active integer;
  v_edge_active integer;
  v_repo_report integer;
  v_repo_report_distinct integer;
  v_edge_report integer;
  v_edge_report_distinct integer;
  v_repo_updated integer := 0;
  v_edge_updated integer := 0;
  v_now timestamptz := clock_timestamp();
  v_legacy_ordering_baseline boolean := false;
begin
  if p_report is null or jsonb_typeof(p_report)<>'object' then
    raise exception using errcode='22023',message='REPORT_SCHEMA_INVALID';
  end if;

  if p_report->>'schema_version' <> 'LF_EXTERNAL_CURRENTNESS_REPORT_V1'
     or p_report->>'input_digest_contract' <> 'SHA256_CANONICAL_JSON_V1' then
    raise exception using errcode='22023',message='REPORT_SCHEMA_INVALID';
  end if;

  v_main_sha := p_report->>'observed_main_sha';
  v_detector_version := nullif(btrim(p_report->>'detector_version'),'');
  v_scope_policy_hash := p_report->>'scope_policy_hash';

  if coalesce(v_main_sha,'') !~ '^[0-9a-f]{40}$'
     or v_main_sha is distinct from (p_report#>>'{repository,observed_main_sha}')
     or v_detector_version is null
     or coalesce(v_scope_policy_hash,'') !~ '^[0-9a-f]{64}$'
     or v_scope_policy_hash <> c_scope_policy_sha256
     or v_scope_policy_hash is distinct from (p_report#>>'{input_sha256,scope_policy}') then
    raise exception using errcode='22023',message='REPORT_SCOPE_POLICY_MISMATCH';
  end if;

  if p_observed_main_committed_at is null
     or p_observed_at is null
     or p_observed_at > v_now + interval '5 minutes'
     or p_observed_main_committed_at > p_observed_at + interval '5 minutes' then
    raise exception using errcode='22023',message='REPORT_TIME_INVALID';
  end if;

  if coalesce((p_report#>>'{repository,tree_truncated}')::boolean,true) then
    raise exception using errcode='22023',message='REPORT_TREE_TRUNCATED';
  end if;

  if coalesce((p_report->>'pass_unknown_currentness')::boolean,false)=false
     or coalesce((p_report#>>'{repository,unknown_currentness}')::integer,1)<>0
     or coalesce((p_report#>>'{edge,unknown_currentness}')::integer,1)<>0
     or exists (
       select 1
       from jsonb_array_elements(coalesce(p_report#>'{repository,records}','[]'::jsonb)) r
       where r->>'state'='UNKNOWN'
     )
     or exists (
       select 1
       from jsonb_array_elements(coalesce(p_report#>'{edge,records}','[]'::jsonb)) r
       where r->>'state'='UNKNOWN'
     ) then
    raise exception using errcode='22023',message='REPORT_UNKNOWN_CURRENTNESS';
  end if;

  if jsonb_typeof(p_report#>'{repository,records}') is distinct from 'array'
     or jsonb_typeof(p_report#>'{edge,records}') is distinct from 'array'
     or exists (
       select 1
       from jsonb_array_elements(p_report#>'{repository,records}') r
       where coalesce(r->>'path','')=''
          or coalesce(r->>'state','') not in ('CURRENT','STALE','MISSING','NEW')
     )
     or exists (
       select 1
       from jsonb_array_elements(p_report#>'{edge,records}') r
       where coalesce(r->>'slug','')=''
          or coalesce(r->>'state','') not in ('CURRENT','STALE','MISSING','NEW')
     ) then
    raise exception using errcode='22023',message='REPORT_SCHEMA_INVALID';
  end if;

  -- Full report hash is part of the idempotence identity so changed classifications
  -- cannot alias an already-applied observation that reused the same input digests.
  v_report_sha := inventory.fn_sha256_canonical_json_v1(p_report);
  v_identity := jsonb_build_object(
    'observed_main_sha',v_main_sha,
    'detector_version',v_detector_version,
    'scope_policy_hash',v_scope_policy_hash,
    'git_tree_sha256',p_report#>>'{input_sha256,git_tree}',
    'repo_inventory_sha256',p_report#>>'{input_sha256,repo_inventory}',
    'edge_runtime_sha256',p_report#>>'{input_sha256,edge_runtime}',
    'edge_inventory_sha256',p_report#>>'{input_sha256,edge_inventory}',
    'scope_policy_sha256',p_report#>>'{input_sha256,scope_policy}',
    'report_sha256',v_report_sha
  );

  if exists (
    select 1
    from jsonb_each_text(v_identity)
    where key <> 'detector_version'
      and coalesce(value,'') !~ '^[0-9a-f]{64}$'
      and key <> 'observed_main_sha'
  ) then
    raise exception using errcode='22023',message='REPORT_DIGEST_INVALID';
  end if;

  if coalesce(p_report#>>'{input_sha256,git_tree}','') !~ '^[0-9a-f]{64}$'
     or coalesce(p_report#>>'{input_sha256,repo_inventory}','') !~ '^[0-9a-f]{64}$'
     or coalesce(p_report#>>'{input_sha256,edge_runtime}','') !~ '^[0-9a-f]{64}$'
     or coalesce(p_report#>>'{input_sha256,edge_inventory}','') !~ '^[0-9a-f]{64}$'
     or coalesce(p_report#>>'{input_sha256,scope_policy}','') !~ '^[0-9a-f]{64}$' then
    raise exception using errcode='22023',message='REPORT_DIGEST_INVALID';
  end if;

  v_identity_sha := inventory.fn_sha256_canonical_json_v1(v_identity);
  v_snapshot_code := 'LF_EXTERNAL_CURRENTNESS_V2_' || v_identity_sha;

  select *
  into v_existing
  from inventory.snapshots s
  where s.snapshot_code=v_snapshot_code;

  if found then
    return query
    select
      'OBSERVATION_ALREADY_APPLIED'::text,
      v_existing.snapshot_id,
      v_existing.snapshot_code,
      0,
      0,
      p_report#>>'{input_sha256,repo_inventory}',
      p_report#>>'{input_sha256,edge_inventory}',
      v_main_sha,
      v_existing.completed_at;
    return;
  end if;

  select exists(
    select 1
    from inventory.snapshots s
    where s.source_system='EXTERNAL_CURRENTNESS_DETECTOR_V1'
      and s.status='COMPLETED'
  ) into v_has_prior;

  select
    (s.metadata->>'observed_main_committed_at')::timestamptz,
    s.completed_at
  into v_latest_commit,v_latest_completed
  from inventory.snapshots s
  where s.source_system='EXTERNAL_CURRENTNESS_DETECTOR_V1'
    and s.status='COMPLETED'
    and nullif(s.metadata->>'observed_main_committed_at','') is not null
  order by (s.metadata->>'observed_main_committed_at')::timestamptz desc,
           s.completed_at desc nulls last,
           s.snapshot_id desc
  limit 1;

  if v_latest_commit is not null then
    if p_observed_main_committed_at < v_latest_commit
       or (
         p_observed_main_committed_at = v_latest_commit
         and v_latest_completed is not null
         and p_observed_at < v_latest_completed
       ) then
      raise exception using errcode='22023',message='REPORT_OLDER_THAN_CURRENT_OBSERVATION';
    end if;
  elsif v_has_prior then
    v_legacy_ordering_baseline := true;
  end if;

  -- Exact coverage of all active, already-inventoried repo:// rows.
  select count(*),count(distinct r->>'path')
  into v_repo_report,v_repo_report_distinct
  from jsonb_array_elements(p_report#>'{repository,records}') r
  where r->>'state'<>'NEW';

  select count(*) into v_repo_active
  from inventory.objects
  where active and object_ref like 'repo://%';

  if v_repo_report<>v_repo_report_distinct
     or v_repo_report<>v_repo_active
     or exists (
       select 1
       from inventory.objects o
       where o.active and o.object_ref like 'repo://%'
         and not exists (
           select 1
           from jsonb_array_elements(p_report#>'{repository,records}') r
           where r->>'state'<>'NEW'
             and o.object_ref='repo://' || (r->>'path')
         )
     )
     or exists (
       select 1
       from jsonb_array_elements(p_report#>'{repository,records}') r
       where r->>'state'<>'NEW'
         and not exists (
           select 1 from inventory.objects o
           where o.active
             and o.object_ref='repo://' || (r->>'path')
         )
     ) then
    raise exception using errcode='22023',message='REPORT_INCOMPLETE';
  end if;

  -- Exact coverage of all active, already-inventoried edge:// rows.
  select count(*),count(distinct r->>'slug')
  into v_edge_report,v_edge_report_distinct
  from jsonb_array_elements(p_report#>'{edge,records}') r
  where r->>'state'<>'NEW';

  select count(*) into v_edge_active
  from inventory.objects
  where active and object_ref like 'edge://%';

  if v_edge_report<>v_edge_report_distinct
     or v_edge_report<>v_edge_active
     or exists (
       select 1
       from inventory.objects o
       where o.active and o.object_ref like 'edge://%'
         and not exists (
           select 1
           from jsonb_array_elements(p_report#>'{edge,records}') r
           where r->>'state'<>'NEW'
             and o.object_ref='edge://' || (r->>'slug')
         )
     )
     or exists (
       select 1
       from jsonb_array_elements(p_report#>'{edge,records}') r
       where r->>'state'<>'NEW'
         and not exists (
           select 1 from inventory.objects o
           where o.active
             and o.object_ref='edge://' || (r->>'slug')
         )
     ) then
    raise exception using errcode='22023',message='REPORT_INCOMPLETE';
  end if;

  -- Re-read current inventory inside the writer transaction. The detector input
  -- must still be the exact DB read-model that was used to build this report.
  v_read_model := inventory.fn_external_currentness_read_model_v1();
  v_repo_sha := v_read_model->>'repo_inventory_sha256';
  v_edge_sha := v_read_model->>'edge_inventory_sha256';
  v_report_repo_sha := p_report#>>'{input_sha256,repo_inventory}';
  v_report_edge_sha := p_report#>>'{input_sha256,edge_inventory}';

  if v_repo_sha is distinct from v_report_repo_sha
     or v_edge_sha is distinct from v_report_edge_sha then
    raise exception using errcode='22023',message='REPORT_INPUT_STALE';
  end if;

  update inventory.objects o
  set currentness=r.value->>'state',
      currentness_source='GITHUB_MAIN',
      observed_at=p_observed_at,
      observed_main_sha=v_main_sha,
      updated_at=v_now
  from jsonb_array_elements(p_report#>'{repository,records}') r(value)
  where o.active
    and o.object_ref='repo://' || (r.value->>'path')
    and r.value->>'state'<>'NEW';
  get diagnostics v_repo_updated = row_count;

  update inventory.objects o
  set currentness=r.value->>'state',
      currentness_source='SUPABASE_EDGE_RUNTIME',
      observed_at=p_observed_at,
      observed_main_sha=v_main_sha,
      source_traceability_state=case
        when r.value->>'state'='MISSING' then o.source_traceability_state
        else nullif(r.value->>'source_state','')
      end,
      updated_at=v_now
  from jsonb_array_elements(p_report#>'{edge,records}') r(value)
  where o.active
    and o.object_ref='edge://' || (r.value->>'slug')
    and r.value->>'state'<>'NEW';
  get diagnostics v_edge_updated = row_count;

  if v_repo_updated<>v_repo_active or v_edge_updated<>v_edge_active then
    raise exception using errcode='22023',message='REPORT_INCOMPLETE';
  end if;

  insert into inventory.snapshots(
    snapshot_code,source_system,scope,started_at,completed_at,status,
    object_count,dependency_count,metadata
  )
  values(
    v_snapshot_code,
    'EXTERNAL_CURRENTNESS_DETECTOR_V1',
    'REPO_AND_EDGE_RUNTIME',
    p_observed_at,
    p_observed_at,
    'COMPLETED',
    v_repo_active+v_edge_active,
    null,
    jsonb_build_object(
      'schema_version','LF_EXTERNAL_CURRENTNESS_OBSERVATION_V2',
      'writer_version','INV-9.1/V1',
      'mode','APPLIED_REPEATABLE_OBSERVATION',
      'identity_sha256',v_identity_sha,
      'report_sha256',v_report_sha,
      'detector_version',v_detector_version,
      'scope_policy_hash',v_scope_policy_hash,
      'observed_main_sha',v_main_sha,
      'observed_main_committed_at',p_observed_main_committed_at,
      'observed_at',p_observed_at,
      'legacy_ordering_baseline',v_legacy_ordering_baseline,
      'input_digest_contract','SHA256_CANONICAL_JSON_V1',
      'input_sha256',p_report->'input_sha256',
      'read_model_sha256',jsonb_build_object(
        'repo_inventory',v_repo_sha,
        'edge_inventory',v_edge_sha
      ),
      'coverage',jsonb_build_object(
        'repo_active',v_repo_active,
        'edge_active',v_edge_active,
        'repo_updated',v_repo_updated,
        'edge_updated',v_edge_updated
      ),
      'repository_counts',p_report#>'{repository,counts}',
      'edge_counts',p_report#>'{edge,counts}'
    )
  )
  returning inventory.snapshots.snapshot_id
  into snapshot_id;

  outcome := 'OBSERVATION_APPLIED';
  snapshot_code := v_snapshot_code;
  repo_updated := v_repo_updated;
  edge_updated := v_edge_updated;
  repo_inventory_sha256 := v_repo_sha;
  edge_inventory_sha256 := v_edge_sha;
  observed_main_sha := v_main_sha;
  observed_at := p_observed_at;
  return next;
end;
$$;

comment on function inventory.fn_apply_external_currentness_observation_v1(jsonb,timestamptz,timestamptz) is
'INV-9.1 repeatable writer. Applies only freshness/currentness fields and a deterministic snapshot. Rejects older observations, stale DB inputs, incomplete coverage, UNKNOWN/truncated reports and NEW-object writes.';

revoke all on function inventory.fn_jsonb_canonical_text_v1(jsonb) from public,anon,authenticated;
revoke all on function inventory.fn_sha256_canonical_json_v1(jsonb) from public,anon,authenticated;
revoke all on function inventory.fn_external_currentness_read_model_v1() from public,anon,authenticated;
revoke all on function inventory.fn_apply_external_currentness_observation_v1(jsonb,timestamptz,timestamptz) from public,anon,authenticated;

grant execute on function inventory.fn_jsonb_canonical_text_v1(jsonb) to service_role;
grant execute on function inventory.fn_sha256_canonical_json_v1(jsonb) to service_role;
grant execute on function inventory.fn_external_currentness_read_model_v1() to service_role;
grant execute on function inventory.fn_apply_external_currentness_observation_v1(jsonb,timestamptz,timestamptz) to service_role;

do $$
declare
  v_probe jsonb := '{"z":1,"a":[true,null,{"b":"á","a":2}]}'::jsonb;
begin
  if inventory.fn_jsonb_canonical_text_v1(v_probe)
     <> '{"a":[true,null,{"a":2,"b":"á"}],"z":1}' then
    raise exception 'INV_9_1_CANONICAL_JSON_SELF_TEST_FAILED';
  end if;

  if inventory.fn_sha256_canonical_json_v1(v_probe)
     !~ '^[0-9a-f]{64}$' then
    raise exception 'INV_9_1_CANONICAL_HASH_SELF_TEST_FAILED';
  end if;
end $$;
