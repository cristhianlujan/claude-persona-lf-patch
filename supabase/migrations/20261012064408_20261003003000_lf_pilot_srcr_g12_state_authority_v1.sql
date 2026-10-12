-- G12 STATE_AUTHORITY: keep public.lf_operation_execution as the sole execution-state authority.
-- private.lf_profile_runtime_queue_v1 is transport/projection only and must never mutate
-- canonical execution state. This replaces the historical MC-11 queue->canonical bridge
-- with a read-only reconciliation check while preserving the public function ABI.
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
  expected_canonical_status text;
begin
  if p_request_id is null
     or nullif(btrim(coalesce(p_actor_execution_id,'')),'') is null then
    return jsonb_build_object(
      'result','INPUT_INVALID',
      'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED',
      'queue_authoritative',false
    );
  end if;

  expected_execution_id := 'EXEC-PROFILE-RUNTIME-' || p_request_id::text;

  select * into q
    from private.lf_profile_runtime_queue_v1
   where request_id=p_request_id;
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
   where execution_id=expected_execution_id;
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
      'canonical_status',e.status,
      'queue_authoritative',false
    );
  end if;

  if q.status in ('PENDING','RUNNING') then
    return jsonb_build_object(
      'result','NON_TERMINAL_QUEUE_STATE',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status,
      'queue_authoritative',false
    );
  end if;

  if q.status='BLOCKED'
     and q.error_code='HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING' then
    return jsonb_build_object(
      'result','NON_TERMINAL_SEMANTIC_REVIEW_PENDING',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status,
      'next_gate','semantic_judge',
      'queue_authoritative',false
    );
  end if;

  if q.status='SUCCEEDED' then
    expected_canonical_status := 'COMPLETED';
  elsif q.status in ('FAILED','BLOCKED') then
    expected_canonical_status := 'BLOCKED';
  elsif q.status='CANCELLED' then
    expected_canonical_status := 'CANCELLED';
  else
    return jsonb_build_object(
      'result','QUEUE_TERMINAL_STATE_UNSUPPORTED',
      'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status,
      'queue_authoritative',false
    );
  end if;

  if e.status = expected_canonical_status then
    return jsonb_build_object(
      'result','TERMINAL_PAIR_RECONCILED',
      'request_id',p_request_id,
      'queue_status',q.status,
      'canonical_status',e.status,
      'queue_authoritative',false
    );
  end if;

  return jsonb_build_object(
    'result','QUEUE_TERMINAL_CANONICAL_NOT_RECONCILED',
    'blocking_code','PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED',
    'request_id',p_request_id,
    'queue_status',q.status,
    'canonical_execution_id',e.execution_id,
    'canonical_status',e.status,
    'expected_canonical_status',expected_canonical_status,
    'actor_execution_id',p_actor_execution_id,
    'queue_authoritative',false,
    'reason','Queue terminal state is evidence only; canonical state must be changed by the governed execution authority.'
  );
end
$function$;

revoke all on function public.lf_profile_execution_reconcile_queue_terminal_v1(uuid,text)
  from public, anon, authenticated;

comment on function public.lf_profile_execution_reconcile_queue_terminal_v1(uuid,text) is
'G12 STATE_AUTHORITY read-only reconciliation: private profile runtime queue is transport/projection only and never mutates public.lf_operation_execution.';
