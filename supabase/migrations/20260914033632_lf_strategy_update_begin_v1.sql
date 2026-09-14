create or replace function public.lf_strategy_update_begin_v1(
  p_execution_id text,
  p_snapshot_id bigint,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  s public.lf_strategy_snapshots%rowtype;
  r jsonb;
  st public.lf_operation_steps%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  target_path text;
  ep jsonb;
begin
  if p_snapshot_id is null or btrim(coalesce(p_execution_id,''))='' or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$' or btrim(coalesce(p_idempotency_key,''))='' or btrim(coalesce(p_actor_execution_id,''))='' or p_manifest is null or jsonb_typeof(p_manifest)<>'object' then
    raise exception 'LF_STRATEGY_UPDATE_BEGIN_INPUT_INVALID';
  end if;

  select * into s from public.lf_strategy_snapshots where id=p_snapshot_id;
  if not found then raise exception 'LF_STRATEGY_UPDATE_BEGIN_TARGET_NOT_FOUND'; end if;
  if coalesce(s.metadata->'strategy_close'->>'status','')='CLOSED' then raise exception 'LF_STRATEGY_UPDATE_BEGIN_CLOSED_TARGET'; end if;

  target_path:=format('supabase://public/lf_strategy_snapshots/%s',s.id);
  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,
    'ACTUALIZACION_ESTRATEGIA_LF',
    'STRATEGY',
    s.snapshot_code,
    p_idempotency_key,
    p_request_sha256,
    p_actor_execution_id,
    null,
    target_path,
    p_manifest
  );

  select * into st from public.lf_operation_steps where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and step_id='init_execution' and active=true;
  if not found then raise exception 'LF_STRATEGY_UPDATE_INIT_STEP_NOT_ACTIVE'; end if;
  select * into b from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and step_id='init_execution' and step_order=st.step_order and status='ACTIVE_ENFORCEMENT';
  if not found then raise exception 'LF_STRATEGY_UPDATE_INIT_BINDING_NOT_ACTIVE'; end if;

  select * into existing from public.lf_operation_execution_steps where execution_id=(r->>'execution_id') and step_order=st.step_order;
  if found then
    if existing.step_id='init_execution' and existing.status=b.clean_result_value then
      return r || jsonb_build_object('init_step','ALREADY_RECORDED_IDEMPOTENT','target_path',target_path,'snapshot_id',s.id);
    end if;
    raise exception 'LF_STRATEGY_UPDATE_INIT_STEP_CONFLICT';
  end if;

  ep:=jsonb_build_object(
    'execution_id_created',r->>'execution_id',
    'target_code',s.snapshot_code,
    'target_path',target_path,
    'assertions_checked','[]'::jsonb,
    'hard_fails_checked','[]'::jsonb,
    'blocking_findings','[]'::jsonb,
    'blocking_codes','[]'::jsonb,
    'return_to_worker_reasons','[]'::jsonb,
    'step_result',b.clean_result_value,
    'derived_result',b.clean_result_value,
    'derived_by_judge',b.judge_code,
    'mini_judge_code',b.judge_code,
    'mini_judge_result',b.clean_result_value,
    'missing_pass_items','[]'::jsonb,
    'triggered_fail_items','[]'::jsonb,
    'attempt_history','[]'::jsonb,
    'recorded_by_rpc','lf_strategy_update_begin_v1'
  );

  insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id)
  values(r->>'execution_id',st.step_order,'init_execution',b.clean_result_value,target_path,ep,'Initialized transactionally by governed Strategy Update begin RPC.',p_actor_execution_id);

  return r || jsonb_build_object('init_step','RECORDED','target_path',target_path,'snapshot_id',s.id);
end
$function$;

revoke all on function public.lf_strategy_update_begin_v1(text,bigint,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_strategy_update_begin_v1(text,bigint,text,text,text,jsonb) to service_role;
comment on function public.lf_strategy_update_begin_v1(text,bigint,text,text,text,jsonb) is 'Governed initializer for ACTUALIZACION_ESTRATEGIA_LF. Reserves execution and materializes immutable init_execution without caller DML.';