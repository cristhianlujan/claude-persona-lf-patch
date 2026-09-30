-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · M0.3 (PAULO-102)
-- Reproducible live call graph: SQL + triggers + constraints.
-- Read-only evidence script. Uses pg_temp objects and ends with ROLLBACK.
--
-- Resolution rules:
--   1. Parse pg_proc.prosrc (function body), not pg_get_functiondef headers.
--   2. Preserve explicit schema qualification for public/programacion/lf_ops calls.
--   3. Resolve unqualified fn_* calls by name only when no schema is explicit.
--   4. Exclude caller_oid = callee_oid.
--   5. Keep direct consumers of public.fn_input_governance_* wrappers as a controlled
--      second-hop incoming boundary so rule-exploration consumers remain in M0.3.
--
-- Current live scope:
--   108 IG/guard seed functions
--   + direct SQL neighbors
--   + direct consumers of public IG wrappers
--   = 117 DB functions.
--
-- Historical M0.2 baseline=118 remains unresolved and is NOT asserted here.

begin;

create temp table m03_allfunc on commit drop as
select
  p.oid,
  n.nspname schema_name,
  p.proname,
  pg_get_function_identity_arguments(p.oid) args,
  p.prosrc body
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('programacion','public','lf_ops')
  and p.prokind in ('f','p');

create temp table m03_seed108 on commit drop as
select *
from m03_allfunc
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

create temp table m03_tokens on commit drop as
select
  f.oid caller_oid,
  nullif(m[2],'') called_schema,
  m[3] called_name
from m03_allfunc f
cross join lateral regexp_matches(
  f.body,
  '(^|[^A-Za-z0-9_])(?:(programacion|public|lf_ops)\.)?(fn_[A-Za-z0-9_]+)[[:space:]]*\(',
  'g'
) m;

create temp table m03_resolved_edges on commit drop as
select distinct
  t.caller_oid,
  c.oid callee_oid
from m03_tokens t
join m03_allfunc c
  on c.proname=t.called_name
 and c.oid<>t.caller_oid
 and (t.called_schema is null or c.schema_name=t.called_schema);

create temp table m03_hop1 on commit drop as
select oid from m03_seed108
union
select callee_oid oid
from m03_resolved_edges
where caller_oid in (select oid from m03_seed108)
union
select caller_oid oid
from m03_resolved_edges
where callee_oid in (select oid from m03_seed108);

create temp table m03_public_wrappers on commit drop as
select f.oid
from m03_hop1 h
join m03_allfunc f on f.oid=h.oid
where f.schema_name='public'
  and f.proname like 'fn_input_governance_%';

create temp table m03_wrapper_consumers on commit drop as
select distinct e.caller_oid oid
from m03_resolved_edges e
where e.callee_oid in (select oid from m03_public_wrappers);

create temp table m03_scope117 on commit drop as
select oid from m03_hop1
union
select oid from m03_wrapper_consumers;

create temp table m03_edges on commit drop as
select *
from m03_resolved_edges
where caller_oid in (select oid from m03_scope117)
   or callee_oid in (select oid from m03_scope117);

create temp table m03_trigger_edges on commit drop as
select
  t.oid trigger_oid,
  pn.nspname function_schema,
  p.proname function_name,
  pg_get_function_identity_arguments(p.oid) function_args,
  n.nspname table_schema,
  c.relname table_name,
  t.tgname trigger_name,
  case
    when (t.tgtype & 2)=2 then 'BEFORE'
    when (t.tgtype & 64)=64 then 'INSTEAD OF'
    else 'AFTER'
  end timing,
  array_remove(array[
    case when (t.tgtype & 4)=4 then 'INSERT' end,
    case when (t.tgtype & 8)=8 then 'DELETE' end,
    case when (t.tgtype & 16)=16 then 'UPDATE' end,
    case when (t.tgtype & 32)=32 then 'TRUNCATE' end
  ],null) events
from pg_trigger t
join pg_proc p on p.oid=t.tgfoid
join pg_namespace pn on pn.oid=p.pronamespace
join pg_class c on c.oid=t.tgrelid
join pg_namespace n on n.oid=c.relnamespace
where not t.tgisinternal
  and p.oid in (select oid from m03_scope117);

create temp table m03_constraint_edges on commit drop as
select
  con.oid constraint_oid,
  n.nspname table_schema,
  c.relname table_name,
  con.conname constraint_name,
  f.oid function_oid,
  f.schema_name function_schema,
  f.proname function_name,
  f.args function_args
from m03_scope117 s
join m03_allfunc f on f.oid=s.oid
join pg_constraint con
  on pg_get_constraintdef(con.oid) ilike '%'||f.proname||'%'
join pg_class c on c.oid=con.conrelid
join pg_namespace n on n.oid=c.relnamespace;

create temp table m03_degrees on commit drop as
select
  f.oid,
  f.schema_name,
  f.proname,
  f.args,
  count(distinct ein.caller_oid) caller_count,
  count(distinct eout.callee_oid) callee_count,
  count(distinct te.trigger_oid) trigger_binding_count,
  count(distinct ce.constraint_oid) constraint_binding_count
from m03_scope117 s
join m03_allfunc f on f.oid=s.oid
left join m03_edges ein on ein.callee_oid=f.oid
left join m03_edges eout on eout.caller_oid=f.oid
left join m03_trigger_edges te
  on te.function_schema=f.schema_name
 and te.function_name=f.proname
 and te.function_args=f.args
left join m03_constraint_edges ce on ce.function_oid=f.oid
group by f.oid,f.schema_name,f.proname,f.args;

do $m03$
declare
  v_graph jsonb;
  v_sha text;
  v integer;
begin
  if (select count(*) from m03_seed108)<>108 then
    raise exception 'M03_SEED_COUNT_DRIFT';
  end if;

  if (select count(*) from m03_public_wrappers)<>5 then
    raise exception 'M03_PUBLIC_WRAPPER_COUNT_DRIFT';
  end if;

  if (
    select count(*)
    from m03_wrapper_consumers
    where oid not in (select oid from m03_hop1)
  )<>2 then
    raise exception 'M03_SECOND_HOP_WRAPPER_CONSUMER_COUNT_DRIFT';
  end if;

  if (select count(*) from m03_scope117)<>117 then
    raise exception 'M03_SCOPE_COUNT_DRIFT';
  end if;

  if (
    select count(*) from m03_edges
    where caller_oid in (select oid from m03_scope117)
      and callee_oid in (select oid from m03_scope117)
  )<>262 then
    raise exception 'M03_IN_SCOPE_EDGE_DRIFT';
  end if;

  if (
    select count(*) from m03_edges
    where caller_oid in (select oid from m03_scope117)
      and callee_oid not in (select oid from m03_scope117)
  )<>2 then
    raise exception 'M03_OUT_BOUNDARY_EDGE_DRIFT';
  end if;

  if (
    select count(*) from m03_edges
    where caller_oid not in (select oid from m03_scope117)
      and callee_oid in (select oid from m03_scope117)
  )<>33 then
    raise exception 'M03_IN_BOUNDARY_EDGE_DRIFT';
  end if;

  if (select count(*) from m03_trigger_edges)<>21 then
    raise exception 'M03_TRIGGER_BINDING_DRIFT';
  end if;

  if (
    select count(*)
    from m03_trigger_edges
    where cardinality(events)>1
  )<>5 then
    raise exception 'M03_MULTI_EVENT_TRIGGER_COUNT_DRIFT';
  end if;

  if (select count(*) from m03_constraint_edges)<>5 then
    raise exception 'M03_CONSTRAINT_BINDING_DRIFT';
  end if;

  if (
    select count(*)
    from m03_degrees
    where caller_count=0
      and trigger_binding_count=0
      and constraint_binding_count=0
  )<>21 then
    raise exception 'M03_NO_SQL_CALLER_COUNT_DRIFT';
  end if;

  if (
    select count(*)
    from m03_degrees
    where callee_count=0
  )<>18 then
    raise exception 'M03_NO_SQL_CALLEE_COUNT_DRIFT';
  end if;

  select jsonb_build_object(
    'scope_count',(select count(*) from m03_scope117),
    'scope_members',(
      select jsonb_agg(
        f.schema_name||'.'||f.proname||'('||f.args||')'
        order by f.schema_name,f.proname,f.args
      )
      from m03_scope117 s
      join m03_allfunc f on f.oid=s.oid
    ),
    'edges',(
      select jsonb_agg(
        jsonb_build_object(
          'caller',ca.schema_name||'.'||ca.proname||'('||ca.args||')',
          'callee',ce.schema_name||'.'||ce.proname||'('||ce.args||')',
          'caller_in_scope',e.caller_oid in (select oid from m03_scope117),
          'callee_in_scope',e.callee_oid in (select oid from m03_scope117)
        )
        order by ca.schema_name,ca.proname,ca.args,ce.schema_name,ce.proname,ce.args
      )
      from m03_edges e
      join m03_allfunc ca on ca.oid=e.caller_oid
      join m03_allfunc ce on ce.oid=e.callee_oid
    ),
    'triggers',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'table',table_schema||'.'||table_name,
            'trigger',trigger_name,
            'function',function_schema||'.'||function_name||'('||function_args||')'
          )
          order by table_schema,table_name,trigger_name
        ),
        '[]'::jsonb
      )
      from m03_trigger_edges
    ),
    'constraints',(
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'table',table_schema||'.'||table_name,
            'constraint',constraint_name,
            'function',function_schema||'.'||function_name||'('||function_args||')'
          )
          order by table_schema,table_name,constraint_name
        ),
        '[]'::jsonb
      )
      from m03_constraint_edges
    )
  ) into v_graph;

  v_sha := encode(
    extensions.digest(convert_to(v_graph::text,'UTF8'),'sha256'),
    'hex'
  );

  if v_sha<>'a70a01d28cf558bb9966208b0f12156cba57a9a33d7e347e0f63ae57b81d4e30' then
    raise exception 'M03_GRAPH_SHA_DRIFT:%',v_sha;
  end if;

  select count(*) into v
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where p.prokind in ('f','p')
    and (
      pg_get_functiondef(p.oid) ~*
        '(insert[[:space:]]+into|update)[[:space:]]+programacion\.input_family_assessments'
      or pg_get_functiondef(p.oid) ~*
        '(insert[[:space:]]+into|update)[[:space:]]+input_family_assessments'
    );

  if v<>8 then
    raise exception 'M03_ASSESSMENT_WRITER_DRIFT:%',v;
  end if;

  select count(*) into v
  from information_schema.triggers
  where event_object_schema='programacion'
    and event_object_table='input_family_assessments';

  if v<>11 then
    raise exception 'M03_ASSESSMENT_TRIGGER_DRIFT:%',v;
  end if;
end
$m03$;

-- One row per scoped function. Empty arrays are explicit graph boundaries
-- to be classified by M0.2; they are not silently converted into edges.
select
  f.schema_name||'.'||f.proname||'('||f.args||')' function_name,
  coalesce((
    select jsonb_agg(
      ca.schema_name||'.'||ca.proname||'('||ca.args||')'
      order by ca.schema_name,ca.proname,ca.args
    )
    from m03_edges e
    join m03_allfunc ca on ca.oid=e.caller_oid
    where e.callee_oid=f.oid
  ),'[]'::jsonb) callers,
  coalesce((
    select jsonb_agg(
      ce.schema_name||'.'||ce.proname||'('||ce.args||')'
      order by ce.schema_name,ce.proname,ce.args
    )
    from m03_edges e
    join m03_allfunc ce on ce.oid=e.callee_oid
    where e.caller_oid=f.oid
  ),'[]'::jsonb) callees,
  coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'table',te.table_schema||'.'||te.table_name,
        'trigger',te.trigger_name,
        'timing',te.timing,
        'events',to_jsonb(te.events)
      )
      order by te.table_schema,te.table_name,te.trigger_name
    )
    from m03_trigger_edges te
    where te.function_schema=f.schema_name
      and te.function_name=f.proname
      and te.function_args=f.args
  ),'[]'::jsonb) trigger_bindings,
  coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'table',ce.table_schema||'.'||ce.table_name,
        'constraint',ce.constraint_name
      )
      order by ce.table_schema,ce.table_name,ce.constraint_name
    )
    from m03_constraint_edges ce
    where ce.function_oid=f.oid
  ),'[]'::jsonb) constraint_bindings
from m03_scope117 s
join m03_allfunc f on f.oid=s.oid
order by f.schema_name,f.proname,f.args;

rollback;
