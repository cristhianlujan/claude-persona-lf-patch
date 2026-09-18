-- AUD-2 transitive closure summary v1
-- Read-only. Catalog and operational graphs are kept separate.
with recursive
catalog_edges as (
  select con.conrelid::regclass::text source,con.confrelid::regclass::text target
  from pg_constraint con
  join pg_class cs on cs.oid=con.conrelid join pg_namespace ns on ns.oid=cs.relnamespace
  join pg_class ct on ct.oid=con.confrelid join pg_namespace nt on nt.oid=ct.relnamespace
  where con.contype='f' and ns.nspname in ('public','private','programacion') and nt.nspname in ('public','private','programacion')
  union
  select distinct vn.nspname||'.'||v.relname,rn.nspname||'.'||r.relname
  from pg_rewrite rw
  join pg_class v on v.oid=rw.ev_class join pg_namespace vn on vn.oid=v.relnamespace
  join pg_depend d on d.classid='pg_rewrite'::regclass and d.objid=rw.oid and d.refclassid='pg_class'::regclass
  join pg_class r on r.oid=d.refobjid join pg_namespace rn on rn.oid=r.relnamespace
  where v.relkind in ('v','m') and vn.nspname in ('public','private','programacion')
    and rn.nspname in ('public','private','programacion') and v.oid<>r.oid
),
catalog_reach(source,target) as (
  select source,target from catalog_edges where source<>target
  union
  select r.source,e.target from catalog_reach r join catalog_edges e on e.source=r.target where r.source<>e.target
),
op_edges as (
  select operation_code source,operation_code||'/'||step_id target from public.lf_operation_steps where active
  union
  select operation_code||'/'||step_id,contract_code from public.lf_operation_step_contracts where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
  union
  select operation_code||'/'||step_id,judge_code from public.lf_operation_step_judge_bindings where status='ACTIVE_ENFORCEMENT'
  union
  select operation_code,policy_code from public.lf_operation_policy_bindings where binding_status='ACTIVE'
),
op_reach(source,target) as (
  select source,target from op_edges where source<>target
  union
  select r.source,e.target from op_reach r join op_edges e on e.source=r.target where r.source<>e.target
)
select jsonb_build_object(
 'catalog',jsonb_build_object(
   'direct_edges',(select count(*) from catalog_edges),
   'transitive_pairs',(select count(*) from catalog_reach),
   'nodes',(select count(*) from (select source n from catalog_edges union select target from catalog_edges)x),
   'top_dependents',coalesce((
     select jsonb_agg(jsonb_build_object('node',target,'dependents',n) order by n desc,target)
     from (select target,count(distinct source)n from catalog_reach group by target order by n desc,target limit 20)s
   ),'[]'::jsonb)
 ),
 'operations',jsonb_build_object(
   'direct_edges',(select count(*) from op_edges),
   'transitive_pairs',(select count(*) from op_reach),
   'nodes',(select count(*) from (select source n from op_edges union select target from op_edges)x),
   'top_dependents',coalesce((
     select jsonb_agg(jsonb_build_object('node',target,'dependents',n) order by n desc,target)
     from (select target,count(distinct source)n from op_reach group by target order by n desc,target limit 20)s
   ),'[]'::jsonb)
 )
) as aud02_transitive_summary;
