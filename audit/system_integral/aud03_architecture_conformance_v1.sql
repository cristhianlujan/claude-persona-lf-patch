-- AUD-3 architecture conformance database controls v1
-- Read-only; freeze-bound to dafe10a / 56c2af88.
with active_assets as (
 select * from public.lf_activos where archived_at is null
),
dup_names as (
 select tipo_activo,nombre_canonico,count(*) n,jsonb_agg(codigo_activo order by codigo_activo) codes
 from active_assets group by tipo_activo,nombre_canonico having count(*)>1
),
det_candidates as (
 select operation_code,step_id,contract_code,resolver_ref,status,purpose
 from public.lf_operation_step_contracts
 where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
   and resolver_ref like 'GPT_RUNTIME%'
   and lower(step_id||' '||coalesce(purpose,'')) ~ '(determin|schema|currentness|parity|duplicate|readback|validate|validation|integrity|hash|fingerprint)'
),
router_steps as (
 select operation_code,step_id,contract_code,resolver_ref,status
 from public.lf_operation_step_contracts
 where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
   and lower(step_id) ~ '(^router$|router_)'
),
router_candidates as (
 select * from router_steps
 where lower(coalesce(resolver_ref,'')) not like '%act-0001%'
   and lower(coalesce(resolver_ref,'')) not like '%lf_router%'
   and lower(coalesce(resolver_ref,'')) not like '%router%'
),
outside_view as (
 select a.codigo_activo,a.tipo_activo,a.estado_operativo
 from active_assets a left join public.v_lf_fuente_operativa v using(codigo_activo)
 where v.codigo_activo is null
)
select jsonb_build_object(
 'duplicate_active_name_groups',(select count(*) from dup_names),
 'duplicate_active_names',coalesce((select jsonb_agg(to_jsonb(dup_names) order by tipo_activo,nombre_canonico) from dup_names),'[]'::jsonb),
 'currentness',jsonb_build_object(
   'operational_view_rows',(select count(*) from public.v_lf_fuente_operativa),
   'version_cleanup_required',(select count(*) from public.v_lf_fuente_operativa where requiere_limpieza_version),
   'missing_owner',(select count(*) from public.v_lf_fuente_operativa where nullif(btrim(coalesce(owner_name,'')),'') is null),
   'missing_url',(select count(*) from public.v_lf_fuente_operativa where nullif(btrim(coalesce(url,'')),'') is null),
   'active_assets_outside_view',coalesce((select jsonb_agg(to_jsonb(outside_view) order by codigo_activo) from outside_view),'[]'::jsonb)
 ),
 'deterministic_semantic_split_candidates',jsonb_build_object(
   'count',(select count(*) from det_candidates),
   'rows',coalesce((select jsonb_agg(to_jsonb(det_candidates) order by operation_code,step_id) from det_candidates),'[]'::jsonb)
 ),
 'router_authority_candidates',jsonb_build_object(
   'router_steps',(select count(*) from router_steps),
   'candidate_count',(select count(*) from router_candidates),
   'rows',coalesce((select jsonb_agg(to_jsonb(router_candidates) order by operation_code,step_id) from router_candidates),'[]'::jsonb)
 ),
 'architecture_closure',(select to_jsonb(v) from public.v_lf_architecture_closure_current v)
) as aud03_db_architecture_conformance;
