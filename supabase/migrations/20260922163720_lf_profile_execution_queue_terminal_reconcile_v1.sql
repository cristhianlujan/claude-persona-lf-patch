-- MC-11: reconcile authoritative Profile Runtime queue terminal failures with
-- the canonical EJECUCION_PERFIL_LF execution.  The queue is an auxiliary
-- transport surface; canonical execution remains public.lf_operation_execution.
create or replace function public.lf_profile_execution_reconcile_queue_terminal_v1(
  p_request_id uuid,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  q private.lf_profile_runtime_queue_v1%rowtype;
  e public.lf_operation_execution%rowtype;
  expected_execution_id text;
  target_status text;
  receipt jsonb;
begin
  if p_request_id is null
     or nullif(btrim(coalesce(p_actor_execution_id,'')),'') is null then
    return jsonb_build_object(
      'result','INPUT_INVALID',
      'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED'
    );
  end if;

  expected_execution_id := 'EXEC-PROFILE-RUNTIME-' || p_request_id::text;

  select * into q
    from private.lf_profile_runtime_queue_v1
   where request_id=p_request_id
   for update;
  if not found then
    return jsonb_build_object(
      'result','NO_QUEUE_ROW',
      'request_id',p_request_id,
      'canonical_execution_id',expected_execution_id,
      'queue_authoritative',false
    );
  end if;

  select * into e
    from public.lf_operation_execution
   where execution_id=expected_execution_id
   for update;
  if not found then
    return jsonb_build_object(
      'result','NO_CANONICAL_EXECUTION',
      'request_id',p_request_id,
      'queue_status',q.status,
      'queue_authoritative',false,
      'reason','The auxiliary queue has no canonical execution identity to reconcile.'
    );
  end if;

  if e.operation_code <> 'EJECUCION_PERFIL_LF'
     or e.target_type <> 'PERFIL'
     or e.target_code is distinct from q.profile_code
     or e.manifest->>'queue_request_id' is distinct from p_request_id::text then
    return jsonb_build_object(
      'result','IDENTITY_MISMATCH',
      'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED',
      'request_id',p_request_id,
      'canonical_execution_id',e.execution_id,
      'queue_status',q.status,
      'canonical_status',e.status
    );
  end if;

  if q.status in ('PENDING','RUNNING') then
    return jsonb_build_object(
      'result','NON_TERMINAL_QUEUE_STATE',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status
    );
  end if;

  if q.status='BLOCKED'
     and q.error_code='HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING' then
    return jsonb_build_object(
      'result','NON_TERMINAL_SEMANTIC_REVIEW_PENDING',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status,
      'next_gate','semantic_judge'
    );
  end if;

  if q.status='SUCCEEDED' then
    if e.status='COMPLETED' then
      return jsonb_build_object(
        'result','TERMINAL_PAIR_RECONCILED',
        'request_id',p_request_id,
        'queue_status',q.status,
        'canonical_status',e.status
      );
    end if;
    return jsonb_build_object(
      'result','QUEUE_SUCCESS_CANONICAL_NOT_COMPLETED',
      'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status
    );
  end if;

  if q.status='FAILED' then
    target_status := 'BLOCKED';
  elsif q.status='BLOCKED' then
    target_status := 'BLOCKED';
  elsif q.status='CANCELLED' then
    -- Forward-compatible with a future queue schema that admits CANCELLED.
    target_status := 'CANCELLED';
  else
    return jsonb_build_object(
      'result','QUEUE_TERMINAL_STATE_UNSUPPORTED',
      'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status
    );
  end if;

  if e.status = target_status then
    return jsonb_build_object(
      'result','TERMINAL_PAIR_ALREADY_RECONCILED',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status
    );
  end if;

  if e.status <> 'IN_PROGRESS' then
    return jsonb_build_object(
      'result','CANONICAL_TERMINAL_CONFLICT',
      'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status,
      'expected_canonical_status',target_status
    );
  end if;

  receipt := jsonb_build_object(
    'schema','PROFILE_RUNTIME_QUEUE_TERMINAL_RECONCILIATION_V1',
    'request_id',p_request_id,
    'queue_status',q.status,
    'queue_error_code',q.error_code,
    'queue_completed_at',q.completed_at,
    'canonical_execution_id',e.execution_id,
    'canonical_status_before',e.status,
    'canonical_status_after',target_status,
    'reconciled_at',clock_timestamp()
  );

  update public.lf_operation_execution
     set status=target_status,
         completed_at=coalesce(completed_at,now()),
         manifest=coalesce(manifest,'{}'::jsonb)
           || jsonb_build_object('queue_terminal_reconciliation',receipt),
         updated_by_execution_id=p_actor_execution_id,
         updated_at=now()
   where execution_id=e.execution_id
     and status='IN_PROGRESS';

  if not found then
    return jsonb_build_object(
      'result','CANONICAL_TERMINAL_COMPARE_AND_SET_FAILED',
      'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_execution_id',e.execution_id
    );
  end if;

  return jsonb_build_object(
    'result','CANONICAL_TERMINAL_RECONCILED',
    'request_id',p_request_id,
    'queue_status',q.status,
    'canonical_execution_id',e.execution_id,
    'canonical_status_before',e.status,
    'canonical_status_after',target_status,
    'receipt',receipt
  );
end
$function$;

revoke all on function public.lf_profile_execution_reconcile_queue_terminal_v1(uuid,text)
  from public, anon, authenticated;

comment on function public.lf_profile_execution_reconcile_queue_terminal_v1(uuid,text) is
'MC-11 fail-closed bridge: terminal Profile Runtime queue failure/block/cancel is reconciled to the exact canonical EJECUCION_PERFIL_LF execution; semantic-review pending remains non-terminal.';
