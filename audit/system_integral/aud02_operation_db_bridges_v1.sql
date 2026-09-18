-- AUD-2 operation -> DB cross-layer bridges v2
-- Read-only. Material edges use the SAME active-status filter as AUD-2 operational graph.
-- Bare object-name matches are emitted only as CANDIDATE_UNQUALIFIED, never material edges.
with db_objects as (
  select n.nspname schema_name,c.relname object_name,n.nspname||'.'||c.relname target,'RELATION' object_kind
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private','programacion') and c.relkind in ('r','p','v','m','f')
  union
  select n.nspname,p.proname,n.nspname||'.'||p.proname,'FUNCTION'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','programacion') and p.prokind='f'
),
active_contracts as (
  select operation_code,step_id,contract_code,status,
         concat_ws(' ',coalesce(resolver_ref,''),coalesce(execution_sql,''),coalesce(notes,'')) txt
  from public.lf_operation_step_contracts
  where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
),
qualified_tokens as (
  select c.operation_code,c.step_id,c.contract_code,(m)[1] schema_name,(m)[2] object_name
  from active_contracts c,
  lateral regexp_matches(c.txt,'(public|private|programacion)\.([A-Za-z_][A-Za-z0-9_]*)','g') m
),
resolved as (
  select distinct
    t.operation_code||'/'||t.step_id source,d.target,d.object_kind,t.contract_code
  from qualified_tokens t join db_objects d using(schema_name,object_name)
),
unresolved as (
  select distinct t.operation_code||'/'||t.step_id source,t.schema_name||'.'||t.object_name target,t.contract_code
  from qualified_tokens t
  where not exists(select 1 from db_objects d where d.schema_name=t.schema_name and d.object_name=t.object_name)
),
unqualified_candidates as (
  select distinct
    c.operation_code||'/'||c.step_id source,d.target,d.object_kind,c.contract_code
  from active_contracts c
  join db_objects d
    on lower(c.txt) ~ ('(^|[^a-z0-9_])'||lower(d.object_name)||'([^a-z0-9_]|$)')
   and lower(c.txt) !~ ('(public|private|programacion)\.'||lower(d.object_name)||'([^a-z0-9_]|$)')
)
select jsonb_build_object(
 'active_contracts',(select count(*) from active_contracts),
 'qualified_tokens',(select count(*) from qualified_tokens),
 'material_edges',(select count(*) from resolved),
 'distinct_sources',(select count(distinct source) from resolved),
 'distinct_targets',(select count(distinct target) from resolved),
 'unresolved_qualified_refs',(select count(*) from unresolved),
 'candidate_unqualified_edges',(select count(*) from unqualified_candidates),
 'candidate_unqualified_sources',(select count(distinct source) from unqualified_candidates),
 'candidate_unqualified_targets',(select count(distinct target) from unqualified_candidates),
 'unresolved_targets',coalesce((select jsonb_agg(distinct target order by target) from unresolved),'[]'::jsonb),
 'material_edges_rows',coalesce((select jsonb_agg(jsonb_build_object('source',source,'target',target,'kind','STEP_DB_CATALOG_VALIDATED','object_kind',object_kind,'contract_code',contract_code) order by source,target) from resolved),'[]'::jsonb),
 'candidate_unqualified_rows',coalesce((select jsonb_agg(jsonb_build_object('source',source,'target',target,'kind','CANDIDATE_UNQUALIFIED','object_kind',object_kind,'contract_code',contract_code) order by source,target) from unqualified_candidates),'[]'::jsonb)
) as aud02_operation_db_bridges;
