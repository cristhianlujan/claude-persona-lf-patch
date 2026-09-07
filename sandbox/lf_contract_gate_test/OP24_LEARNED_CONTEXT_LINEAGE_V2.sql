-- OP24 Learned Context Lineage V2 — hardened sandbox candidate.
-- Extends V1 semantics with deterministic ref resolution, execution provenance,
-- pre-insert self-loop/cycle prevention and append-only lineage edges.
-- No production authorization. No durable migration.

create table private.sbx_lf_learned_context_lineage_v2 (
  id bigint generated always as identity primary key,
  transformation_group_id uuid not null,
  source_type text not null check (source_type in ('KB','EKB','CARD')),
  source_ref text not null check (length(btrim(source_ref)) > 0),
  target_type text not null check (target_type in ('KB','EKB','CARD')),
  target_ref text not null check (length(btrim(target_ref)) > 0),
  relation_type text not null check (
    relation_type in ('DERIVED_FROM','TRANSFORMED_TO','MOVED_TO','MERGED_INTO','SPLIT_INTO','SUPERSEDES','RETIRES')
  ),
  disposition_reason text not null check (length(btrim(disposition_reason)) > 0),
  evidence_ref text not null check (length(btrim(evidence_ref)) > 0),
  authority_ref text not null check (length(btrim(authority_ref)) > 0),
  reversible boolean not null,
  created_by_execution_id text not null check (length(btrim(created_by_execution_id)) > 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint sbx_lf_learned_context_lineage_v2_no_self_loop
    check (not (source_type = target_type and source_ref = target_ref)),
  constraint sbx_lf_learned_context_lineage_v2_unique_edge
    unique (transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type)
);

alter table private.sbx_lf_learned_context_lineage_v2 enable row level security;
alter table private.sbx_lf_learned_context_lineage_v2 force row level security;
revoke all on private.sbx_lf_learned_context_lineage_v2 from public, anon, authenticated, service_role;

create or replace function private.sbx_fn_lf_lineage_ref_resolves_v2(p_type text,p_ref text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if p_type='KB' then
    if coalesce(p_ref,'') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
    return exists(select 1 from public.lf_knowledge_base where kb_id=p_ref::uuid);
  elsif p_type='EKB' then
    return exists(select 1 from public.lf_error_knowledge where codigo=p_ref);
  elsif p_type='CARD' then
    return exists(select 1 from public.lf_cards where id_card=p_ref);
  end if;
  return false;
exception when invalid_text_representation then
  return false;
end
$function$;

revoke all on function private.sbx_fn_lf_lineage_ref_resolves_v2(text,text) from public, anon, authenticated, service_role;

create or replace function private.sbx_fn_lf_lineage_guard_v2()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'private', 'public'
as $function$
declare v_cycle boolean := false;
begin
  if new.source_type=new.target_type and new.source_ref=new.target_ref then
    raise exception 'LINEAGE_SELF_LOOP_FORBIDDEN';
  end if;
  if private.sbx_fn_lf_lineage_ref_resolves_v2(new.source_type,new.source_ref) is not true then
    raise exception 'LINEAGE_SOURCE_REF_NOT_RESOLVED:%:%',new.source_type,new.source_ref;
  end if;
  if private.sbx_fn_lf_lineage_ref_resolves_v2(new.target_type,new.target_ref) is not true then
    raise exception 'LINEAGE_TARGET_REF_NOT_RESOLVED:%:%',new.target_type,new.target_ref;
  end if;
  if not exists(select 1 from public.lf_operation_execution where execution_id=new.created_by_execution_id) then
    raise exception 'LINEAGE_EXECUTION_PROVENANCE_NOT_RESOLVED:%',new.created_by_execution_id;
  end if;
  if new.relation_type='SUPERSEDES' then
    with recursive reach(node_type,node_ref) as (
      select new.target_type,new.target_ref
      union
      select e.target_type,e.target_ref
      from private.sbx_lf_learned_context_lineage_v2 e
      join reach r on e.source_type=r.node_type and e.source_ref=r.node_ref
      where e.relation_type='SUPERSEDES'
    )
    select exists(select 1 from reach where node_type=new.source_type and node_ref=new.source_ref) into v_cycle;
    if v_cycle then raise exception 'LINEAGE_SUPERSESSION_CYCLE_FORBIDDEN'; end if;
  end if;
  return new;
end
$function$;

revoke all on function private.sbx_fn_lf_lineage_guard_v2() from public, anon, authenticated, service_role;
create trigger trg_sbx_lf_lineage_guard_v2 before insert on private.sbx_lf_learned_context_lineage_v2 for each row execute function private.sbx_fn_lf_lineage_guard_v2();

create or replace function private.sbx_fn_lf_lineage_append_only_v2()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'private'
as $function$
begin raise exception 'LINEAGE_EDGES_ARE_APPEND_ONLY'; end
$function$;

revoke all on function private.sbx_fn_lf_lineage_append_only_v2() from public, anon, authenticated, service_role;
create trigger trg_sbx_lf_lineage_append_only_v2 before update or delete on private.sbx_lf_learned_context_lineage_v2 for each row execute function private.sbx_fn_lf_lineage_append_only_v2();

comment on table private.sbx_lf_learned_context_lineage_v2 is
  'OP24 hardened sandbox-only lineage carrier. Canonical refs: KB=kb_id UUID, EKB=codigo, CARD=id_card. No production authority.';
