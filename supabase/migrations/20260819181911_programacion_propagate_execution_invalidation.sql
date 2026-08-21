create or replace view programacion.v_ejecucion_cierre as
with latest as (
  select o.id as objetivo_id,
         o.execution_id,
         o.aplicabilidad,
         e.id as evaluacion_id,
         e.resultado,
         e.intento
  from programacion.objetivos_ejecucion o
  left join lateral (
    select ev.id, ev.resultado, ev.intento
    from programacion.evaluaciones ev
    where ev.objetivo_id = o.id
    order by ev.intento desc
    limit 1
  ) e on true
), agg as (
  select latest.execution_id,
         count(*) as objetivos_total,
         count(*) filter (where latest.aplicabilidad = 'REQUIRED') as required_total,
         count(*) filter (where latest.aplicabilidad = 'NOT_APPLICABLE') as not_applicable_total,
         count(*) filter (where latest.aplicabilidad = 'BLOCKED') as blocked_by_applicability,
         count(*) filter (where latest.aplicabilidad = 'REQUIRED' and latest.resultado = 'PASS') as required_pass,
         count(*) filter (where latest.aplicabilidad = 'REQUIRED' and latest.resultado = any (array['FAIL','FINDING','ERROR'])) as required_fail,
         count(*) filter (where latest.aplicabilidad = 'REQUIRED' and latest.resultado = 'BLOCKED') as required_blocked,
         count(*) filter (where latest.aplicabilidad = 'REQUIRED' and (latest.resultado is null or latest.resultado = 'PENDING')) as required_pending
  from latest
  group by latest.execution_id
)
select ex.id as execution_id,
       ex.version_id,
       ex.repo_full_name,
       ex.branch_name,
       ex.head_sha,
       ex.estado,
       case
         when exists (select 1 from programacion.execution_invalidations inv where inv.execution_id = ex.id) then 'INVALIDATED'::text
         else ex.veredicto
       end as veredicto,
       coalesce(a.objetivos_total,0::bigint) as objetivos_total,
       coalesce(a.required_total,0::bigint) as required_total,
       coalesce(a.not_applicable_total,0::bigint) as not_applicable_total,
       coalesce(a.blocked_by_applicability,0::bigint) as blocked_by_applicability,
       coalesce(a.required_pass,0::bigint) as required_pass,
       coalesce(a.required_fail,0::bigint) as required_fail,
       coalesce(a.required_blocked,0::bigint) as required_blocked,
       coalesce(a.required_pending,0::bigint) as required_pending,
       case
         when exists (select 1 from programacion.execution_invalidations inv where inv.execution_id = ex.id) then 'INVALIDATED'::text
         when not exists (select 1 from programacion.context_packs cp where cp.execution_id = ex.id and cp.estado = 'COMPLETE') then 'BLOCKED_CONTEXT'::text
         when ex.request_ref ~ '^agent-task://[1-9][0-9]*$' and not programacion.fn_agent_task_worker_context_receipt_ok(ex.id) then 'BLOCKED_WORKER_CONTEXT_RECEIPT'::text
         when coalesce(a.objetivos_total,0::bigint)=0 then 'BLOCKED_EMPTY_UNIVERSE'::text
         when coalesce(a.blocked_by_applicability,0::bigint)>0 or coalesce(a.required_blocked,0::bigint)>0 then 'BLOCKED'::text
         when coalesce(a.required_fail,0::bigint)>0 then 'FAIL'::text
         when coalesce(a.required_pending,0::bigint)>0 then 'PENDING'::text
         when coalesce(a.required_total,0::bigint)=coalesce(a.required_pass,0::bigint) then 'ELIGIBLE_PASS'::text
         else 'PENDING'::text
       end as derived_status
from programacion.ejecuciones ex
left join agg a on a.execution_id = ex.id;