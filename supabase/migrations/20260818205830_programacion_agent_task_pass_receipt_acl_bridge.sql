create or replace function programacion.fn_agent_task_worker_context_receipt_ok(p_execution_id bigint)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, programacion
as $function$
  select exists(
    select 1
    from programacion.ejecuciones ex
    join programacion.context_packs cp on cp.execution_id=ex.id and cp.estado='COMPLETE' and cp.digest_version=2
    join programacion.objetivos_ejecucion obj on obj.execution_id=ex.id
    join programacion.evaluaciones eva on eva.objetivo_id=obj.id and eva.resultado='PASS'
    join programacion.evidencias ev on ev.evaluacion_id=eva.id
    where ex.id=p_execution_id
      and ex.request_ref~'^agent-task://[1-9][0-9]*$'
      and ev.tipo='VERIFIED_WORKER_RECEIPT'
      and ev.source_system='PROGRAMMING_AGENT_WORKER'
      and ev.sha256=ev.metadata->>'receipt_sha256'
      and ev.metadata#>>'{worker_receipt,status}'='PASS'
      and ev.metadata#>>'{worker_receipt,execution_id}'=ex.id::text
      and ev.metadata#>>'{worker_receipt,context_pack_id}'=cp.id::text
      and ev.metadata#>>'{worker_receipt,context_pack_sha256}'=cp.context_sha256
      and exists(
        select 1 from programacion.evidence_verifications vv
        where vv.evidence_id=ev.id
          and vv.verification_status='VERIFIED'
          and vv.evidence_sha256=ev.sha256
          and vv.source_system=ev.source_system
          and vv.source_ref=ev.source_ref
      )
  );
$function$;

revoke all on function programacion.fn_agent_task_worker_context_receipt_ok(bigint) from public, anon, authenticated;
grant execute on function programacion.fn_agent_task_worker_context_receipt_ok(bigint)
  to programacion_builder,programacion_auditor,programacion_verifier,programacion_promoter,programacion_human_authority;

create or replace view programacion.v_ejecucion_cierre
with (security_invoker=true)
as
with latest as (
  select o.id as objetivo_id,o.execution_id,o.aplicabilidad,e.id as evaluacion_id,e.resultado,e.intento
  from programacion.objetivos_ejecucion o
  left join lateral (
    select ev.id,ev.resultado,ev.intento
    from programacion.evaluaciones ev
    where ev.objetivo_id=o.id
    order by ev.intento desc
    limit 1
  ) e on true
), agg as (
  select latest.execution_id,
    count(*) as objetivos_total,
    count(*) filter(where latest.aplicabilidad='REQUIRED') as required_total,
    count(*) filter(where latest.aplicabilidad='NOT_APPLICABLE') as not_applicable_total,
    count(*) filter(where latest.aplicabilidad='BLOCKED') as blocked_by_applicability,
    count(*) filter(where latest.aplicabilidad='REQUIRED' and latest.resultado='PASS') as required_pass,
    count(*) filter(where latest.aplicabilidad='REQUIRED' and latest.resultado in('FAIL','FINDING','ERROR')) as required_fail,
    count(*) filter(where latest.aplicabilidad='REQUIRED' and latest.resultado='BLOCKED') as required_blocked,
    count(*) filter(where latest.aplicabilidad='REQUIRED' and (latest.resultado is null or latest.resultado='PENDING')) as required_pending
  from latest
  group by latest.execution_id
)
select ex.id as execution_id,ex.version_id,ex.repo_full_name,ex.branch_name,ex.head_sha,ex.estado,ex.veredicto,
  coalesce(a.objetivos_total,0) as objetivos_total,
  coalesce(a.required_total,0) as required_total,
  coalesce(a.not_applicable_total,0) as not_applicable_total,
  coalesce(a.blocked_by_applicability,0) as blocked_by_applicability,
  coalesce(a.required_pass,0) as required_pass,
  coalesce(a.required_fail,0) as required_fail,
  coalesce(a.required_blocked,0) as required_blocked,
  coalesce(a.required_pending,0) as required_pending,
  case
    when not exists(
      select 1 from programacion.context_packs cp
      where cp.execution_id=ex.id and cp.estado='COMPLETE'
    ) then 'BLOCKED_CONTEXT'
    when ex.request_ref~'^agent-task://[1-9][0-9]*$'
      and not programacion.fn_agent_task_worker_context_receipt_ok(ex.id)
      then 'BLOCKED_WORKER_CONTEXT_RECEIPT'
    when coalesce(a.objetivos_total,0)=0 then 'BLOCKED_EMPTY_UNIVERSE'
    when coalesce(a.blocked_by_applicability,0)>0 or coalesce(a.required_blocked,0)>0 then 'BLOCKED'
    when coalesce(a.required_fail,0)>0 then 'FAIL'
    when coalesce(a.required_pending,0)>0 then 'PENDING'
    when coalesce(a.required_total,0)=coalesce(a.required_pass,0) then 'ELIGIBLE_PASS'
    else 'PENDING'
  end as derived_status
from programacion.ejecuciones ex
left join agg a on a.execution_id=ex.id;