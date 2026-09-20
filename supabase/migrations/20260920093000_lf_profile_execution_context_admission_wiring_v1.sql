do $pre$
declare c int;
begin
  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='EJECUCION_PERFIL_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
      and status='PRODUCCION_CONTROLADA_READ_ONLY'
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_PRE_OPERATION_STATE_DRIFT';
  end if;

  select count(*) into c
  from public.lf_operation_steps
  where operation_code='EJECUCION_PERFIL_LF' and active;
  if c<>9 then raise exception 'PROFILE_EXEC_CONTEXT_PRE_ACTIVE_STEPS:%',c; end if;

  select count(*) into c
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>9 then raise exception 'PROFILE_EXEC_CONTEXT_PRE_ACTIVE_BINDINGS:%',c; end if;

  if exists (
    select 1 from public.lf_operation_steps
    where operation_code='EJECUCION_PERFIL_LF' and step_id='context_admission'
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_PRE_STEP_ALREADY_EXISTS';
  end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='input_validate'
      and status='ACTIVE_ENFORCEMENT'
      and next_if_pass='execute_profile'
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_PRE_INPUT_EDGE_DRIFT';
  end if;

  if to_regprocedure('public.fn_lf_router_preflight_v1(text)') is null
     or to_regprocedure('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)') is null
     or to_regprocedure('public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb)') is null
  then
    raise exception 'PROFILE_EXEC_CONTEXT_PRE_REQUIRED_PRIMITIVE_MISSING';
  end if;

  if not exists (
    select 1 from public.v_lf_fuente_operativa
    where codigo_activo='EVIDENCE_RESOLVER_REGISTRY'
      and estado_operativo='ACTIVO'
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_PRE_JIT_RESOLVER_NOT_CURRENT';
  end if;

  select count(*) into c
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql';
  if c<>1 then
    raise exception 'PROFILE_EXEC_CONTEXT_PRE_RUNTIME_UPDATE_ACTOR_COUNT:%',c;
  end if;
end
$pre$;

create or replace function public.fn_lf_operation_provenance_guard_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_created_operation text;
  v_updated_operation text;
  v_created_status text;
  v_updated_status text;
  v_created_manifest jsonb;
  v_updated_manifest jsonb;
  v_validate_created boolean;
  v_validate_updated boolean;
  v_target_status text;
  v_created_bootstrap_allowed boolean := false;
  v_updated_bootstrap_allowed boolean := false;
  v_created_runtime_update_allowed boolean := false;
  v_updated_runtime_update_allowed boolean := false;
begin
  if tg_op = 'UPDATE' and new.operation_code is distinct from old.operation_code then
    raise exception 'LF_OPERATION_PROVENANCE_OPERATION_CODE_IMMUTABLE:%:%', old.operation_code, new.operation_code
      using errcode = '23514';
  end if;

  v_validate_created := tg_op = 'INSERT'
    or (tg_op = 'UPDATE' and new.created_by_execution_id is distinct from old.created_by_execution_id);
  v_validate_updated := tg_op = 'INSERT'
    or (tg_op = 'UPDATE' and new.updated_by_execution_id is distinct from old.updated_by_execution_id);

  if tg_table_name = 'lf_operation_registry' then
    v_target_status := new.status;
  else
    select r.status into v_target_status
    from public.lf_operation_registry r
    where r.operation_code = new.operation_code;
  end if;

  if v_validate_created then
    if new.created_by_execution_id is null or btrim(new.created_by_execution_id) = '' or new.created_by_execution_id = 'UNKNOWN' then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_EXECUTION_REQUIRED'
        using errcode = '23514';
    end if;

    select e.operation_code,e.status,e.manifest
      into v_created_operation,v_created_status,v_created_manifest
    from public.lf_operation_execution e
    where e.execution_id = new.created_by_execution_id;

    if v_created_operation is null then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_EXECUTION_MISSING:%', new.created_by_execution_id
        using errcode = '23503';
    end if;

    v_created_bootstrap_allowed :=
      v_created_operation = 'VULNERABILITY_COVERAGE_REPAIR_LF'
      and v_created_status = 'IN_PROGRESS'
      and coalesce((v_created_manifest->>'governance_bootstrap')::boolean,false) = true
      and v_created_manifest->>'bootstrap_operation_code' = new.operation_code
      and coalesce(v_created_manifest->>'bootstrap_status_ceiling','') = 'SANDBOX_ACTIVE'
      and v_target_status in ('SANDBOX_ACTIVE','CANDIDATO_READ_ONLY');

    v_created_runtime_update_allowed :=
      v_created_operation = 'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and v_created_status = 'IN_PROGRESS'
      and coalesce((v_created_manifest->>'runtime_update_governed')::boolean,false) = true
      and v_created_manifest->>'target_operation' = new.operation_code;

    if v_created_operation <> new.operation_code
       and not v_created_bootstrap_allowed
       and not v_created_runtime_update_allowed then
      raise exception 'LF_OPERATION_PROVENANCE_CREATED_SCOPE_MISMATCH:%:%:%',
        new.created_by_execution_id, v_created_operation, new.operation_code
        using errcode = '23514';
    end if;
  end if;

  if v_validate_updated and new.updated_by_execution_id is not null and btrim(new.updated_by_execution_id) <> '' then
    select e.operation_code,e.status,e.manifest
      into v_updated_operation,v_updated_status,v_updated_manifest
    from public.lf_operation_execution e
    where e.execution_id = new.updated_by_execution_id;

    if v_updated_operation is null then
      raise exception 'LF_OPERATION_PROVENANCE_UPDATED_EXECUTION_MISSING:%', new.updated_by_execution_id
        using errcode = '23503';
    end if;

    v_updated_bootstrap_allowed :=
      v_updated_operation = 'VULNERABILITY_COVERAGE_REPAIR_LF'
      and v_updated_status = 'IN_PROGRESS'
      and coalesce((v_updated_manifest->>'governance_bootstrap')::boolean,false) = true
      and v_updated_manifest->>'bootstrap_operation_code' = new.operation_code
      and coalesce(v_updated_manifest->>'bootstrap_status_ceiling','') = 'SANDBOX_ACTIVE'
      and v_target_status in ('SANDBOX_ACTIVE','CANDIDATO_READ_ONLY');

    v_updated_runtime_update_allowed :=
      v_updated_operation = 'ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
      and v_updated_status = 'IN_PROGRESS'
      and coalesce((v_updated_manifest->>'runtime_update_governed')::boolean,false) = true
      and v_updated_manifest->>'target_operation' = new.operation_code;

    if v_updated_operation <> new.operation_code
       and not v_updated_bootstrap_allowed
       and not v_updated_runtime_update_allowed then
      raise exception 'LF_OPERATION_PROVENANCE_UPDATED_SCOPE_MISMATCH:%:%:%',
        new.updated_by_execution_id, v_updated_operation, new.operation_code
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function public.lf_profile_execution_begin_v1(
  p_execution_id text,
  p_idempotency_key text,
  p_request_sha256 text,
  p_actor_execution_id text,
  p_profile_code text,
  p_target_repo text,
  p_target_path text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare
  r jsonb;
  b public.lf_operation_step_judge_bindings%rowtype;
begin
  if nullif(btrim(coalesce(p_profile_code,'')),'') is null
     or nullif(btrim(coalesce(p_target_repo,'')),'') is null
     or nullif(btrim(coalesce(p_target_path,'')),'') is null then
    raise exception 'PROFILE_EXECUTION_BEGIN_TARGET_REQUIRED';
  end if;

  r:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'EJECUCION_PERFIL_LF',
    'PERFIL',p_profile_code,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,
    p_target_repo,p_target_path,
    coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object(
      'profile_execution_governed',true,
      'context_admission_required',true,
      'context_delivery','COMPACT_JIT_ONLY',
      'profile_source_mode','JIT_BY_REF',
      'automatic_impact',false
    )
  );

  select * into b
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='init_execution'
    and status='ACTIVE_ENFORCEMENT';

  if r->>'result'='RESERVED_NEW_EXECUTION' then
    insert into public.lf_operation_execution_steps(
      execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id
    ) values(
      r->>'execution_id',0,'init_execution',b.clean_result_value,
      'supabase://public.lf_operation_execution/'||(r->>'execution_id'),
      jsonb_build_object(
        'execution_id_created',true,
        'profile_code',p_profile_code,
        'context_admission_required',true,
        'step_result',b.clean_result_value,
        'blocking_codes','[]'::jsonb,
        'mini_judge_code',b.judge_code,
        'mini_judge_result',b.clean_result_value,
        'recorded_by_rpc','lf_profile_execution_begin_v1'
      ),
      'Profile execution init materialized after canonical reserve.',
      p_actor_execution_id
    );
  end if;

  return r||jsonb_build_object(
    'init_materialized',true,
    'context_admission_required',true
  );
end
$fn$;

create or replace function public.lf_profile_execution_context_admission_v1(
  p_execution_id text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  prior public.lf_operation_execution_steps%rowtype;
  prior_binding public.lf_operation_step_judge_bindings%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  context_binding public.lf_operation_step_judge_bindings%rowtype;
  compiled jsonb;
  receipt jsonb;
  event_id bigint;
  budget_event_id bigint;
  digest text;
  resolver_version text;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception 'BLOCK_PROFILE_CONTEXT_EXECUTION_ID_REQUIRED';
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or e.operation_code<>'EJECUCION_PERFIL_LF'
     or e.target_type<>'PERFIL'
     or e.status<>'IN_PROGRESS' then
    raise exception 'BLOCK_PROFILE_CONTEXT_EXECUTION_BINDING_INVALID:%',p_execution_id;
  end if;

  select * into context_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='context_admission'
    and status='ACTIVE_ENFORCEMENT';

  select * into existing
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='context_admission';

  if found and existing.status=context_binding.clean_result_value then
    return existing.evidence_payload||jsonb_build_object('replay',true);
  end if;

  select * into prior_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='input_validate'
    and status='ACTIVE_ENFORCEMENT';

  select * into prior
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='input_validate';

  if not found or prior.status<>prior_binding.clean_result_value then
    raise exception 'BLOCK_PROFILE_CONTEXT_INPUT_VALIDATE_NOT_CLEAN:%',p_execution_id;
  end if;

  select version_normalizada into resolver_version
  from public.v_lf_fuente_operativa
  where codigo_activo='EVIDENCE_RESOLVER_REGISTRY'
    and estado_operativo='ACTIVO';

  if resolver_version is null then
    raise exception 'BLOCK_PROFILE_CONTEXT_JIT_RESOLVER_NOT_CURRENT';
  end if;

  compiled:=public.fn_lf_router_preflight_v1(p_execution_id);

  if coalesce(compiled->>'status','')<>'READY'
     or compiled->>'blocking_code' is not null
     or coalesce(compiled#>>'{context_budget,status}','')='RED'
     or coalesce((compiled#>>'{delivery,jit_only}')::boolean,false) is not true
     or coalesce((compiled#>>'{delivery,policy_payloads}')::boolean,true) is not false
     or coalesce((compiled#>>'{delivery,full_ekb_entries}')::boolean,true) is not false
     or coalesce((compiled#>>'{delivery,full_readmes}')::boolean,true) is not false
     or jsonb_typeof(compiled->'lazy_refs')<>'object'
  then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(compiled->>'blocking_code','BLOCK_PROFILE_CONTEXT_ADMISSION_NOT_READY'),
      'compiled_context',compiled,
      'server_validated',false
    );
  end if;

  event_id:=(compiled->>'evento_id')::bigint;
  budget_event_id:=(compiled->>'context_budget_event_id')::bigint;

  select payload->'context_receipt' into receipt
  from public.lf_eventos
  where id=event_id
    and created_by_execution_id=p_execution_id
    and payload->>'producer'='fn_lf_router_preflight_v1';

  if receipt is null then
    raise exception 'BLOCK_PROFILE_CONTEXT_EVENT_READBACK_MISSING:%',event_id;
  end if;

  if not exists (
    select 1
    from private.lf_context_budget_events_v2
    where id=budget_event_id
      and execution_id=p_execution_id
      and evidence_event_id=event_id
      and context_status in ('GREEN','YELLOW')
  ) then
    raise exception 'BLOCK_PROFILE_CONTEXT_BUDGET_READBACK_MISSING:%',budget_event_id;
  end if;

  digest:='sha256:'||encode(
    extensions.digest(convert_to(receipt::text,'UTF8'),'sha256'),'hex'
  );

  return jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'server_validated',true,
    'compiler_ref','public.fn_lf_router_preflight_v1',
    'context_event_id',event_id,
    'context_budget_event_id',budget_event_id,
    'context_receipt_ref','supabase://public.lf_eventos/'||event_id::text||'#context_receipt',
    'context_receipt_digest',digest,
    'context_budget_status',receipt#>>'{context_budget,status}',
    'context_capsule_estimated_tokens',(receipt#>>'{context_budget,estimated_tokens}')::bigint,
    'context_capsule_bytes',octet_length(receipt::text),
    'soft_limit_tokens',(receipt#>>'{context_budget,soft_limit_tokens}')::bigint,
    'hard_limit_tokens',(receipt#>>'{context_budget,hard_limit_tokens}')::bigint,
    'delivery',receipt->'delivery',
    'lazy_refs',receipt->'lazy_refs',
    'profile_source_mode','JIT_BY_REF',
    'jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
    'jit_resolver_version',resolver_version,
    'context_capsule',receipt,
    'replay',false
  );
end
$fn$;

create or replace function public.lf_profile_execution_trust_validation_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  event_id bigint;
  budget_event_id bigint;
  receipt jsonb;
  expected_digest text;
  context_step public.lf_operation_execution_steps%rowtype;
  context_binding public.lf_operation_step_judge_bindings%rowtype;
  transport jsonb;
  hard jsonb := '[]'::jsonb;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_step_id,'')),'') is null
     or p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_TRUST_INPUT_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or e.operation_code<>'EJECUCION_PERFIL_LF'
     or e.target_type<>'PERFIL'
     or e.status<>'IN_PROGRESS' then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_BINDING_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if p_step_id='context_admission' then
    if coalesce((p_evidence_payload->>'server_validated')::boolean,false) is not true
       or p_evidence_payload->>'compiler_ref'<>'public.fn_lf_router_preflight_v1'
       or p_evidence_payload->>'profile_source_mode'<>'JIT_BY_REF'
       or p_evidence_payload->>'jit_resolver_ref'<>'supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY'
       or p_evidence_payload->>'context_budget_status' not in ('GREEN','YELLOW')
       or jsonb_typeof(p_evidence_payload->'delivery')<>'object'
       or jsonb_typeof(p_evidence_payload->'lazy_refs')<>'object'
    then
      hard:=hard||jsonb_build_array('context_admission_shape_invalid');
    else
      event_id:=(p_evidence_payload->>'context_event_id')::bigint;
      budget_event_id:=(p_evidence_payload->>'context_budget_event_id')::bigint;

      select payload->'context_receipt' into receipt
      from public.lf_eventos
      where id=event_id
        and created_by_execution_id=p_execution_id
        and payload->>'producer'='fn_lf_router_preflight_v1';

      if receipt is null then
        hard:=hard||jsonb_build_array('context_event_readback_missing');
      else
        expected_digest:='sha256:'||encode(
          extensions.digest(convert_to(receipt::text,'UTF8'),'sha256'),'hex'
        );
        if p_evidence_payload->>'context_receipt_digest' is distinct from expected_digest
           or p_evidence_payload->>'context_receipt_ref' is distinct from
              'supabase://public.lf_eventos/'||event_id::text||'#context_receipt'
           or coalesce((receipt#>>'{delivery,jit_only}')::boolean,false) is not true
           or coalesce((receipt#>>'{delivery,policy_payloads}')::boolean,true) is not false
           or coalesce((receipt#>>'{delivery,full_ekb_entries}')::boolean,true) is not false
           or coalesce((receipt#>>'{delivery,full_readmes}')::boolean,true) is not false
           or receipt#>>'{context_budget,status}' not in ('GREEN','YELLOW')
        then
          hard:=hard||jsonb_build_array('context_receipt_readback_mismatch');
        end if;
      end if;

      if not exists (
        select 1
        from private.lf_context_budget_events_v2
        where id=budget_event_id
          and execution_id=p_execution_id
          and evidence_event_id=event_id
          and context_status in ('GREEN','YELLOW')
      ) then
        hard:=hard||jsonb_build_array('context_budget_readback_mismatch');
      end if;
    end if;

  elsif p_step_id='execute_profile' then
    select * into context_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='context_admission'
      and status='ACTIVE_ENFORCEMENT';

    select * into context_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id
      and step_id='context_admission';

    if not found or context_step.status<>context_binding.clean_result_value then
      hard:=hard||jsonb_build_array('context_admission_predecessor_not_clean');
    else
      transport:=p_evidence_payload->'context_transport';
      if p_evidence_payload->>'context_receipt_digest' is distinct from
           context_step.evidence_payload->>'context_receipt_digest'
         or p_evidence_payload->>'context_receipt_ref' is distinct from
           context_step.evidence_payload->>'context_receipt_ref'
         or jsonb_typeof(transport)<>'object'
         or transport->>'profile_source_mode'<>'JIT_BY_REF'
         or transport->>'jit_resolver_ref'<>'supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY'
         or coalesce((transport->>'jit_only')::boolean,false) is not true
         or coalesce((transport->>'policy_payloads')::boolean,true) is not false
         or coalesce((transport->>'full_ekb_entries')::boolean,true) is not false
         or coalesce((transport->>'full_readmes')::boolean,true) is not false
         or coalesce((transport->>'full_prefetch_count')::integer,0)<>0
         or jsonb_typeof(transport->'hydrated_refs')<>'array'
      then
        hard:=hard||jsonb_build_array('execute_profile_context_transport_invalid');
      end if;
    end if;
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','PROFILE_EXECUTION_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','PROFILE_EXECUTION_SERVER_VALIDATED',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$fn$;

create or replace function public.lf_record_profile_execution_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $fn$
declare v_trust jsonb;
begin
  v_trust:=public.lf_profile_execution_trust_validation_v1(
    p_execution_id,p_step_id,p_evidence_payload
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'EJECUCION_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    v_trust,true,'lf_record_profile_execution_step_v1'
  );
end
$fn$;

revoke all on function public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.lf_profile_execution_context_admission_v1(text) from public,anon,authenticated;
revoke all on function public.lf_profile_execution_trust_validation_v1(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb) to service_role;
grant execute on function public.lf_profile_execution_context_admission_v1(text) to service_role;
grant execute on function public.lf_profile_execution_trust_validation_v1(text,text,jsonb) to service_role;
grant execute on function public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text) to service_role;

insert into public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,active,
  execution_order,created_by_execution_id,updated_by_execution_id
)
select
  'EJECUCION_PERFIL_LF',45,'context_admission',true,
  'context_receipt_ref; context_receipt_digest; context_budget_status; context_event_id; context_budget_event_id; delivery; lazy_refs; profile_source_mode; jit_resolver_ref; server_validated',
  'public.lf_operation_step_contracts/EJECUCION_PERFIL_LF/context_admission',
  true,45,
  (
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
),
  (
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where not exists (
  select 1 from public.lf_operation_steps
  where operation_code='EJECUCION_PERFIL_LF' and step_id='context_admission'
);

insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
  created_by_execution_id,updated_by_execution_id
)
select
  'EJECUCION_PERFIL_LF',
  'MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1',
  'supabase://public/lf_operation_judges/EJECUCION_PERFIL_LF/MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1',
  null,
  '["server_validated"]'::jsonb,
  '["server_validation_failed"]'::jsonb,
  '["STEP_PASS_WITH_EVIDENCE","BLOCKED_STEP_NOT_CLEAN","RETURN_TO_ROUTER"]'::jsonb,
  'ACTIVE_ENFORCEMENT',
  (
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
),
  (
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where not exists (
  select 1 from public.lf_operation_judges
  where operation_code='EJECUCION_PERFIL_LF'
    and judge_code='MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1'
);

insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,
  resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,
  required_evidence_keys,next_if_pass,next_if_blocked,status,notes,execution_sql,fail_condition,
  created_by_execution_id,updated_by_execution_id
)
select
  'EJECUCION_PERFIL_LF','context_admission',45,45,
  'CONTRACT-EJECUCION-PERFIL-LF-v0.1',
  'Compilar y verificar el contexto mínimo necesario antes de despachar el modelo.',
  '[]'::jsonb,
  'public.lf_profile_execution_context_admission_v1 + NATIVE_MODEL_RUNTIME_WITH_SUPABASE_CONTEXT',
  '["context_receipt_ref","context_receipt_digest","context_budget_status","context_event_id","context_budget_event_id","delivery","lazy_refs","profile_source_mode","jit_resolver_ref","server_validated"]'::jsonb,
  '{"server_validated":true,"context_budget_status":["GREEN","YELLOW"],"delivery":"COMPACT_JIT_ONLY"}'::jsonb,
  '{"missing_context_receipt":true,"context_budget_red":true,"context_readback_mismatch":true,"full_prefetch_forbidden":true}'::jsonb,
  'BLOCKED_EJECUCION_PERFIL_LF_CONTEXT_ADMISSION_NOT_CLEAN',
  'MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1',
  '["context_receipt_ref","context_receipt_digest","context_budget_status","context_event_id","context_budget_event_id","delivery","lazy_refs","profile_source_mode","jit_resolver_ref","server_validated"]'::jsonb,
  'execute_profile','RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT',
  'Mandatory server-derived bounded context gate. Full policies, EKB entries and READMEs remain out of model transport by default.',
  'public.lf_profile_execution_context_admission_v1(text)',
  '{"server_validation_failed":true}'::jsonb,
  (
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
),
  (
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where not exists (
  select 1 from public.lf_operation_step_contracts
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='context_admission'
    and status='ACTIVE_ENFORCEMENT'
);

insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,
  clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
)
select
  'EJECUCION_PERFIL_LF',45,'context_admission',
  'MINI_JUDGE_EJECUCION_PERFIL_CONTEXT_ADMISSION_V1',
  'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
  '["context_receipt_ref","context_receipt_digest","context_budget_status","context_event_id","context_budget_event_id","delivery","lazy_refs","profile_source_mode","jit_resolver_ref","server_validated"]'::jsonb,
  'ACTIVE_ENFORCEMENT',
  (
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
),
  (
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where not exists (
  select 1 from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='context_admission'
    and status='ACTIVE_ENFORCEMENT'
);

update public.lf_operation_step_contracts
set next_if_pass='context_admission',
    updated_at=now(),
    updated_by_execution_id=(
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where operation_code='EJECUCION_PERFIL_LF'
  and step_id='input_validate'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_contracts
set required_evidence_keys=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(
        required_evidence_keys ||
        '["context_receipt_ref","context_receipt_digest","context_transport"]'::jsonb
      ) x
    ),
    output_payload=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(
        output_payload ||
        '["context_receipt_ref","context_receipt_digest","context_transport"]'::jsonb
      ) x
    ),
    pass_condition=pass_condition||jsonb_build_object(
      'context_admission_predecessor_clean',true,
      'context_delivery','COMPACT_JIT_ONLY',
      'full_prefetch_forbidden',true
    ),
    resolver_ref='public.lf_record_profile_execution_step_v1 + NATIVE_MODEL_RUNTIME_WITH_SUPABASE_CONTEXT',
    updated_at=now(),
    updated_by_execution_id=(
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where operation_code='EJECUCION_PERFIL_LF'
  and step_id='execute_profile'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_judge_bindings
set required_evidence_keys=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(
        required_evidence_keys ||
        '["context_receipt_ref","context_receipt_digest","context_transport"]'::jsonb
      ) x
    ),
    updated_at=now(),
    updated_by_execution_id=(
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where operation_code='EJECUCION_PERFIL_LF'
  and step_id='execute_profile'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_steps
set evidence_required='profile_output; source_refs; context_receipt_ref; context_receipt_digest; context_transport',
    updated_at=now(),
    updated_by_execution_id=(
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where operation_code='EJECUCION_PERFIL_LF'
  and step_id='execute_profile';

update public.lf_operation_contracts
set required_before_write=
      case when required_before_write @> '["context_admission_receipt"]'::jsonb
           then required_before_write
           else required_before_write||'["context_admission_receipt"]'::jsonb end,
    allowed=allowed||jsonb_build_object(
      'context_admission_required',true,
      'context_delivery','COMPACT_JIT_ONLY',
      'profile_source_mode','JIT_BY_REF'
    ),
    blocked=blocked
      ||case when blocked @> '["context_admission_missing"]'::jsonb then '[]'::jsonb else '["context_admission_missing"]'::jsonb end
      ||case when blocked @> '["context_budget_red"]'::jsonb then '[]'::jsonb else '["context_budget_red"]'::jsonb end
      ||case when blocked @> '["context_receipt_mismatch"]'::jsonb then '[]'::jsonb else '["context_receipt_mismatch"]'::jsonb end
      ||case when blocked @> '["full_context_prefetch"]'::jsonb then '[]'::jsonb else '["full_context_prefetch"]'::jsonb end,
    updated_at=now(),
    updated_by_execution_id=(
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where operation_code='EJECUCION_PERFIL_LF'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_registry
set notes=coalesce(notes,'')||
  ' | 2026-09-20 context wiring: mandatory server-derived context_admission before execute_profile; compact JIT-only receipt, current resolver readback, and exact receipt digest binding enforced.',
    updated_at=now(),
    updated_by_execution_id=(
  select e.execution_id
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260920093000_lf_profile_execution_context_admission_wiring_v1.sql'
)
where operation_code='EJECUCION_PERFIL_LF';

comment on function public.lf_profile_execution_context_admission_v1(text)
is 'Compiles the existing bounded Context Admission receipt for EJECUCION_PERFIL_LF, proves current JIT resolver availability, and returns an exact event-bound digest without hydrating full policies/EKB/readmes.';

comment on function public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
is 'Canonical server-bound recorder for EJECUCION_PERFIL_LF. Context admission and model dispatch are fail-closed against exact persisted context receipt/readback.';

do $post$
declare c int;
begin
  select count(*) into c
  from public.lf_operation_steps
  where operation_code='EJECUCION_PERFIL_LF' and active;
  if c<>10 then raise exception 'PROFILE_EXEC_CONTEXT_POST_ACTIVE_STEPS:%',c; end if;

  select count(*) into c
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>10 then raise exception 'PROFILE_EXEC_CONTEXT_POST_ACTIVE_BINDINGS:%',c; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='input_validate'
      and status='ACTIVE_ENFORCEMENT'
      and next_if_pass='context_admission'
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_POST_INPUT_EDGE_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='context_admission'
      and status='ACTIVE_ENFORCEMENT'
      and step_order=45
      and execution_order=45
      and next_if_pass='execute_profile'
      and required_evidence_keys @> '["context_receipt_ref","context_receipt_digest","context_budget_status","context_event_id","context_budget_event_id","delivery","lazy_refs","profile_source_mode","jit_resolver_ref","server_validated"]'::jsonb
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_POST_CONTEXT_STEP_INVALID';
  end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='execute_profile'
      and status='ACTIVE_ENFORCEMENT'
      and required_evidence_keys @> '["context_receipt_ref","context_receipt_digest","context_transport"]'::jsonb
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_POST_EXECUTE_BINDING_MISSING';
  end if;

  if to_regprocedure('public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb)') is null
     or to_regprocedure('public.lf_profile_execution_context_admission_v1(text)') is null
     or to_regprocedure('public.lf_profile_execution_trust_validation_v1(text,text,jsonb)') is null
     or to_regprocedure('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)') is null
  then
    raise exception 'PROFILE_EXEC_CONTEXT_POST_FUNCTIONS_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_operation_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and status='ACTIVE_ENFORCEMENT'
      and allowed->>'context_admission_required'='true'
      and allowed->>'context_delivery'='COMPACT_JIT_ONLY'
      and allowed->>'profile_source_mode'='JIT_BY_REF'
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_POST_OPERATION_CONTRACT_MISSING';
  end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='EJECUCION_PERFIL_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
      and status='PRODUCCION_CONTROLADA_READ_ONLY'
  ) then
    raise exception 'PROFILE_EXEC_CONTEXT_POST_OPERATION_STATE_CHANGED';
  end if;
end
$post$;
