-- OP24 Learned Context Lineage V1 — sandbox candidate source
-- Source-first candidate only. Not a Supabase migration. No production authorization.
-- Target intentionally lives in private schema to avoid Data API exposure.

create table private.sbx_lf_learned_context_lineage_v1 (
  id bigint generated always as identity primary key,
  transformation_group_id uuid not null,
  source_type text not null check (length(btrim(source_type)) > 0),
  source_ref text not null check (length(btrim(source_ref)) > 0),
  target_type text not null check (length(btrim(target_type)) > 0),
  target_ref text not null check (length(btrim(target_ref)) > 0),
  relation_type text not null check (
    relation_type in (
      'DERIVED_FROM',
      'TRANSFORMED_TO',
      'MOVED_TO',
      'MERGED_INTO',
      'SPLIT_INTO',
      'SUPERSEDES',
      'RETIRES'
    )
  ),
  disposition_reason text not null check (length(btrim(disposition_reason)) > 0),
  evidence_ref text not null check (length(btrim(evidence_ref)) > 0),
  authority_ref text not null check (length(btrim(authority_ref)) > 0),
  reversible boolean not null,
  created_by_execution_id text not null check (length(btrim(created_by_execution_id)) > 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint sbx_lf_learned_context_lineage_v1_no_self_loop
    check (not (source_type = target_type and source_ref = target_ref)),
  constraint sbx_lf_learned_context_lineage_v1_unique_edge
    unique (
      transformation_group_id,
      source_type,
      source_ref,
      target_type,
      target_ref,
      relation_type
    )
);

alter table private.sbx_lf_learned_context_lineage_v1 enable row level security;
alter table private.sbx_lf_learned_context_lineage_v1 force row level security;
revoke all on private.sbx_lf_learned_context_lineage_v1 from public, anon, authenticated, service_role;

create or replace function private.sbx_fn_lf_learned_context_lineage_cycle_v1(
  p_relation_type text default 'SUPERSEDES'
)
returns boolean
language sql
stable
set search_path to 'pg_catalog', 'private'
as $function$
with recursive edges as (
  select source_type || ':' || source_ref as src,
         target_type || ':' || target_ref as dst
  from private.sbx_lf_learned_context_lineage_v1
  where relation_type = p_relation_type
), walk(start_node, node, path, has_cycle) as (
  select src, dst, array[src, dst]::text[], src = dst
  from edges
  union all
  select w.start_node,
         e.dst,
         w.path || e.dst,
         e.dst = any(w.path)
  from walk w
  join edges e on e.src = w.node
  where not w.has_cycle
    and cardinality(w.path) < 128
)
select exists(select 1 from walk where has_cycle);
$function$;

revoke all on function private.sbx_fn_lf_learned_context_lineage_cycle_v1(text)
  from public, anon, authenticated, service_role;

comment on table private.sbx_lf_learned_context_lineage_v1 is
  'OP24 sandbox-only lineage edge carrier. Source-first candidate; no production authority.';
