BEGIN;
-- PE10 C4 operation-neutral frozen-required-step parity. No profile-specific exception.
-- Preflight: preserve known enforcement logic except frozen step membership.
DO $check$
BEGIN
 IF (SELECT count(*) FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>24 THEN RAISE EXCEPTION 'PE10_OPEN_SET_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_operation_execution WHERE status='IN_PROGRESS' AND manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}' IS NOT NULL)<>24 THEN RAISE EXCEPTION 'FROZEN_SCOPE_DRIFT'; END IF;
END; $check$;

CREATE OR REPLACE FUNCTION public.lf_record_operation_step_core_v1(p_execution_id text, p_step_id text, p_evidence_ref text, p_evidence_payload jsonb, p_actor_execution_id text, p_expected_operation_code text, p_expected_target_type text, p_contract_status text, p_binding_status text, p_judge_status text, p_trust_validation jsonb, p_close_on_report_output boolean, p_recorder_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_registry public.lf_operation_registry%rowtype;
  v_step public.lf_operation_steps%rowtype;
  v_contract public.lf_operation_step_contracts%rowtype;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
  v_judge public.lf_operation_judges%rowtype;
  v_existing public.lf_operation_execution_steps%rowtype;
  v_contract_count integer := 0;
  v_binding_count integer := 0;
  v_judge_count integer := 0;
  v_prior_missing integer := 0;
  v_prior_bad integer := 0;
  v_required_not_clean integer := 0;
  v_key text;
  v_missing_keys text[] := array[]::text[];
  v_blocking_codes jsonb := '[]'::jsonb;
  v_assertions jsonb := '[]'::jsonb;
  v_hard_fails jsonb := '[]'::jsonb;
  v_pass_if_norm jsonb := '[]'::jsonb;
  v_fail_if_norm jsonb := '[]'::jsonb;
  v_result_values_norm jsonb := '[]'::jsonb;
  v_missing_pass_items text[] := array[]::text[];
  v_triggered_fail_items text[] := array[]::text[];
  v_pass_item text;
  v_fail_item text;
  v_derived_result text;
  v_block_code text;
  v_block_details jsonb := '{}'::jsonb;
  v_payload jsonb;
  v_attempt_history jsonb := '[]'::jsonb;
  v_existing_retryable boolean := false;
  v_snapshot_steps jsonb;
  v_snapshot_applies boolean := false;
  v_snapshot_invalid boolean := false;
  v_route_guard jsonb;
begin
  if p_execution_id is null or btrim(p_execution_id)='' or p_step_id is null or btrim(p_step_id)='' or p_actor_execution_id is null or btrim(p_actor_execution_id)='' then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_OR_ACTOR_MISSING','durable',false);
  end if;
  if p_step_id='init_execution' then return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE','durable',false); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false); end if;
  if p_trust_validation is null
     or jsonb_typeof(p_trust_validation) is distinct from 'object'
     or not (p_trust_validation ? 'valid')
     or jsonb_typeof(p_trust_validation->'valid') is distinct from 'boolean' then
    return jsonb_build_object('outcome','BLOCKED','code','TRUST_VALIDATION_INVALID','durable',false);
  end if;

  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found or v_execution.operation_code<>p_expected_operation_code or v_execution.target_type<>p_expected_target_type then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  if v_execution.status<>'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false); end if;
  -- Frozen execution contract is authoritative when present. No silent fallback
  -- when a snapshot is malformed; legacy executions without a snapshot retain
  -- the original current-catalog behavior.
  v_snapshot_steps:=v_execution.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}';
  if v_snapshot_steps is not null then
    if jsonb_typeof(v_snapshot_steps)<>'array' or jsonb_array_length(v_snapshot_steps)=0 then
      return jsonb_build_object('outcome','BLOCKED','code','FROZEN_REQUIRED_STEPS_INVALID','durable',false);
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_snapshot_steps) a(value)
      where jsonb_typeof(a.value)<>'string' or nullif(btrim(a.value #>> '{}'),'') is null
    ) or (
      select count(*) from jsonb_array_elements_text(v_snapshot_steps)
    ) <> (
      select count(distinct value) from jsonb_array_elements_text(v_snapshot_steps) s(value)
    ) or exists (
      select 1 from jsonb_array_elements_text(v_snapshot_steps) s(value)
      where not exists (
        select 1 from public.lf_operation_steps os
        where os.operation_code=v_execution.operation_code and os.step_id=s.value
          and os.active and os.required
      )
    ) then
      return jsonb_build_object('outcome','BLOCKED','code','FROZEN_REQUIRED_STEPS_INVALID','durable',false);
    end if;
    v_snapshot_applies:=true;
  end if;


  select * into v_registry from public.lf_operation_registry where operation_code=v_execution.operation_code;
  if not found or v_registry.applies_to_asset_type<>v_execution.target_type then return jsonb_build_object('outcome','BLOCKED','code','OPERATION_REGISTRY_TARGET_MISMATCH','durable',false); end if;

  select * into v_step from public.lf_operation_steps where operation_code=v_execution.operation_code and step_id=p_step_id and active is true;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;

  select count(*) into v_contract_count from public.lf_operation_step_contracts where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_contract_status;
  if v_contract_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_CONTRACT_NOT_EXACT','count',v_contract_count,'durable',false); end if;
  select * into v_contract from public.lf_operation_step_contracts where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_contract_status limit 1;

  select count(*) into v_binding_count from public.lf_operation_step_judge_bindings where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_binding_status;
  if v_binding_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_BINDING_NOT_EXACT','count',v_binding_count,'durable',false); end if;
  select * into v_binding from public.lf_operation_step_judge_bindings where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_binding_status limit 1;

  select count(*) into v_judge_count from public.lf_operation_judges where operation_code=v_execution.operation_code and judge_code=v_binding.judge_code and status=p_judge_status;
  if v_judge_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_NOT_EXACT','count',v_judge_count,'durable',false); end if;
  select * into v_judge from public.lf_operation_judges where operation_code=v_execution.operation_code and judge_code=v_binding.judge_code and status=p_judge_status limit 1;

  select * into v_existing from public.lf_operation_execution_steps where execution_id=p_execution_id and step_order=v_step.step_order;
  if found and v_existing.step_id<>p_step_id then return jsonb_build_object('outcome','BLOCKED','code','STEP_ORDER_ALREADY_BOUND_TO_OTHER_STEP','durable',true); end if;
  if found then
    if v_existing.status=v_binding.clean_result_value
       and v_existing.evidence_ref is not distinct from p_evidence_ref
       and (
         (v_existing.evidence_payload - array[
           'step_result','derived_result','derived_by_judge','mini_judge_code','mini_judge_result',
           'missing_pass_items','triggered_fail_items','attempt_history','recorded_by_rpc','core_recorder',
           'trust_validation','assertions_checked','hard_fails_checked','caller_assertions_ignored',
           'blocking_findings','blocking_codes','return_to_worker_reasons','canonical_route_guard_receipt'
         ]::text[])
         is not distinct from
         (p_evidence_payload - array['assertions_checked','hard_fails_checked','caller_assertions_ignored','blocking_codes','canonical_route_guard_receipt']::text[])
       )
       and coalesce(v_existing.evidence_payload->'blocking_codes','[]'::jsonb)
           is not distinct from coalesce(p_evidence_payload->'blocking_codes','[]'::jsonb)
       and (v_existing.evidence_payload->'trust_validation') is not distinct from p_trust_validation
       and (p_trust_validation->'valid') is not distinct from 'true'::jsonb then
      return jsonb_build_object('outcome','STEP_RECORDED','replay',true,'step_id',p_step_id,'status',v_existing.status,'execution_status',v_execution.status);
    end if;
    if v_existing.status in (v_binding.blocked_result_value,v_binding.return_result_value) then
      v_existing_retryable:=true;
      if jsonb_typeof(v_existing.evidence_payload->'attempt_history')='array' then v_attempt_history:=v_existing.evidence_payload->'attempt_history'; end if;
    else
      return jsonb_build_object('outcome','BLOCKED','code','STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE','status',v_existing.status,'durable',true);
    end if;
  end if;

  select count(*) into v_prior_missing
  from public.lf_operation_steps s
  where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and (not v_snapshot_applies or exists (
      select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id)
      where frozen.step_id=s.step_id
    ))
    and coalesce(s.execution_order,s.step_order)<coalesce(v_step.execution_order,v_step.step_order)
    and not exists(select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id);

  select count(*) into v_prior_bad
  from public.lf_operation_steps s
  join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings pb on pb.operation_code=s.operation_code and pb.step_order=s.step_order and pb.step_id=s.step_id and pb.status=p_binding_status
  where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and (not v_snapshot_applies or exists (
      select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id)
      where frozen.step_id=s.step_id
    ))
    and coalesce(s.execution_order,s.step_order)<coalesce(v_step.execution_order,v_step.step_order)
    and (pb.clean_result_value is null or es.status<>pb.clean_result_value);

  if v_prior_missing>0 or v_prior_bad>0 then
    v_block_code:='PRIOR_REQUIRED_STEP_NOT_CLEAN';
    v_block_details:=jsonb_build_object('prior_missing',v_prior_missing,'prior_bad',v_prior_bad);
  end if;

  if v_block_code is null and (p_trust_validation->'valid') is distinct from 'true'::jsonb then
    v_block_code:=coalesce(nullif(p_trust_validation->>'code',''),'TRUST_VALIDATION_FAILED');
    v_block_details:=coalesce(p_trust_validation->'details','{}'::jsonb);
  end if;

  if v_block_code is null then
    for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop
      if not (p_evidence_payload ? v_key) or p_evidence_payload->v_key is null or p_evidence_payload->v_key='null'::jsonb or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then
        v_missing_keys:=array_append(v_missing_keys,v_key);
      end if;
    end loop;
    if cardinality(v_missing_keys)>0 then
      v_block_code:='REQUIRED_EVIDENCE_MISSING';
      v_block_details:=jsonb_build_object('missing_keys',to_jsonb(v_missing_keys));
    end if;
  end if;

  if v_block_code is null
     and v_execution.operation_code='EJECUCION_ESTRATEGIA_LF'
     and p_step_id='pre_write_execution_binding_gate' then
    v_route_guard:=public.lf_strategy_canonical_route_guard_v1(
      p_execution_id,v_execution.operation_code,false
    );
    if coalesce((v_route_guard->>'valid')::boolean,false) is not true then
      v_block_code:=coalesce(nullif(v_route_guard->>'blocking_code',''),'CANONICAL_ROUTE_GUARD_FAILED');
      v_block_details:=jsonb_build_object(
        'route_guard',v_route_guard,
        'execution_id',p_execution_id,
        'step_id',p_step_id
      );
    end if;
  end if;

  if v_block_code is null and p_evidence_payload ? 'blocking_codes' then
    if jsonb_typeof(p_evidence_payload->'blocking_codes')<>'array' then v_block_code:='BLOCKING_CODES_INVALID';
    else v_blocking_codes:=p_evidence_payload->'blocking_codes'; if jsonb_array_length(v_blocking_codes)>0 then v_block_code:=coalesce(v_contract.blocking_code,'STEP_BLOCKED'); v_block_details:=jsonb_build_object('caller_blocking_codes',v_blocking_codes); end if; end if;
  end if;

  if jsonb_typeof(v_judge.result_values)='array' then v_result_values_norm:=v_judge.result_values;
  elsif jsonb_typeof(v_judge.result_values)='object' then select coalesce(jsonb_agg(value order by key),'[]'::jsonb) into v_result_values_norm from jsonb_each_text(v_judge.result_values) where value is not null and btrim(value)<>'';
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_RESULT_VALUES_SHAPE_INVALID','durable',false); end if;

  if jsonb_typeof(v_judge.pass_if)='array' then v_pass_if_norm:=v_judge.pass_if;
  elsif jsonb_typeof(v_judge.pass_if)='object' and jsonb_typeof(v_judge.pass_if->'pass_if')='array' then v_pass_if_norm:=v_judge.pass_if->'pass_if';
  elsif jsonb_typeof(v_judge.pass_if)='object' then select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_pass_if_norm from jsonb_each(v_judge.pass_if) where value='true'::jsonb;
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_PASS_IF_SHAPE_INVALID','durable',false); end if;

  if jsonb_typeof(v_judge.fail_if)='array' then v_fail_if_norm:=v_judge.fail_if;
  elsif jsonb_typeof(v_judge.fail_if)='object' and jsonb_typeof(v_judge.fail_if->'fail_if')='array' then v_fail_if_norm:=v_judge.fail_if->'fail_if';
  elsif jsonb_typeof(v_judge.fail_if)='object' then select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_fail_if_norm from jsonb_each(v_judge.fail_if) where value='true'::jsonb;
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_FAIL_IF_SHAPE_INVALID','durable',false); end if;

  if (p_trust_validation->'valid') is not distinct from 'true'::jsonb
     and not (p_trust_validation ? 'server_assertions') then
    return jsonb_build_object('outcome','BLOCKED','code','SERVER_ASSERTIONS_REQUIRED_FOR_VALID_TRUST','durable',false);
  end if;
  v_assertions:=coalesce(p_trust_validation->'server_assertions','[]'::jsonb);
  v_hard_fails:=coalesce(p_trust_validation->'server_hard_fails','[]'::jsonb);
  if jsonb_typeof(v_assertions)<>'array' or jsonb_typeof(v_hard_fails)<>'array' then
    if v_block_code is null then v_block_code:='JUDGE_EVIDENCE_ARRAYS_INVALID'; v_block_details:='{}'::jsonb; end if;
  end if;

  if v_block_code is null then
    for v_fail_item in select jsonb_array_elements_text(v_fail_if_norm) loop
      if exists(select 1 from jsonb_array_elements_text(v_hard_fails) hf where hf=v_fail_item) then v_triggered_fail_items:=array_append(v_triggered_fail_items,v_fail_item); end if;
    end loop;
    if cardinality(v_triggered_fail_items)>0 then
      v_block_code:='JUDGE_FAIL_CONDITION_TRIGGERED';
      v_block_details:=jsonb_build_object('triggered_fail_items',to_jsonb(v_triggered_fail_items));
    else
      for v_pass_item in select jsonb_array_elements_text(v_pass_if_norm) loop
        if not exists(select 1 from jsonb_array_elements_text(v_assertions) pa where pa=v_pass_item) then v_missing_pass_items:=array_append(v_missing_pass_items,v_pass_item); end if;
      end loop;
      if cardinality(v_missing_pass_items)>0 then v_derived_result:=v_binding.return_result_value; else v_derived_result:=v_binding.clean_result_value; end if;
    end if;
  end if;

  if v_block_code is not null then v_derived_result:=v_binding.blocked_result_value; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_result_values_norm) rv where rv=v_derived_result) then return jsonb_build_object('outcome','BLOCKED','code','DERIVED_RESULT_NOT_ALLOWED_BY_JUDGE','derived_result',v_derived_result,'durable',false); end if;

  v_payload:=(p_evidence_payload - array['assertions_checked','hard_fails_checked','caller_assertions_ignored']::text[])
    || jsonb_build_object(
      'assertions_checked',v_assertions,
      'hard_fails_checked',v_hard_fails,
      'caller_assertions_ignored',true
    );
  if v_route_guard is not null then
    v_payload:=v_payload||jsonb_build_object('canonical_route_guard_receipt',v_route_guard);
  end if;
  for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;

  if v_derived_result=v_binding.blocked_result_value then
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','BLOCKED','code',v_block_code,'evidence_ref',p_evidence_ref,'details',v_block_details));
    v_payload:=v_payload||jsonb_build_object('blocking_findings',jsonb_build_array(v_block_code),'blocking_codes',jsonb_build_array(v_block_code),'return_to_worker_reasons','[]'::jsonb);
  elsif v_derived_result=v_binding.return_result_value then
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','RETURN','code','JUDGE_PASS_CONDITIONS_INCOMPLETE','evidence_ref',p_evidence_ref,'details',jsonb_build_object('missing_pass_items',to_jsonb(v_missing_pass_items))));
    v_payload:=v_payload||jsonb_build_object('blocking_findings','[]'::jsonb,'blocking_codes','[]'::jsonb,'return_to_worker_reasons',to_jsonb(v_missing_pass_items));
  else
    v_payload:=v_payload||jsonb_build_object('blocking_findings','[]'::jsonb,'blocking_codes','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb);
  end if;

  v_payload:=v_payload||jsonb_build_object('step_result',v_derived_result,'derived_result',v_derived_result,'derived_by_judge',v_binding.judge_code,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_derived_result,'missing_pass_items',to_jsonb(v_missing_pass_items),'triggered_fail_items',to_jsonb(v_triggered_fail_items),'attempt_history',v_attempt_history,'recorded_by_rpc',p_recorder_name,'core_recorder','lf_record_operation_step_core_v1','trust_validation',p_trust_validation);

  if v_existing_retryable then
    update public.lf_operation_execution_steps set status=v_derived_result,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Retry persisted transactionally by operation-neutral recorder core.' where execution_id=p_execution_id and step_order=v_step.step_order and step_id=p_step_id;
  else
    insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id)
    values(p_execution_id,v_step.step_order,p_step_id,v_derived_result,p_evidence_ref,v_payload,'Recorded transactionally by operation-neutral recorder core.',p_actor_execution_id);
  end if;

  if v_derived_result=v_binding.clean_result_value and p_close_on_report_output and p_step_id='report_output' then
    select count(*) into v_required_not_clean
    from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_order=s.step_order and b.step_id=s.step_id and b.status=p_binding_status
    where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and (not v_snapshot_applies or exists (
      select 1 from jsonb_array_elements_text(v_snapshot_steps) frozen(step_id)
      where frozen.step_id=s.step_id
    )) and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'OPERATION_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution set status='COMPLETED',completed_at=coalesce(completed_at,now()),manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),updated_by_execution_id=p_actor_execution_id,updated_at=now() where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;

  return jsonb_build_object('outcome',case when v_derived_result=v_binding.clean_result_value then 'STEP_RECORDED' when v_derived_result=v_binding.return_result_value then 'RETURN_TO_ROUTER' else 'BLOCKED' end,'replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_derived_result,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_derived_result,'next_gate',v_contract.next_if_pass,'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history),'code',v_block_code);
end;
$function$


-- Structural readback after function replacement, before any durable execution close.
DO $verify$
DECLARE v_def text;
BEGIN
 SELECT pg_get_functiondef('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure) INTO v_def;
 IF position('FROZEN_REQUIRED_STEPS_INVALID' in v_def)=0 OR position('v_snapshot_applies' in v_def)=0 OR position('not v_snapshot_applies or exists' in v_def)=0 THEN RAISE EXCEPTION 'RECORDER_FROZEN_GUARD_NOT_INSTALLED'; END IF;
 IF (SELECT count(*) FROM public.lf_operation_execution WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>24 THEN RAISE EXCEPTION 'RECORDER_UNEXPECTED_EXECUTION_MUTATION'; END IF;
END; $verify$;
COMMIT;
