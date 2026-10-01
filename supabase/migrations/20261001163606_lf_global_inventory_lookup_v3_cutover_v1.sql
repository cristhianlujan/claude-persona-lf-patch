-- LF Global Technical Inventory - canonical lookup v3 and v2 compatibility marker
-- B2 corrective.
--
-- Transport requirement:
--   EXACT_VERSION_SOURCE_FIRST
-- Apply this migration with SUPABASE_CLI_DB_PUSH_LINKED or the governed
-- SOURCE_FIRST_EXACT_VERSION_MANUAL_LEDGER_DML fallback.
-- SUPABASE_MCP_APPLY_MIGRATION_WHEN_EXACT_VERSION_REQUIRED is forbidden.
--
-- Historical migrations/canaries that reference fn_lookup_v2 are intentionally
-- not edited. v2 remains executable for compatibility but is no longer canonical.

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
language sql
stable
security invoker
set search_path=inventory,pg_catalog
as $function$
with p as (
  select
    lower(nullif(btrim(p_term),'')) as term,
    case
      when p_currentness is null then null::text[]
      else array(
        select upper(btrim(x))
        from unnest(p_currentness) as u(x)
      )
    end as requested_currentness
),
matched as (
  select
    s.*,
    case
      when p.term is null then 'ALL'
      when s.object_ref_lc=p.term then 'EXACT_REF'
      when s.object_name_lc=p.term then 'EXACT_NAME'
      when p.term=any(s.tags_lc) then 'TAG'
      when p.term=any(s.column_names_lc) then 'COLUMN'
      when s.search_document @@ plainto_tsquery('simple',p.term) then 'TEXT'
      else null
    end as match_reason,
    case
      when p.term=any(s.column_names_lc)
        then array(
          select c
          from unnest(s.column_names) c
          where lower(c)=p.term
        )
      else '{}'::text[]
    end as matching_columns
  from inventory.search_index s
  cross join p
  where (p_object_types is null or s.object_type=any(p_object_types))
    and (
      p.requested_currentness is null
      or (
        not exists (
          select 1
          from unnest(p.requested_currentness) as rc(value)
          where rc.value not in ('CURRENT','STALE','MISSING','NEW','UNKNOWN')
        )
        and s.currentness=any(p.requested_currentness)
      )
    )
    and (
      p.term is null
      or s.object_ref_lc=p.term
      or s.object_name_lc=p.term
      or p.term=any(s.tags_lc)
      or p.term=any(s.column_names_lc)
      or s.search_document @@ plainto_tsquery('simple',p.term)
    )
)
select
  m.object_ref,
  m.object_type,
  m.schema_name,
  m.object_name,
  m.match_reason,
  m.matching_columns,
  m.tags,
  m.source_system,
  m.source_of_truth,
  m.status,
  m.currentness,
  m.currentness_source,
  m.observed_at,
  m.observed_main_sha,
  m.source_traceability_state
from matched m
order by
  case m.match_reason
    when 'EXACT_REF' then 0
    when 'EXACT_NAME' then 1
    when 'TAG' then 2
    when 'COLUMN' then 3
    else 4
  end,
  m.object_ref
limit greatest(1,least(coalesce(p_limit,100),500));
$function$;

revoke all on function inventory.fn_lookup_v3(text,text[],integer,text[]) from public;

grant execute on function inventory.fn_lookup_v3(text,text[],integer,text[]) to
  programacion_auditor,
  programacion_builder,
  programacion_human_authority,
  programacion_verifier,
  service_role;

comment on function inventory.fn_lookup_v2(text,text[],integer) is
'DEPRECATED_COMPATIBILITY: retained unchanged for historical/applied consumers, including existing canaries. New consumers must use inventory.fn_lookup_v3(text,text[],integer,text[]) so external currentness and source traceability are visible.';

comment on function inventory.fn_lookup_v3(text,text[],integer,text[]) is
'CANONICAL_GLOBAL_INVENTORY_LOOKUP_V3: backward-friendly parameter order relative to v2, with optional fourth currentness filter and explicit currentness/source-traceability output.';

do $$
declare
  v_expected integer := 4;
  v_found integer;
begin
  select count(*) into v_found
  from public.lf_activos
  where codigo_activo in (
    'LF_GLOBAL_TECHNICAL_INVENTORY_V1',
    'AUTHORITY_READBACK',
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET'
  )
  and archived_at is null;

  if v_found <> v_expected then
    raise exception 'BLOCK_LOOKUP_V3_CANONICAL_POINTER_ASSETS_MISSING expected=% found=%',v_expected,v_found;
  end if;
end
$$;

update public.lf_activos
set
  raw_payload=jsonb_set(
    coalesce(raw_payload,'{}'::jsonb),
    '{lookup}',
    to_jsonb('inventory.fn_lookup_v3(text,text[],integer,text[])'::text),
    true
  ),
  metadata=jsonb_set(
    coalesce(metadata,'{}'::jsonb),
    '{lookup_compatibility}',
    jsonb_build_object(
      'canonical_lookup','inventory.fn_lookup_v3(text,text[],integer,text[])',
      'deprecated_lookup','inventory.fn_lookup_v2(text,text[],integer)',
      'deprecated_status','DEPRECATED_COMPATIBILITY',
      'known_v2_consumers',jsonb_build_array(
        'HISTORICAL_APPLIED_MIGRATIONS_AND_CANARIES_DO_NOT_EDIT',
        'AUTHORITY_READBACK_PRE_B2_V3',
        'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1_PRE_B2_V3',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET_PRE_B2_V3'
      ),
      'new_consumer_policy','USE_V3'
    ),
    true
  ),
  updated_at=now(),
  updated_by_execution_id='LF_GLOBAL_INVENTORY_B2_LOOKUP_V3'
where codigo_activo='LF_GLOBAL_TECHNICAL_INVENTORY_V1'
  and archived_at is null;

update public.lf_activos
set
  raw_payload=jsonb_set(
    coalesce(raw_payload,'{}'::jsonb),
    '{fast_lookup_map}',
    to_jsonb('inventory.fn_lookup_v3'::text),
    true
  ),
  metadata=jsonb_set(
    coalesce(metadata,'{}'::jsonb),
    '{inventory_lookup}',
    jsonb_build_object(
      'canonical','inventory.fn_lookup_v3(text,text[],integer,text[])',
      'deprecated_compatibility','inventory.fn_lookup_v2(text,text[],integer)',
      'policy','NEW_CALLS_USE_V3'
    ),
    true
  ),
  updated_at=now(),
  updated_by_execution_id='LF_GLOBAL_INVENTORY_B2_LOOKUP_V3'
where codigo_activo='AUTHORITY_READBACK'
  and archived_at is null;

update public.lf_activos
set
  metadata=jsonb_set(
    jsonb_set(
      coalesce(metadata,'{}'::jsonb),
      '{global_inventory,lookup}',
      to_jsonb('inventory.fn_lookup_v3(text,text[],integer,text[])'::text),
      true
    ),
    '{global_inventory,legacy_lookup}',
    to_jsonb('inventory.fn_lookup_v2(text,text[],integer)'::text),
    true
  ),
  updated_at=now(),
  updated_by_execution_id='LF_GLOBAL_INVENTORY_B2_LOOKUP_V3'
where codigo_activo in (
  'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
  'PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET'
)
and archived_at is null;

do $$
declare
  v_v2_security_definer boolean;
  v_v3_security_definer boolean;
begin
  select p.prosecdef into v_v2_security_definer
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='inventory'
    and p.oid='inventory.fn_lookup_v2(text,text[],integer)'::regprocedure;

  select p.prosecdef into v_v3_security_definer
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='inventory'
    and p.oid='inventory.fn_lookup_v3(text,text[],integer,text[])'::regprocedure;

  if coalesce(v_v2_security_definer,false) <> coalesce(v_v3_security_definer,false) then
    raise exception 'BLOCK_LOOKUP_V3_SECURITY_MODE_DIFFERS_FROM_V2';
  end if;

  if has_function_privilege('programacion_auditor','inventory.fn_lookup_v3(text,text[],integer,text[])','EXECUTE') is not true
     or has_function_privilege('programacion_builder','inventory.fn_lookup_v3(text,text[],integer,text[])','EXECUTE') is not true
     or has_function_privilege('programacion_human_authority','inventory.fn_lookup_v3(text,text[],integer,text[])','EXECUTE') is not true
     or has_function_privilege('programacion_verifier','inventory.fn_lookup_v3(text,text[],integer,text[])','EXECUTE') is not true
     or has_function_privilege('service_role','inventory.fn_lookup_v3(text,text[],integer,text[])','EXECUTE') is not true
  then
    raise exception 'BLOCK_LOOKUP_V3_REQUIRED_EXECUTE_GRANTS_MISSING';
  end if;

  if exists (
    select 1
    from public.lf_activos
    where codigo_activo='LF_GLOBAL_TECHNICAL_INVENTORY_V1'
      and raw_payload->>'lookup' <> 'inventory.fn_lookup_v3(text,text[],integer,text[])'
  ) then
    raise exception 'BLOCK_LOOKUP_V3_GLOBAL_INVENTORY_POINTER_NOT_UPDATED';
  end if;

  if exists (
    select 1
    from public.lf_activos
    where codigo_activo='AUTHORITY_READBACK'
      and raw_payload->>'fast_lookup_map' <> 'inventory.fn_lookup_v3'
  ) then
    raise exception 'BLOCK_LOOKUP_V3_AUTHORITY_READBACK_POINTER_NOT_UPDATED';
  end if;
end
$$;
