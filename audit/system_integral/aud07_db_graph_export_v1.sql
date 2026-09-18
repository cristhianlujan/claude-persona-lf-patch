-- AUD-7 unified graph DB/operation export v1
-- Read-only. Freeze: main dafe10a6a730d63bc59ce036360f214cd6fd8d96
-- schema_fp: 56c2af889d3f6a4781b1ac74ba7da5bb
-- Material edges are catalog/active-binding validated. Function body refs are emitted separately as INFERRED.
with
relations as (
 select n.nspname||'.'||c.relname name
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','private','programacion') and c.relkind in ('r','p','v','m','f')
),
fn_family as (
 select distinct n.nspname||'.'||p.proname name
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private','programacion') and p.prokind='f'
),
db_objects as (
 select name,'RELATION' kind from relations
 union all select name,'FUNCTION_FAMILY' kind from fn_family
),
fk as (
 select 'db::'||ns.nspname||'.'||cs.relname source,
        'db::'||nt.nspname||'.'||ct.relname target,
        'DB_FK' kind
 from pg_constraint con
 join pg_class cs on cs.oid=con.conrelid join pg_namespace ns on ns.oid=cs.relnamespace
 join pg_class ct on ct.oid=con.confrelid join pg_namespace nt on nt.oid=ct.relnamespace
 where con.contype='f' and ns.nspname in ('public','private','programacion') and nt.nspname in ('public','private','programacion')
),
viewdeps as (
 select distinct 'db::'||vn.nspname||'.'||v.relname source,'db::'||rn.nspname||'.'||r.relname target,'DB_VIEW_DEP' kind
 from pg_rewrite rw
 join pg_class v on v.oid=rw.ev_class join pg_namespace vn on vn.oid=v.relnamespace
 join pg_depend d on d.classid='pg_rewrite'::regclass and d.objid=rw.oid and d.refclassid='pg_class'::regclass
 join pg_class r on r.oid=d.refobjid join pg_namespace rn on rn.oid=r.relnamespace
 where v.relkind in ('v','m') and vn.nspname in ('public','private','programacion')
   and rn.nspname in ('public','private','programacion') and v.oid<>r.oid
),
op_step as (
 select 'op::'||operation_code source,'step::'||operation_code||'/'||step_id target,'OP_STEP' kind
 from public.lf_operation_steps where active
),
step_contract as (
 select 'step::'||operation_code||'/'||step_id source,'contract::'||contract_code target,'STEP_CONTRACT' kind
 from public.lf_operation_step_contracts where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
),
judge_bind as (
 select 'step::'||operation_code||'/'||step_id source,'judge::'||operation_code||'/'||judge_code target,'STEP_JUDGE' kind
 from public.lf_operation_step_judge_bindings where status='ACTIVE_ENFORCEMENT'
),
policy_bind as (
 select 'op::'||operation_code source,'policy::'||policy_code target,'OP_POLICY' kind
 from public.lf_operation_policy_bindings where binding_status='ACTIVE'
),
active_contracts as (
 select operation_code,step_id,contract_code,
        concat_ws(' ',coalesce(resolver_ref,''),coalesce(execution_sql,''),coalesce(notes,'')) txt
 from public.lf_operation_step_contracts
 where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
),
qualified_tokens as (
 select c.operation_code,c.step_id,c.contract_code,(m)[1] schema_name,(m)[2] object_name
 from active_contracts c,
 lateral regexp_matches(c.txt,'(public|private|programacion)\.([A-Za-z_][A-Za-z0-9_]*)','g') m
),
step_db as (
 select distinct 'step::'||t.operation_code||'/'||t.step_id source,
        case when d.kind='FUNCTION_FAMILY' then 'dbfn::'||d.name else 'db::'||d.name end target,
        'STEP_DB_CATALOG_VALIDATED' kind
 from qualified_tokens t
 join db_objects d on d.name=t.schema_name||'.'||t.object_name
),
unqualified_candidates as (
 select distinct 'step::'||c.operation_code||'/'||c.step_id source,d.name target,d.kind object_kind,c.contract_code
 from active_contracts c
 join db_objects d
   on lower(c.txt) ~ ('(^|[^a-z0-9_])'||lower(split_part(d.name,'.',2))||'([^a-z0-9_]|$)')
  and lower(c.txt) !~ ('(public|private|programacion)\.'||lower(split_part(d.name,'.',2))||'([^a-z0-9_]|$)')
),
funcs as (
 select n.nspname||'.'||p.proname source_name,lower(pg_get_functiondef(p.oid)) def
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private','programacion') and p.prokind='f'
),
ftokens as (
 select f.source_name,(m)[1] target_schema,(m)[2] target_name
 from funcs f,lateral regexp_matches(f.def,'(public|private|programacion)\.([a-z_][a-z0-9_]*)','g') m
),
func_inferred as (
 select distinct 'dbfn::'||t.source_name source,
        case when r.name is not null then 'db::'||t.target_schema||'.'||t.target_name else 'dbfn::'||t.target_schema||'.'||t.target_name end target,
        'DB_FUNCTION_REF_INFERRED' kind
 from ftokens t
 left join relations r on r.name=t.target_schema||'.'||t.target_name
 left join fn_family f on f.name=t.target_schema||'.'||t.target_name
 where r.name is not null or f.name is not null
),
material_edges as (
 select * from fk union select * from viewdeps union select * from op_step
 union select * from step_contract union select * from judge_bind union select * from policy_bind union select * from step_db
)
select jsonb_build_object(
 'schema_version','aud07-db-graph-export/v1',
 'freeze',jsonb_build_object('main_sha','dafe10a6a730d63bc59ce036360f214cd6fd8d96','schema_fp','56c2af889d3f6a4781b1ac74ba7da5bb'),
 'db_objects',coalesce((select jsonb_agg(jsonb_build_object('name',name,'kind',kind) order by name,kind) from db_objects),'[]'::jsonb),
 'material_edges',coalesce((select jsonb_agg(jsonb_build_object('source',source,'target',target,'kind',kind) order by kind,source,target) from material_edges),'[]'::jsonb),
 'inferred_edges',coalesce((select jsonb_agg(jsonb_build_object('source',source,'target',target,'kind',kind) order by source,target) from func_inferred),'[]'::jsonb),
 'candidate_unqualified',coalesce((select jsonb_agg(jsonb_build_object('source',source,'target',target,'object_kind',object_kind,'contract_code',contract_code) order by source,target) from unqualified_candidates),'[]'::jsonb),
 'metrics',jsonb_build_object(
   'material_edges',(select count(*) from material_edges),
   'inferred_edges',(select count(*) from func_inferred),
   'step_db_edges',(select count(*) from step_db),
   'candidate_unqualified_edges',(select count(*) from unqualified_candidates)
 )
) aud07_db_graph_export;
