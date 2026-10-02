-- INV-9.E0 - external observation freshness for repo:// and edge://
-- Exact-version identity: 20261001212156
-- Transport: EXACT_VERSION_SOURCE_FIRST
-- External CURRENT is trustworthy for at most 7 hours from observed_at.
-- Negative drift states (STALE/MISSING/NEW) are preserved as evidence and do not age to UNKNOWN.
-- This TTL is a fail-closed safety net only; R units still must rerun the detector after deploy.

create or replace function inventory.fn_external_currentness_eval_v1(
  p_currentness text,
  p_observed_at timestamptz,
  p_as_of timestamptz default now()
)
returns text
language sql
stable
security invoker
set search_path=inventory,pg_catalog
as $$
select case
  when coalesce(p_currentness,'UNKNOWN') <> 'CURRENT'
    then coalesce(p_currentness,'UNKNOWN')
  when p_as_of is null
    or p_observed_at is null
    or p_observed_at > p_as_of
    or p_as_of - p_observed_at > interval '7 hours'
    then 'UNKNOWN'
  else 'CURRENT'
end;
$$;

comment on function inventory.fn_external_currentness_eval_v1(text,timestamptz,timestamptz) is
'External repo/edge observation freshness. Persisted CURRENT becomes UNKNOWN when observed_at is missing, in the future, or older than 7 hours. STALE/MISSING/NEW remain explicit. This does not replace post-deploy detector execution.';

create or replace view inventory.v_objects_search_v1
with (security_invoker=true)
as
select
  o.object_id,o.object_ref,o.object_type,o.schema_name,o.object_name,o.domain,
  o.source_system,o.source_of_truth,o.status,o.definition_sha256,o.source_version,
  coalesce(tags.tags,'{}'::text[]) as tags,
  o.metadata,o.last_seen_at,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then inventory.fn_external_currentness_eval_v1(
        o.currentness,o.observed_at,now()
      )
    when ms.source_system is not null then ms.currentness
    else 'UNKNOWN'
  end as currentness,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then o.currentness_source
    when ms.source_system is not null then ms.currentness_source
    else null
  end as currentness_source,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then o.observed_at
    when ms.source_system is not null then ms.observed_at
    else null
  end as observed_at,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then o.observed_main_sha
    else null
  end as observed_main_sha,
  case
    when o.object_ref like 'edge://%'
      then coalesce(o.source_traceability_state,'UNKNOWN')
    else o.source_traceability_state
  end as source_traceability_state
from inventory.objects o
left join inventory.v_managed_currentness_v1 ms
  on ms.source_system=o.source_system
left join lateral (
  select array_agg(distinct ot.tag_code order by ot.tag_code) tags
  from inventory.object_tags ot
  where ot.object_id=o.object_id
) tags on true
where o.active;

create or replace function inventory.fn_refresh_search_index_v1()
returns bigint
language plpgsql
set search_path=inventory,pg_catalog
as $$
declare
  v_count bigint;
begin
  insert into inventory.search_index(
    object_id,object_ref,object_ref_lc,object_type,schema_name,object_name,object_name_lc,
    tags,tags_lc,column_names,column_names_lc,source_system,source_of_truth,status,
    search_document,refreshed_at,currentness,currentness_source,observed_at,
    observed_main_sha,source_traceability_state
  )
  select
    o.object_id,o.object_ref,lower(o.object_ref),o.object_type,o.schema_name,o.object_name,lower(o.object_name),
    coalesce(t.tags,'{}'::text[]),coalesce(t.tags_lc,'{}'::text[]),
    coalesce(c.cols,'{}'::text[]),coalesce(c.cols_lc,'{}'::text[]),
    o.source_system,o.source_of_truth,o.status,
    to_tsvector(
      'simple',
      coalesce(o.object_ref,'')||' '||coalesce(o.object_name,'')||' '||
      coalesce(o.schema_name,'')||' '||
      array_to_string(coalesce(t.tags,'{}'::text[]),' ')||' '||
      array_to_string(coalesce(c.cols,'{}'::text[]),' ')
    ),
    now(),
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then inventory.fn_external_currentness_eval_v1(
          o.currentness,o.observed_at,now()
        )
      when ms.source_system is not null then ms.currentness
      else 'UNKNOWN'
    end,
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then o.currentness_source
      when ms.source_system is not null then ms.currentness_source
      else null
    end,
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then o.observed_at
      when ms.source_system is not null then ms.observed_at
      else null
    end,
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then o.observed_main_sha
      else null
    end,
    case
      when o.object_ref like 'edge://%'
        then coalesce(o.source_traceability_state,'UNKNOWN')
      else o.source_traceability_state
    end
  from inventory.objects o
  left join inventory.v_managed_currentness_v1 ms
    on ms.source_system=o.source_system
  left join lateral (
    select array_agg(distinct ot.tag_code order by ot.tag_code) tags,
           array_agg(distinct lower(ot.tag_code) order by lower(ot.tag_code)) tags_lc
    from inventory.object_tags ot
    where ot.object_id=o.object_id
  ) t on true
  left join lateral (
    select array_agg(ic.column_name order by ic.ordinal_position) cols,
           array_agg(lower(ic.column_name) order by ic.ordinal_position) cols_lc
    from inventory.columns ic
    where ic.object_id=o.object_id
  ) c on true
  where o.active
  on conflict(object_id) do update set
    object_ref=excluded.object_ref,object_ref_lc=excluded.object_ref_lc,
    object_type=excluded.object_type,schema_name=excluded.schema_name,
    object_name=excluded.object_name,object_name_lc=excluded.object_name_lc,
    tags=excluded.tags,tags_lc=excluded.tags_lc,
    column_names=excluded.column_names,column_names_lc=excluded.column_names_lc,
    source_system=excluded.source_system,source_of_truth=excluded.source_of_truth,
    status=excluded.status,search_document=excluded.search_document,
    refreshed_at=now(),currentness=excluded.currentness,
    currentness_source=excluded.currentness_source,observed_at=excluded.observed_at,
    observed_main_sha=excluded.observed_main_sha,
    source_traceability_state=excluded.source_traceability_state;

  delete from inventory.search_index s
  where not exists (
    select 1 from inventory.objects o
    where o.object_id=s.object_id and o.active
  );

  select count(*) into v_count from inventory.search_index;
  return v_count;
end;
$$;

create or replace function inventory.fn_lookup_v3(
  p_term text default null,
  p_object_types text[] default null,
  p_limit integer default 100,
  p_currentness text[] default null
)
returns table(
  object_ref text,
  object_type text,
  schema_name text,
  object_name text,
  match_reason text,
  matching_columns text[],
  tags text[],
  source_system text,
  source_of_truth boolean,
  status text,
  currentness text,
  currentness_source text,
  observed_at timestamptz,
  observed_main_sha text,
  source_traceability_state text
)
language plpgsql
stable
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_requested text[];
begin
  v_requested := inventory.fn_normalize_currentness_filter_v1(p_currentness);

  return query
  with enriched as (
    select
      s.*,
      case
        when s.object_ref like 'repo://%' or s.object_ref like 'edge://%'
          then inventory.fn_external_currentness_eval_v1(
            s.currentness,s.observed_at,now()
          )
        when ms.source_system is not null then ms.currentness
        else 'UNKNOWN'
      end as effective_currentness,
      case
        when s.object_ref like 'repo://%' or s.object_ref like 'edge://%'
          then s.currentness_source
        when ms.source_system is not null then ms.currentness_source
        else null
      end as effective_currentness_source,
      case
        when s.object_ref like 'repo://%' or s.object_ref like 'edge://%'
          then s.observed_at
        when ms.source_system is not null then ms.observed_at
        else null
      end as effective_observed_at
    from inventory.search_index s
    left join inventory.v_managed_currentness_v1 ms
      on ms.source_system=s.source_system
  ),
  matched as (
    select
      e.*,
      case
        when lower(nullif(btrim(p_term),'')) is null then 'ALL'
        when e.object_ref_lc=lower(btrim(p_term)) then 'EXACT_REF'
        when e.object_name_lc=lower(btrim(p_term)) then 'EXACT_NAME'
        when lower(btrim(p_term))=any(e.tags_lc) then 'TAG'
        when lower(btrim(p_term))=any(e.column_names_lc) then 'COLUMN'
        when e.search_document @@ plainto_tsquery('simple',lower(btrim(p_term))) then 'TEXT'
        else null
      end as computed_match_reason,
      case
        when lower(nullif(btrim(p_term),'')) is not null
         and lower(btrim(p_term))=any(e.column_names_lc)
        then array(
          select c from unnest(e.column_names) c
          where lower(c)=lower(btrim(p_term))
        )
        else '{}'::text[]
      end as computed_matching_columns
    from enriched e
    where (p_object_types is null or e.object_type=any(p_object_types))
      and (
        v_requested is null
        or e.effective_currentness=any(v_requested)
        or (
          'CURRENT'=any(v_requested)
          and e.effective_currentness='CATALOG_MANAGED'
        )
      )
      and (
        lower(nullif(btrim(p_term),'')) is null
        or e.object_ref_lc=lower(btrim(p_term))
        or e.object_name_lc=lower(btrim(p_term))
        or lower(btrim(p_term))=any(e.tags_lc)
        or lower(btrim(p_term))=any(e.column_names_lc)
        or e.search_document @@ plainto_tsquery('simple',lower(btrim(p_term)))
      )
  )
  select
    m.object_ref,m.object_type,m.schema_name,m.object_name,
    m.computed_match_reason,m.computed_matching_columns,m.tags,
    m.source_system,m.source_of_truth,m.status,
    m.effective_currentness,m.effective_currentness_source,
    m.effective_observed_at,
    case
      when m.object_ref like 'repo://%' or m.object_ref like 'edge://%'
        then m.observed_main_sha
      else null
    end,
    m.source_traceability_state
  from matched m
  order by
    case m.computed_match_reason
      when 'EXACT_REF' then 0
      when 'EXACT_NAME' then 1
      when 'TAG' then 2
      when 'COLUMN' then 3
      else 4
    end,
    m.object_ref
  limit greatest(1,least(coalesce(p_limit,100),500));
end;
$$;

comment on function inventory.fn_lookup_v3(text,text[],integer,text[]) is
'CANONICAL_GLOBAL_INVENTORY_LOOKUP_V3. External repo:// and edge:// persisted CURRENT ages to UNKNOWN after 7h from observed_at; returned observed_at remains the evidence timestamp. Managed catalog/registry currentness keeps the same <=7h rule. STALE/MISSING/NEW remain explicit. Edge CURRENT does not imply source traceability.';

select inventory.fn_refresh_search_index_v1();

do $$
declare
  v_now timestamptz := clock_timestamp();
begin
  if inventory.fn_external_currentness_eval_v1(
    'CURRENT',v_now-interval '8 hours',v_now
  ) <> 'UNKNOWN' then
    raise exception 'BLOCK_EXTERNAL_CURRENTNESS_STALE_CURRENT_ACCEPTED';
  end if;

  if inventory.fn_external_currentness_eval_v1(
    'CURRENT',v_now-interval '6 hours 59 minutes',v_now
  ) <> 'CURRENT' then
    raise exception 'BLOCK_EXTERNAL_CURRENTNESS_FRESH_CURRENT_REJECTED';
  end if;

  if inventory.fn_external_currentness_eval_v1(
    'CURRENT',null,v_now
  ) <> 'UNKNOWN' then
    raise exception 'BLOCK_EXTERNAL_CURRENTNESS_NULL_OBSERVED_AT_ACCEPTED';
  end if;

  if inventory.fn_external_currentness_eval_v1(
    'CURRENT',v_now+interval '1 minute',v_now
  ) <> 'UNKNOWN' then
    raise exception 'BLOCK_EXTERNAL_CURRENTNESS_FUTURE_OBSERVED_AT_ACCEPTED';
  end if;

  if inventory.fn_external_currentness_eval_v1(
    'STALE',v_now-interval '30 hours',v_now
  ) <> 'STALE' then
    raise exception 'BLOCK_EXTERNAL_CURRENTNESS_STALE_EVIDENCE_AGED_OUT';
  end if;

  if inventory.fn_external_currentness_eval_v1(
    'MISSING',v_now-interval '30 hours',v_now
  ) <> 'MISSING' then
    raise exception 'BLOCK_EXTERNAL_CURRENTNESS_MISSING_EVIDENCE_AGED_OUT';
  end if;
end
$$;
