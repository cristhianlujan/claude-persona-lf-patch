-- CANDIDATE ONLY — DO NOT RUN DIRECTLY OR EDIT PRIOR MIGRATIONS.
-- Applies only to NEW governed ACTUALIZACION_PERFIL_LF executions with
-- manifest.native_placement_gate_version PROFILE_NATIVE_PLACEMENT_SOURCE_READBACK_V1,
-- derived by the EXISTING run-creacion-perfil-lf caller at initialization.
-- Materialize through the governed updater/database change train.
-- Important: checks SOURCE provenance and sequence, NOT actual native method
-- runtime execution. Require separately verified enforcement at regression_after
-- before declaring the complete profile operational.
-- Source: read-only pg_get_functiondef of live public.lf_profile_update_substantive_block_v1.

CREATE OR REPLACE FUNCTION public.lf_profile_update_substantive_block_v1(p_execution_id text, p_step_id text, p_payload jsonb, p_manifest jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_golden boolean := coalesce(p_manifest->>'graduation_contract','') = 'GOLDEN_CAPABLE_V1';
  v_governed boolean := coalesce(p_manifest->>'router_semantic_receipt_sha256','') <> '';
  v_fixture jsonb;
  v_grad jsonb;
  v_receipt jsonb;
  v_readback_head text;
  v_write_commit text;
  v_write jsonb;
  v_bound text;
  v_declared integer;
  v_delivered integer;
  -- Optional frozen policy bit for NEW governed executions only.
  v_native_placement boolean := p_manifest->>'native_placement_gate_version'
    = 'PROFILE_NATIVE_PLACEMENT_SOURCE_READBACK_V1';
  v_native_scope jsonb;
  v_native_attestation jsonb;
  v_native_adoptions jsonb;
begin
  -- Existing change_scope (40), not a new operation or standalone judge.
  if v_native_placement and v_governed and p_step_id='change_scope' then
    v_native_adoptions:=p_payload->'native_step_adoptions';
    v_native_attestation:=p_payload->'native_step_placement_readback';
    if jsonb_typeof(v_native_adoptions) is distinct from 'array'
      or jsonb_typeof(v_native_attestation) is distinct from 'object'
      or p_payload->>'native_step_placement_readback_source' is distinct from 'run-creacion-perfil-lf'
      or v_native_attestation->>'profile_slug' is distinct from split_part(
        (select target_path from public.lf_operation_execution where execution_id=p_execution_id), '/', 2)
      or v_native_attestation->>'base_sha' is distinct from p_manifest->>'initial_main_revision'
    then return 'PROFILE_NATIVE_PLACEMENT_SCOPE_NOT_SOURCE_VERIFIED'; end if;
    if jsonb_array_length(v_native_adoptions)>0 then
      if v_native_attestation->>'schema' is distinct from 'PROFILE_NATIVE_PLACEMENT_SOURCE_ATTESTATION_V1'
        or v_native_attestation->>'state' is distinct from 'SOURCE_ONLY_NOT_ENFORCEMENT'
        or v_native_attestation->>'source' is distinct from 'EXISTING_GITHUB_EXACT_REF_READER'
        or jsonb_typeof(v_native_attestation->'records') is distinct from 'array'
        or jsonb_array_length(v_native_attestation->'records')<>jsonb_array_length(v_native_adoptions)
      then return 'PROFILE_NATIVE_PLACEMENT_SOURCE_ATTESTATION_INVALID'; end if;
    elsif v_native_attestation->>'state' is distinct from 'NO_ADOPTION_DECLARED' then
      return 'PROFILE_NATIVE_NO_ADOPTION_PROOF_MISMATCH';
    end if;
  end if;

  -- Existing deterministic_validation (90) after existing GitHub readback.
  if v_native_placement and v_governed and p_step_id='deterministic_validation' then
    select evidence_payload into v_native_scope
      from public.lf_operation_execution_steps where execution_id=p_execution_id
        and step_id='change_scope' and status='STEP_PASS_WITH_EVIDENCE';
    v_native_attestation:=p_payload->'native_step_placement_readback';
    if v_native_scope is null or jsonb_typeof(v_native_attestation) is distinct from 'object'
      or p_payload->>'native_step_placement_readback_source' is distinct from 'run-creacion-perfil-lf'
      or v_native_attestation->>'base_sha' is distinct from
           v_native_scope#>>'{native_step_placement_readback,base_sha}'
      or v_native_attestation->>'candidate_sha' is distinct from
           p_payload#>>'{server_trust_context,candidate_sha}'
    then return 'PROFILE_NATIVE_PLACEMENT_POSTWRITE_READBACK_MISMATCH'; end if;
    v_native_adoptions:=v_native_scope->'native_step_adoptions';
    if jsonb_typeof(v_native_adoptions) is distinct from 'array' then
      return 'PROFILE_NATIVE_PLACEMENT_SCOPE_MISSING'; end if;
    if jsonb_array_length(v_native_adoptions)>0 then
      if v_native_attestation->>'state' is distinct from 'SOURCE_ONLY_NOT_ENFORCEMENT'
        or jsonb_typeof(v_native_attestation->'records') is distinct from 'array'
        or jsonb_array_length(v_native_attestation->'records')<>jsonb_array_length(v_native_adoptions)
      then return 'PROFILE_NATIVE_PLACEMENT_POSTWRITE_COVERAGE_MISMATCH'; end if;
    elsif v_native_attestation->>'state' is distinct from 'NO_ADOPTION_DECLARED' then
      return 'PROFILE_NATIVE_UNDECLARED_CHANGE_UNVERIFIED';
    end if;
  end if;

  if v_governed and p_step_id in ('github_write','github_readback') then
    if coalesce(p_payload->'server_trust_context_valid','false'::jsonb) <> 'true'::jsonb
       or p_payload->>'server_trust_context_source' <> 'run-creacion-perfil-lf'
       or jsonb_typeof(p_payload->'server_trust_context') <> 'object'
       or p_payload->'server_trust_context'->>'resolver' <> 'GITHUB_PUBLIC_API_EXACT_COMMIT_V1'
       or coalesce(p_payload->'server_trust_context'->>'commit_sha','') !~ '^[0-9a-f]{40}$'
       or (p_step_id = 'github_write' and jsonb_typeof(p_payload->'written_files') is distinct from 'array')
       or (p_step_id = 'github_readback' and jsonb_typeof(p_payload->'readback_files') is distinct from 'array')
    then return 'PROFILE_UPDATE_GITHUB_EVIDENCE_NOT_SERVER_VERIFIED'; end if;
    if p_step_id = 'github_readback' then
      select evidence_payload->'server_trust_context'->>'commit_sha' into v_write_commit
        from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='github_write';
      if v_write_commit is null or p_payload->>'exact_head' is distinct from v_write_commit
         or p_payload->'server_trust_context'->>'commit_sha' is distinct from v_write_commit
      then return 'PROFILE_UPDATE_READBACK_HEAD_NOT_WRITE_COMMIT'; end if;
    end if;
  end if;

  if p_step_id = 'github_write' and coalesce(p_payload->'identity_preserved','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_IDENTITY_NOT_PRESERVED'; end if;
  if p_step_id = 'github_readback' then
    if coalesce(p_payload->'sha_match','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_READBACK_SHA_MISMATCH'; end if;
    if coalesce(p_payload->'identity_preserved','false'::jsonb) <> 'true'::jsonb then return 'PROFILE_UPDATE_READBACK_IDENTITY_MISMATCH'; end if;
  end if;

  if v_governed and p_step_id = 'deterministic_validation' then
    select evidence_payload into v_write from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='github_write';
    if v_write is not null then
      select evidence_payload->>'bound_revision' into v_bound from public.lf_operation_execution_steps where execution_id=p_execution_id and step_id='pre_write_execution_binding_gate';
      if coalesce(p_payload->'server_trust_context_valid','false'::jsonb) <> 'true'::jsonb
         or p_payload->>'server_trust_context_source' is distinct from 'run-creacion-perfil-lf'
         or jsonb_typeof(p_payload->'server_trust_context') <> 'object'
         or p_payload->'server_trust_context'->>'resolver' is distinct from 'GITHUB_ACTIONS_EVOLUTION_PROOF_V1'
         or p_payload->'server_trust_context'->>'mode' is distinct from 'compare'
         or v_bound is null or p_payload->'server_trust_context'->>'base_sha' is distinct from v_bound
         or p_payload->'server_trust_context'->>'candidate_sha' is distinct from v_write->'server_trust_context'->>'commit_sha'
         or coalesce(p_payload->'evolution_proof_verified','false'::jsonb) <> 'true'::jsonb
      then return 'PROFILE_UPDATE_EVOLUTION_PROOF_NOT_SERVER_VERIFIED'; end if;
    end if;
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

  -- Mandatory for NEW frozen-governed placement executions only.
  -- Keep existing step IDs (semantic_judge, regression_after) and receipts.
  -- This establishes PASS floors; independent SOURCE/CALL authority still
  -- needs verification from the existing governed executor before promotion.
  if v_native_placement and v_governed
      and p_step_id in ('semantic_judge','regression_after') then
    select evidence_payload into v_native_scope
      from public.lf_operation_execution_steps
     where execution_id=p_execution_id
       and step_id='change_scope'
       and status='STEP_PASS_WITH_EVIDENCE';
    if v_native_scope is null or
       jsonb_typeof(v_native_scope->'native_step_adoptions') is distinct from 'array' then
      return 'PROFILE_NATIVE_PLACEMENT_SCOPE_RECEIPT_REQUIRED';
    end if;
    if jsonb_array_length(v_native_scope->'native_step_adoptions')>0 then
      if p_step_id='semantic_judge' then
        if public.lf_profile_update_result_class_v1(p_payload->'semantic_judge_result')
             is distinct from 'PASS'
          or public.lf_profile_update_result_class_v1(p_payload->'independent_semantic_evaluation')
             is distinct from 'PASS' then
          return 'PROFILE_NATIVE_PLACEMENT_INDEPENDENT_SEMANTIC_PASS_REQUIRED';
        end if;
      else
        if public.lf_profile_update_result_class_v1(p_payload->'adversarial_result')
             is distinct from 'PASS'
          or public.lf_profile_update_result_class_v1(p_payload->'holdout_result')
             is distinct from 'PASS' then
          return 'PROFILE_NATIVE_PLACEMENT_ADVERSARIAL_HOLDOUT_PASS_REQUIRED';
        end if;
      end if;
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
$function$
