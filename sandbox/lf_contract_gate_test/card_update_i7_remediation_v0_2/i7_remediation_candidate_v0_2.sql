-- LF_CARD_UPDATE_I7_REMEDIATION_V2
-- Repairs independent review findings IR-F01..IR-F07 without enabling provider writes.
-- Still candidate/read-only. No carrier dispatch or rollback mutation is authorized.

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
  v_input_evidence_sha256 text;
  v_input_trust_sha256 text;
begin
  if p_execution_id is null or btrim(p_execution_id)='' or p_step_id is null or btrim(p_step_id)=''
     or p_actor_execution_id is null or btrim(p_actor_execution_id)='' then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_OR_ACTOR_MISSING','durable',false);
  end if;
  if p_step_id='init_execution' then
    return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE','durable',false);
  end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false);
  end if;
  if p_trust_validation is null or jsonb_typeof(p_trust_validation) is distinct from 'object'
     or not (p_trust_validation ? 'valid')
     or jsonb_typeof(p_trust_validation->'valid') is distinct from 'boolean' then
    return jsonb_build_object('outcome','BLOCKED','code','TRUST_VALIDATION_INVALID','durable',false);
  end if;

  v_input_evidence_sha256:=encode(extensions.digest(p_evidence_payload::text,'sha256'),'hex');
  v_input_trust_sha256:=encode(extensions.digest(p_trust_validation::text,'sha256'),'hex');

  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found or v_execution.operation_code is distinct from p_expected_operation_code
     or v_execution.target_type is distinct from p_expected_target_type then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  if v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false);
  end if;

  select * into v_registry from public.lf_operation_registry where operation_code=v_execution.operation_code;
  if not found or v_registry.applies_to_asset_type is distinct from v_execution.target_type then
    return jsonb_build_object('outcome','BLOCKED','code','OPERATION_REGISTRY_TARGET_MISMATCH','durable',false);
  end if;

  select * into v_step from public.lf_operation_steps where operation_code=v_execution.operation_code and step_id=p_step_id and active is true;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;

  select count(*) into v_contract_count from public.lf_operation_step_contracts
  where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_contract_status;
  if v_contract_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_CONTRACT_NOT_EXACT','count',v_contract_count,'durable',false); end if;
  select * into v_contract from public.lf_operation_step_contracts
  where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_contract_status limit 1;

  select count(*) into v_binding_count from public.lf_operation_step_judge_bindings
  where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_binding_status;
  if v_binding_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_BINDING_NOT_EXACT','count',v_binding_count,'durable',false); end if;
  select * into v_binding from public.lf_operation_step_judge_bindings
  where operation_code=v_execution.operation_code and step_id=p_step_id and step_order=v_step.step_order and status=p_binding_status limit 1;

  select count(*) into v_judge_count from public.lf_operation_judges
  where operation_code=v_execution.operation_code and judge_code=v_binding.judge_code and status=p_judge_status;
  if v_judge_count<>1 then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_NOT_EXACT','count',v_judge_count,'durable',false); end if;
  select * into v_judge from public.lf_operation_judges
  where operation_code=v_execution.operation_code and judge_code=v_binding.judge_code and status=p_judge_status limit 1;

  select * into v_existing from public.lf_operation_execution_steps where execution_id=p_execution_id and step_order=v_step.step_order;
  if found and v_existing.step_id is distinct from p_step_id then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_ORDER_ALREADY_BOUND_TO_OTHER_STEP','durable',true);
  end if;
  if found then
    if v_existing.status=v_binding.clean_result_value
       and v_existing.evidence_ref is not distinct from p_evidence_ref
       and (v_existing.evidence_payload->>'input_evidence_sha256') is not distinct from v_input_evidence_sha256
       and (v_existing.evidence_payload->>'input_trust_sha256') is not distinct from v_input_trust_sha256
       and (p_trust_validation->'valid') is not distinct from 'true'::jsonb then
      return jsonb_build_object('outcome','STEP_RECORDED','replay',true,'step_id',p_step_id,'status',v_existing.status,
        'execution_status',v_execution.status,'input_evidence_sha256',v_input_evidence_sha256);
    end if;
    if v_existing.status in (v_binding.blocked_result_value,v_binding.return_result_value) then
      v_existing_retryable:=true;
      if jsonb_typeof(v_existing.evidence_payload->'attempt_history')='array' then v_attempt_history:=v_existing.evidence_payload->'attempt_history'; end if;
    else
      return jsonb_build_object('outcome','BLOCKED','code',
        case when v_existing.status=v_binding.clean_result_value then 'STEP_REPLAY_INPUT_MISMATCH' else 'STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE' end,
        'status',v_existing.status,'durable',true);
    end if;
  end if;

  select count(*) into v_prior_missing from public.lf_operation_steps s
  where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and coalesce(s.execution_order,s.step_order)<coalesce(v_step.execution_order,v_step.step_order)
    and not exists(select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id);

  select count(*) into v_prior_bad from public.lf_operation_steps s
  join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
  left join public.lf_operation_step_judge_bindings pb on pb.operation_code=s.operation_code and pb.step_order=s.step_order and pb.step_id=s.step_id and pb.status=p_binding_status
  where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
    and coalesce(s.execution_order,s.step_order)<coalesce(v_step.execution_order,v_step.step_order)
    and (pb.clean_result_value is null or es.status is distinct from pb.clean_result_value);

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
      if not (p_evidence_payload ? v_key) or p_evidence_payload->v_key is null or p_evidence_payload->v_key='null'::jsonb
         or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then
        v_missing_keys:=array_append(v_missing_keys,v_key);
      end if;
    end loop;
    if cardinality(v_missing_keys)>0 then
      v_block_code:='REQUIRED_EVIDENCE_MISSING';
      v_block_details:=jsonb_build_object('missing_keys',to_jsonb(v_missing_keys));
    end if;
  end if;

  if v_block_code is null and p_evidence_payload ? 'blocking_codes' then
    if jsonb_typeof(p_evidence_payload->'blocking_codes') is distinct from 'array' then v_block_code:='BLOCKING_CODES_INVALID';
    else
      v_blocking_codes:=p_evidence_payload->'blocking_codes';
      if jsonb_array_length(v_blocking_codes)>0 then
        v_block_code:=coalesce(v_contract.blocking_code,'STEP_BLOCKED');
        v_block_details:=jsonb_build_object('caller_blocking_codes',v_blocking_codes);
      end if;
    end if;
  end if;

  if jsonb_typeof(v_judge.result_values)='array' then v_result_values_norm:=v_judge.result_values;
  elsif jsonb_typeof(v_judge.result_values)='object' then
    select coalesce(jsonb_agg(value order by key),'[]'::jsonb) into v_result_values_norm from jsonb_each_text(v_judge.result_values) where value is not null and btrim(value)<>'';
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_RESULT_VALUES_SHAPE_INVALID','durable',false); end if;

  if jsonb_typeof(v_judge.pass_if)='array' then v_pass_if_norm:=v_judge.pass_if;
  elsif jsonb_typeof(v_judge.pass_if)='object' and jsonb_typeof(v_judge.pass_if->'pass_if')='array' then v_pass_if_norm:=v_judge.pass_if->'pass_if';
  elsif jsonb_typeof(v_judge.pass_if)='object' then
    select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_pass_if_norm from jsonb_each(v_judge.pass_if) where value='true'::jsonb;
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_PASS_IF_SHAPE_INVALID','durable',false); end if;

  if jsonb_typeof(v_judge.fail_if)='array' then v_fail_if_norm:=v_judge.fail_if;
  elsif jsonb_typeof(v_judge.fail_if)='object' and jsonb_typeof(v_judge.fail_if->'fail_if')='array' then v_fail_if_norm:=v_judge.fail_if->'fail_if';
  elsif jsonb_typeof(v_judge.fail_if)='object' then
    select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_fail_if_norm from jsonb_each(v_judge.fail_if) where value='true'::jsonb;
  else return jsonb_build_object('outcome','BLOCKED','code','JUDGE_FAIL_IF_SHAPE_INVALID','durable',false); end if;

  v_assertions:=coalesce(p_trust_validation->'server_assertions','[]'::jsonb);
  v_hard_fails:=coalesce(p_trust_validation->'server_hard_fails','[]'::jsonb);
  if jsonb_typeof(v_assertions) is distinct from 'array' or jsonb_typeof(v_hard_fails) is distinct from 'array' then
    if v_block_code is null then v_block_code:='SERVER_JUDGE_EVIDENCE_ARRAYS_INVALID'; v_block_details:='{}'::jsonb; end if;
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
  if not exists(select 1 from jsonb_array_elements_text(v_result_values_norm) rv where rv=v_derived_result) then
    return jsonb_build_object('outcome','BLOCKED','code','DERIVED_RESULT_NOT_ALLOWED_BY_JUDGE','derived_result',v_derived_result,'durable',false);
  end if;

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

  v_payload:=v_payload||jsonb_build_object(
    'step_result',v_derived_result,'derived_result',v_derived_result,'derived_by_judge',v_binding.judge_code,
    'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_derived_result,
    'missing_pass_items',to_jsonb(v_missing_pass_items),'triggered_fail_items',to_jsonb(v_triggered_fail_items),
    'attempt_history',v_attempt_history,'recorded_by_rpc',p_recorder_name,'core_recorder','lf_record_operation_step_core_v1',
    'trust_validation',p_trust_validation,'assertions_checked',v_assertions,'hard_fails_checked',v_hard_fails,
    'input_evidence_sha256',v_input_evidence_sha256,'input_trust_sha256',v_input_trust_sha256,'caller_assertions_ignored',true);

  if v_existing_retryable then
    update public.lf_operation_execution_steps set status=v_derived_result,evidence_ref=p_evidence_ref,evidence_payload=v_payload,
      notes='Retry persisted transactionally by operation-neutral recorder core v2 hardening.',updated_by_execution_id=p_actor_execution_id,updated_at=now()
    where execution_id=p_execution_id and step_order=v_step.step_order and step_id=p_step_id;
  else
    insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id)
    values(p_execution_id,v_step.step_order,p_step_id,v_derived_result,p_evidence_ref,v_payload,
      'Recorded transactionally by operation-neutral recorder core v2 hardening.',p_actor_execution_id);
  end if;

  if v_derived_result=v_binding.clean_result_value and p_close_on_report_output and p_step_id='report_output' then
    select count(*) into v_required_not_clean from public.lf_operation_steps s
    left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
    left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_order=s.step_order and b.step_id=s.step_id and b.status=p_binding_status
    where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
      and (es.step_id is null or b.clean_result_value is null or es.status is distinct from b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'OPERATION_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution set status='COMPLETED',completed_at=coalesce(completed_at,now()),
      manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),
      updated_by_execution_id=p_actor_execution_id,updated_at=now() where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;

  return jsonb_build_object('outcome',case when v_derived_result=v_binding.clean_result_value then 'STEP_RECORDED'
    when v_derived_result=v_binding.return_result_value then 'RETURN_TO_ROUTER' else 'BLOCKED' end,
    'replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,
    'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_derived_result,
    'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_derived_result,'next_gate',v_contract.next_if_pass,
    'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history),'code',v_block_code,
    'input_evidence_sha256',v_input_evidence_sha256);
end;
$function$;

create or replace function public.lf_validate_card_update_trust_v1(p_execution_id text,p_step_id text,p_evidence_payload jsonb)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare
  v_execution public.lf_operation_execution%rowtype; v_card public.lf_activos%rowtype; v_binding jsonb; v_trust jsonb;
  v_policy_version text; v_policy_sha text; v_policy_count integer:=0; v_parent_count integer:=0; v_parent_code text;
  v_parent_ref text; v_change_ref text; v_regression_ref text; v_expected_binding_ref text; v_expected_trust_ref text;
  v_trust_observed_at timestamptz; v_carrier_type text; v_expected_trust_source text; v_expected_currentness_token text;
  v_expected_anchor_or_path text; v_expected_guard text; v_expected_content_hash text;
begin
  if p_step_id is distinct from 'pre_write_execution_binding_gate' then return jsonb_build_object('valid',false,'code','CARD_TRUST_WRONG_STEP','details',jsonb_build_object('step_id',p_step_id)); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then return jsonb_build_object('valid',false,'code','CARD_TRUST_EVIDENCE_PAYLOAD_INVALID','details','{}'::jsonb); end if;
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then return jsonb_build_object('valid',false,'code','CARD_TRUST_EXECUTION_IDENTITY_INVALID','details','{}'::jsonb); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('valid',false,'code','CARD_TRUST_TARGET_NOT_FOUND','details',jsonb_build_object('target_code',v_execution.target_code)); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then return jsonb_build_object('valid',false,'code','CARD_TRUST_DURABLE_BINDING_MISSING','details','{}'::jsonb); end if;
  if (v_binding->>'binding_status') is distinct from 'CURRENT_AT_OBSERVATION' or coalesce((v_binding->>'carrier_authority')::boolean,true) is true or coalesce((v_binding->>'carrier_write_allowed')::boolean,true) is true then return jsonb_build_object('valid',false,'code','CARD_TRUST_DURABLE_BINDING_STATE_INVALID','details','{}'::jsonb); end if;
  if v_card.runtime_estado is distinct from 'PRODUCCION_CONTROLADA_READ_ONLY' or v_card.estado_operativo is distinct from 'READ_ONLY' or v_card.impacto_automatico is distinct from 'BLOQUEADO' then return jsonb_build_object('valid',false,'code','CARD_TRUST_SAFETY_CEILING_CHANGED','details',jsonb_build_object('runtime_estado',v_card.runtime_estado,'estado_operativo',v_card.estado_operativo,'impacto_automatico',v_card.impacto_automatico)); end if;
  v_carrier_type:=v_binding->>'carrier_type';
  if v_carrier_type='GOOGLE_DOC_EMBEDDED_BLOCK' then
    if coalesce((v_card.metadata->'storage_refs'->'google_drive'->>'operational_read_allowed')::boolean,true) is true then return jsonb_build_object('valid',false,'code','CARD_TRUST_GOOGLE_OPERATIONAL_READ_NOT_BLOCKED','details','{}'::jsonb); end if;
    v_expected_trust_source:='GOOGLE_DOCS_API_CONNECTOR_FRESH_READ'; v_expected_currentness_token:=v_binding->>'provider_revision_id'; v_expected_anchor_or_path:=v_binding->>'block_anchor'; v_expected_guard:='requiredRevisionId'; v_expected_content_hash:=v_binding->>'content_sha256';
    if nullif(v_binding->>'document_id','') is null or nullif(v_expected_currentness_token,'') is null or nullif(v_expected_anchor_or_path,'') is null or nullif(v_expected_content_hash,'') is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_GOOGLE_BINDING_FIELD_MISSING','details','{}'::jsonb); end if;
  elsif v_carrier_type='GITHUB_FILE' then
    v_expected_trust_source:='GITHUB_API_CONNECTOR_FRESH_READ'; v_expected_currentness_token:=v_binding->>'provider_blob_sha'; v_expected_anchor_or_path:=v_binding->>'path'; v_expected_guard:='EXPECTED_HEAD_AND_BLOB_SHA'; v_expected_content_hash:=v_binding->>'content_sha256';
    if nullif(v_binding->>'repository_full_name','') is null or nullif(v_binding->>'path','') is null or nullif(v_binding->>'provider_head_sha','') is null or nullif(v_binding->>'provider_blob_sha','') is null or nullif(v_binding->>'carrier_ref','') is null or nullif(v_expected_content_hash,'') is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_GITHUB_BINDING_FIELD_MISSING','details','{}'::jsonb); end if;
  else return jsonb_build_object('valid',false,'code','CARD_TRUST_CARRIER_NOT_SUPPORTED_V2','details',jsonb_build_object('carrier_type',v_carrier_type)); end if;
  select count(*) into v_policy_count from public.v_lf_operation_policy_snapshot where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_count<>1 then return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_NOT_EXACT','details',jsonb_build_object('count',v_policy_count)); end if;
  select policy_version,policy_sha into v_policy_version,v_policy_sha from public.v_lf_operation_policy_snapshot where operation_code='ACTUALIZACION_CARD_LF' and policy_code='POL-LF-SOURCE-RESOLUTION';
  if v_policy_version is distinct from 'v1.4-transversal-supabase-authority-visual-support' or v_policy_sha is distinct from '5fab0c7fec2d7cc88fa13a54db8dfd15c8b7e008b381364f69c707a3675aae46' then return jsonb_build_object('valid',false,'code','CARD_TRUST_SOURCE_POLICY_STALE','details',jsonb_build_object('version',v_policy_version,'sha',v_policy_sha)); end if;
  if (v_binding->>'source_policy_version') is distinct from v_policy_version or (v_binding->>'source_policy_sha') is distinct from v_policy_sha then return jsonb_build_object('valid',false,'code','CARD_TRUST_BINDING_POLICY_STALE','details','{}'::jsonb); end if;
  v_trust:=v_execution.manifest->'connector_trust_context';
  if v_trust is null or jsonb_typeof(v_trust) is distinct from 'object' then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_MISSING','details','{}'::jsonb); end if;
  if (v_trust->>'source') is distinct from v_expected_trust_source then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_SOURCE_INVALID','details',jsonb_build_object('source',v_trust->>'source','expected',v_expected_trust_source)); end if;
  if nullif(v_trust->>'observed_at','') is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_OBSERVED_AT_MISSING','details','{}'::jsonb); end if;
  begin v_trust_observed_at:=(v_trust->>'observed_at')::timestamptz; exception when others then return jsonb_build_object('valid',false,'code','CARD_TRUST_OBSERVED_AT_INVALID','details','{}'::jsonb); end;
  if v_trust_observed_at<v_execution.started_at then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_PREDATES_EXECUTION','details',jsonb_build_object('observed_at',v_trust_observed_at,'started_at',v_execution.started_at)); end if;
  if v_trust_observed_at>clock_timestamp()+interval '60 seconds' or clock_timestamp()-v_trust_observed_at>interval '5 minutes' then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_OUTSIDE_FRESHNESS_WINDOW','details',jsonb_build_object('observed_at',v_trust_observed_at,'max_age_seconds',300)); end if;
  if (v_trust->>'carrier_type') is distinct from v_carrier_type or (v_trust->>'carrier_ref') is distinct from (v_binding->>'carrier_ref') or (v_trust->>'content_sha256') is distinct from v_expected_content_hash or (v_trust->>'block_anchor_or_path') is distinct from v_expected_anchor_or_path or (v_trust->>'provider_write_guard') is distinct from v_expected_guard then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_BINDING_MISMATCH','details','{}'::jsonb); end if;
  if v_carrier_type='GOOGLE_DOC_EMBEDDED_BLOCK' then
    if (v_trust->>'document_id') is distinct from (v_binding->>'document_id') or (v_trust->>'provider_revision_id') is distinct from (v_binding->>'provider_revision_id') then return jsonb_build_object('valid',false,'code','CARD_TRUST_GOOGLE_CURRENTNESS_MISMATCH','details','{}'::jsonb); end if;
  else
    if (v_trust->>'repository_full_name') is distinct from (v_binding->>'repository_full_name') or (v_trust->>'path') is distinct from (v_binding->>'path') or (v_trust->>'provider_head_sha') is distinct from (v_binding->>'provider_head_sha') or (v_trust->>'provider_blob_sha') is distinct from (v_binding->>'provider_blob_sha') then return jsonb_build_object('valid',false,'code','CARD_TRUST_GITHUB_CURRENTNESS_MISMATCH','details','{}'::jsonb); end if;
  end if;
  select count(*),min(relacionado_codigo) into v_parent_count,v_parent_code from public.lf_activo_relaciones where codigo_activo=v_execution.target_code and relacion_tipo='HIJO_DE';
  if v_parent_count<>1 or v_parent_code is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_PARENT_RELATION_NOT_EXACT','details',jsonb_build_object('count',v_parent_count)); end if;
  v_parent_ref:='supabase://public/lf_activos/'||v_parent_code;
  select evidence_ref into v_change_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='change_scope';
  select evidence_ref into v_regression_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='regression_plan';
  if v_change_ref is null or v_regression_ref is null then return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REFS_MISSING','details','{}'::jsonb); end if;
  if coalesce((select evidence_payload->>'parent_source_ref' from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='parent_source_read'),'') is distinct from v_parent_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_PARENT_SOURCE_MISMATCH','details',jsonb_build_object('expected',v_parent_ref)); end if;
  v_expected_binding_ref:='supabase://public/lf_activos/'||v_execution.target_code||'#metadata.carrier_binding_v1'; v_expected_trust_ref:=p_execution_id||'/manifest/connector_trust_context';
  if (p_evidence_payload->>'execution_id') is distinct from p_execution_id or (p_evidence_payload->>'card_code') is distinct from v_execution.target_code then return jsonb_build_object('valid',false,'code','CARD_TRUST_PAYLOAD_IDENTITY_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'current_source_policy_code') is distinct from 'POL-LF-SOURCE-RESOLUTION' or (p_evidence_payload->>'current_source_policy_version') is distinct from v_policy_version or (p_evidence_payload->>'current_source_policy_sha') is distinct from v_policy_sha then return jsonb_build_object('valid',false,'code','CARD_TRUST_PAYLOAD_POLICY_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'supabase_authority_ref') is distinct from (v_binding->>'operational_authority_ref') or (p_evidence_payload->>'carrier_binding_ref') is distinct from v_expected_binding_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_AUTHORITY_OR_BINDING_REF_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'carrier_type') is distinct from v_carrier_type or (p_evidence_payload->>'carrier_ref') is distinct from (v_binding->>'carrier_ref') then return jsonb_build_object('valid',false,'code','CARD_TRUST_CARRIER_ROUTE_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'fresh_provider_revision_or_blob_sha') is distinct from v_expected_currentness_token then return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_CURRENTNESS_TOKEN_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'content_sha256') is distinct from v_expected_content_hash then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTENT_HASH_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'block_anchor_or_path') is distinct from v_expected_anchor_or_path then return jsonb_build_object('valid',false,'code','CARD_TRUST_ANCHOR_OR_PATH_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'trusted_context_ref') is distinct from v_expected_trust_ref or (v_trust->>'trusted_context_ref') is distinct from v_expected_trust_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_CONTEXT_REF_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'change_scope_ref') is distinct from v_change_ref or (p_evidence_payload->>'regression_plan_ref') is distinct from v_regression_ref then return jsonb_build_object('valid',false,'code','CARD_TRUST_PLANNING_REF_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->>'provider_write_guard') is distinct from v_expected_guard or (v_binding->>'provider_write_guard') is distinct from v_expected_guard then return jsonb_build_object('valid',false,'code','CARD_TRUST_PROVIDER_GUARD_MISMATCH','details','{}'::jsonb); end if;
  if (p_evidence_payload->'pre_write_gate_passed') is distinct from 'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_TRUST_PREWRITE_PASS_FLAG_MISSING','details','{}'::jsonb); end if;
  return jsonb_build_object('valid',true,'code','CARD_TRUST_EXACT','server_assertions',jsonb_build_array('required evidence present','prior required steps clean','Supabase operational authority preserved','external carrier not used as authority'),'server_hard_fails','[]'::jsonb,
    'details',jsonb_build_object('card_code',v_execution.target_code,'parent_source_ref',v_parent_ref,'carrier_type',v_carrier_type,'currentness_token',v_expected_currentness_token,'content_sha256',v_expected_content_hash,'source_policy_sha',v_policy_sha,'freshness_window_seconds',300,'provider_guard',v_expected_guard));
end;
$function$;

create or replace function public.lf_validate_card_update_step_evidence_v2(p_execution_id text,p_step_id text,p_evidence_payload jsonb)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare
  v_execution public.lf_operation_execution%rowtype; v_card public.lf_activos%rowtype; v_binding jsonb; v_trust jsonb;
  v_parent_count integer; v_parent_code text; v_parent_ref text; v_expected_binding_ref text;
  v_assertions jsonb:=jsonb_build_array('required evidence present','prior required steps clean','Supabase operational authority preserved','external carrier not used as authority');
  v_hash text; v_state text;
begin
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then return jsonb_build_object('valid',false,'code','CARD_STEP_EVIDENCE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then return jsonb_build_object('valid',false,'code','CARD_STEP_EXECUTION_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('valid',false,'code','CARD_STEP_TARGET_NOT_FOUND','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1'; v_trust:=v_execution.manifest->'connector_trust_context';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then return jsonb_build_object('valid',false,'code','CARD_STEP_BINDING_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  if (v_binding->>'carrier_authority')::boolean is distinct from false or (v_binding->>'carrier_write_allowed')::boolean is distinct from false or v_card.runtime_estado is distinct from 'PRODUCCION_CONTROLADA_READ_ONLY' or v_card.estado_operativo is distinct from 'READ_ONLY' or v_card.impacto_automatico is distinct from 'BLOQUEADO' then return jsonb_build_object('valid',false,'code','CARD_STEP_AUTHORITY_CEILING_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested')); end if;
  select count(*),min(relacionado_codigo) into v_parent_count,v_parent_code from public.lf_activo_relaciones where codigo_activo=v_execution.target_code and relacion_tipo='HIJO_DE';
  if v_parent_count<>1 or v_parent_code is null then return jsonb_build_object('valid',false,'code','CARD_STEP_PARENT_NOT_EXACT','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('identity or parent source changed')); end if;
  v_parent_ref:='supabase://public/lf_activos/'||v_parent_code; v_expected_binding_ref:='supabase://public/lf_activos/'||v_execution.target_code||'#metadata.carrier_binding_v1';
  if p_step_id='router' then
    if (p_evidence_payload->>'action') is distinct from 'CARD_UPDATE' or (p_evidence_payload->>'router_state') is distinct from 'CANDIDATO_READ_ONLY_NO_WRITE' or nullif(p_evidence_payload->>'router_read','') is null then return jsonb_build_object('valid',false,'code','CARD_STEP_ROUTER_EVIDENCE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='card_resolve' then
    if (p_evidence_payload->>'card_code') is distinct from v_execution.target_code or nullif(p_evidence_payload->>'card_id','') is null or (p_evidence_payload->>'card_id')::bigint is distinct from v_card.id or p_evidence_payload->'exact_card_resolved' is distinct from 'true'::jsonb or p_evidence_payload->'active_before' is distinct from 'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_STEP_CARD_RESOLVE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='carrier_resolve' then
    if (p_evidence_payload->>'carrier_type') is distinct from (v_binding->>'carrier_type') or (p_evidence_payload->>'carrier_ref') is distinct from (v_binding->>'carrier_ref') or (p_evidence_payload->>'parent_asset_code') is distinct from v_parent_code or (p_evidence_payload->>'parent_source_ref') is distinct from v_parent_ref or (p_evidence_payload->>'supabase_authority_ref') is distinct from (v_binding->>'operational_authority_ref') or (p_evidence_payload->>'carrier_binding_ref') is distinct from v_expected_binding_ref or (p_evidence_payload->>'block_anchor') is distinct from case when (v_binding->>'carrier_type')='GITHUB_FILE' then v_binding->>'path' else v_binding->>'block_anchor' end then return jsonb_build_object('valid',false,'code','CARD_STEP_CARRIER_RESOLVE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('authority inferred from carrier')); end if;
  elsif p_step_id='parent_source_read' then
    if v_trust is null or jsonb_typeof(v_trust) is distinct from 'object' then return jsonb_build_object('valid',false,'code','CARD_STEP_PARENT_TRUST_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
    if (p_evidence_payload->>'parent_source_ref') is distinct from v_parent_ref or p_evidence_payload->'block_anchor_found' is distinct from 'true'::jsonb or p_evidence_payload->'transport_integrity_only' is distinct from 'true'::jsonb or (p_evidence_payload->>'source_currentness') is distinct from 'FRESH_CONNECTOR_CURRENT' or (p_evidence_payload->>'carrier_revision') is distinct from case when (v_binding->>'carrier_type')='GITHUB_FILE' then v_binding->>'provider_blob_sha' else v_binding->>'provider_revision_id' end then return jsonb_build_object('valid',false,'code','CARD_STEP_PARENT_SOURCE_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='baseline_read' then
    if nullif(p_evidence_payload->>'baseline_canonical_content','') is null or nullif(p_evidence_payload->>'baseline_content_sha256','') is null or nullif(p_evidence_payload->>'baseline_block_excerpt_hash','') is null then return jsonb_build_object('valid',false,'code','CARD_STEP_BASELINE_REVERSIBLE_CONTENT_MISSING','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
    v_hash:=encode(extensions.digest(p_evidence_payload->>'baseline_canonical_content','sha256'),'hex');
    v_state:=v_card.estado_documental||'/'||v_card.estado_operativo||'/'||v_card.runtime_estado||'/'||v_card.impacto_automatico;
    if (p_evidence_payload->>'baseline_identity') is distinct from v_execution.target_code or (p_evidence_payload->>'baseline_card_state') is distinct from v_state or (p_evidence_payload->>'baseline_carrier_type') is distinct from (v_binding->>'carrier_type') or (p_evidence_payload->>'baseline_carrier_ref') is distinct from (v_binding->>'carrier_ref') or (p_evidence_payload->>'baseline_block_anchor_or_path') is distinct from case when (v_binding->>'carrier_type')='GITHUB_FILE' then v_binding->>'path' else v_binding->>'block_anchor' end or (p_evidence_payload->>'baseline_carrier_revision') is distinct from case when (v_binding->>'carrier_type')='GITHUB_FILE' then v_binding->>'provider_blob_sha' else v_binding->>'provider_revision_id' end or (p_evidence_payload->>'baseline_block_excerpt_hash') is distinct from (v_binding->>'content_sha256') or (p_evidence_payload->>'baseline_content_sha256') is distinct from v_hash or (p_evidence_payload->>'baseline_content_sha256') is distinct from (v_binding->>'content_sha256') or (p_evidence_payload->>'baseline_content_chars')::integer is distinct from length(p_evidence_payload->>'baseline_canonical_content') then return jsonb_build_object('valid',false,'code','CARD_STEP_BASELINE_CONTENT_OR_IDENTITY_MISMATCH','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('identity or parent source changed')); end if;
  elsif p_step_id='change_scope' then
    if nullif(p_evidence_payload->>'defect','') is null or nullif(p_evidence_payload->>'root_cause','') is null or jsonb_typeof(p_evidence_payload->'minimal_patch_scope') is distinct from 'array' or jsonb_array_length(p_evidence_payload->'minimal_patch_scope')=0 or jsonb_typeof(p_evidence_payload->'preserved_constraints') is distinct from 'array' or jsonb_array_length(p_evidence_payload->'preserved_constraints')=0 or p_evidence_payload->'authority_boundaries_preserved' is distinct from 'true'::jsonb or p_evidence_payload->'carrier_route_preserved' is distinct from 'true'::jsonb then return jsonb_build_object('valid',false,'code','CARD_STEP_CHANGE_SCOPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='regression_plan' then
    if jsonb_typeof(p_evidence_payload->'positive_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'negative_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'adversarial_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'stale_revision_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'wrong_carrier_cases') is distinct from 'array' or jsonb_typeof(p_evidence_payload->'holdout') is distinct from 'array' or jsonb_array_length(p_evidence_payload->'positive_cases')=0 or jsonb_array_length(p_evidence_payload->'negative_cases')=0 or jsonb_array_length(p_evidence_payload->'adversarial_cases')=0 or jsonb_array_length(p_evidence_payload->'stale_revision_cases')=0 or jsonb_array_length(p_evidence_payload->'wrong_carrier_cases')=0 or jsonb_array_length(p_evidence_payload->'holdout')=0 then return jsonb_build_object('valid',false,'code','CARD_STEP_REGRESSION_PLAN_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  elsif p_step_id='pre_write_execution_binding_gate' then return public.lf_validate_card_update_trust_v1(p_execution_id,p_step_id,p_evidence_payload);
  else return jsonb_build_object('valid',false,'code','CARD_STEP_VALIDATOR_STEP_NOT_SUPPORTED','details',jsonb_build_object('step_id',p_step_id),'server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb); end if;
  return jsonb_build_object('valid',true,'code','CARD_STEP_SERVER_VALIDATED','server_assertions',v_assertions,'server_hard_fails','[]'::jsonb,
    'details',jsonb_build_object('step_id',p_step_id,'card_code',v_execution.target_code,'carrier_type',v_binding->>'carrier_type','authority','SUPABASE'));
exception when invalid_text_representation or numeric_value_out_of_range then
  return jsonb_build_object('valid',false,'code','CARD_STEP_EVIDENCE_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
end;
$function$;

create or replace function public.lf_record_card_operation_step_v1(p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,p_actor_execution_id text)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare v_step_order integer; v_server_validation jsonb;
begin
  select step_order into v_step_order from public.lf_operation_steps where operation_code='ACTUALIZACION_CARD_LF' and step_id=p_step_id and active is true;
  if v_step_order is null then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;
  if v_step_order>80 then
    v_server_validation:=jsonb_build_object('valid',false,'code','CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I7','details',jsonb_build_object('step_order',v_step_order,'ceiling_step_order',80),'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested'));
  else v_server_validation:=public.lf_validate_card_update_step_evidence_v2(p_execution_id,p_step_id,p_evidence_payload); end if;
  return public.lf_record_operation_step_core_v1(p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'ACTUALIZACION_CARD_LF','CARD','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY',v_server_validation,true,'lf_record_card_operation_step_v1');
end;
$function$;

create or replace function public.lf_prepare_card_carrier_write_intent_v1(p_execution_id text)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare v_execution public.lf_operation_execution%rowtype; v_card public.lf_activos%rowtype; v_binding jsonb; v_trust jsonb;
  v_step80 public.lf_operation_execution_steps%rowtype; v_clean_result text; v_guard jsonb; v_intent jsonb; v_hash text;
begin
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' or v_execution.status is distinct from 'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','I5_EXECUTION_IDENTITY_OR_STATUS_INVALID'); end if;
  select * into v_step80 from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='pre_write_execution_binding_gate' and step_order=80;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_STEP80_MISSING'); end if;
  select clean_result_value into v_clean_result from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_CARD_LF' and step_id='pre_write_execution_binding_gate' and step_order=80 and status='CANDIDATO_READ_ONLY';
  if v_clean_result is null or v_step80.status is distinct from v_clean_result then return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_STEP80_NOT_CLEAN','status',v_step80.status); end if;
  if (v_step80.evidence_payload->'trust_validation'->>'valid') is distinct from 'true' or (v_step80.evidence_payload->'trust_validation'->>'code') is distinct from 'CARD_TRUST_EXACT' then return jsonb_build_object('outcome','BLOCKED','code','I5_PREWRITE_TRUST_NOT_EXACT'); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','I5_CARD_TARGET_NOT_FOUND'); end if;
  if v_card.runtime_estado is distinct from 'PRODUCCION_CONTROLADA_READ_ONLY' or v_card.estado_operativo is distinct from 'READ_ONLY' or v_card.impacto_automatico is distinct from 'BLOQUEADO' then return jsonb_build_object('outcome','BLOCKED','code','I5_CARD_SAFETY_CEILING_CHANGED'); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1'; v_trust:=v_execution.manifest->'connector_trust_context';
  if v_binding is null or jsonb_typeof(v_binding) is distinct from 'object' then return jsonb_build_object('outcome','BLOCKED','code','I5_DURABLE_BINDING_MISSING'); end if;
  if (v_binding->>'binding_status') is distinct from 'CURRENT_AT_OBSERVATION' or coalesce((v_binding->>'carrier_authority')::boolean,true) is true or coalesce((v_binding->>'carrier_write_allowed')::boolean,true) is true then return jsonb_build_object('outcome','BLOCKED','code','I5_DURABLE_BINDING_STATE_INVALID'); end if;
  if (v_binding->>'carrier_type')='GOOGLE_DOC_EMBEDDED_BLOCK' and coalesce((v_card.metadata->'storage_refs'->'google_drive'->>'operational_read_allowed')::boolean,true) is true then return jsonb_build_object('outcome','BLOCKED','code','I5_GOOGLE_OPERATIONAL_READ_NOT_BLOCKED'); end if;
  v_guard:=public.lf_validate_carrier_write_guard_shape_v1(v_binding->>'carrier_type',v_binding,v_trust);
  if (v_guard->>'valid') is distinct from 'true' then return jsonb_build_object('outcome','BLOCKED','code',coalesce(v_guard->>'code','I5_CARRIER_GUARD_INVALID'),'guard',v_guard); end if;
  v_intent:=jsonb_build_object('intent_schema','LF_CARD_CARRIER_WRITE_INTENT_V1','execution_id',p_execution_id,'operation_code','ACTUALIZACION_CARD_LF','card_code',v_execution.target_code,
    'supabase_authority_ref',v_binding->>'operational_authority_ref','carrier_type',v_binding->>'carrier_type','carrier_ref',v_binding->>'carrier_ref','write_route',v_guard->>'write_route',
    'provider_guard_kind',v_guard->>'provider_guard_kind','provider_precondition',v_guard->'provider_precondition','bounded_target',v_guard->'bounded_target',
    'change_scope_ref',(select evidence_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='change_scope'),
    'regression_plan_ref',(select evidence_ref from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='regression_plan'),
    'source_policy_sha',v_binding->>'source_policy_sha','provider_call_authorized',false,'candidate_only',true,'carrier_authority',false,
    'generated_from','SUPABASE_EXECUTION_PLUS_DURABLE_BINDING_PLUS_BOUNDED_FRESH_TRUST_CONTEXT');
  v_hash:=encode(extensions.digest(v_intent::text,'sha256'),'hex');
  return v_intent||jsonb_build_object('intent_sha256',v_hash,'outcome','INTENT_PREPARED_NO_WRITE');
end;
$function$;

create or replace function public.lf_prepare_card_rollback_intent_v1(p_execution_id text)
returns jsonb language plpgsql security invoker set search_path to 'public' as $function$
declare v_execution public.lf_operation_execution%rowtype; v_card public.lf_activos%rowtype; v_binding jsonb;
  v_baseline public.lf_operation_execution_steps%rowtype; v_readback public.lf_operation_execution_steps%rowtype;
  v_current_revision text; v_intent jsonb; v_hash text;
begin
  select * into v_execution from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF' or v_execution.target_type is distinct from 'CARD' then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_EXECUTION_IDENTITY_INVALID'); end if;
  select * into v_card from public.lf_activos where codigo_activo=v_execution.target_code and tipo_activo='CARD' and archived_at is null;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_CARD_NOT_FOUND'); end if;
  v_binding:=v_card.metadata->'carrier_binding_v1';
  if (v_binding->>'carrier_type') is distinct from 'GOOGLE_DOC_EMBEDDED_BLOCK' then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_PROVIDER_NOT_IMPLEMENTED'); end if;
  select * into v_baseline from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='baseline_read' and step_order=50;
  if not found or v_baseline.status is distinct from 'STEP_PASS_WITH_EVIDENCE' or nullif(v_baseline.evidence_payload->>'baseline_canonical_content','') is null or nullif(v_baseline.evidence_payload->>'baseline_content_sha256','') is null then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_REVERSIBLE_BASELINE_NOT_AVAILABLE'); end if;
  select * into v_readback from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='carrier_readback' and step_order=100;
  if not found or v_readback.status is distinct from 'STEP_PASS_WITH_EVIDENCE' then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_POST_WRITE_READBACK_NOT_AVAILABLE'); end if;
  v_current_revision:=v_readback.evidence_payload->>'readback_carrier_revision';
  if nullif(v_current_revision,'') is null then return jsonb_build_object('outcome','BLOCKED','code','ROLLBACK_CURRENT_REVISION_MISSING'); end if;
  v_intent:=jsonb_build_object('intent_schema','LF_CARD_ROLLBACK_INTENT_V1','execution_id',p_execution_id,'card_code',v_execution.target_code,
    'carrier_type','GOOGLE_DOC_EMBEDDED_BLOCK','carrier_ref',v_binding->>'carrier_ref','provider_guard_kind','requiredRevisionId',
    'provider_precondition',jsonb_build_object('requiredRevisionId',v_current_revision),
    'bounded_target',jsonb_build_object('document_id',v_binding->>'document_id','tab_id',v_binding->>'tab_id','block_anchor',v_binding->>'block_anchor',
      'anchor_start_index',v_binding->>'anchor_start_index','last_bound_paragraph_end_index',v_binding->>'last_bound_paragraph_end_index'),
    'restore_content',v_baseline.evidence_payload->>'baseline_canonical_content','restore_content_sha256',v_baseline.evidence_payload->>'baseline_content_sha256',
    'baseline_evidence_ref',v_baseline.evidence_ref,'post_write_readback_ref',v_readback.evidence_ref,'provider_call_authorized',false,'rollback_write_executed',false,
    'requires_fresh_provider_revision_match',true);
  v_hash:=encode(extensions.digest(v_intent::text,'sha256'),'hex');
  return v_intent||jsonb_build_object('intent_sha256',v_hash,'outcome','ROLLBACK_INTENT_PREPARED_NO_WRITE','authorization_ceiling','NO_PROVIDER_CALL');
end;
$function$;

update public.lf_operation_step_judge_bindings
set required_evidence_keys='["baseline_card_state","baseline_carrier_revision","baseline_block_excerpt_hash","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_carrier_type","baseline_carrier_ref","baseline_block_anchor_or_path"]'::jsonb,
  updated_by_execution_id='EXEC-CARD-UPDATE-I7-REMEDIATION-20260913-001',updated_at=now()
where operation_code='ACTUALIZACION_CARD_LF' and step_id='baseline_read' and step_order=50 and status='CANDIDATO_READ_ONLY';

update public.lf_operation_step_contracts
set output_payload='["baseline_card_state","baseline_carrier_revision","baseline_block_excerpt_hash","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_carrier_type","baseline_carrier_ref","baseline_block_anchor_or_path"]'::jsonb,
  required_evidence_keys='["baseline_card_state","baseline_carrier_revision","baseline_block_excerpt_hash","baseline_identity","baseline_canonical_content","baseline_content_chars","baseline_content_sha256","baseline_carrier_type","baseline_carrier_ref","baseline_block_anchor_or_path"]'::jsonb,
  notes=coalesce(notes,'')||' I7 hardening: reversible baseline content + independently recomputed SHA are mandatory before pre-write.',
  updated_by_execution_id='EXEC-CARD-UPDATE-I7-REMEDIATION-20260913-001',updated_at=now()
where operation_code='ACTUALIZACION_CARD_LF' and step_id='baseline_read' and step_order=50 and status='CANDIDATO_READ_ONLY';

revoke execute on function public.lf_validate_card_update_step_evidence_v2(text,text,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_prepare_card_rollback_intent_v1(text) from public,anon,authenticated;
grant execute on function public.lf_validate_card_update_step_evidence_v2(text,text,jsonb) to service_role;
grant execute on function public.lf_prepare_card_rollback_intent_v1(text) to service_role;
