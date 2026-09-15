-- LF_PROFILE_UPDATE_SUBSTANTIVE_GATE_V1
-- S25 canary remediation: classify actual outcome values and add GOLDEN_CAPABLE_V1 obligations.

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
  v_fixture jsonb;
  v_grad jsonb;
  v_receipt jsonb;
  v_readback_head text;
  v_declared integer;
  v_delivered integer;
begin
  if p_step_id = 'github_write' and coalesce(p_payload->'identity_preserved','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_IDENTITY_NOT_PRESERVED'; end if;
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
      exception when others then return 'PROFILE_UPDATE_GOLDEN_FIXTURE_COUNTS_INVALID'; end;
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

  if p_step_id = 'report_output' and (jsonb_typeof(p_payload->'open_blockers') <> 'array' or jsonb_array_length(p_payload->'open_blockers') <> 0) then return 'PROFILE_UPDATE_REPORT_OPEN_BLOCKERS'; end if;
  return null;
end;
$function$;

revoke all on function public.lf_profile_update_result_class_v1(jsonb) from public, anon, authenticated;
revoke all on function public.lf_profile_update_substantive_block_v1(text,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.lf_profile_update_result_class_v1(jsonb) to service_role, postgres;
grant execute on function public.lf_profile_update_substantive_block_v1(text,text,jsonb,jsonb) to service_role, postgres;
