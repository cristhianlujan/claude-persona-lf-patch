-- OP24 Learned Context Lineage durable candidate v1.
-- SOURCE-ONLY. This file does not authorize DDL application, runtime, production,
-- historical backfill, Card creation, or Strategy 23 execution.
-- Derived from PR #575 V2 rollback-proven semantics and bound to Strategy24 v0.3.

create table programacion.learned_context_lineage (
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
  constraint learned_context_lineage_no_self_loop
    check (not (source_type = target_type and source_ref = target_ref)),
  constraint learned_context_lineage_unique_edge
    unique (transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type)
);

alter table programacion.learned_context_lineage enable row level security;
alter table programacion.learned_context_lineage force row level security;
revoke all on programacion.learned_context_lineage from public, anon, authenticated, service_role;

create or replace function programacion.lf_lineage_ref_resolves_v1(p_type text,p_ref text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $function$
begin
  if p_type='KB' then
    if coalesce(p_ref,'') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      return false;
    end if;
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

revoke all on function programacion.lf_lineage_ref_resolves_v1(text,text) from public, anon, authenticated, service_role;

create or replace function programacion.lf_lineage_guard_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion', 'public'
as $function$
declare
  v_cycle boolean := false;
begin
  if new.source_type=new.target_type and new.source_ref=new.target_ref then
    raise exception 'LINEAGE_SELF_LOOP_FORBIDDEN';
  end if;
  if programacion.lf_lineage_ref_resolves_v1(new.source_type,new.source_ref) is not true then
    raise exception 'LINEAGE_SOURCE_REF_NOT_RESOLVED:%:%',new.source_type,new.source_ref;
  end if;
  if programacion.lf_lineage_ref_resolves_v1(new.target_type,new.target_ref) is not true then
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
      from programacion.learned_context_lineage e
      join reach r on e.source_type=r.node_type and e.source_ref=r.node_ref
      where e.relation_type='SUPERSEDES'
    )
    select exists(select 1 from reach where node_type=new.source_type and node_ref=new.source_ref) into v_cycle;
    if v_cycle then
      raise exception 'LINEAGE_SUPERSESSION_CYCLE_FORBIDDEN';
    end if;
  end if;
  return new;
end
$function$;

revoke all on function programacion.lf_lineage_guard_v1() from public, anon, authenticated, service_role;
create trigger trg_lf_lineage_guard_v1
before insert on programacion.learned_context_lineage
for each row execute function programacion.lf_lineage_guard_v1();

create or replace function programacion.lf_lineage_append_only_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'programacion'
as $function$
begin
  raise exception 'LINEAGE_EDGES_ARE_APPEND_ONLY';
end
$function$;

revoke all on function programacion.lf_lineage_append_only_v1() from public, anon, authenticated, service_role;
create trigger trg_lf_lineage_append_only_v1
before update or delete on programacion.learned_context_lineage
for each row execute function programacion.lf_lineage_append_only_v1();

create or replace function programacion.record_learned_context_lineage_v1(
  p_source_type text,
  p_source_ref text,
  p_target_type text,
  p_target_ref text,
  p_relation_type text,
  p_created_by_execution_id text,
  p_payload jsonb
)
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion', 'public'
as $function$
declare
  v_group uuid;
  v_reason text;
  v_evidence text;
  v_authority text;
  v_reversible boolean;
  v_id bigint;
begin
  if coalesce(jsonb_typeof(p_payload),'null') <> 'object' then
    raise exception 'LINEAGE_PAYLOAD_OBJECT_REQUIRED';
  end if;
  v_reason := btrim(coalesce(p_payload->>'disposition_reason',''));
  v_evidence := btrim(coalesce(p_payload->>'evidence_ref',''));
  v_authority := btrim(coalesce(p_payload->>'authority_ref',''));
  if v_reason='' or v_evidence='' or v_authority='' then
    raise exception 'LINEAGE_PAYLOAD_REQUIRED_FIELDS_MISSING';
  end if;
  if p_payload ? 'transformation_group_id' then
    begin
      v_group := (p_payload->>'transformation_group_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'LINEAGE_TRANSFORMATION_GROUP_UUID_REQUIRED';
    end;
  else
    v_group := gen_random_uuid();
  end if;
  if jsonb_typeof(p_payload->'reversible') <> 'boolean' then
    raise exception 'LINEAGE_REVERSIBLE_BOOLEAN_REQUIRED';
  end if;
  v_reversible := (p_payload->>'reversible')::boolean;

  insert into programacion.learned_context_lineage(
    transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
    disposition_reason,evidence_ref,authority_ref,reversible,created_by_execution_id
  ) values (
    v_group,p_source_type,p_source_ref,p_target_type,p_target_ref,p_relation_type,
    v_reason,v_evidence,v_authority,v_reversible,p_created_by_execution_id
  ) returning id into v_id;
  return v_id;
end
$function$;

revoke all on function programacion.record_learned_context_lineage_v1(text,text,text,text,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function programacion.record_learned_context_lineage_v1(text,text,text,text,text,text,jsonb)
  to service_role;

comment on table programacion.learned_context_lineage is
  'Strategy24 candidate durable lineage carrier. Canonical refs: KB=kb_id UUID, EKB=public.lf_error_knowledge.codigo (view over transversal.error_knowledge), CARD=id_card. Append-only; writes only through governed recorder.';
