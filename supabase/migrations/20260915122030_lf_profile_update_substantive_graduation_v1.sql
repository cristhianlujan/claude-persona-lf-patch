-- LF_PROFILE_UPDATE_SUBSTANTIVE_GRADUATION_V1
-- Owner remediation for S25 updater acceptance canary (#800 / #805).
-- Ordinary UPDATE remains compatible, but explicit substantive failures may never be recorded clean.
-- GOLDEN_CAPABLE_V1 adds stricter graduation obligations; it grants no runtime/promotion/production authority.

create or replace function public.lf_profile_update_result_class_v1(p_value jsonb)
returns text
language plpgsql
immutable
set search_path to 'public'
as $function$
declare
  v_key text;
  v_value jsonb;
  v_class text;
  v_text text;
  v_saw_pass boolean := false;
begin
  if p_value is null or p_value = 'null'::jsonb then return 'UNPROVEN'; end if;
  case jsonb_typeof(p_value)
    when 'string' then
      v_text := upper(btrim(p_value #>> '{}'));
      if v_text = '' then return 'UNPROVEN'; end if;
      if v_text ~ '^(FAIL|FAILED|BLOCK|BLOCKED|ERROR|NOT_EXECUTED|NOT EXECUTED|DEFERRED|NOT_COVERED|NOT COVERED)' then return 'FAIL'; end if;
      if v_text ~ '^(PASS|SUCCESS|SUCCEEDED|VERIFIED)' or v_text ~ '(^|[^A-Z])(PASS|SUCCESS|SUCCEEDED|VERIFIED)([^A-Z]|$)' then return 'PASS'; end if;
      return 'UNPROVEN';
    when 'boolean' then
      if p_value = 'true'::jsonb then return 'PASS'; else return 'FAIL'; end if;
    when 'object' then
      for v_key, v_value in
        select key, value from jsonb_each(p_value)
        where lower(key) in ('result','status','verdict','conclusion','outcome','state','semantic_quality_review','behavioral_execution_status','behavioral_proof_status')
      loop
        v_class := public.lf_profile_update_result_class_v1(v_value);
        if v_class = 'FAIL' then return 'FAIL'; end if;
        if v_class = 'PASS' then v_saw_pass := true; end if;
      end loop;
      if v_saw_pass then return 'PASS'; end if;
      return 'UNPROVEN';
    else
      return 'UNPROVEN';
  end case;
end;
$function$;

create or replace function public.lf_profile_update_substantive_block_v1(
  p_execution_id text,
  p_step_id text,
  p_payload jsonb,
  p_manifest jsonb
)
returns text
language plpgsql
stable
set search_path to 'public'
as $function$
declare
  v_golden boolean := coalesce(p_manifest->>'graduation_contract','') = 'GOLDEN_CAPABLE_V1';
  v_class text;
  v_fixture jsonb;
  v_grad jsonb;
  v_receipt jsonb;
  v_readback_head text;
  v_declared integer;
  v_delivered integer;
begin
  if p_step_id = 'github_write' and coalesce(p_payload->'identity_preserved','false'::jsonb) <> 'true'::jsonb then
    return 'PROFILE_UPDATE_IDENTITY_NOT_PRESERVED';
  end if;

  if p_step_id = 'github_readback' then
    if coalesce(p_payload->'sha_match','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_READBACK_SHA_MISMATCH'; end if;
    if coalesce(p_payload->'identity_preserved','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_READBACK_IDENTITY_MISMATCH'; end if;
  end if;

  if p_step_id = 'deterministic_validation' then
    if public.lf_profile_update_result_class_v1(p_payload->'validator_result') = 'FAIL' then return 'PROFILE_UPDATE_VALIDATOR_RESULT_FAILED'; end if;
    if public.lf_profile_update_result_class_v1(p_payload->'malformed_input_result') = 'FAIL' then return 'PROFILE_UPDATE_MALFORMED_INPUT_GATE_FAILED'; end if;
    if v_golden then
      if public.lf_profile_update_result_class_v1(p_payload->'validator_result') <> 'PASS' then return 'PROFILE_UPDATE_GOLDEN_VALIDATOR_PASS_UNPROVEN'; end if;
      if public.lf_profile_update_result_class_v1(p_payload->'malformed_input_result') <> 'PASS' then return 'PROFILE_UPDATE_GOLDEN_FAIL_CLOSED_PROOF_UNPROVEN'; end if;
      v_fixture := p_payload->'fixture_completeness';
      if jsonb_typeof(v_fixture) <> 'object' or public.lf_profile_update_result_class_v1(v_fixture) <> 'PASS' then return 'PROFILE_UPDATE_GOLDEN_FIXTURE_COMPLETENESS_UNPROVEN'; end if;
      if jsonb_typeof(v_fixture->'missing_cases') <> 'array' or jsonb_array_length(v_fixture->'missing_cases') <> 0 then return 'PROFILE_UPDATE_GOLDEN_FIXTURE_CASES_MISSING'; end if;
      begin
        v_declared := (v_fixture->>'declared_case_count')::integer;
        v_delivered := (v_fixture->>'delivered_fixture_count')::integer;
      exception when others then
        return 'PROFILE_UPDATE_GOLDEN_FIXTURE_COUNTS_INVALID';
      end;
      if v_declared <= 0 or v_declared <> v_delivered then return 'PROFILE_UPDATE_GOLDEN_FIXTURE_COUNTS_MISMATCH'; end if;
    end if;
  end if;

  if p_step_id = 'semantic_judge' then
    if public.lf_profile_update_result_class_v1(p_payload->'semantic_judge_result') = 'FAIL' then return 'PROFILE_UPDATE_SEMANTIC_JUDGE_FAILED'; end if;
    if v_golden then
      if public.lf_profile_update_result_class_v1(p_payload->'semantic_judge_result') <> 'PASS' then return 'PROFILE_UPDATE_GOLDEN_SEMANTIC_PASS_UNPROVEN'; end if;
      if public.lf_profile_update_result_class_v1(p_payload->'independent_semantic_evaluation') <> 'PASS' then return 'PROFILE_UPDATE_GOLDEN_INDEPENDENT_SEMANTIC_UNPROVEN'; end if;
    end if;
  end if;

  if p_step_id = 'regression_after' then
    if public.lf_profile_update_result_class_v1(p_payload->'adversarial_result') = 'FAIL' then return 'PROFILE_UPDATE_ADVERSARIAL_FAILED'; end if;
    if public.lf_profile_update_result_class_v1(p_payload->'holdout_result') = 'FAIL' then return 'PROFILE_UPDATE_HOLDOUT_FAILED'; end if;
    if v_golden then
      if public.lf_profile_update_result_class_v1(p_payload->'adversarial_result') <> 'PASS' then return 'PROFILE_UPDATE_GOLDEN_ADVERSARIAL_PASS_UNPROVEN'; end if;
      if public.lf_profile_update_result_class_v1(p_payload->'holdout_result') <> 'PASS' then return 'PROFILE_UPDATE_GOLDEN_HOLDOUT_PASS_UNPROVEN'; end if;
      v_grad := p_payload->'graduation_evidence';
      if jsonb_typeof(v_grad) <> 'object' then return 'PROFILE_UPDATE_GOLDEN_GRADUATION_EVIDENCE_MISSING'; end if;
      if jsonb_typeof(v_grad->'raw_governed_execution_refs') <> 'array' or jsonb_array_length(v_grad->'raw_governed_execution_refs') = 0 then return 'PROFILE_UPDATE_GOLDEN_RAW_GOVERNED_RUNS_MISSING'; end if;
      if coalesce(v_grad->'adversarial_executed','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_GOLDEN_ADVERSARIAL_NOT_EXECUTED'; end if;
      if coalesce(v_grad->'unseen_holdout_executed','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_GOLDEN_UNSEEN_HOLDOUT_NOT_EXECUTED'; end if;
      if coalesce(v_grad->'independent_semantic_evaluation','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_GOLDEN_INDEPENDENT_EVALUATION_MISSING'; end if;
      if coalesce(v_grad->'no_aggregate_masking','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_GOLDEN_NO_AGGREGATE_MASKING_UNPROVEN'; end if;
    end if;
  end if;

  if p_step_id = 'close' then
    if coalesce(p_payload->'all_required_steps_clean','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_CLOSE_REQUIRED_STEPS_NOT_CLEAN'; end if;
    if coalesce(p_payload->'runtime_unchanged','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_CLOSE_RUNTIME_CHANGED'; end if;
    if coalesce(p_payload->'no_auto_promotion','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_CLOSE_AUTO_PROMOTION_NOT_BLOCKED'; end if;
    if jsonb_typeof(p_payload->'open_blockers') <> 'array' or jsonb_array_length(p_payload->'open_blockers') <> 0 then return 'PROFILE_UPDATE_CLOSE_OPEN_BLOCKERS'; end if;
    if v_golden then
      if coalesce(p_payload->'server_contract_receipt_verified','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_GOLDEN_CONTRACT_RECEIPT_UNVERIFIED'; end if;
      if p_payload->>'graduation_receipt_source' <> 'run-creacion-perfil-lf' then return 'PROFILE_UPDATE_GOLDEN_RECEIPT_SOURCE_INVALID'; end if;
      v_receipt := p_payload->'server_contract_receipt';
      if jsonb_typeof(v_receipt) <> 'object' then return 'PROFILE_UPDATE_GOLDEN_CONTRACT_RECEIPT_MISSING'; end if;
      if v_receipt->>'receipt_type' <> 'LF_OPERATION_CONTRACT_RECEIPT' then return 'PROFILE_UPDATE_GOLDEN_RECEIPT_TYPE_INVALID'; end if;
      if v_receipt->>'operation_code' <> 'ACTUALIZACION_PERFIL_LF' then return 'PROFILE_UPDATE_GOLDEN_RECEIPT_OPERATION_MISMATCH'; end if;
      if v_receipt->>'execution_id' <> p_execution_id then return 'PROFILE_UPDATE_GOLDEN_RECEIPT_EXECUTION_MISMATCH'; end if;
      if public.lf_profile_update_result_class_v1(to_jsonb(v_receipt->>'result')) <> 'PASS' then return 'PROFILE_UPDATE_GOLDEN_RECEIPT_RESULT_NOT_PASS'; end if;
      if coalesce(v_receipt->'all_required_steps_pass','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_GOLDEN_RECEIPT_STEPS_NOT_PASS'; end if;
      if jsonb_typeof(v_receipt->'blocking_codes') <> 'array' or jsonb_array_length(v_receipt->'blocking_codes') <> 0 then return 'PROFILE_UPDATE_GOLDEN_RECEIPT_BLOCKERS_PRESENT'; end if;
      select evidence_payload->>'exact_head' into v_readback_head from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='github_readback';
      if v_readback_head is null or v_readback_head !~ '^[0-9a-f]{40}$' or v_receipt->>'exact_head' <> v_readback_head then return 'PROFILE_UPDATE_GOLDEN_RECEIPT_HEAD_MISMATCH'; end if;
    end if;
  end if;

  if p_step_id = 'report_output' then
    if jsonb_typeof(p_payload->'open_blockers') <> 'array' or jsonb_array_length(p_payload->'open_blockers') <> 0 then return 'PROFILE_UPDATE_REPORT_OPEN_BLOCKERS'; end if;
  end if;

  return null;
end;
$function$;

create or replace function public.lf_record_profile_operation_step_v1(
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
  v_execution public.lf_operation_execution%rowtype;
  v_step public.lf_operation_steps%rowtype;
  v_contract public.lf_operation_step_contracts%rowtype;
  v_binding public.lf_operation_step_judge_bindings%rowtype;
  v_existing public.lf_operation_execution_steps%rowtype;
  v_key text;
  v_missing_keys text[] := array[]::text[];
  v_prior_missing integer := 0;
  v_prior_bad integer := 0;
  v_required_not_clean integer := 0;
  v_blocking_codes jsonb := '[]'::jsonb;
  v_payload jsonb;
  v_attempt_history jsonb := '[]'::jsonb;
  v_existing_retryable boolean := false;
  v_block_code text;
  v_block_details jsonb := '{}'::jsonb;
  v_trust jsonb;
begin
  if p_execution_id is null or btrim(p_execution_id) = '' or p_step_id is null or btrim(p_step_id) = '' then return jsonb_build_object('outcome','BLOCKED','code','STEP_IDENTITY_MISSING','durable',false); end if;
  if p_step_id = 'init_execution' then return jsonb_build_object('outcome','BLOCKED','code','INIT_STEP_IMMUTABLE','durable',false); end if;
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) <> 'object' then return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false); end if;
  select * into v_execution from public.lf_operation_execution where execution_id = p_execution_id for update;
  if not found or v_execution.target_type <> 'PERFIL' or v_execution.operation_code not in ('CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF') then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false); end if;
  if v_execution.status <> 'IN_PROGRESS' then return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_NOT_IN_PROGRESS','status',v_execution.status,'durable',false); end if;
  select * into v_step from public.lf_operation_steps where operation_code=v_execution.operation_code and step_id=p_step_id and active is true;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false); end if;
  select * into v_contract from public.lf_operation_step_contracts where operation_code=v_execution.operation_code and step_id=p_step_id and status=case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' then 'ACTIVE_ENFORCEMENT' else 'ACTIVE' end;
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_CONTRACT_MISSING','durable',false); end if;
  select * into v_binding from public.lf_operation_step_judge_bindings where operation_code=v_execution.operation_code and step_id=p_step_id and status='ACTIVE_ENFORCEMENT';
  if not found then return jsonb_build_object('outcome','BLOCKED','code','STEP_JUDGE_BINDING_MISSING','durable',false); end if;
  select * into v_existing from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id=p_step_id;
  if found then
    if v_existing.status=v_binding.clean_result_value and v_existing.evidence_ref=p_evidence_ref and v_existing.evidence_payload @> p_evidence_payload then
      if v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then
        select count(*) into v_required_not_clean
        from public.lf_operation_steps s
        left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id
        left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
        where s.operation_code=v_execution.operation_code and s.required is true and s.active is true
          and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
        if v_required_not_clean>0 then return jsonb_build_object('outcome','BLOCKED','code','PROFILE_UPDATE_COMPLETION_NOT_CLEAN','required_not_clean',v_required_not_clean,'durable',false); end if;
        update public.lf_operation_execution set status='COMPLETED',completed_at=coalesce(completed_at,now()),manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate')),updated_by_execution_id=p_actor_execution_id,updated_at=now() where execution_id=p_execution_id and status='IN_PROGRESS';
      end if;
      return jsonb_build_object('outcome','STEP_RECORDED','replay',true,'step_id',p_step_id,'status',v_existing.status,'execution_status',case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then 'COMPLETED' else v_execution.status end);
    end if;
    if v_existing.status in (v_binding.blocked_result_value,v_binding.return_result_value) then v_existing_retryable:=true; if jsonb_typeof(v_existing.evidence_payload->'attempt_history')='array' then v_attempt_history:=v_existing.evidence_payload->'attempt_history'; end if; else return jsonb_build_object('outcome','BLOCKED','code','STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE','status',v_existing.status,'durable',true); end if;
  end if;
  select count(*) into v_prior_missing from public.lf_operation_steps s where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and coalesce(s.execution_order,0)<coalesce(v_step.execution_order,0) and not exists(select 1 from public.lf_operation_execution_steps es where es.execution_id=p_execution_id and es.step_id=s.step_id);
  select count(*) into v_prior_bad from public.lf_operation_steps s join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id left join public.lf_operation_step_judge_bindings pb on pb.operation_code=s.operation_code and pb.step_id=s.step_id and pb.status='ACTIVE_ENFORCEMENT' where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and coalesce(s.execution_order,0)<coalesce(v_step.execution_order,0) and (pb.clean_result_value is null or es.status<>pb.clean_result_value);
  if v_prior_missing>0 or v_prior_bad>0 then v_block_code:='PRIOR_REQUIRED_STEP_NOT_CLEAN'; v_block_details:=jsonb_build_object('prior_missing',v_prior_missing,'prior_bad',v_prior_bad); end if;
  if v_block_code is null then for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (p_evidence_payload ? v_key) or p_evidence_payload->v_key is null or p_evidence_payload->v_key='null'::jsonb or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then v_missing_keys:=array_append(v_missing_keys,v_key); end if; end loop; if cardinality(v_missing_keys)>0 then v_block_code:='REQUIRED_EVIDENCE_MISSING'; v_block_details:=jsonb_build_object('missing_keys',to_jsonb(v_missing_keys)); end if; end if;
  if v_block_code is null and p_evidence_payload ? 'blocking_codes' then if jsonb_typeof(p_evidence_payload->'blocking_codes')<>'array' then v_block_code:='BLOCKING_CODES_INVALID'; else v_blocking_codes:=p_evidence_payload->'blocking_codes'; if jsonb_array_length(v_blocking_codes)>0 then v_block_code:=coalesce(v_contract.blocking_code,'STEP_BLOCKED'); v_block_details:=jsonb_build_object('caller_blocking_codes',v_blocking_codes); end if; end if; end if;
  if v_block_code is null and v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='pre_write_execution_binding_gate' then
    v_trust:=p_evidence_payload->'server_trust_context';
    if coalesce(p_evidence_payload->'server_trust_context_valid','false'::jsonb) <> 'true'::jsonb or p_evidence_payload->>'server_trust_context_source'<>'run-creacion-perfil-lf' or jsonb_typeof(v_trust)<>'object' or v_trust->>'resolver'<>'GITHUB_PUBLIC_API_EXACT_REF_V1' or v_trust->>'repository'<>coalesce(v_execution.target_repo,'') or v_trust->>'ref'<>'main' or v_trust->>'target_path'<>coalesce(v_execution.target_path,'') or v_trust->>'bound_revision'<>p_evidence_payload->>'bound_revision' or v_trust->>'continuity_state' not in ('CURRENT_BOUND','STALE_REBOUND_CURRENT') or (v_trust->>'revision_sha') !~ '^[0-9a-f]{40}$' or (v_trust->>'target_blob_sha') !~ '^[0-9a-f]{40}$' or (v_trust->>'baseline_revision') !~ '^[0-9a-f]{40}$' then v_block_code:='PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED'; v_block_details:=jsonb_build_object('reason','Validated server-derived trust context required'); end if;
  end if;
  if v_block_code is null and v_execution.operation_code='ACTUALIZACION_PERFIL_LF' then
    v_block_code:=public.lf_profile_update_substantive_block_v1(p_execution_id,p_step_id,p_evidence_payload,v_execution.manifest);
    if v_block_code is not null then v_block_details:=jsonb_build_object('reason','Substantive Profile update/graduation evidence did not satisfy fail-closed contract','graduation_contract',v_execution.manifest->>'graduation_contract'); end if;
  end if;
  if v_block_code is not null then
    v_payload:=p_evidence_payload; for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;
    v_attempt_history:=v_attempt_history||jsonb_build_array(jsonb_build_object('at',clock_timestamp(),'outcome','BLOCKED','code',v_block_code,'evidence_ref',p_evidence_ref,'details',v_block_details));
    v_payload:=v_payload||jsonb_build_object('step_result',v_binding.blocked_result_value,'blocking_findings',jsonb_build_array(v_block_code),'blocking_codes',jsonb_build_array(v_block_code),'return_to_worker_reasons','[]'::jsonb,'assertions_checked',coalesce(v_payload->'assertions_checked','[]'::jsonb),'hard_fails_checked',coalesce(v_payload->'hard_fails_checked','[]'::jsonb),'blocked_by_recorder',true,'blocked_reason_code',v_block_code,'blocked_details',v_block_details,'attempt_history',v_attempt_history,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.blocked_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1');
    if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.blocked_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Blocked attempt persisted transactionally; retry remains allowed on same row.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.blocked_result_value,p_evidence_ref,v_payload,'Blocked attempt persisted transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
    return jsonb_build_object('outcome','BLOCKED','code',v_block_code,'durable',true,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'status',v_binding.blocked_result_value,'retryable',true,'attempt_count',jsonb_array_length(v_attempt_history))||v_block_details;
  end if;
  v_payload:=p_evidence_payload||jsonb_build_object('step_result',v_binding.clean_result_value,'blocking_codes','[]'::jsonb,'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'recorded_by_rpc','lf_record_profile_operation_step_v1','attempt_history',v_attempt_history);
  if v_existing_retryable then update public.lf_operation_execution_steps set status=v_binding.clean_result_value,evidence_ref=p_evidence_ref,evidence_payload=v_payload,notes='Clean retry accepted transactionally; prior blocked attempts preserved in attempt_history.' where execution_id=p_execution_id and step_id=p_step_id; else insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,p_evidence_payload,notes,created_by_execution_id) values(p_execution_id,v_step.step_order,p_step_id,v_binding.clean_result_value,p_evidence_ref,v_payload,'Recorded transactionally by common governed Profile operation recorder.',p_actor_execution_id); end if;
  if v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then
    select count(*) into v_required_not_clean from public.lf_operation_steps s left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_id=s.step_id left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT' where s.operation_code=v_execution.operation_code and s.required is true and s.active is true and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value);
    if v_required_not_clean>0 then raise exception 'PROFILE_UPDATE_COMPLETION_NOT_CLEAN execution=% required_not_clean=%',p_execution_id,v_required_not_clean; end if;
    update public.lf_operation_execution set status='COMPLETED',completed_at=coalesce(completed_at,now()),manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('operation_closed',true,'next_gate',coalesce(p_evidence_payload->'next_gate',manifest->'next_gate'),'graduation_contract',manifest->>'graduation_contract'),updated_by_execution_id=p_actor_execution_id,updated_at=now() where execution_id=p_execution_id and status='IN_PROGRESS';
  end if;
  return jsonb_build_object('outcome','STEP_RECORDED','replay',false,'execution_id',p_execution_id,'operation_code',v_execution.operation_code,'step_id',p_step_id,'step_order',v_step.step_order,'execution_order',v_step.execution_order,'status',v_binding.clean_result_value,'execution_status',case when v_execution.operation_code='ACTUALIZACION_PERFIL_LF' and p_step_id='report_output' then 'COMPLETED' else v_execution.status end,'mini_judge_code',v_binding.judge_code,'mini_judge_result',v_binding.clean_result_value,'next_gate',v_contract.next_if_pass,'resumed_from_blocked',v_existing_retryable,'prior_attempt_count',jsonb_array_length(v_attempt_history));
end;
$function$;

revoke all on function public.lf_profile_update_result_class_v1(jsonb) from public, anon, authenticated;
revoke all on function public.lf_profile_update_substantive_block_v1(text,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.lf_profile_update_result_class_v1(jsonb) to service_role, postgres;
grant execute on function public.lf_profile_update_substantive_block_v1(text,text,jsonb,jsonb) to service_role, postgres;
