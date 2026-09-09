-- OP24 / Strategy24 — durable Learned Context lineage carrier V3 candidate.
-- SOURCE_ONLY / NOT_DEPLOYED / CANDIDATO_READ_ONLY.
-- No migration is generated or applied by this source file.
-- Parent authority: LF_LEARNED_CONTEXT_MEMORY_MODEL_20260904.
-- Strategy24 requires origin -> destination lineage with disposition, reason and evidence.
-- Only relations with an unambiguous origin -> destination orientation are admitted here.
-- DERIVED_FROM and RETIRES remain intentionally excluded until a separate semantic contract exists.
-- Reuses the common recorder pattern: the operation that performs a transformation
-- must already have a clean evidence step whose active judge binding explicitly requires `lineage`.

create table programacion.learned_context_lineage (
  lineage_id bigint generated always as identity primary key,
  transformation_group_id uuid not null,
  source_type text not null check (source_type in ('KB','EKB','CARD')),
  source_ref text not null check (length(btrim(source_ref)) > 0),
  target_type text not null check (target_type in ('KB','EKB','CARD')),
  target_ref text not null check (length(btrim(target_ref)) > 0),
  relation_type text not null check (
    relation_type in ('TRANSFORMED_TO','MOVED_TO','MERGED_INTO','SPLIT_INTO','SUPERSEDES')
  ),
  disposition_reason text not null check (length(btrim(disposition_reason)) > 0),
  reversible boolean not null,
  evidence_execution_id text not null check (length(btrim(evidence_execution_id)) > 0),
  evidence_step_id text not null check (length(btrim(evidence_step_id)) > 0),
  evidence_ref text not null check (length(btrim(evidence_ref)) > 0),
  authority_snapshot_id bigint not null,
  authority_snapshot_code text not null,
  authority_snapshot_version text not null,
  created_by_execution_id text not null check (length(btrim(created_by_execution_id)) > 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint learned_context_lineage_same_execution
    check (created_by_execution_id = evidence_execution_id),
  constraint learned_context_lineage_no_self_loop
    check (not (source_type = target_type and source_ref = target_ref)),
  constraint learned_context_lineage_unique_edge
    unique (transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type)
);

alter table programacion.learned_context_lineage enable row level security;
alter table programacion.learned_context_lineage force row level security;
revoke all on programacion.learned_context_lineage from public, anon, authenticated, service_role,
  programacion_builder, programacion_auditor, programacion_human_authority;

create or replace function programacion.lf_learned_context_ref_resolves_v3(p_type text,p_ref text)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $function$
begin
  if p_type='KB' then
    if coalesce(p_ref,'') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      return false;
    end if;
    return exists(select 1 from public.lf_knowledge_base where kb_id=p_ref::uuid);
  elsif p_type='EKB' then
    -- public.lf_error_knowledge is the governed compatibility view over transversal.error_knowledge.
    return exists(select 1 from public.lf_error_knowledge where codigo=p_ref);
  elsif p_type='CARD' then
    return exists(select 1 from public.lf_cards where id_card=p_ref);
  end if;
  return false;
exception when invalid_text_representation then
  return false;
end
$function$;

revoke all on function programacion.lf_learned_context_ref_resolves_v3(text,text)
  from public, anon, authenticated, service_role;

create or replace function programacion.record_learned_context_lineage_v1(
  p_execution_id text,
  p_evidence_step_id text,
  p_transformation_group_id uuid,
  p_source_type text,
  p_source_ref text,
  p_target_type text,
  p_target_ref text,
  p_relation_type text,
  p_disposition_reason text,
  p_reversible boolean,
  p_authority_snapshot_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_step public.lf_operation_execution_steps%rowtype;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
  v_authority public.lf_strategy_snapshots%rowtype;
  v_lineage jsonb;
  v_id bigint;
  v_cycle boolean := false;
begin
  if p_execution_id is null or btrim(p_execution_id)=''
     or p_evidence_step_id is null or btrim(p_evidence_step_id)=''
     or p_transformation_group_id is null
     or p_source_type is null or btrim(p_source_type)=''
     or p_source_ref is null or btrim(p_source_ref)=''
     or p_target_type is null or btrim(p_target_type)=''
     or p_target_ref is null or btrim(p_target_ref)=''
     or p_relation_type is null or btrim(p_relation_type)=''
     or p_disposition_reason is null or btrim(p_disposition_reason)=''
     or p_authority_snapshot_id is null then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_REQUIRED_INPUT_MISSING','durable',false);
  end if;

  if p_source_type not in ('KB','EKB','CARD') or p_target_type not in ('KB','EKB','CARD') then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_TYPE_INVALID','durable',false);
  end if;
  if p_relation_type not in ('TRANSFORMED_TO','MOVED_TO','MERGED_INTO','SPLIT_INTO','SUPERSEDES') then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_RELATION_INVALID_OR_AMBIGUOUS','durable',false);
  end if;
  if p_source_type=p_target_type and p_source_ref=p_target_ref then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_SELF_LOOP_FORBIDDEN','durable',false);
  end if;

  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_EXECUTION_NOT_RESOLVED','durable',false);
  end if;
  if v_execution.status <> 'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false);
  end if;

  select * into v_step
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id=p_evidence_step_id;
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_EVIDENCE_STEP_NOT_RESOLVED','durable',false);
  end if;

  select * into v_binding
  from public.lf_operation_step_judge_bindings
  where operation_code=v_execution.operation_code
    and step_id=p_evidence_step_id
    and status='ACTIVE_ENFORCEMENT';
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_EVIDENCE_BINDING_NOT_ACTIVE','durable',false);
  end if;
  if not (coalesce(v_binding.required_evidence_keys,'[]'::jsonb) @> '["lineage"]'::jsonb) then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_NOT_REQUIRED_BY_PRODUCER_CONTRACT','durable',false);
  end if;
  if v_step.status <> v_binding.clean_result_value then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_EVIDENCE_STEP_NOT_CLEAN','observed_status',v_step.status,'durable',false);
  end if;
  if v_step.evidence_ref is null or btrim(v_step.evidence_ref)='' then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_EVIDENCE_REF_MISSING','durable',false);
  end if;

  v_lineage := v_step.evidence_payload->'lineage';
  if jsonb_typeof(v_lineage) <> 'object'
     or jsonb_typeof(v_lineage->'reversible') <> 'boolean'
     or v_lineage->>'transformation_group_id' <> p_transformation_group_id::text
     or v_lineage->>'source_type' <> p_source_type
     or v_lineage->>'source_ref' <> p_source_ref
     or v_lineage->>'target_type' <> p_target_type
     or v_lineage->>'target_ref' <> p_target_ref
     or v_lineage->>'relation_type' <> p_relation_type
     or v_lineage->>'disposition_reason' <> p_disposition_reason
     or (v_lineage->>'reversible')::boolean <> p_reversible then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_EVIDENCE_EDGE_MISMATCH','durable',false);
  end if;

  if programacion.lf_learned_context_ref_resolves_v3(p_source_type,p_source_ref) is not true then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_SOURCE_REF_NOT_RESOLVED','durable',false);
  end if;
  if programacion.lf_learned_context_ref_resolves_v3(p_target_type,p_target_ref) is not true then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_TARGET_REF_NOT_RESOLVED','durable',false);
  end if;

  select * into v_authority
  from public.lf_strategy_snapshots
  where id=p_authority_snapshot_id
    and snapshot_code='LF_LEARNED_CONTEXT_MEMORY_MODEL_20260904'
    and archived_at is null
    and status <> 'SUPERSEDED';
  if not found then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_PARENT_AUTHORITY_NOT_CURRENT','durable',false);
  end if;
  if exists (
    select 1 from public.lf_strategy_snapshots newer
    where newer.snapshot_code=v_authority.snapshot_code
      and newer.id>v_authority.id
      and newer.archived_at is null
      and newer.status <> 'SUPERSEDED'
  ) then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_PARENT_AUTHORITY_STALE','durable',false);
  end if;

  if p_relation_type='SUPERSEDES' then
    -- Orientation: source is the newer/current entity; target is the older entity it supersedes.
    with recursive reach(node_type,node_ref) as (
      select p_target_type,p_target_ref
      union
      select e.target_type,e.target_ref
      from programacion.learned_context_lineage e
      join reach r on e.source_type=r.node_type and e.source_ref=r.node_ref
      where e.relation_type='SUPERSEDES'
    )
    select exists(
      select 1 from reach where node_type=p_source_type and node_ref=p_source_ref
    ) into v_cycle;
    if v_cycle then
      return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_SUPERSESSION_CYCLE_FORBIDDEN','durable',false);
    end if;
  end if;

  insert into programacion.learned_context_lineage(
    transformation_group_id,source_type,source_ref,target_type,target_ref,relation_type,
    disposition_reason,reversible,evidence_execution_id,evidence_step_id,evidence_ref,
    authority_snapshot_id,authority_snapshot_code,authority_snapshot_version,created_by_execution_id
  ) values (
    p_transformation_group_id,p_source_type,p_source_ref,p_target_type,p_target_ref,p_relation_type,
    p_disposition_reason,p_reversible,p_execution_id,p_evidence_step_id,v_step.evidence_ref,
    v_authority.id,v_authority.snapshot_code,v_authority.version,p_execution_id
  ) returning lineage_id into v_id;

  return jsonb_build_object(
    'outcome','LINEAGE_RECORDED','durable',true,'lineage_id',v_id,
    'execution_id',p_execution_id,'evidence_step_id',p_evidence_step_id,
    'authority_snapshot_id',v_authority.id,
    'authority_snapshot_version',v_authority.version
  );
exception
  when unique_violation then
    return jsonb_build_object('outcome','BLOCKED','code','LINEAGE_EDGE_DUPLICATE','durable',false);
end
$function$;

revoke all on function programacion.record_learned_context_lineage_v1(
  text,text,uuid,text,text,text,text,text,text,boolean,bigint
) from public, anon, authenticated;
grant execute on function programacion.record_learned_context_lineage_v1(
  text,text,uuid,text,text,text,text,text,text,boolean,bigint
) to service_role, programacion_builder, programacion_human_authority;

create or replace function programacion.block_learned_context_lineage_mutation_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','programacion'
as $function$
begin
  raise exception 'LEARNED_CONTEXT_LINEAGE_APPEND_ONLY';
end
$function$;

revoke all on function programacion.block_learned_context_lineage_mutation_v1()
  from public, anon, authenticated, service_role;

create trigger trg_learned_context_lineage_append_only
before update or delete on programacion.learned_context_lineage
for each row execute function programacion.block_learned_context_lineage_mutation_v1();

comment on table programacion.learned_context_lineage is
  'Strategy24 durable lineage carrier candidate. Append-only origin->destination edges across KB/EKB/CARD. Writes only through a recorder bound to an explicitly lineage-required clean operation step and current Strategy24 authority. SOURCE_ONLY until governed migration approval.';
