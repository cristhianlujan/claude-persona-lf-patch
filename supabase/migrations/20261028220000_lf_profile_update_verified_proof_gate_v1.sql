-- Profile update (governed route): replace the ledger-receipt requirement with a server-verified measurement,
-- and require a server-verified before/after proof for deterministic_validation once a profile write exists.
--  * method_selection / evolution_decision: the profile assessment is the structural S26 measurement of the bound
--    revision, read back from a GitHub Actions run by run-creacion-perfil-lf (resolver GITHUB_ACTIONS_EVOLUTION_PROOF_V1).
--  * deterministic_validation: when a github_write exists, the payload must carry a compare proof whose base is the
--    pre-write bound revision and whose candidate is the written commit (>=1 dimension fail->pass, none pass->fail).
-- Legacy (non-governed) executions keep the previous behaviour.
CREATE OR REPLACE FUNCTION public.lf_profile_update_evolution_step_guard_v1(p_execution_id text, p_step_id text, p_payload jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  recorded public.lf_operation_execution_steps%rowtype;
  portfolio jsonb;
  r record;
  m record;
  method_data jsonb;
  slug text;
  decision text;
  mode text;
  v_governed boolean;
  ctx jsonb;
BEGIN
  IF p_step_id NOT IN ('method_selection','evolution_decision') THEN RETURN NULL; END IF;
  SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR e.operation_code<>'ACTUALIZACION_PERFIL_LF'
     OR e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps_by_outcome}' IS NULL
  THEN RETURN 'EVOLUTION_OPERATION_CONTEXT_INVALID'; END IF;
  IF jsonb_typeof(p_payload) <> 'object' THEN RETURN 'EVOLUTION_EVIDENCE_NOT_OBJECT'; END IF;
  v_governed := coalesce(e.manifest->>'router_semantic_receipt_sha256','') <> '';
  slug:=split_part(e.target_path,'/',2);
  IF NULLIF(slug,'') IS NULL OR p_payload->>'profile_slug' IS DISTINCT FROM slug THEN
    RETURN 'EVOLUTION_PROFILE_IDENTITY_MISMATCH';
  END IF;
  IF p_payload->>'source_head_sha' IS DISTINCT FROM coalesce(e.manifest->>'initial_main_revision','')
     OR p_payload->>'source_head_sha' !~ '^[0-9a-f]{40}$'
  THEN RETURN 'EVOLUTION_SOURCE_REVISION_MISMATCH'; END IF;

  IF v_governed THEN
    -- Governed executions: the assessment is the structural measurement of the bound revision, read back from a
    -- GitHub Actions run by run-creacion-perfil-lf. The ledger receipt is not used on this route.
    IF p_step_id='method_selection' THEN
      ctx := p_payload->'server_trust_context';
      IF coalesce(p_payload->'server_trust_context_valid','false'::jsonb) <> 'true'::jsonb
         OR p_payload->>'server_trust_context_source' IS DISTINCT FROM 'run-creacion-perfil-lf'
         OR jsonb_typeof(ctx) <> 'object'
         OR ctx->>'resolver' IS DISTINCT FROM 'GITHUB_ACTIONS_EVOLUTION_PROOF_V1'
         OR ctx->>'mode' IS DISTINCT FROM 'measure'
         OR ctx->>'profile_slug' IS DISTINCT FROM slug
         OR ctx->>'base_sha' IS DISTINCT FROM p_payload->>'source_head_sha'
         OR coalesce(ctx->>'proof_sha256','') !~ '^[0-9a-f]{64}$'
         OR ctx->>'proof_sha256' IS DISTINCT FROM p_payload->>'profile_assessment_sha256'
         OR coalesce(ctx->>'run_id','') = ''
         OR ctx->>'run_id' IS DISTINCT FROM p_payload->>'profile_assessment_receipt_id'
      THEN RETURN 'EVOLUTION_PROFILE_ASSESSMENT_NOT_VERIFIED'; END IF;
    ELSE
      SELECT * INTO recorded FROM public.lf_operation_execution_steps
       WHERE execution_id=p_execution_id AND step_id='method_selection';
      IF NOT FOUND OR recorded.evidence_payload->>'profile_assessment_sha256'
           IS DISTINCT FROM p_payload->>'profile_assessment_sha256'
      THEN RETURN 'EVOLUTION_PROFILE_ASSESSMENT_NOT_VERIFIED'; END IF;
    END IF;
  ELSIF NOT public.lf_profile_update_verified_receipt_v1(
       'PROFILE_ASSESSMENT',slug,
       p_payload->>'profile_assessment_receipt_id',
       p_payload->>'profile_assessment_sha256',
       p_payload->>'source_head_sha'
  ) THEN RETURN 'EVOLUTION_PROFILE_ASSESSMENT_NOT_VERIFIED'; END IF;

  IF p_step_id='method_selection' THEN
    IF p_payload->>'selector_version' IS DISTINCT FROM (
      SELECT version FROM public.lf_capability_current
       WHERE capability_code='CAPABILITY_SELECTOR'
    ) THEN RETURN 'EVOLUTION_SELECTOR_VERSION_STALE'; END IF;
    SELECT v.manifest#>'{contract,qualified_method_portfolio}' INTO portfolio
      FROM public.lf_capability_current c
      JOIN public.lf_capability_version_registry v
        ON v.capability_code=c.capability_code AND v.version=c.version
     WHERE c.capability_code='METHOD_PACK_REGISTRY'
       AND v.release_state='RELEASED';
    IF coalesce(jsonb_typeof(portfolio),'')<>'array'
       OR coalesce(jsonb_typeof(p_payload->'selected_methods'),'')<>'array'
    THEN RETURN 'EVOLUTION_METHOD_PORTFOLIO_INVALID'; END IF;

    IF jsonb_array_length(p_payload->'selected_methods')=0 THEN
      IF p_payload->'no_additional_method_needed' IS DISTINCT FROM 'true'::jsonb
         OR nullif(btrim(p_payload->>'empty_selection_reason'),'') IS NULL
      THEN RETURN 'EVOLUTION_EMPTY_METHOD_UNJUSTIFIED'; END IF;
    ELSE
      IF p_payload->'no_additional_method_needed'='true'::jsonb THEN
        RETURN 'EVOLUTION_METHOD_SELECTION_CONTRADICTORY';
      END IF;
    END IF;
    FOR r IN SELECT value AS item FROM jsonb_array_elements(p_payload->'selected_methods')
    LOOP
      IF jsonb_typeof(r.item)<>'object' OR
         nullif(btrim(r.item->>'method_id'),'') IS NULL OR
         nullif(btrim(r.item->>'exact_version'),'') IS NULL OR
         nullif(btrim(r.item->>'receipt_id'),'') IS NULL
      THEN RETURN 'EVOLUTION_METHOD_RECORD_INVALID'; END IF;
      SELECT elem.value INTO method_data
        FROM jsonb_array_elements(portfolio) AS elem(value)
       WHERE elem.value->>'method_id'=r.item->>'method_id'
         AND elem.value->>'exact_version'=r.item->>'exact_version'
         AND elem.value->>'qualification_state'='QUALIFIED'
       LIMIT 1;
      IF method_data IS NULL THEN RETURN 'EVOLUTION_METHOD_NOT_QUALIFIED'; END IF;
      IF NOT public.lf_profile_update_verified_receipt_v1(
        'METHOD_QUALIFICATION',
        (r.item->>'method_id')||'@'||(r.item->>'exact_version'),
        r.item->>'receipt_id',
        r.item->>'subject_sha256',
        r.item->>'source_head_sha'
      ) THEN RETURN 'EVOLUTION_METHOD_QUALIFICATION_UNVERIFIED'; END IF;
    END LOOP;
    IF p_payload->'method_execution_permitted' IS DISTINCT FROM 'false'::jsonb
    THEN RETURN 'EVOLUTION_SELECTION_ILLEGAL_EXECUTION_PERMISSION'; END IF;
    RETURN NULL;
  END IF;

  SELECT * INTO recorded FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id AND step_id='method_selection';
  IF NOT FOUND OR recorded.status IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
     OR recorded.evidence_payload->>'recorded_by_rpc' IS DISTINCT FROM 'lf_record_profile_operation_step_v1'
     OR recorded.evidence_payload->>'mini_judge_result' IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN RETURN 'EVOLUTION_SELECTION_STEP_NOT_CLEAN'; END IF;
  IF recorded.evidence_payload->>'profile_assessment_receipt_id'
     IS DISTINCT FROM p_payload->>'profile_assessment_receipt_id'
  THEN RETURN 'EVOLUTION_DECISION_ASSESSMENT_RECEIPT_MISMATCH'; END IF;
  decision:=p_payload->>'decision';
  mode:=p_payload->>'evolution_mode';
  IF decision='NO_CHANGE' AND mode IS DISTINCT FROM 'NO_CHANGE' THEN
    RETURN 'EVOLUTION_NO_CHANGE_MODE_INVALID';
  ELSIF decision='UPDATE' AND (mode IS NULL OR mode NOT IN ('PATCH','SPECIALIZE','ADAPT','REARCHITECT','OPTIMIZE'))
  THEN RETURN 'EVOLUTION_UPDATE_MODE_INVALID';
  ELSIF decision IS NULL OR decision NOT IN ('NO_CHANGE','UPDATE')
  THEN RETURN 'EVOLUTION_DECISION_NOT_ADMITTED';
  END IF;
  IF nullif(btrim(p_payload->>'decision_evidence_ref'),'') IS NULL THEN
    RETURN 'EVOLUTION_DECISION_EVIDENCE_MISSING';
  END IF;
  IF p_payload->'github_write_permitted' IS DISTINCT FROM 'false'::jsonb THEN
    RETURN 'EVOLUTION_DECISION_CANNOT_AUTHORIZE_WRITE';
  END IF;
  RETURN NULL;
END;
$function$;

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
begin
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
