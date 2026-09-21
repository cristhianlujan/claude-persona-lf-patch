begin;

-- Transversal pre-research baseline freeze for governed profile execution.
-- Applicability is derived from canonical profile asset metadata; legacy profiles default to NOT_REQUIRED.
-- The durable baseline step precedes execute_profile and the final profile output is bound back to that exact step.

do $pre$
declare c int;
begin
  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='EJECUCION_PERFIL_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
      and status='PRODUCCION_CONTROLADA_READ_ONLY'
  ) then raise exception 'PROFILE_BASELINE_PRE_OPERATION_STATE_DRIFT'; end if;

  select count(*) into c from public.lf_operation_steps
  where operation_code='EJECUCION_PERFIL_LF' and active;
  if c<>10 then raise exception 'PROFILE_BASELINE_PRE_ACTIVE_STEPS:%',c; end if;

  select count(*) into c from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>10 then raise exception 'PROFILE_BASELINE_PRE_ACTIVE_BINDINGS:%',c; end if;

  if exists (
    select 1 from public.lf_operation_steps
    where operation_code='EJECUCION_PERFIL_LF' and step_id='research_baseline_freeze'
  ) then raise exception 'PROFILE_BASELINE_PRE_STEP_ALREADY_EXISTS'; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='context_admission'
      and status='ACTIVE_ENFORCEMENT'
      and next_if_pass='execute_profile'
  ) then raise exception 'PROFILE_BASELINE_PRE_CONTEXT_EDGE_DRIFT'; end if;

  if to_regprocedure('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)') is null
     or to_regprocedure('public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb)') is null
     or to_regprocedure('public.lf_profile_execution_trust_validation_v1(text,text,jsonb)') is null
  then raise exception 'PROFILE_BASELINE_PRE_REQUIRED_PRIMITIVE_MISSING'; end if;

  select count(*) into c
  from public.lf_operation_execution e
  where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
    and e.status='IN_PROGRESS'
    and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
    and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
    and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql';
  if c<>1 then raise exception 'PROFILE_BASELINE_PRE_RUNTIME_UPDATE_ACTOR_COUNT:%',c; end if;
end
$pre$;

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
  v_baseline_mode text;
begin
  if nullif(btrim(coalesce(p_profile_code,'')),'') is null
     or nullif(btrim(coalesce(p_target_repo,'')),'') is null
     or nullif(btrim(coalesce(p_target_path,'')),'') is null then
    raise exception 'PROFILE_EXECUTION_BEGIN_TARGET_REQUIRED';
  end if;

  select coalesce(nullif(metadata->>'research_baseline_mode',''),'NOT_REQUIRED')
    into v_baseline_mode
  from public.lf_activos
  where codigo_activo=p_profile_code
    and tipo_activo='PERFIL'
    and archived_at is null;

  if v_baseline_mode is null then
    raise exception 'PROFILE_EXECUTION_BEGIN_PROFILE_ASSET_NOT_FOUND:%',p_profile_code;
  end if;
  if v_baseline_mode not in ('NOT_REQUIRED','PRE_RESEARCH_ALWAYS') then
    raise exception 'PROFILE_RESEARCH_BASELINE_MODE_INVALID:%',v_baseline_mode;
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
      'research_baseline_mode',v_baseline_mode,
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
        'research_baseline_mode',v_baseline_mode,
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
    'context_admission_required',true,
    'research_baseline_mode',v_baseline_mode
  );
end
$fn$;

create or replace function public.lf_profile_execution_research_baseline_v1(
  p_execution_id text,
  p_baseline_snapshot jsonb,
  p_actor_execution_id text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','extensions'
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  prior public.lf_operation_execution_steps%rowtype;
  prior_binding public.lf_operation_step_judge_bindings%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  step_binding public.lf_operation_step_judge_bindings%rowtype;
  mode text;
  expected_input text;
  expected_source text;
  baseline_digest text;
  receipt_ref text;
  binding jsonb;
  payload jsonb;
  trust jsonb;
  ref text;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception 'PROFILE_RESEARCH_BASELINE_EXECUTION_ID_REQUIRED';
  end if;

  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or e.operation_code<>'EJECUCION_PERFIL_LF' or e.target_type<>'PERFIL' or e.status<>'IN_PROGRESS' then
    raise exception 'PROFILE_RESEARCH_BASELINE_EXECUTION_BINDING_INVALID:%',p_execution_id;
  end if;

  mode:=coalesce(nullif(e.manifest->>'research_baseline_mode',''),'NOT_REQUIRED');
  if mode not in ('NOT_REQUIRED','PRE_RESEARCH_ALWAYS') then
    raise exception 'PROFILE_RESEARCH_BASELINE_MODE_INVALID:%',mode;
  end if;

  select * into step_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='research_baseline_freeze'
    and status='ACTIVE_ENFORCEMENT';
  if not found then raise exception 'PROFILE_RESEARCH_BASELINE_BINDING_MISSING'; end if;

  select * into existing
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='research_baseline_freeze';
  if found and existing.status=step_binding.clean_result_value then
    return existing.evidence_payload||jsonb_build_object('replay',true);
  end if;

  select * into prior_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='context_admission'
    and status='ACTIVE_ENFORCEMENT';
  select * into prior
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='context_admission';
  if not found or prior.status<>prior_binding.clean_result_value then
    raise exception 'PROFILE_RESEARCH_BASELINE_CONTEXT_NOT_CLEAN:%',p_execution_id;
  end if;

  receipt_ref:='supabase://public.lf_operation_execution_steps/'||p_execution_id||'/research_baseline_freeze';

  if mode='NOT_REQUIRED' then
    binding:=jsonb_build_object(
      'applicability','NOT_APPLICABLE',
      'mode',mode,
      'capture_stage','NOT_APPLICABLE',
      'baseline_digest','NOT_APPLICABLE',
      'baseline_snapshot','{}'::jsonb
    );
  else
    if p_baseline_snapshot is null or jsonb_typeof(p_baseline_snapshot)<>'object' then
      raise exception 'PROFILE_RESEARCH_BASELINE_REQUIRED';
    end if;
    if p_baseline_snapshot->>'snapshot_version'<>'SRCR_BASELINE_SOLUTION_V1'
       or p_baseline_snapshot->>'capture_stage'<>'PRE_RESEARCH_CHALLENGER'
       or nullif(btrim(coalesce(p_baseline_snapshot->>'input_digest','')),'') is null
       or nullif(btrim(coalesce(p_baseline_snapshot->>'profile_source_digest','')),'') is null
       or jsonb_typeof(p_baseline_snapshot->'evidence_refs')<>'array'
       or jsonb_array_length(p_baseline_snapshot->'evidence_refs')=0
       or nullif(btrim(coalesce(p_baseline_snapshot->>'leading_solution_summary','')),'') is null
       or jsonb_typeof(p_baseline_snapshot->'known_gaps')<>'array'
       or jsonb_typeof(p_baseline_snapshot->'assumptions')<>'array'
    then raise exception 'PROFILE_RESEARCH_BASELINE_SHAPE_INVALID'; end if;

    expected_input:=e.manifest->>'input_sha256';
    if expected_input ~ '^[0-9a-f]{64}$' then expected_input:='sha256:'||expected_input; end if;
    expected_source:=e.manifest->>'profile_source_digest';
    if expected_source ~ '^[0-9a-f]{64}$' then expected_source:='sha256:'||expected_source; end if;

    if coalesce(expected_input,'') !~ '^sha256:[0-9a-f]{64}$'
       or p_baseline_snapshot->>'input_digest' is distinct from expected_input then
      raise exception 'PROFILE_RESEARCH_BASELINE_INPUT_DIGEST_MISMATCH';
    end if;
    if coalesce(expected_source,'') !~ '^sha256:[0-9a-f]{64}$'
       or p_baseline_snapshot->>'profile_source_digest' is distinct from expected_source then
      raise exception 'PROFILE_RESEARCH_BASELINE_SOURCE_DIGEST_MISMATCH';
    end if;

    for ref in select jsonb_array_elements_text(p_baseline_snapshot->'evidence_refs') loop
      if ref ~* '^(https?://|external://|web://)' then
        raise exception 'PROFILE_RESEARCH_BASELINE_EXTERNAL_REF_FORBIDDEN:%',ref;
      end if;
    end loop;

    baseline_digest:='sha256:'||encode(
      extensions.digest(convert_to(p_baseline_snapshot::text,'UTF8'),'sha256'),'hex'
    );
    binding:=jsonb_build_object(
      'applicability','REQUIRED',
      'mode',mode,
      'capture_stage','PRE_RESEARCH_CHALLENGER',
      'baseline_digest',baseline_digest,
      'baseline_snapshot',p_baseline_snapshot
    );
  end if;

  payload:=jsonb_build_object(
    'research_baseline_binding',binding,
    'baseline_receipt_ref',receipt_ref,
    'server_validated',true,
    'blocking_codes','[]'::jsonb
  );
  trust:=jsonb_build_object(
    'valid',true,
    'code','PROFILE_RESEARCH_BASELINE_SERVER_VALIDATED',
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );

  return public.lf_record_operation_step_core_v1(
    p_execution_id,'research_baseline_freeze',receipt_ref,payload,p_actor_execution_id,
    'EJECUCION_PERFIL_LF','PERFIL',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
    trust,true,'lf_profile_execution_research_baseline_v1'
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
  baseline_step public.lf_operation_execution_steps%rowtype;
  baseline_binding public.lf_operation_step_judge_bindings%rowtype;
  baseline jsonb;
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

  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or e.operation_code<>'EJECUCION_PERFIL_LF' or e.target_type<>'PERFIL' or e.status<>'IN_PROGRESS' then
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
    then hard:=hard||jsonb_build_array('context_admission_shape_invalid');
    else
      event_id:=(p_evidence_payload->>'context_event_id')::bigint;
      budget_event_id:=(p_evidence_payload->>'context_budget_event_id')::bigint;
      select payload->'context_receipt' into receipt
      from public.lf_eventos
      where id=event_id and created_by_execution_id=p_execution_id and payload->>'producer'='fn_lf_router_preflight_v1';
      if receipt is null then hard:=hard||jsonb_build_array('context_event_readback_missing');
      else
        expected_digest:='sha256:'||encode(extensions.digest(convert_to(receipt::text,'UTF8'),'sha256'),'hex');
        if p_evidence_payload->>'context_receipt_digest' is distinct from expected_digest
           or p_evidence_payload->>'context_receipt_ref' is distinct from 'supabase://public.lf_eventos/'||event_id::text||'#context_receipt'
           or coalesce((receipt#>>'{delivery,jit_only}')::boolean,false) is not true
           or coalesce((receipt#>>'{delivery,policy_payloads}')::boolean,true) is not false
           or coalesce((receipt#>>'{delivery,full_ekb_entries}')::boolean,true) is not false
           or coalesce((receipt#>>'{delivery,full_readmes}')::boolean,true) is not false
           or receipt#>>'{context_budget,status}' not in ('GREEN','YELLOW')
        then hard:=hard||jsonb_build_array('context_receipt_readback_mismatch'); end if;
      end if;
      if not exists (
        select 1 from private.lf_context_budget_events_v2
        where id=budget_event_id and execution_id=p_execution_id and evidence_event_id=event_id and context_status in ('GREEN','YELLOW')
      ) then hard:=hard||jsonb_build_array('context_budget_readback_mismatch'); end if;
    end if;

  elsif p_step_id='execute_profile' then
    select * into context_binding from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF' and step_id='context_admission' and status='ACTIVE_ENFORCEMENT';
    select * into context_step from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='context_admission';
    if not found or context_step.status<>context_binding.clean_result_value then
      hard:=hard||jsonb_build_array('context_admission_predecessor_not_clean');
    else
      transport:=p_evidence_payload->'context_transport';
      if p_evidence_payload->>'context_receipt_digest' is distinct from context_step.evidence_payload->>'context_receipt_digest'
         or p_evidence_payload->>'context_receipt_ref' is distinct from context_step.evidence_payload->>'context_receipt_ref'
         or jsonb_typeof(transport)<>'object'
         or transport->>'profile_source_mode'<>'JIT_BY_REF'
         or transport->>'jit_resolver_ref'<>'supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY'
         or coalesce((transport->>'jit_only')::boolean,false) is not true
         or coalesce((transport->>'policy_payloads')::boolean,true) is not false
         or coalesce((transport->>'full_ekb_entries')::boolean,true) is not false
         or coalesce((transport->>'full_readmes')::boolean,true) is not false
         or coalesce((transport->>'full_prefetch_count')::integer,0)<>0
         or jsonb_typeof(transport->'hydrated_refs')<>'array'
      then hard:=hard||jsonb_build_array('execute_profile_context_transport_invalid'); end if;
    end if;

    select * into baseline_binding from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF' and step_id='research_baseline_freeze' and status='ACTIVE_ENFORCEMENT';
    select * into baseline_step from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='research_baseline_freeze';
    if not found or baseline_step.status<>baseline_binding.clean_result_value then
      hard:=hard||jsonb_build_array('research_baseline_predecessor_not_clean');
    else
      baseline:=baseline_step.evidence_payload->'research_baseline_binding';
      if p_evidence_payload->>'research_baseline_ref' is distinct from baseline_step.evidence_payload->>'baseline_receipt_ref'
         or p_evidence_payload->>'research_baseline_digest' is distinct from baseline->>'baseline_digest' then
        hard:=hard||jsonb_build_array('research_baseline_execute_binding_mismatch');
      end if;
      if baseline->>'applicability'='REQUIRED' then
        if jsonb_typeof(p_evidence_payload->'profile_output')<>'object'
           or p_evidence_payload#>>'{profile_output,research_assurance,baseline_digest}' is distinct from baseline->>'baseline_digest'
           or p_evidence_payload#>'{profile_output,research_assurance,baseline_solution_snapshot}' is distinct from baseline->'baseline_snapshot'
        then hard:=hard||jsonb_build_array('research_baseline_output_mutated'); end if;
      end if;
    end if;
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,'code','PROFILE_EXECUTION_SERVER_VALIDATED',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$fn$;

revoke all on function public.lf_profile_execution_research_baseline_v1(text,jsonb,text) from public,anon,authenticated;
grant execute on function public.lf_profile_execution_research_baseline_v1(text,jsonb,text) to service_role;

insert into public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,
  execution_order,created_by_execution_id,updated_by_execution_id
)
select 'EJECUCION_PERFIL_LF',47,'research_baseline_freeze',true,
  'research_baseline_binding; baseline_receipt_ref; server_validated',
  'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json',
  'e64b38a85e7f3dd347b3979258287ecd047f46549522ba15935f8c9eeea11aef',true,47,e.execution_id,e.execution_id
from public.lf_operation_execution e
where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and e.status='IN_PROGRESS'
  and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
  and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
  and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql';

insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
  created_by_execution_id,updated_by_execution_id
)
select 'EJECUCION_PERFIL_LF','MINI_JUDGE_EJECUCION_PERFIL_RESEARCH_BASELINE_V1',
  'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json',
  'e64b38a85e7f3dd347b3979258287ecd047f46549522ba15935f8c9eeea11aef','["server_validated"]'::jsonb,'["server_validation_failed"]'::jsonb,
  '["STEP_PASS_WITH_EVIDENCE","BLOCKED_STEP_NOT_CLEAN","RETURN_TO_ROUTER"]'::jsonb,
  'ACTIVE_ENFORCEMENT',e.execution_id,e.execution_id
from public.lf_operation_execution e
where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and e.status='IN_PROGRESS'
  and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
  and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
  and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql';

insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,
  output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,
  next_if_pass,next_if_blocked,status,notes,execution_sql,fail_condition,created_by_execution_id,updated_by_execution_id
)
select 'EJECUCION_PERFIL_LF','research_baseline_freeze',47,47,'CONTRACT-EJECUCION-PERFIL-LF-v0.1',
  'Freeze a compact server-bound pre-research solution baseline when the canonical profile asset requires it; otherwise close as server-side N/A.',
  '[]'::jsonb,'public.lf_profile_execution_research_baseline_v1 + NATIVE_MODEL_RUNTIME_WITH_SUPABASE_CONTEXT',
  '["research_baseline_binding","baseline_receipt_ref","server_validated"]'::jsonb,
  '{"server_validated":true,"applicability_source":"PROFILE_ASSET_METADATA","clean_step_immutable":true}'::jsonb,
  '{"missing_or_mutated_baseline":true,"external_pre_freeze_evidence":true,"binding_mismatch":true}'::jsonb,
  'BLOCKED_EJECUCION_PERFIL_LF_RESEARCH_BASELINE_NOT_CLEAN',
  'MINI_JUDGE_EJECUCION_PERFIL_RESEARCH_BASELINE_V1',
  '["research_baseline_binding","baseline_receipt_ref","server_validated"]'::jsonb,
  'execute_profile','RETURN_TO_ROUTER','ACTIVE_ENFORCEMENT',
  'Transversal and profile-agnostic. PRE_RESEARCH_ALWAYS is opt-in from canonical profile asset metadata; NOT_REQUIRED costs no model baseline phase.',
  'public.lf_profile_execution_research_baseline_v1(text,jsonb,text)',
  '{"server_validation_failed":true}'::jsonb,e.execution_id,e.execution_id
from public.lf_operation_execution e
where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and e.status='IN_PROGRESS'
  and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
  and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
  and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql';

insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
)
select 'EJECUCION_PERFIL_LF',47,'research_baseline_freeze','MINI_JUDGE_EJECUCION_PERFIL_RESEARCH_BASELINE_V1',
  'STEP_PASS_WITH_EVIDENCE','BLOCKED_STEP_NOT_CLEAN','RETURN_TO_ROUTER',
  '["research_baseline_binding","baseline_receipt_ref","server_validated"]'::jsonb,
  'ACTIVE_ENFORCEMENT',e.execution_id,e.execution_id
from public.lf_operation_execution e
where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and e.status='IN_PROGRESS'
  and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
  and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
  and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql';

update public.lf_operation_step_contracts
set next_if_pass='research_baseline_freeze',updated_at=now(),
    updated_by_execution_id=(select e.execution_id from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF' and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql')
where operation_code='EJECUCION_PERFIL_LF' and step_id='context_admission' and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_contracts
set required_evidence_keys=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(required_evidence_keys||'["research_baseline_ref","research_baseline_digest"]'::jsonb) x
    ),
    output_payload=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(output_payload||'["research_baseline_ref","research_baseline_digest"]'::jsonb) x
    ),
    pass_condition=pass_condition||jsonb_build_object(
      'research_baseline_predecessor_clean',true,
      'research_baseline_exact_binding',true,
      'research_baseline_output_immutable_when_required',true
    ),
    updated_at=now(),
    updated_by_execution_id=(select e.execution_id from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF' and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql')
where operation_code='EJECUCION_PERFIL_LF' and step_id='execute_profile' and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_judge_bindings
set required_evidence_keys=(
      select jsonb_agg(distinct x order by x)
      from jsonb_array_elements_text(required_evidence_keys||'["research_baseline_ref","research_baseline_digest"]'::jsonb) x
    ),
    updated_at=now(),
    updated_by_execution_id=(select e.execution_id from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF' and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql')
where operation_code='EJECUCION_PERFIL_LF' and step_id='execute_profile' and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_steps
set evidence_required='profile_output; source_refs; context_receipt_ref; context_receipt_digest; context_transport; research_baseline_ref; research_baseline_digest',
    updated_at=now(),
    updated_by_execution_id=(select e.execution_id from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF' and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql')
where operation_code='EJECUCION_PERFIL_LF' and step_id='execute_profile';

update public.lf_operation_contracts
set required_before_write=case when required_before_write @> '["research_baseline_freeze"]'::jsonb
       then required_before_write else required_before_write||'["research_baseline_freeze"]'::jsonb end,
    allowed=allowed||jsonb_build_object(
      'research_baseline_applicability_authority','public.lf_activos.metadata.research_baseline_mode',
      'research_baseline_modes',jsonb_build_array('NOT_REQUIRED','PRE_RESEARCH_ALWAYS'),
      'research_baseline_default','NOT_REQUIRED',
      'research_baseline_external_refs_before_freeze',false
    ),
    blocked=blocked
      ||case when blocked @> '["research_baseline_missing"]'::jsonb then '[]'::jsonb else '["research_baseline_missing"]'::jsonb end
      ||case when blocked @> '["research_baseline_mutated"]'::jsonb then '[]'::jsonb else '["research_baseline_mutated"]'::jsonb end
      ||case when blocked @> '["research_before_baseline_freeze"]'::jsonb then '[]'::jsonb else '["research_before_baseline_freeze"]'::jsonb end,
    updated_at=now(),
    updated_by_execution_id=(select e.execution_id from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF' and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql')
where operation_code='EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,linea_codigo,
  estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
  accion_migracion,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
  raw_payload,metadata,created_by_execution_id,updated_by_execution_id
)
select 'PROFILE_RESEARCH_BASELINE_FREEZE','PROFILE_RESEARCH_BASELINE_FREEZE','CAPABILITY','TRANSVERSAL_RUNTIME_ASSURANCE',
  'SQL+JSON','GOV_CAPACIDADES_REUTILIZABLES','CANDIDATE_PENDING_QUALIFICATION','VIGENTE','READ_ONLY','TRANSVERSAL',
  'CANDIDATE_READ_ONLY','BLOQUEADO','REGISTER_TRANSVERSAL_CAPABILITY','v1.0',
  'sandbox/lf_contract_gate_test/transversal_assets/profile_research_baseline_freeze/README.md',
  'supabase://public.lf_operation_registry/EJECUCION_PERFIL_LF','LF_GOVERNANCE','2026-09-21',
  'Generic pre-research baseline identity and immutable runtime binding for governed profile execution.',
  'NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','PROFILE_RESEARCH_BASELINE_FREEZE_20260921',1,gen_random_uuid(),
  jsonb_build_object(
    'operation_code','EJECUCION_PERFIL_LF',
    'step_id','research_baseline_freeze',
    'function','public.lf_profile_execution_research_baseline_v1',
    'contract_sha256','e64b38a85e7f3dd347b3979258287ecd047f46549522ba15935f8c9eeea11aef'
  ),
  jsonb_build_object(
    'source_kind','GITHUB_SOURCE_PLUS_SUPABASE_REGISTRY',
    'transversal_inventory',jsonb_build_object(
      'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
      'logical_key','PROFILE_RESEARCH_BASELINE_FREEZE',
      'class','RUNTIME_ASSURANCE_GUARD',
      'inventory_status','CANDIDATE_PENDING_QUALIFICATION',
      'lookup_rule','ASSET_INVENTORY_FIRST_THEN_CURRENTNESS_THEN_EXPAND_SEARCH',
      'no_duplicate_engine',true,
      'consumers_known',jsonb_build_array('EJECUCION_PERFIL_LF'),
      'documentation',jsonb_build_object(
        'status','SOURCE_FIRST_BOUND','repo','cristhianlujan/claude-persona-lf-patch',
        'readme_ref','sandbox/lf_contract_gate_test/transversal_assets/profile_research_baseline_freeze/README.md',
        'contract_version','lf-transversal-readme-contract/v3'
      ),
      'physical_assets',jsonb_build_array(
        'public.lf_operation_execution_steps',
        'public.lf_profile_execution_research_baseline_v1',
        'public.lf_profile_execution_trust_validation_v1',
        'sandbox/lf_contract_gate_test/profile_execution_runtime/profile_research_baseline_freeze_contract_v1.json'
      )
    )
  ),e.execution_id,e.execution_id
from public.lf_operation_execution e
where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF'
  and e.status='IN_PROGRESS'
  and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
  and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF'
  and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql'
  and not exists(select 1 from public.lf_activos where codigo_activo='PROFILE_RESEARCH_BASELINE_FREEZE' and archived_at is null);

update public.lf_operation_registry
set notes=coalesce(notes,'')||
  ' | 2026-09-21 research baseline wiring: canonical profile asset decides applicability; durable baseline_freeze step precedes execute_profile; exact snapshot/digest is rebound at server trust validation; legacy profiles default NOT_REQUIRED.',
    updated_at=now(),
    updated_by_execution_id=(select e.execution_id from public.lf_operation_execution e
      where e.operation_code='ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS'
        and coalesce((e.manifest->>'runtime_update_governed')::boolean,false)=true
        and e.manifest->>'target_operation'='EJECUCION_PERFIL_LF' and e.target_path='supabase/migrations/20260921043000_lf_profile_execution_research_baseline_freeze_v1.sql')
where operation_code='EJECUCION_PERFIL_LF';

comment on function public.lf_profile_execution_research_baseline_v1(text,jsonb,text)
is 'Transversal fail-closed pre-research baseline freeze for EJECUCION_PERFIL_LF. Applicability comes from canonical profile asset metadata; required baselines are persisted before execute_profile and cannot be replaced after a clean step.';

comment on function public.lf_profile_execution_trust_validation_v1(text,text,jsonb)
is 'Server trust boundary for EJECUCION_PERFIL_LF. Enforces context transport and exact persisted pre-research baseline binding when the profile asset opts into research baseline assurance.';

do $post$
declare c int;
begin
  select count(*) into c from public.lf_operation_steps
  where operation_code='EJECUCION_PERFIL_LF' and active;
  if c<>11 then raise exception 'PROFILE_BASELINE_POST_ACTIVE_STEPS:%',c; end if;

  select count(*) into c from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF' and status='ACTIVE_ENFORCEMENT';
  if c<>11 then raise exception 'PROFILE_BASELINE_POST_ACTIVE_BINDINGS:%',c; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF' and step_id='context_admission'
      and status='ACTIVE_ENFORCEMENT' and next_if_pass='research_baseline_freeze'
  ) then raise exception 'PROFILE_BASELINE_POST_CONTEXT_EDGE_MISSING'; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF' and step_id='research_baseline_freeze'
      and status='ACTIVE_ENFORCEMENT' and step_order=47 and execution_order=47 and next_if_pass='execute_profile'
      and required_evidence_keys @> '["research_baseline_binding","baseline_receipt_ref","server_validated"]'::jsonb
  ) then raise exception 'PROFILE_BASELINE_POST_STEP_INVALID'; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='EJECUCION_PERFIL_LF' and step_id='execute_profile' and status='ACTIVE_ENFORCEMENT'
      and required_evidence_keys @> '["research_baseline_ref","research_baseline_digest"]'::jsonb
  ) then raise exception 'PROFILE_BASELINE_POST_EXECUTE_BINDING_MISSING'; end if;

  if to_regprocedure('public.lf_profile_execution_research_baseline_v1(text,jsonb,text)') is null
     or to_regprocedure('public.lf_profile_execution_trust_validation_v1(text,text,jsonb)') is null
  then raise exception 'PROFILE_BASELINE_POST_FUNCTIONS_MISSING'; end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='PROFILE_RESEARCH_BASELINE_FREEZE' and tipo_activo='CAPABILITY'
      and estado_operativo='READ_ONLY' and archived_at is null
      and metadata#>>'{transversal_inventory,inventory_status}'='CANDIDATE_PENDING_QUALIFICATION'
  ) then raise exception 'PROFILE_BASELINE_POST_ASSET_REGISTRATION_MISSING'; end if;

  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='EJECUCION_PERFIL_LF' and lifecycle_state_code='OP_OPERATIONAL'
      and status='PRODUCCION_CONTROLADA_READ_ONLY'
  ) then raise exception 'PROFILE_BASELINE_POST_OPERATION_STATE_CHANGED'; end if;
end
$post$;

commit;
