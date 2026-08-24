create or replace function programacion.fn_guard_execution_update()
returns trigger
language plpgsql
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_missing_gates integer := 0;
  v_missing_controls integer := 0;
  v_foreign_gates integer := 0;
  v_superseded_gates integer := 0;
begin
  if old.estado = 'COMPLETED' then
    raise exception 'completed execution % is immutable', old.id;
  end if;

  if row(old.version_id, old.perfil_calidad_id, old.proyecto_codigo, old.repository_provider,
         old.repo_full_name, old.branch_name, old.head_sha, old.source_snapshot_sha256,
         old.target_language, old.scope, old.request_ref)
     is distinct from
     row(new.version_id, new.perfil_calidad_id, new.proyecto_codigo, new.repository_provider,
         new.repo_full_name, new.branch_name, new.head_sha, new.source_snapshot_sha256,
         new.target_language, new.scope, new.request_ref) then
    raise exception 'execution identity/scope is pinned; new HEAD or scope requires a new execution';
  end if;

  if old.estado='CREATED' and new.estado='RUNNING' then
    if not exists (
      select 1 from programacion.context_packs cp
      where cp.execution_id=old.id and cp.estado='COMPLETE'
    ) then
      raise exception 'execution % cannot RUN without COMPLETE Context Pack', old.id;
    end if;

    if not exists (
      select 1 from programacion.objetivos_ejecucion o where o.execution_id=old.id
    ) then
      raise exception 'execution % cannot RUN with empty frozen objective universe', old.id;
    end if;

    if exists (
      select 1 from programacion.objetivos_ejecucion o
      where o.execution_id=old.id and o.aplicabilidad='BLOCKED'
    ) then
      raise exception 'execution % has BLOCKED objectives and cannot RUN', old.id;
    end if;

    with recursive version_chain as (
      select v.id, v.supersedes_version_id, 0 as depth
      from programacion.versiones_agente v where v.id=old.version_id
      union all
      select p.id, p.supersedes_version_id, vc.depth+1
      from programacion.versiones_agente p
      join version_chain vc on p.id=vc.supersedes_version_id
    ), effective_gates as (
      select distinct on (g.gate_codigo) g.id
      from programacion.gates g
      join version_chain vc on vc.id=g.version_id
      where g.bloqueante=true and g.estado in ('defined','active')
      order by g.gate_codigo, vc.depth asc, g.id desc
    )
    select count(*) into v_missing_gates
    from effective_gates eg
    where not exists (
      select 1 from programacion.objetivos_ejecucion o
      where o.execution_id=old.id and o.gate_id=eg.id
    );

    if v_missing_gates > 0 then
      raise exception 'execution % frozen universe is missing % effective required gates', old.id, v_missing_gates;
    end if;

    with recursive version_chain as (
      select v.id, v.supersedes_version_id, 0 as depth
      from programacion.versiones_agente v where v.id=old.version_id
      union all
      select p.id, p.supersedes_version_id, vc.depth+1
      from programacion.versiones_agente p
      join version_chain vc on p.id=vc.supersedes_version_id
    ), effective_gates as (
      select distinct on (g.gate_codigo) g.id
      from programacion.gates g
      join version_chain vc on vc.id=g.version_id
      where g.bloqueante=true and g.estado in ('defined','active')
      order by g.gate_codigo, vc.depth asc, g.id desc
    )
    select count(*) into v_superseded_gates
    from programacion.objetivos_ejecucion o
    join programacion.gates g on g.id=o.gate_id
    where o.execution_id=old.id
      and g.bloqueante=true
      and g.estado in ('defined','active')
      and not exists (select 1 from effective_gates eg where eg.id=o.gate_id);

    if v_superseded_gates > 0 then
      raise exception 'execution % frozen universe contains % superseded gate revisions; keep only the effective revision per gate code', old.id, v_superseded_gates;
    end if;

    with recursive version_chain as (
      select v.id, v.supersedes_version_id
      from programacion.versiones_agente v where v.id=old.version_id
      union all
      select p.id, p.supersedes_version_id
      from programacion.versiones_agente p
      join version_chain vc on p.id=vc.supersedes_version_id
    )
    select count(*) into v_foreign_gates
    from programacion.objetivos_ejecucion o
    join programacion.gates g on g.id=o.gate_id
    where o.execution_id=old.id
      and o.gate_id is not null
      and not exists (select 1 from version_chain vc where vc.id=g.version_id);

    if v_foreign_gates > 0 then
      raise exception 'execution % frozen universe contains % gates outside its effective version chain', old.id, v_foreign_gates;
    end if;

    if old.perfil_calidad_id is not null then
      select count(*) into v_missing_controls
      from programacion.perfiles_calidad_controles pcc
      where pcc.perfil_id=old.perfil_calidad_id
        and pcc.obligatorio=true
        and pcc.estado in ('defined','active')
        and not exists (
          select 1 from programacion.objetivos_ejecucion o
          where o.execution_id=old.id and o.control_calidad_id=pcc.control_id
        );

      if v_missing_controls > 0 then
        raise exception 'execution % frozen universe is missing % required controls from quality profile %', old.id, v_missing_controls, old.perfil_calidad_id;
      end if;
    end if;

  elsif old.estado='CREATED' and new.estado='COMPLETED' then
    if new.veredicto <> 'BLOCKED' then
      raise exception 'CREATED execution can only close directly as BLOCKED';
    end if;
  elsif old.estado='RUNNING' and new.estado not in ('RUNNING','COMPLETED') then
    raise exception 'invalid execution transition % -> %', old.estado, new.estado;
  elsif old.estado='CREATED' and new.estado not in ('CREATED','RUNNING','COMPLETED') then
    raise exception 'invalid execution transition % -> %', old.estado, new.estado;
  end if;
  return new;
end;
$function$;

create or replace view programacion.v_ejecucion_cierre as
with recursive version_chain as (
  select ex.id as execution_id, v.id as version_id, v.supersedes_version_id, 0 as depth
  from programacion.ejecuciones ex
  join programacion.versiones_agente v on v.id=ex.version_id
  union all
  select vc.execution_id, p.id, p.supersedes_version_id, vc.depth+1
  from version_chain vc
  join programacion.versiones_agente p on p.id=vc.supersedes_version_id
), effective_gates as (
  select distinct on (vc.execution_id,g.gate_codigo)
         vc.execution_id,g.gate_codigo,g.id as gate_id
  from version_chain vc
  join programacion.gates g on g.version_id=vc.version_id
  where g.bloqueante=true and g.estado in ('defined','active')
  order by vc.execution_id,g.gate_codigo,vc.depth asc,g.id desc
), latest as (
  select o.id as objetivo_id,o.execution_id,o.aplicabilidad,
         e.id as evaluacion_id,e.resultado,e.intento
  from programacion.objetivos_ejecucion o
  left join effective_gates eg
    on eg.execution_id=o.execution_id and eg.gate_id=o.gate_id
  left join lateral (
    select ev.id,ev.resultado,ev.intento
    from programacion.evaluaciones ev
    where ev.objetivo_id=o.id
    order by ev.intento desc
    limit 1
  ) e on true
  where o.control_calidad_id is not null
     or o.gate_id is null
     or eg.gate_id is not null
), agg as (
  select execution_id,
         count(*) as objetivos_total,
         count(*) filter(where aplicabilidad='REQUIRED') as required_total,
         count(*) filter(where aplicabilidad='NOT_APPLICABLE') as not_applicable_total,
         count(*) filter(where aplicabilidad='BLOCKED') as blocked_by_applicability,
         count(*) filter(where aplicabilidad='REQUIRED' and resultado='PASS') as required_pass,
         count(*) filter(where aplicabilidad='REQUIRED' and resultado in('FAIL','FINDING','ERROR')) as required_fail,
         count(*) filter(where aplicabilidad='REQUIRED' and resultado='BLOCKED') as required_blocked,
         count(*) filter(where aplicabilidad='REQUIRED' and (resultado is null or resultado='PENDING')) as required_pending
  from latest group by execution_id
)
select ex.id as execution_id,ex.version_id,ex.repo_full_name,ex.branch_name,ex.head_sha,ex.estado,
       case when exists(select 1 from programacion.execution_invalidations inv where inv.execution_id=ex.id)
            then 'INVALIDATED' else ex.veredicto end as veredicto,
       coalesce(a.objetivos_total,0) as objetivos_total,
       coalesce(a.required_total,0) as required_total,
       coalesce(a.not_applicable_total,0) as not_applicable_total,
       coalesce(a.blocked_by_applicability,0) as blocked_by_applicability,
       coalesce(a.required_pass,0) as required_pass,
       coalesce(a.required_fail,0) as required_fail,
       coalesce(a.required_blocked,0) as required_blocked,
       coalesce(a.required_pending,0) as required_pending,
       case
         when exists(select 1 from programacion.execution_invalidations inv where inv.execution_id=ex.id) then 'INVALIDATED'
         when not exists(select 1 from programacion.context_packs cp where cp.execution_id=ex.id and cp.estado='COMPLETE') then 'BLOCKED_CONTEXT'
         when ex.request_ref~'^agent-task://[1-9][0-9]*$' and not programacion.fn_agent_task_worker_context_receipt_ok(ex.id) then 'BLOCKED_WORKER_CONTEXT_RECEIPT'
         when coalesce(a.objetivos_total,0)=0 then 'BLOCKED_EMPTY_UNIVERSE'
         when coalesce(a.blocked_by_applicability,0)>0 or coalesce(a.required_blocked,0)>0 then 'BLOCKED'
         when coalesce(a.required_fail,0)>0 then 'FAIL'
         when coalesce(a.required_pending,0)>0 then 'PENDING'
         when coalesce(a.required_total,0)=coalesce(a.required_pass,0) then 'ELIGIBLE_PASS'
         else 'PENDING'
       end as derived_status
from programacion.ejecuciones ex
left join agg a on a.execution_id=ex.id;