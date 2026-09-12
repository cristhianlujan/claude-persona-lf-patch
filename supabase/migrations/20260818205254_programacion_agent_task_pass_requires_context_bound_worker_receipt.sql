create or replace function programacion.fn_guard_evidence()
returns trigger
language plpgsql
set search_path = pg_catalog, programacion
as $function$
declare
  v_eval_head text;
  v_exec_head text;
  v_exec_estado text;
  v_execution_id bigint;
  v_request_ref text;
  v_source_snapshot_sha256 text;
  v_context_pack_id bigint;
  v_context_pack_sha256 text;
  v_task_id bigint;
  v_task_code text;
  v_task_version integer;
  v_task_sha256 text;
  v_hidden_oracle_sha256 text;
  v_receipt jsonb;
  v_receipt_sha256 text;
  v_runtime jsonb;
begin
  select ev.head_sha, ex.head_sha, ex.estado, ex.id, ex.request_ref, ex.source_snapshot_sha256
    into v_eval_head, v_exec_head, v_exec_estado, v_execution_id, v_request_ref, v_source_snapshot_sha256
  from programacion.evaluaciones ev
  join programacion.objetivos_ejecucion o on o.id=ev.objetivo_id
  join programacion.ejecuciones ex on ex.id=o.execution_id
  where ev.id=new.evaluacion_id;

  if v_eval_head is null then
    raise exception 'evaluation % not found for evidence', new.evaluacion_id;
  end if;
  if v_exec_estado <> 'RUNNING' then
    raise exception 'evidence may only be attached while execution is RUNNING';
  end if;
  if new.head_sha <> v_eval_head or new.head_sha <> v_exec_head then
    raise exception 'evidence HEAD must match evaluation and execution HEAD';
  end if;

  if new.tipo='VERIFIED_WORKER_RECEIPT' then
    if new.source_system<>'PROGRAMMING_AGENT_WORKER' then
      raise exception 'VERIFIED_WORKER_RECEIPT source_system must be PROGRAMMING_AGENT_WORKER';
    end if;
    if v_request_ref is null or v_request_ref!~'^agent-task://[1-9][0-9]*$' then
      raise exception 'VERIFIED_WORKER_RECEIPT requires agent-task execution';
    end if;
    if length(btrim(coalesce(new.source_ref,'')))=0 then
      raise exception 'VERIFIED_WORKER_RECEIPT requires source_ref';
    end if;

    select cp.id,cp.context_sha256
      into v_context_pack_id,v_context_pack_sha256
    from programacion.context_packs cp
    where cp.execution_id=v_execution_id and cp.estado='COMPLETE' and cp.digest_version=2;
    if v_context_pack_id is null then
      raise exception 'VERIFIED_WORKER_RECEIPT requires COMPLETE Context Pack v2';
    end if;

    select t.id,t.task_code,t.task_version,t.task_sha256,tc.hidden_oracle_sha256
      into v_task_id,v_task_code,v_task_version,v_task_sha256,v_hidden_oracle_sha256
    from programacion.agent_tasks t
    join programacion.test_contracts tc on tc.task_id=t.id and tc.status='SEALED'
    where v_request_ref='agent-task://'||t.id::text;
    if v_task_id is null then
      raise exception 'VERIFIED_WORKER_RECEIPT task/Test Contract binding not found';
    end if;

    v_receipt:=new.metadata->'worker_receipt';
    if v_receipt is null or jsonb_typeof(v_receipt)<>'object' then
      raise exception 'VERIFIED_WORKER_RECEIPT metadata.worker_receipt object is required';
    end if;
    if coalesce(v_receipt->>'receipt_sha256','')!~'^[0-9a-f]{64}$' then
      raise exception 'VERIFIED_WORKER_RECEIPT receipt_sha256 is invalid';
    end if;
    v_receipt_sha256:=programacion.fn_v09_sha256_jsonb(v_receipt-'receipt_sha256');
    if v_receipt->>'receipt_sha256' is distinct from v_receipt_sha256
       or new.sha256 is distinct from v_receipt_sha256
       or new.metadata->>'receipt_sha256' is distinct from v_receipt_sha256 then
      raise exception 'VERIFIED_WORKER_RECEIPT digest mismatch';
    end if;

    v_runtime:=programacion.fn_agent_task_runtime_context(v_execution_id);
    if v_receipt->>'execution_id' is distinct from v_execution_id::text
       or v_receipt->>'context_pack_id' is distinct from v_context_pack_id::text
       or v_receipt->>'context_pack_sha256' is distinct from v_context_pack_sha256
       or v_receipt->>'runtime_context_sha256' is distinct from v_runtime->>'runtime_context_sha256'
       or v_receipt->>'base_head_sha' is distinct from v_exec_head
       or v_receipt->>'source_snapshot_sha256' is distinct from v_source_snapshot_sha256
       or v_receipt->>'task_id' is distinct from v_task_code||'.v'||v_task_version::text
       or v_receipt->>'task_sha256' is distinct from v_task_sha256
       or v_receipt->>'oracle_manifest_sha256' is distinct from v_hidden_oracle_sha256 then
      raise exception 'VERIFIED_WORKER_RECEIPT execution/context/task/oracle binding mismatch';
    end if;
    if v_receipt->>'status' not in ('PASS','FAIL','BLOCKED') then
      raise exception 'VERIFIED_WORKER_RECEIPT status is invalid';
    end if;
    if v_receipt->'commit_allowed' is distinct from 'false'::jsonb
       or v_receipt->'push_allowed' is distinct from 'false'::jsonb
       or v_receipt->'merge_allowed' is distinct from 'false'::jsonb
       or v_receipt->'production_allowed' is distinct from 'false'::jsonb
       or v_receipt->'independent_audit_required' is distinct from 'true'::jsonb then
      raise exception 'VERIFIED_WORKER_RECEIPT governance flags are invalid';
    end if;
  end if;

  return new;
end;
$function$;

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
    when ex.request_ref~'^agent-task://[1-9][0-9]*$' and not exists(
      select 1
      from programacion.evidencias ev
      join programacion.evaluaciones eva on eva.id=ev.evaluacion_id and eva.resultado='PASS'
      join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id and obj.execution_id=ex.id
      join programacion.context_packs cp on cp.execution_id=ex.id and cp.estado='COMPLETE' and cp.digest_version=2
      where ev.tipo='VERIFIED_WORKER_RECEIPT'
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
    ) then 'BLOCKED_WORKER_CONTEXT_RECEIPT'
    when coalesce(a.objetivos_total,0)=0 then 'BLOCKED_EMPTY_UNIVERSE'
    when coalesce(a.blocked_by_applicability,0)>0 or coalesce(a.required_blocked,0)>0 then 'BLOCKED'
    when coalesce(a.required_fail,0)>0 then 'FAIL'
    when coalesce(a.required_pending,0)>0 then 'PENDING'
    when coalesce(a.required_total,0)=coalesce(a.required_pass,0) then 'ELIGIBLE_PASS'
    else 'PENDING'
  end as derived_status
from programacion.ejecuciones ex
left join agg a on a.execution_id=ex.id;