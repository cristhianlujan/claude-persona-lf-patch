-- LF_CARD_UPDATE_I4_OPERATION_NEUTRAL_RECORDER_V1
-- Candidate-only Card Update recorder built on an operation-neutral core.
-- Does not modify the production Profile recorder or the global enforcement trigger.
-- Card wrapper is intentionally capped at pre_write_execution_binding_gate (step 80); write phase remains unauthorized until I5.

create or replace function public.lf_record_operation_step_core_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text,
  p_expected_operation_code text,
  p_expected_target_type text,
  p_contract_status text,
  p_binding_status text,
  p_judge_status text,
  p_trust_validation jsonb,
  p_close_on_report_output boolean,
  p_recorder_name text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
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
begin
  if p_execution_id is null or btrim(p_execution_id)='' or p_step_id is null or btrim(p_step_id)='' or p_actor_execution_id is null or btrim(p_actor_execution_id)='' then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_OR_ACTOR_MISSING','durable',false);
  end if;
  if p_step_id='init_execution' then return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE','durable',false); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false); end if;
  if p_trust_validation is null or jsonb_typeof(p_trust_validation)<>'object' then return jsonb_build_object('outcome','BLOCKED','code','TRUST_VALIDATION_INVALID','durable',false); end if;

  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found or v_execution.operation_code<>p_expected_operation_code or v_execution.target_type<>p_expected_target_type then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  if v_execution.status<>'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false); end if;

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
    if v_existing.status=v_binding.clean_result_value and v_existing.evidence_ref=p_evidence_ref and v_existing.evidence_payload @> p_evidence_payload and p_trust_validation->'valid'='true'::jsonb then
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
    and coalesce(s.execution_order,s.step_order)<coalesce(v_step.execution_order,v_step.step_order)
    and not exists(select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id);

  select count(*) into v_prior_bad
  from public.lf_operation_steps s
  join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings pb on pb.operation_code=s.operation_code and pb.step_order=s.step_order and pb.step_id=s.step_id and pb.status=p_binding_status
  where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and coalesce(s.execution_order,s.step_order)<coalesce(v_step.execution_order,v_step.step_order)
    and (pb.clean_result_value is null or es.status<>pb.clean_result_value);

  if v_prior_missing>0 or v_prior_bad>0 then
    v_block_code:='PRIOR_REQUIRED_STEP_NOT_CLEAN';
    v_block_details:=jsonb_build_object('prior_missing',v_prior_missing,'prior_bad',v_prior_bad);
  end if;

  if v_block_code is null and p_trust_validation->'valid'<>'true'::jsonb then
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

  v_assertions:=coalesce(p_evidence_payload->'assertions_checked','[]'::jsonb);
  v_hard_fails:=coalesce(p_evidence_payload->'hard_fails_checked','[]'::jsonb);
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

  v_payload:=p_evidence_payload;
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
    where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'OPERATION_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution set status='COMPLETED',completed_at=coalesce(completed_at,now()),manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),updated_by_execution_id=p_actor_execution_id,updated_at=now() where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;

  return jsonb_build_object('outcome',case when v_derived_result=v_binding.clean_result_value then 'STEP_RECORDED' when v_derived_result=v_binding.return_result_value then 'RETURN_TO_ROUTER' else 'BLOCKED' end,'replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_derived_result,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_derived_result,'next_gate',v_contract.next_if_pass,'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history),'code',v_block_code);
end;
$function$;

create or replace function public.lf_validate_card_update_trust_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_card public.lf_activos%rowtype;
  v_binding jsonb;
  v_trust jsonb;
  v_policy_version text;
  v_policy_sha text;
  v_policy_count integer := 0;
  v_parent_count integer := 0;
  v_parent_code text;
  v_parent_ref text;
  v_change_ref text;
  v_regression_ref text;
  v_expected_binding_ref text;
  v_expected_trust_ref text;
  v_trust_observed_at timestamptz;
begin
  if p_step_id<>'pre_write_execution_binding_gate' then return jsonb_build_object('valid',true,'code','TRUST_GATE_NOT_APPLICABLE','details',jsonb_build_object('step_id',p_step_id)); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then return jsonb_build_object('valid',false,'code','CARD_TRUST_EVIDENCE_PAYLOAD_INVALID','details','{}'::jsonb); end if;

  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code<>'ACTUALIZACION_CARD_LF' or v_execution.target_type<>'CARD' or v_execution.status<>'IN_PROGRESS' then return jsonb_build_object('valid',false,'code','CARD_TRUST_EXECUTION_IDENTITY_INVALID','details','{}'::jsonb); end if;

  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('valid',false,'code','CARD_TRUST_TARGET_NOT_FOUND','details',jsonb_build_object('target_code',v_execution.target_code)); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if jsonb_typeof(v_binding)<>'object' then return jsonb_build_object('valid',false,'code','CARD_TRUST_DURABLE_BINDING_MISSING','details','{}'::jsonb); end if;
  if coalesce(v_binding->>'binding_status','')<>'CURRENT_AT_OBSERVATION' or coalesce((v_binding->>'carrier_authority')::boolean,true) is true or coalesce((v_binding->>'carrier_write_allowed')::boolean,true) is true then return jsonb_build_object('valid',false,'code','CARD_TRUST_DURABLE_BINDING_STATE_INVALID','details','{}'::jsonb); end if;
  if coalesce(v_binding->>'carrier_type','')<>'GOOGLE_DOC_EMBEDDED_BLOCK' then return jsonb_build_object('valid',false,'code','CARD_TRUST_CARRIER_NOT_SUPPORTED_I4','details',jsonb_build_object('carrier_type',v_binding->>'carrier_type')); end if;

  select count(*) into v_policy_count from public.v_lf_operation_policy_snapshot where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_count<>1 then return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_NOT_EXACT','details',jsonb_build_object('count',v_policy_count)); end if;
  select policy_version,policy_sha into v_policy_version,v_policy_sha from public.v_lf_operation_policy_snapshot where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_version<>'v1.4-transversal-supabase-authority-visual-support' or v_policy_sha<>'5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46' then return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_STALE','details',jsonb_build_object('version',v_policy_version,'sha',v_policy_sha)); end if;
  if v_binding->>'source_policy_version'<>v_policy_version or v_binding->>'source_policy_sha'<>v_policy_sha then return jsonb_build_object('valid',false,'code','CARD_TRUST_BINDING_POLICY_STALE','details','{}'::jsonb); end if;

  v_trust:=v_execution.manifest->'connector_trust_context';
  if jsonb_typeof(v_trust)<>'object' then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_MISSING','details','{}'::jsonb); end if;
  if v_trust->>'source'<>'GOOGLE_DOCS_API_CONNECTOR_FRESH_READ' then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_SOURCE_INVALID','details',jsonb_build_object('source',v_trust->>'source')); end if;
  begin v_trust_observed_at:=(v_trust->>'observed_at')::timestamptz; exception when others then return jsonb_build_object('valid',false,'code','CARD_TRUST_OBSERVED_AT_INVALID','details','{}'::jsonb); end;
  if v_trust_observed_at<v_execution.started_at then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_PREDATES_EXECUTION','details',jsonb_build_object('observed_at',v_trust_observed_at,'started_at',v_execution.started_at)); end if;

  select count(*),min(relacionado_codigo) into v_parent_count,v_parent_code from public.lf_activo_relaciones where codigo_activo=v_execution.target_code and relacion_tipo='HIJO_DE';
  if v_parent_count<>1 then return jsonb_build_object('valid',false,'code','CARD_TRUST_PARENT_RELATION_NOT_EXACT','details',jsonb_build_object('count',v_parent_count)); end if;
  v_parent_ref:='supabase://public/lf_activos/'||v_parent_code;
  select evidence_ref into v_change_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='change_scope';
  select evidence_ref into v_regression_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='regression_plan';
  if v_change_ref is null or v_regression_ref is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REFS_MISSING','details','{}'::jsonb); end if;
  if coalesce((select evidence_payload->>'parent_source_ref' from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='parent_source_read'),'')<>v_parent_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_PARENT_SOURCE_MISMATCH','details',jsonb_build_object('expected',v_parent_ref)); end if;

  v_expected_binding_ref:='supabase://public/lf_activos/'||v_execution.target_code||'#metadata.carrier_binding_v1';
  v_expected_trust_ref:=p_execution_id||'/manifest/connector_trust_context';

  if p_evidence_payload->>'execution_id'<>p_execution_id or p_evidence_payload->>'card_code'<>v_execution.target_code then return jsonb_build_object('valid',false,'code','CARD_TRUST_PAYLOAD_IDENTITY_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'current_source_policy_code'<>'POL-LF-SOURCE-RESOLUTION' or p_evidence_payload->>'current_source_policy_version'<>v_policy_version or p_evidence_payload->>'current_source_policy_sha'<>v_policy_sha then return jsonb_build_object('valid',false,'code','CARD_TRUST_PAYLOAD_POLICY_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'supabase_authority_ref'<>v_binding->>'operational_authority_ref' or p_evidence_payload->>'carrier_binding_ref'<>v_expected_binding_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_AUTHORITY_OR_BINDING_REF_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'carrier_type'<>v_binding->>'carrier_type' or p_evidence_payload->>'carrier_ref'<>v_binding->>'carrier_ref' then return jsonb_build_object('valid',false,'code','CARD_TRUST_CARRIER_ROUTE_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'fresh_provider_revision_or_blob_sha'<>v_binding->>'provider_revision_id' then return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_REVISION_BINDING_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'fresh_provider_revision_or_blob_sha'<>v_trust->>'provider_revision_id' then return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_REVISION_PAYLOAD_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'content_sha256'<>v_binding->>'content_sha256' or p_evidence_payload->>'content_sha256'<>v_trust->>'content_sha256' then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTENT_HASH_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'block_anchor_or_path'<>v_binding->>'block_anchor' or p_evidence_payload->>'block_anchor_or_path'<>v_trust->>'block_anchor_or_path' then return jsonb_build_object('valid',false,'code','CARD_TRUST_ANCHOR_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'trusted_context_ref'<>v_expected_trust_ref or v_trust->>'trusted_context_ref'<>v_expected_trust_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_REF_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->>'change_scope_ref'<>v_change_ref or p_evidence_payload->>'regression_plan_ref'<>v_regression_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REF_MISMATCH','details',jsonb_build_object('change_scope_expected',v_change_ref,'regression_plan_expected',v_regression_ref)); end if;
  if p_evidence_payload->>'provider_write_guard'<>'requiredRevisionId' or v_binding->>'provider_write_guard'<>'requiredRevisionId' or v_trust->>'provider_write_guard'<>'requiredRevisionId' then return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_GUARD_MISMATCH','details','{}'::jsonb); end if;
  if p_evidence_payload->'pre_write_gate_passed'<>'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_TRUST_PREWRITE_PASS_FLAG_MISSING','details','{}'::jsonb); end if;
  if v_card.runtime_estado<>'PRODUCCION_CONTROLADA_READ_ONLY' or v_card.impacto_automatico<>'BLOQUEADO' or coalesce((v_card.metadata->'storage_refs'->'google_drive'->>'operational_read_allowed')::boolean,true) is true then return jsonb_build_object('valid',false,'code','CARD_TRUST_SAFETY_CEILING_CHANGED','details',jsonb_build_object('runtime_estado',v_card.runtime_estado,'impacto_automatico',v_card.impacto_automatico)); end if;

  return jsonb_build_object('valid',true,'code','CARD_TRUST_EXACT','details',jsonb_build_object('card_code',v_execution.target_code,'parent_source_ref',v_parent_ref,'carrier_type',v_binding->>'carrier_type','provider_revision_id',v_binding->>'provider_revision_id','content_sha256',v_binding->>'content_sha256','source_policy_sha',v_policy_sha));
end;
$function$;

create or replace function public.lf_record_card_operation_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_step_order integer;
  v_trust jsonb;
begin
  select step_order into v_step_order from public.lf_operation_steps where operation_code='ACTUALIZACION_CARD_LF' and step_id=p_step_id and active is true;
  if v_step_order is null then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;
  if v_step_order>80 then
    v_trust:=jsonb_build_object('valid',false,'code','CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I4','details',jsonb_build_object('step_order',v_step_order,'ceiling_step_order',80));
  elsif p_step_id='pre_write_execution_binding_gate' then
    v_trust:=public.lf_validate_card_update_trust_v1(p_execution_id,p_step_id,p_evidence_payload);
  else
    v_trust:=jsonb_build_object('valid',true,'code','CARD_TRUST_GATE_NOT_APPLICABLE','details',jsonb_build_object('step_order',v_step_order));
  end if;

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'ACTUALIZACION_CARD_LF','CARD','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY',
    v_trust,true,'lf_record_card_operation_step_v1'
  );
end;
$function$;

revoke execute on function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) from public,anon,authenticated;
revoke execute on function public.lf_validate_card_update_trust_v1(text,text,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) to service_role;
grant execute on function public.lf_validate_card_update_trust_v1(text,text,jsonb) to service_role;
grant execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) to service_role;
