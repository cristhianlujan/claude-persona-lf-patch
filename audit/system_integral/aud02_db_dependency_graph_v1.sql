-- AUD-2 DB / OPERATION dependency graph v1
-- Read-only. Bound to main dafe10a6a730d63bc59ce036360f214cd6fd8d96
-- and schema_fp 56c2af889d3f6a4781b1ac74ba7da5bb.
with
fk as (
  select 'FK'::text kind,con.conrelid::regclass::text source,con.confrelid::regclass::text target,con.conname detail
  from pg_constraint con
  join pg_class cs on cs.oid=con.conrelid join pg_namespace ns on ns.oid=cs.relnamespace
  join pg_class ct on ct.oid=con.confrelid join pg_namespace nt on nt.oid=ct.relnamespace
  where con.contype='f' and ns.nspname in ('public','private','programacion') and nt.nspname in ('public','private','programacion')
),
viewdeps as (
  select distinct 'VIEW_RELATION'::text kind,vn.nspname||'.'||v.relname source,rn.nspname||'.'||r.relname target,''::text detail
  from pg_rewrite rw
  join pg_class v on v.oid=rw.ev_class join pg_namespace vn on vn.oid=v.relnamespace
  join pg_depend d on d.classid='pg_rewrite'::regclass and d.objid=rw.oid and d.refclassid='pg_class'::regclass
  join pg_class r on r.oid=d.refobjid join pg_namespace rn on rn.oid=r.relnamespace
  where v.relkind in ('v','m') and vn.nspname in ('public','private','programacion')
    and rn.nspname in ('public','private','programacion') and v.oid<>r.oid
),
funcs as (
  select p.oid,n.nspname,p.proname,
         n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' source,
         lower(pg_get_functiondef(p.oid)) def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','programacion') and p.prokind='f'
),
tokens as (
  select f.source,(m)[1] target_schema,(m)[2] target_name
  from funcs f,lateral regexp_matches(f.def,'(public|private|programacion)\.([a-z_][a-z0-9_]*)','g') m
),
func_rel as (
  select distinct 'FUNCTION_RELATION_INFERRED'::text kind,t.source,t.target_schema||'.'||t.target_name target,''::text detail
  from tokens t join pg_class c on c.relname=t.target_name join pg_namespace n on n.oid=c.relnamespace and n.nspname=t.target_schema
),
func_func as (
  select distinct 'FUNCTION_FUNCTION_INFERRED'::text kind,t.source,
         n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' target,''::text detail
  from tokens t join pg_proc p on p.proname=t.target_name join pg_namespace n on n.oid=p.pronamespace and n.nspname=t.target_schema
),
op_step as (
  select 'OP_STEP'::text kind,operation_code source,operation_code||'/'||step_id target,step_order::text detail
  from public.lf_operation_steps where active
),
step_contract as (
  select 'STEP_CONTRACT'::text kind,operation_code||'/'||step_id source,contract_code target,coalesce(resolver_ref,'') detail
  from public.lf_operation_step_contracts where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
),
judge_bind as (
  select 'STEP_JUDGE'::text kind,operation_code||'/'||step_id source,judge_code target,coalesce(clean_result_value,'') detail
  from public.lf_operation_step_judge_bindings where status='ACTIVE_ENFORCEMENT'
),
policy_bind as (
  select 'OP_POLICY'::text kind,operation_code source,policy_code target,coalesce(policy_role,'') detail
  from public.lf_operation_policy_bindings where binding_status='ACTIVE'
),
caps as (
  select codigo_activo capability_code from public.v_lf_fuente_operativa where tipo_activo='CAPABILITY'
),
cap_contract as (
  select distinct 'CAPABILITY_CONSUMED_BY_OPERATION'::text kind,c.capability_code source,s.operation_code target,'CONTRACT_TEXT'::text detail
  from caps c join public.lf_operation_step_contracts s
    on concat_ws(' ',coalesce(s.resolver_ref,''),coalesce(s.notes,''),coalesce(s.execution_sql,''),
                 coalesce(s.input_required::text,''),coalesce(s.output_payload::text,''),coalesce(s.required_evidence_keys::text,''))
       ~ ('(^|[^A-Z0-9_-])'||regexp_replace(c.capability_code,'([\W])','\\\1','g')||'([^A-Z0-9_-]|$)')
),
cap_relation as (
  select distinct 'CAPABILITY_ASSET_RELATION'::text kind,c.capability_code source,r.codigo_activo target,r.relacion_tipo detail
  from caps c join public.lf_activo_relaciones r on r.relacionado_codigo=c.capability_code
),
catalog_edges as (select * from fk union all select * from viewdeps),
inferred_function_edges as (select * from func_rel union all select * from func_func),
operational_edges as (select * from op_step union all select * from step_contract union all select * from judge_bind union all select * from policy_bind),
capability_edges as (select * from cap_contract union all select * from cap_relation)
select jsonb_build_object(
 'catalog',jsonb_build_object(
   'fk',(select count(*) from fk),'view_relation',(select count(*) from viewdeps),'total',(select count(*) from catalog_edges),
   'fingerprint',(select md5(coalesce(string_agg(kind||'|'||source||'|'||target||'|'||detail,E'\n' order by kind,source,target,detail),'')) from catalog_edges)
 ),
 'functions_inferred',jsonb_build_object(
   'functions_scanned',(select count(*) from funcs),'qualified_tokens',(select count(*) from tokens),
   'relation_edges',(select count(*) from func_rel),'function_edges',(select count(*) from func_func),
   'total',(select count(*) from inferred_function_edges),
   'fingerprint',(select md5(coalesce(string_agg(kind||'|'||source||'|'||target,E'\n' order by kind,source,target),'')) from inferred_function_edges),
   'evidence_class','INFERRED_FROM_FUNCTION_DEFINITION'
 ),
 'operations',jsonb_build_object(
   'op_step',(select count(*) from op_step),'step_contract',(select count(*) from step_contract),
   'step_judge',(select count(*) from judge_bind),'op_policy',(select count(*) from policy_bind),
   'total',(select count(*) from operational_edges),
   'fingerprint',(select md5(coalesce(string_agg(kind||'|'||source||'|'||target||'|'||detail,E'\n' order by kind,source,target,detail),'')) from operational_edges)
 ),
 'capabilities',jsonb_build_object(
   'universe',(select count(*) from caps),
   'registry_rows',(select count(*) from public.lf_capability_registry),
   'binding_rows',(select count(*) from public.lf_capability_binding),
   'contract_edges',(select count(*) from cap_contract),'asset_relation_edges',(select count(*) from cap_relation),
   'with_observed_consumer',(select count(distinct source) from capability_edges),
   'without_observed_consumer',(select count(*) from caps c where not exists(select 1 from capability_edges e where e.source=c.capability_code)),
   'fingerprint',(select md5(coalesce(string_agg(kind||'|'||source||'|'||target||'|'||detail,E'\n' order by kind,source,target,detail),'')) from capability_edges)
 )
) as aud02_db_dependency_summary;
