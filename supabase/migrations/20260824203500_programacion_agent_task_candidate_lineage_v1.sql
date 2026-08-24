-- PROG-017: derive Agent Task candidate continuity from verified Worker delivery.
-- No execution identity is mutated. No PASS is copied to the candidate execution.
-- Worker gates may be NOT_APPLICABLE on a successor only when a prior execution
-- of the same task has every effective G_WORKER_* gate at latest PASS and a
-- separately verified Worker receipt whose delivered_head_sha equals the
-- successor exact HEAD.

create or replace function programacion.fn_agent_task_candidate_lineage_v1(p_execution_id bigint)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_candidate programacion.ejecuciones%rowtype;
  v_result jsonb;
begin
  select * into v_candidate
  from programacion.ejecuciones
  where id=p_execution_id;

  if not found then
    return jsonb_build_object('eligible',false,'reason','CANDIDATE_EXECUTION_NOT_FOUND','execution_id',p_execution_id);
  end if;

  if v_candidate.request_ref is null or v_candidate.request_ref !~ '^agent-task://[1-9][0-9]*$' then
    return jsonb_build_object('eligible',false,'reason','NOT_AGENT_TASK_EXECUTION','execution_id',p_execution_id);
  end if;

  with recursive version_chain as (
    select v.id as version_id,v.supersedes_version_id,0 as depth
    from programacion.versiones_agente v
    where v.id=v_candidate.version_id
    union all
    select p.id,p.supersedes_version_id,vc.depth+1
    from version_chain vc
    join programacion.versiones_agente p on p.id=vc.supersedes_version_id
  ), effective_worker_gates as (
    select distinct on (g.gate_codigo)
           g.id as gate_id,g.gate_codigo
    from version_chain vc
    join programacion.gates g on g.version_id=vc.version_id
    where g.bloqueante=true
      and g.estado in ('defined','active')
      and g.gate_codigo like 'G_WORKER_%'
    order by g.gate_codigo,vc.depth asc,g.id desc
  ), predecessor_receipts as (
    select p.id as predecessor_execution_id,
           cp.id as context_pack_id,
           cp.context_sha256 as context_pack_sha256,
           ev.id as evidence_id,
           ev.sha256 as evidence_sha256,
           ev.source_ref,
           ev.metadata->'worker_receipt' as worker_receipt
    from programacion.ejecuciones p
    join programacion.context_packs cp
      on cp.execution_id=p.id and cp.estado='COMPLETE' and cp.digest_version=2
    join programacion.objetivos_ejecucion obj on obj.execution_id=p.id
    join programacion.evaluaciones eva on eva.objetivo_id=obj.id
    join programacion.evidencias ev on ev.evaluacion_id=eva.id
    where p.id < v_candidate.id
      and p.request_ref=v_candidate.request_ref
      and p.version_id=v_candidate.version_id
      and p.perfil_calidad_id is not distinct from v_candidate.perfil_calidad_id
      and p.proyecto_codigo is not distinct from v_candidate.proyecto_codigo
      and p.repository_provider is not distinct from v_candidate.repository_provider
      and p.repo_full_name is not distinct from v_candidate.repo_full_name
      and p.target_language is not distinct from v_candidate.target_language
      and p.scope is not distinct from v_candidate.scope
      and p.head_sha is distinct from v_candidate.head_sha
      and ev.tipo='VERIFIED_WORKER_RECEIPT'
      and ev.source_system='PROGRAMMING_AGENT_WORKER'
      and ev.sha256=ev.metadata->>'receipt_sha256'
      and ev.metadata#>>'{worker_receipt,status}'='PASS'
      and ev.metadata#>>'{worker_receipt,execution_id}'=p.id::text
      and ev.metadata#>>'{worker_receipt,base_head_sha}'=p.head_sha
      and ev.metadata#>>'{worker_receipt,source_snapshot_sha256}'=p.source_snapshot_sha256
      and ev.metadata#>>'{worker_receipt,context_pack_id}'=cp.id::text
      and ev.metadata#>>'{worker_receipt,context_pack_sha256}'=cp.context_sha256
      and ev.metadata#>>'{worker_receipt,delivered_head_sha}'=v_candidate.head_sha
      and exists(
        select 1
        from programacion.evidence_verifications vv
        where vv.evidence_id=ev.id
          and vv.verification_status='VERIFIED'
          and vv.evidence_sha256=ev.sha256
          and vv.source_system=ev.source_system
          and vv.source_ref=ev.source_ref
      )
  ), scored as (
    select pr.*,
           (select count(*) from effective_worker_gates) as worker_gate_total,
           (
             select count(*)
             from effective_worker_gates ewg
             join programacion.objetivos_ejecucion o
               on o.execution_id=pr.predecessor_execution_id
              and o.gate_id=ewg.gate_id
              and o.aplicabilidad='REQUIRED'
             join lateral (
               select e.resultado
               from programacion.evaluaciones e
               where e.objetivo_id=o.id
               order by e.intento desc,e.id desc
               limit 1
             ) latest on latest.resultado='PASS'
           ) as worker_gate_pass
    from predecessor_receipts pr
  )
  select jsonb_build_object(
           'eligible',true,
           'reason','VERIFIED_WORKER_DELIVERY_LINEAGE',
           'execution_id',v_candidate.id,
           'candidate_head_sha',v_candidate.head_sha,
           'predecessor_execution_id',s.predecessor_execution_id,
           'worker_receipt_evidence_id',s.evidence_id,
           'worker_receipt_sha256',s.evidence_sha256,
           'worker_receipt_source_ref',s.source_ref,
           'worker_gate_total',s.worker_gate_total,
           'worker_gate_pass',s.worker_gate_pass,
           'delivered_head_sha',s.worker_receipt->>'delivered_head_sha'
         )
    into v_result
  from scored s
  where s.worker_gate_total > 0
    and s.worker_gate_pass=s.worker_gate_total
  order by s.predecessor_execution_id desc,s.evidence_id desc
  limit 1;

  return coalesce(
    v_result,
    jsonb_build_object(
      'eligible',false,
      'reason','VERIFIED_WORKER_DELIVERY_LINEAGE_NOT_PROVEN',
      'execution_id',v_candidate.id,
      'candidate_head_sha',v_candidate.head_sha
    )
  );
end;
$function$;

revoke all on function programacion.fn_agent_task_candidate_lineage_v1(bigint) from public;
grant execute on function programacion.fn_agent_task_candidate_lineage_v1(bigint)
  to programacion_builder,programacion_auditor,programacion_verifier,programacion_promoter,programacion_human_authority;

create or replace function programacion.fn_agent_task_candidate_lineage_ok(p_execution_id bigint)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select coalesce((programacion.fn_agent_task_candidate_lineage_v1(p_execution_id)->>'eligible')::boolean,false);
$function$;

revoke all on function programacion.fn_agent_task_candidate_lineage_ok(bigint) from public;
grant execute on function programacion.fn_agent_task_candidate_lineage_ok(bigint)
  to programacion_builder,programacion_auditor,programacion_verifier,programacion_promoter,programacion_human_authority;

create or replace function programacion.fn_agent_task_worker_context_receipt_ok(p_execution_id bigint)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select
    exists(
      select 1
      from programacion.ejecuciones ex
      join programacion.context_packs cp
        on cp.execution_id=ex.id and cp.estado='COMPLETE' and cp.digest_version=2
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
          select 1
          from programacion.evidence_verifications vv
          where vv.evidence_id=ev.id
            and vv.verification_status='VERIFIED'
            and vv.evidence_sha256=ev.sha256
            and vv.source_system=ev.source_system
            and vv.source_ref=ev.source_ref
        )
    )
    or programacion.fn_agent_task_candidate_lineage_ok(p_execution_id);
$function$;

revoke all on function programacion.fn_agent_task_worker_context_receipt_ok(bigint) from public;
grant execute on function programacion.fn_agent_task_worker_context_receipt_ok(bigint)
  to programacion_builder,programacion_auditor,programacion_verifier,programacion_promoter,programacion_human_authority;

create or replace function programacion.fn_guard_frozen_insert()
returns trigger
language plpgsql
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_execution_id bigint;
  v_estado text;
  v_request_ref text;
  v_gate_code text;
begin
  if tg_table_name='context_packs' then
    v_execution_id:=new.execution_id;
  elsif tg_table_name='objetivos_ejecucion' then
    v_execution_id:=new.execution_id;
  else
    raise exception 'unsupported frozen insert table %',tg_table_name;
  end if;

  select estado,request_ref into v_estado,v_request_ref
  from programacion.ejecuciones
  where id=v_execution_id;

  if v_estado is distinct from 'CREATED' then
    raise exception '% can only be inserted while execution % is CREATED',tg_table_name,v_execution_id;
  end if;

  if tg_table_name='objetivos_ejecucion'
     and new.gate_id is not null
     and v_request_ref~'^agent-task://[1-9][0-9]*$' then
    select gate_codigo into v_gate_code
    from programacion.gates
    where id=new.gate_id;

    if v_gate_code like 'G_WORKER_%'
       and new.aplicabilidad='NOT_APPLICABLE'
       and not programacion.fn_agent_task_candidate_lineage_ok(v_execution_id) then
      raise exception 'AGENT_TASK_WORKER_GATE_NA_REQUIRES_VERIFIED_DELIVERY_LINEAGE: execution %, gate %',
        v_execution_id,v_gate_code;
    end if;
  end if;

  return new;
end;
$function$;

comment on function programacion.fn_agent_task_candidate_lineage_v1(bigint) is
  'PROG-017 fail-closed lineage: successor exact HEAD is eligible only from externally verified Worker delivery plus latest PASS for every effective G_WORKER_* gate on the predecessor execution.';
