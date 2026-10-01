-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · M0.2 (PAULO-101)
-- Live inventory v2: separates IG proper from boundary functions, derives
-- transitive liveness from runtime roots, and verifies post-#1324 registry closure.
-- Read-only evidence; ends with ROLLBACK.
--
-- IMPORTANT:
-- The historical "118 functions" member list was never preserved and is NOT
-- reconstructed here. Current observed scope is modeled explicitly as:
--   113 IG_PROPER functions + 6 BOUNDARY functions = 119 functions
--   + 3 registered IG Edge runtimes = 122 inventory rows.
--
-- Legacy inventory/liveness labels are observational only. Canonical lifecycle
-- remains governed by POL-LF-STATE-MODEL v2.0-canonical-lifecycle.

begin;

create temp table m02_allfunc on commit drop as
select
  p.oid,
  n.nspname schema_name,
  p.proname,
  pg_get_function_identity_arguments(p.oid) args,
  p.prosrc body,
  n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('programacion','public','lf_ops')
  and p.prokind in ('f','p');

create temp table m02_seed109 on commit drop as
select *
from m02_allfunc
where
  (schema_name='programacion' and (
    proname like 'fn_input_governance_%'
    or proname like 'fn_input_readiness_%'
    or (
      proname like 'fn_input_%'
      and proname not like 'fn_input_governance_%'
      and proname not like 'fn_input_readiness_%'
    )
    or proname='fn_lf_router_input_governance_resolve_v1'
    or proname like 'fn_guard_input_%'
  ))
  or (
    schema_name='public'
    and proname='fn_input_governance_validator_resume_context_v1'
  );

create temp table m02_wrappers4 on commit drop as
select *
from m02_allfunc
where schema_name='public'
  and proname in (
    'fn_input_governance_execute',
    'fn_input_governance_safe_autofix_v1',
    'fn_input_governance_curator_materialize_v1',
    'fn_input_governance_validator_validate_v1'
  );

create temp table m02_ig_proper113 on commit drop as
select oid from m02_seed109
union
select oid from m02_wrappers4;

create temp table m02_tokens on commit drop as
select
  f.oid caller_oid,
  nullif(m[2],'') called_schema,
  m[3] called_name
from m02_allfunc f
cross join lateral regexp_matches(
  f.body,
  '(^|[^A-Za-z0-9_])(?:(programacion|public|lf_ops)\.)?(fn_[A-Za-z0-9_]+)[[:space:]]*\(',
  'g'
) m;

create temp table m02_edges on commit drop as
select distinct
  t.caller_oid,
  c.oid callee_oid
from m02_tokens t
join m02_allfunc c
  on c.proname=t.called_name
 and c.oid<>t.caller_oid
 and (t.called_schema is null or c.schema_name=t.called_schema);

create temp table m02_out_closure on commit drop as
with recursive closure(oid) as (
  select oid from m02_ig_proper113
  union
  select e.callee_oid
  from closure c
  join m02_edges e on e.caller_oid=c.oid
)
select distinct oid from closure;

create temp table m02_boundary_dependencies3 on commit drop as
select oid
from m02_out_closure
where oid not in (select oid from m02_ig_proper113);

create temp table m02_boundary_consumers3 on commit drop as
select distinct e.caller_oid oid
from m02_edges e
where e.callee_oid in (select oid from m02_ig_proper113)
  and e.caller_oid not in (select oid from m02_ig_proper113);

create temp table m02_boundary6 on commit drop as
select oid,'TRANSVERSAL_DEPENDENCY'::text scope_role
from m02_boundary_dependencies3
union
select oid,'EXTERNAL_CONSUMER'::text
from m02_boundary_consumers3;

create temp table m02_inventory119 on commit drop as
select oid,'IG_PROPER'::text scope_role
from m02_ig_proper113
union
select oid,scope_role
from m02_boundary6;

create temp table m02_trigger_roots on commit drop as
select distinct t.tgfoid oid
from pg_trigger t
where not t.tgisinternal
  and t.tgfoid in (select oid from m02_inventory119);

create temp table m02_constraint_roots on commit drop as
select distinct f.oid
from m02_inventory119 i
join m02_allfunc f on f.oid=i.oid
join pg_constraint c
  on pg_get_constraintdef(c.oid) ilike '%'||f.proname||'%';

create temp table m02_known_api_roots on commit drop as
select oid
from m02_allfunc
where
  (
    schema_name='public'
    and proname in (
      'fn_input_governance_execute',
      'fn_input_governance_safe_autofix_v1',
      'fn_input_governance_curator_materialize_v1',
      'fn_input_governance_validator_validate_v1',
      'fn_input_governance_validator_resume_context_v1',
      'lf_router_resolve_v1',
      'lf_rule_exploration_prepare_v1',
      'lf_rule_exploration_materialize_candidate_v1'
    )
  )
  or (
    schema_name='programacion'
    and proname in (
      'fn_lf_router_input_governance_resolve_v1',
      'fn_input_source_inventory_lookup_l1_v1'
    )
  );

create temp table m02_external_caller_roots on commit drop as
select distinct e.callee_oid oid
from m02_edges e
where e.callee_oid in (select oid from m02_inventory119)
  and e.caller_oid not in (select oid from m02_inventory119);

create temp table m02_roots on commit drop as
select oid from m02_trigger_roots
union select oid from m02_constraint_roots
union select oid from m02_known_api_roots
union select oid from m02_external_caller_roots;

create temp table m02_active_reachable on commit drop as
with recursive reachable(oid) as (
  select oid from m02_roots
  union
  select e.callee_oid
  from reachable r
  join m02_edges e on e.caller_oid=r.oid
  join m02_allfunc f on f.oid=e.callee_oid
  where e.callee_oid in (select oid from m02_inventory119)
    and f.proname not like '%shadow%'
    and f.proname not like '%test%'
    and f.proname not like '%fixture%'
)
select distinct oid from reachable;

create temp table m02_registered_members on commit drop as
select jsonb_array_elements_text(
  coalesce(a.raw_payload->'members','[]'::jsonb)
) member
from public.lf_activos a
where a.archived_at is null
  and (
    (a.subtipo_activo='DB_FUNCTION_SET'
     and a.codigo_activo like 'PROGRAMACION_FN_INPUT_GOVERNANCE_%')
    or a.codigo_activo='PROGRAMACION_INPUT_SOURCE_INVENTORY_L1'
  );

create temp table m02_function_rows on commit drop as
select
  f.oid,
  'FUNCTION'::text item_type,
  f.identity item_identity,
  i.scope_role,
  case
    when f.proname like '%shadow%' then 'SHADOW'
    when f.proname like '%test%' or f.proname like '%fixture%' then 'TEST'
    when f.oid in (select oid from m02_active_reachable) then 'ACTIVE_REACHABLE'
    when exists (
      select 1
      from m02_edges e
      where e.callee_oid=f.oid
        and e.caller_oid in (select oid from m02_inventory119)
    ) then 'ACTIVE_ONLY_VIA_UNUSED'
    when f.proname like '%candidate%' then 'CANDIDATE'
    else 'ORPHAN'
  end liveness_label,
  case
    when i.scope_role<>'IG_PROPER' then 'EXTERNAL_OWNER_BOUNDARY'
    when f.identity in (select member from m02_registered_members)
      or (
        f.schema_name='programacion'
        and f.proname='fn_lf_router_input_governance_resolve_v1'
        and exists (
          select 1 from public.lf_activos a
          where a.archived_at is null
            and a.codigo_activo='PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'
        )
      )
      then 'REGISTERED_FUNCTION_IDENTITY'
    else 'UNREGISTERED_FUNCTION_IDENTITY'
  end registry_status
from m02_inventory119 i
join m02_allfunc f on f.oid=i.oid;

create temp table m02_edge_rows on commit drop as
select
  null::oid oid,
  'EDGE'::text item_type,
  a.codigo_activo item_identity,
  'IG_EDGE_RUNTIME'::text scope_role,
  'ACTIVE_REACHABLE'::text liveness_label,
  'REGISTERED_FUNCTION_IDENTITY'::text registry_status
from public.lf_activos a
where a.archived_at is null
  and a.codigo_activo in (
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1',
    'EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1'
  );

create temp table m02_all_rows on commit drop as
select oid,item_type,item_identity,scope_role,liveness_label,registry_status
from m02_function_rows
union all
select * from m02_edge_rows;

do $m02$
declare
  v_rows jsonb;
  v_sha text;
begin
  if (select count(*) from m02_seed109)<>109 then
    raise exception 'M02_SEED_COUNT_DRIFT';
  end if;

  if (select count(*) from m02_wrappers4)<>4 then
    raise exception 'M02_WRAPPER_COUNT_DRIFT';
  end if;

  if (select count(*) from m02_ig_proper113)<>113 then
    raise exception 'M02_IG_PROPER_COUNT_DRIFT';
  end if;

  if (select count(*) from m02_boundary_dependencies3)<>3 then
    raise exception 'M02_BOUNDARY_DEPENDENCY_COUNT_DRIFT';
  end if;

  if (select count(*) from m02_boundary_consumers3)<>3 then
    raise exception 'M02_BOUNDARY_CONSUMER_COUNT_DRIFT';
  end if;

  if (select count(*) from m02_boundary6)<>6 then
    raise exception 'M02_BOUNDARY_COUNT_DRIFT';
  end if;

  if (select count(*) from m02_function_rows)<>119 then
    raise exception 'M02_FUNCTION_COUNT_DRIFT';
  end if;

  if (select count(*) from m02_edge_rows)<>3 then
    raise exception 'M02_EDGE_COUNT_DRIFT';
  end if;

  if (select count(*) from m02_all_rows)<>122 then
    raise exception 'M02_TOTAL_ROW_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m02_function_rows
    where liveness_label='ACTIVE_REACHABLE'
  )<>90 then
    raise exception 'M02_ACTIVE_REACHABLE_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m02_function_rows
    where liveness_label='ACTIVE_ONLY_VIA_UNUSED'
  )<>12 then
    raise exception 'M02_ACTIVE_ONLY_UNUSED_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m02_function_rows
    where liveness_label='ORPHAN'
  )<>11 then
    raise exception 'M02_ORPHAN_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m02_function_rows
    where liveness_label='SHADOW'
  )<>6 then
    raise exception 'M02_SHADOW_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m02_function_rows
    where liveness_label in ('TEST','CANDIDATE')
  )<>0 then
    raise exception 'M02_TEST_OR_CANDIDATE_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m02_all_rows
    where registry_status='REGISTERED_FUNCTION_IDENTITY'
  )<>116 then
    raise exception 'M02_REGISTERED_FUNCTION_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m02_all_rows
    where registry_status='UNREGISTERED_FUNCTION_IDENTITY'
  )<>0 then
    raise exception 'M02_UNREGISTERED_FUNCTION_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m02_all_rows
    where registry_status='EXTERNAL_OWNER_BOUNDARY'
  )<>6 then
    raise exception 'M02_EXTERNAL_BOUNDARY_COUNT_DRIFT';
  end if;

  if (
    select count(*)
    from public.lf_activos
    where archived_at is null
      and codigo_activo='PROGRAMACION_INPUT_SOURCE_INVENTORY_L1'
      and estado_documental='CANDIDATO'
      and estado_operativo='READ_ONLY'
      and runtime_estado='CANDIDATE_READ_ONLY'
      and metadata->>'approval_status'='NOT_APPROVED'
      and metadata->>'l2_decision_note'='decidir en L2 si lo absorbe T-SOURCE'
  )<>1 then
    raise exception 'M02_SOURCE_INVENTORY_CANDIDATE_ASSET_DRIFT';
  end if;

  if not exists (
    select 1
    from m02_function_rows
    where item_identity='programacion.fn_input_source_inventory_lookup_l1_v1(p_term text)'
      and registry_status='REGISTERED_FUNCTION_IDENTITY'
  ) then
    raise exception 'M02_LOOKUP_FUNCTION_REGISTRY_STATUS_DRIFT';
  end if;

  if not exists (
    select 1
    from public.lf_policy_versions
    where policy_code='POL-LF-STATE-MODEL'
      and policy_version='v2.0-canonical-lifecycle'
      and policy_sha='f0d039a7a0f5588494c1f31b27a57ed7de8877a2a191bcd205cd38a6d5b495b3'
      and status='ACTIVE'
  ) then
    raise exception 'M02_STATE_MODEL_POLICY_DRIFT';
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'item_type',item_type,
      'item_identity',item_identity,
      'scope_role',scope_role,
      'liveness_label',liveness_label,
      'registry_status',registry_status
    )
    order by item_type,item_identity
  )
  into v_rows
  from m02_all_rows;

  v_sha := encode(
    extensions.digest(convert_to(v_rows::text,'UTF8'),'sha256'),
    'hex'
  );

  if v_sha<>'977178a13c06adec4b6c7033c7dc07519eeb2a63351d3c8a4ba5da2991222ae3' then
    raise exception 'M02_INVENTORY_SHA_DRIFT:%',v_sha;
  end if;
end
$m02$;

select
  (select count(*) from m02_ig_proper113) ig_proper_count,
  (select count(*) from m02_boundary6) boundary_count,
  (select count(*) from m02_function_rows) function_count,
  (select count(*) from m02_edge_rows) edge_count,
  (select count(*) from m02_all_rows) total_rows,
  (select jsonb_object_agg(liveness_label,n order by liveness_label)
   from (
     select liveness_label,count(*) n
     from m02_function_rows
     group by liveness_label
   ) x) function_liveness_counts,
  (select jsonb_object_agg(registry_status,n order by registry_status)
   from (
     select registry_status,count(*) n
     from m02_all_rows
     group by registry_status
   ) x) registry_counts;

-- Explicitly surface the functions that are reachable only through unused chains.
select
  f.item_identity,
  coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'caller',ca.identity,
        'caller_reachable',e.caller_oid in (select oid from m02_active_reachable),
        'caller_shadow',ca.proname like '%shadow%'
      )
      order by ca.identity
    )
    from m02_edges e
    join m02_allfunc ca on ca.oid=e.caller_oid
    where e.callee_oid=f.oid
      and e.caller_oid in (select oid from m02_inventory119)
  ),'[]'::jsonb) callers
from m02_function_rows f
where f.liveness_label='ACTIVE_ONLY_VIA_UNUSED'
order by f.item_identity;

-- Explicit registry gaps. The source-inventory capability asset does not silently
-- convert its lookup function into a registered DB_FUNCTION identity.
select item_identity
from m02_function_rows
where registry_status='UNREGISTERED_FUNCTION_IDENTITY'
order by item_identity;

-- Full deterministic inventory receipt.
select item_type,item_identity,scope_role,liveness_label,registry_status
from m02_all_rows
order by item_type,item_identity;

rollback;
