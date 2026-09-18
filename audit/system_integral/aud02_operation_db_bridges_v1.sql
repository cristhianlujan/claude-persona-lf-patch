-- AUD-2 operation -> DB cross-layer bridges v1
-- Read-only. Only qualified DB references that resolve to a real relation/function become material edges.
with db_objects as (
  select n.nspname schema_name,c.relname object_name,n.nspname||'.'||c.relname target,'RELATION' object_kind
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private','programacion') and c.relkind in ('r','p','v','m','f')
  union
  select n.nspname,p.proname,n.nspname||'.'||p.proname,'FUNCTION'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','programacion') and p.prokind='f'
),
contract_text as (
  select operation_code,step_id,contract_code,
         concat_ws(' ',coalesce(resolver_ref,''),coalesce(execution_sql,''),coalesce(notes,'')) txt
  from public.lf_operation_step_contracts
),
tokens as (
  select c.operation_code,c.step_id,c.contract_code,(m)[1] schema_name,(m)[2] object_name
  from contract_text c,
  lateral regexp_matches(c.txt,'(public|private|programacion)\.([A-Za-z_][A-Za-z0-9_]*)','g') m
),
resolved as (
  select distinct
    t.operation_code||'/'||t.step_id source,
    d.target,d.object_kind,t.contract_code
  from tokens t join db_objects d using(schema_name,object_name)
),
unresolved as (
  select distinct t.operation_code||'/'||t.step_id source,t.schema_name||'.'||t.object_name target,t.contract_code
  from tokens t
  where not exists(select 1 from db_objects d where d.schema_name=t.schema_name and d.object_name=t.object_name)
)
select jsonb_build_object(
 'qualified_tokens',(select count(*) from tokens),
 'material_edges',(select count(*) from resolved),
 'distinct_sources',(select count(distinct source) from resolved),
 'distinct_targets',(select count(distinct target) from resolved),
 'unresolved_refs',(select count(*) from unresolved),
 'unresolved_targets',coalesce((select jsonb_agg(distinct target order by target) from unresolved),'[]'::jsonb),
 'edges',coalesce((select jsonb_agg(jsonb_build_object('source',source,'target',target,'kind','STEP_DB_CATALOG_VALIDATED','object_kind',object_kind,'contract_code',contract_code) order by source,target) from resolved),'[]'::jsonb)
) as aud02_operation_db_bridges;
