-- GPT-native in-chat producer capture: candidate governance only.
-- Does not modify active operational policies, runtime dispatch, permissions or profile sources.
-- All authority and production cutover remain blocked pending independent evidence.
begin;
do $pre$
begin
  if (select count(*) from public.lf_policy_versions
      where policy_code='POL-PROFILE-UPDATE-PASS'
      and policy_version='v1.1' and status='ACTIVE') <> 1
    then raise exception 'GPT_NATIVE_CHAT_ACTIVE_BASELINE_MISSING';
  end if;
  if exists(select 1 from public.lf_policy_versions
      where policy_code='POL-PROFILE-UPDATE-PASS'
      and policy_version='v1.2-gpt-native-in-chat-candidate')
    then raise exception 'GPT_NATIVE_CHAT_CANDIDATE_VERSION_ALREADY_EXISTS';
  end if;
end $pre$;
with baseline as (
  select policy_code, policy_payload
  from public.lf_policy_versions
  where policy_code='POL-PROFILE-UPDATE-PASS'
    and policy_version='v1.1' and status='ACTIVE'
), proposed as (
  select policy_code,
         policy_payload || jsonb_build_object('gpt_native_in_chat_candidate_v1',
           '{"contract_schema":"LF_GPT_NATIVE_IN_CHAT_CAPTURE_CONTRACT_V1","source_git_path":"skills/profile_creator/contracts/gpt_native_in_chat_capture_contract_v1.json","status":"CANDIDATE_TEST_ONLY","executor_mode":"GPT_NATIVE","transport":"CHAT_SESSION_AUTHORING","source_readback_required":true,"independent_semantic_review_required":true,"chat_output_is_runtime_attestation":false,"runtime_provider_attestation":"NOT_AVAILABLE","operational_cutover_allowed":false,"existing_profile_runtime_validation_unmodified":true,"legacy_runtime_adapter_bypass_allowed":false,"benchmark_admission_allowed":false,"forbidden":["FORGE_RUNTIME_ATTESTATION","SELF_ATTESTATION","PAID_MODEL_CALL","OTHER_MODEL_FALLBACK","AUTO_PROMOTE","AUTO_CUTOVER"],"admission_requires":["EXACT_GIT_AND_DB_READBACK","TRUSTED_MODEL_PROVENANCE_OR_GOVERNED_EQUIVALENT","BLIND_INDEPENDENT_REVIEW","FOUR_ARM_BENCHMARK_PASS","SAFE_CHANGE_ADMISSION"]}'::jsonb) as payload
  from baseline
)
insert into public.lf_policy_versions
 (policy_code,policy_version,policy_payload,policy_sha,status,effective_at,source_ref,created_by_execution_id)
select policy_code,'v1.2-gpt-native-in-chat-candidate',payload,
       encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),
       'CANDIDATE',clock_timestamp(),
       'supabase/migrations/20261012072000_lf_gpt_native_in_chat_capture_policy_candidate_v1.sql',
       'EXEC-PE-GPT-NATIVE-INCHAT-GOV-20261012-001'
from proposed;
do $post$
begin
  if (select count(*) from public.lf_policy_versions
      where policy_code='POL-PROFILE-UPDATE-PASS'
        and policy_version='v1.2-gpt-native-in-chat-candidate'
        and status='CANDIDATE'
        and policy_payload->'gpt_native_in_chat_candidate_v1'->>'executor_mode'='GPT_NATIVE'
        and policy_payload->'gpt_native_in_chat_candidate_v1'->>'operational_cutover_allowed'='false'
        and policy_payload->'gpt_native_in_chat_candidate_v1'->>'benchmark_admission_allowed'='false'
        and policy_sha=encode(extensions.digest(convert_to(policy_payload::text,'UTF8'),'sha256'),'hex'))<>1
      then raise exception 'GPT_NATIVE_CHAT_CANDIDATE_POLICY_INVALID';
  end if;
  if (select count(*) from public.lf_policy_versions
       where policy_code='POL-PROFILE-UPDATE-PASS' and status='ACTIVE')<>1
      then raise exception 'GPT_NATIVE_CHAT_ACTIVE_POLICY_DRIFT';
  end if;
end $post$;
commit;
