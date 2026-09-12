create or replace function programacion.fn_agent_task_pending_worker_evidence_v1(p_task_id bigint)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v jsonb;
  v_task programacion.agent_tasks%rowtype;
  v_current_task_id bigint;
begin
  if p_task_id is null or p_task_id < 1 then raise exception 'AGENT_TASK_ID_INVALID'; end if;

  select * into v_task from programacion.agent_tasks where id=p_task_id;
  if v_task.id is null then raise exception 'AGENT_TASK_NOT_FOUND:%',p_task_id; end if;
  if v_task.definition_status<>'SEALED' then raise exception 'AGENT_TASK_SEALED_REQUIRED:%',p_task_id; end if;

  select t.id into v_current_task_id
  from programacion.agent_tasks t
  where t.task_code=v_task.task_code and t.definition_status='SEALED'
  order by t.task_version desc,t.id desc
  limit 1;
  if v_current_task_id is distinct from p_task_id then
    raise exception 'AGENT_TASK_CURRENT_VERSION_REQUIRED:% current=%',p_task_id,v_current_task_id;
  end if;

  select jsonb_build_object(
    'execution_id',ex.id,'request_ref',ex.request_ref,'head_sha',ex.head_sha,
    'source_snapshot_sha256',ex.source_snapshot_sha256,'context_pack_id',cp.id,'context_pack_sha256',cp.context_sha256,
    'evaluation_id',eva.id,'evaluation_status',eva.resultado,
    'evidence_id',ev.id,'evidence_sha256',ev.sha256,'source_system',ev.source_system,'source_ref',ev.source_ref,
    'worker_receipt_status',ev.metadata#>>'{worker_receipt,status}'
  ) into v
  from programacion.ejecuciones ex
  join programacion.context_packs cp on cp.execution_id=ex.id and cp.estado='COMPLETE' and cp.digest_version=2
  join programacion.objetivos_ejecucion obj on obj.execution_id=ex.id
  join programacion.evaluaciones eva on eva.objetivo_id=obj.id and eva.resultado='PENDING'
  join programacion.evidencias ev on ev.evaluacion_id=eva.id
  where ex.request_ref='agent-task://'||p_task_id::text and ex.estado='RUNNING'
    and ev.tipo='VERIFIED_WORKER_RECEIPT' and ev.source_system='PROGRAMMING_AGENT_WORKER'
    and ev.sha256=ev.metadata->>'receipt_sha256' and ev.metadata#>>'{worker_receipt,status}'='PASS'
    and ev.metadata#>>'{worker_receipt,execution_id}'=ex.id::text
    and ev.metadata#>>'{worker_receipt,context_pack_id}'=cp.id::text
    and ev.metadata#>>'{worker_receipt,context_pack_sha256}'=cp.context_sha256
    and not exists(select 1 from programacion.evidence_verifications vv where vv.evidence_id=ev.id and vv.verification_status='VERIFIED')
  order by ex.id desc,ev.id desc limit 1;

  if v is null then raise exception 'PENDING_WORKER_EVIDENCE_NOT_FOUND: agent-task://%',p_task_id; end if;
  return v;
end;
$$;