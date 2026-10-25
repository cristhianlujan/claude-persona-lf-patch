-- LF P0: production-safe, transaction-scoped integration test for the existing
-- profile-policy pipeline. No new router, profile, registry, function or service.
--
-- IMPORTANT: This migration is a TEST ONLY. All fixtures and temporary
-- policy rows are created inside a PL/pgSQL exception subtransaction that
-- is deliberately rolled back. If ANY assertion or governed trigger fails,
-- the exception propagates and the migration transaction is rejected.
-- The sole intended durable record is the ordinary migration-ledger receipt.
BEGIN;

DO $lf_p0_verify$
DECLARE
  v_visual_id CONSTANT text := 'LF-P0-POLICY-VISUAL-ROLLBACK-ONLY-20261025';
  v_read_id CONSTANT text := 'LF-P0-POLICY-READ-ROLLBACK-ONLY-20261025';
  v_optional_policy CONSTANT text := 'LF-P0-REGRESSION-OPTIONAL-NOT-PERSISTED';
  v_visual_request jsonb;
  v_read_request jsonb;
  v_optional_request jsonb;
  v_selected jsonb;
  v_result jsonb;
  v_discovery jsonb;
  v_assertions int := 0;
  v_rollback_verified boolean := false;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id IN (v_visual_id,v_read_id)
  ) OR EXISTS (
    SELECT 1 FROM private.lf_reusable_policy_registry_v1
    WHERE policy_code=v_optional_policy
  ) THEN
    RAISE EXCEPTION 'LF_P0_TEST_FIXTURE_COLLISION';
  END IF;

  BEGIN
    -- Real operation insert; ALL existing operation triggers remain enabled.
    -- These are read-only intent fixtures: no queueing, profile execution,
    -- or external side effects are requested.
    INSERT INTO public.lf_operation_execution (
      execution_id,operation_code,target_type,target_code,target_repo,target_path,
      status,manifest,created_by_execution_id
    ) VALUES (
      v_visual_id,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-UI-ARCHITECT',
      'cristhianlujan/claude-persona-lf-patch','profiles/ui_architect/SKILL.md',
      'IN_PROGRESS',
      jsonb_build_object(
        'read_only',true,'no_write',true,'no_promotion',true,
        'router_profile_handoff',jsonb_build_object(
          'business','LF','channel','PRODUCTO','action','UPDATE',
          'scope',jsonb_build_object('target_type','PANTALLA')
        )
      ),
      'LF-P0-VALIDATION-TRANSACTION'
    ),(
      v_read_id,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-UI-ARCHITECT',
      'cristhianlujan/claude-persona-lf-patch','profiles/ui_architect/SKILL.md',
      'IN_PROGRESS',
      jsonb_build_object(
        'read_only',true,'no_write',true,'no_promotion',true,
        'router_profile_handoff',jsonb_build_object(
          'business','LF','channel','PRODUCTO','action','READ_PRODUCT_DEFINITION',
          'scope',jsonb_build_object('target_type','PANTALLA')
        )
      ),
      'LF-P0-VALIDATION-TRANSACTION'
    );

    -- C01. The UI operation must receive the existing required token policy.
    v_visual_request:=public.lf_profile_policy_selection_prepare_v1(v_visual_id);
    IF v_visual_request->>'status' IS DISTINCT FROM 'READY'
       OR (v_visual_request->>'candidate_count')::integer IS DISTINCT FROM 1
       OR v_visual_request#>>'{candidate_policies,0,policy_code}'
          IS DISTINCT FROM 'LF-DESIGN-TOKEN-REFERENCE-POLICY-V1'
       OR v_visual_request#>>'{candidate_policies,0,required}' IS DISTINCT FROM 'true' THEN
       RAISE EXCEPTION 'LF_P0_C01_REQUIRED_DISCOVERY_FAILED:%',v_visual_request;
    END IF;
    v_assertions:=v_assertions+1;

    -- C02. Semantic NONE must never discard a required policy.
    v_result:=public.lf_profile_policy_selection_finalize_v1(
      v_visual_request,jsonb_build_object(
        'decision','NONE','selected_policy_codes','[]'::jsonb,
        'reason','negative test of required policy'));
    IF v_result->>'status' IS DISTINCT FROM 'BLOCKED'
       OR v_result->>'blocking_code'
          IS DISTINCT FROM 'POLICY_SELECTION_REQUIRED_POLICY_OMITTED' THEN
       RAISE EXCEPTION 'LF_P0_C02_REQUIRED_POLICY_OMISSION_ALLOWED:%',v_result;
    END IF;
    v_assertions:=v_assertions+1;

    -- C03. An authentic, selected required policy passes.
    v_result:=public.lf_profile_policy_selection_finalize_v1(
      v_visual_request,jsonb_build_object(
        'decision','SELECTED',
        'selected_policy_codes',jsonb_build_array('LF-DESIGN-TOKEN-REFERENCE-POLICY-V1'),
        'reason','positive test of current required policy'));
    IF v_result->>'status' IS DISTINCT FROM 'VALID'
       OR v_result->>'selected_policy_count' IS DISTINCT FROM '1'
       OR v_result#>>'{selected_policies,0,policy_code}'
          IS DISTINCT FROM 'LF-DESIGN-TOKEN-REFERENCE-POLICY-V1' THEN
       RAISE EXCEPTION 'LF_P0_C03_CANONICAL_POLICY_REJECTED:%',v_result;
    END IF;
    v_assertions:=v_assertions+1;

    -- C04. Changing a canonical request digest makes it stale/forged.
    v_result:=public.lf_profile_policy_selection_finalize_v1(
      jsonb_set(v_visual_request,'{candidate_set_sha256}',to_jsonb('FORGED'::text)),
      jsonb_build_object(
        'decision','SELECTED',
        'selected_policy_codes',jsonb_build_array('LF-DESIGN-TOKEN-REFERENCE-POLICY-V1'),
        'reason','negative test of digest tampering'));
    IF v_result->>'status' IS DISTINCT FROM 'BLOCKED'
       OR v_result->>'blocking_code' IS DISTINCT FROM 'POLICY_SELECTION_REQUEST_STALE_OR_FORGED' THEN
       RAISE EXCEPTION 'LF_P0_C04_FORGED_DIGEST_ACCEPTED:%',v_result;
    END IF;
    v_assertions:=v_assertions+1;

    -- C05. A candidate outside the authentic shortlist must be rejected.
    v_result:=public.lf_profile_policy_selection_finalize_v1(
      v_visual_request,jsonb_build_object(
        'decision','SELECTED','selected_policy_codes',jsonb_build_array('FORGED_OUTSIDE_POLICY'),
        'reason','negative test of shortlist expansion'));
    IF v_result->>'status' IS DISTINCT FROM 'BLOCKED'
       OR v_result->>'blocking_code' IS DISTINCT FROM 'POLICY_SELECTION_OUTSIDE_SHORTLIST_FORBIDDEN' THEN
       RAISE EXCEPTION 'LF_P0_C05_OUTSIDE_SHORTLIST_ACCEPTED:%',v_result;
    END IF;
    v_assertions:=v_assertions+1;

    -- C06. Duplicate policy codes must be rejected deterministically.
    v_result:=public.lf_profile_policy_selection_finalize_v1(
      v_visual_request,jsonb_build_object(
        'decision','SELECTED',
        'selected_policy_codes',jsonb_build_array(
          'LF-DESIGN-TOKEN-REFERENCE-POLICY-V1',
          'LF-DESIGN-TOKEN-REFERENCE-POLICY-V1'
        ),
        'reason','duplicate policy test'));
    IF v_result->>'status' IS DISTINCT FROM 'BLOCKED'
       OR v_result->>'blocking_code' IS DISTINCT FROM 'POLICY_SELECTION_CODES_INVALID' THEN
       RAISE EXCEPTION 'LF_P0_C06_DUPLICATES_ACCEPTED:%',v_result;
    END IF;
    v_assertions:=v_assertions+1;

    -- C07. No-policy execution is permitted (READ does not match visual UPDATE).
    v_read_request:=public.lf_profile_policy_selection_prepare_v1(v_read_id);
    IF v_read_request->>'status' IS DISTINCT FROM 'READY'
       OR v_read_request->>'candidate_count' IS DISTINCT FROM '0' THEN
       RAISE EXCEPTION 'LF_P0_C07_NO_POLICY_DISCOVERY_FAILED:%',v_read_request;
    END IF;
    v_result:=public.lf_profile_policy_selection_finalize_v1(
      v_read_request,jsonb_build_object(
        'decision','NONE','selected_policy_codes','[]'::jsonb,
        'reason','zero matching policies are permitted'));
    IF v_result->>'status' IS DISTINCT FROM 'VALID'
       OR v_result->>'selected_policy_count' IS DISTINCT FROM '0' THEN
       RAISE EXCEPTION 'LF_P0_C07_NO_POLICY_EXECUTION_BLOCKED:%',v_result;
    END IF;
    v_assertions:=v_assertions+1;

    -- C08. Candidate discovery never crosses the LF/SALY business boundary.
    v_discovery:=public.lf_profile_policy_deterministic_discovery_v1(
      'PERFIL-UI-ARCHITECT','SALY','PRODUCTO','UPDATE','PANTALLA');
    IF v_discovery->>'candidate_count' IS DISTINCT FROM '0' THEN
       RAISE EXCEPTION 'LF_P0_C08_CROSS_BUSINESS_POLICY_LEAK:%',v_discovery;
    END IF;
    v_assertions:=v_assertions+1;

    -- C09. A temporary OPTIONAL policy can be semantically omitted.
    -- This row is never committed; its source is a test marker, not authority.
    INSERT INTO private.lf_reusable_policy_registry_v1 (
      policy_code,status,business_scope,channel_scope,capabilities_any,
      action_families_any,asset_types_any,semantic_descriptor,
      execution_constraints,source_ref,priority,required
    ) VALUES (
      v_optional_policy,'VIGENTE',ARRAY['LF']::text[],ARRAY['PRODUCTO']::text[],
      ARRAY['DESIGN_TOKENS']::text[],ARRAY['READ']::text[],ARRAY['PANTALLA']::text[],
      'Non-authoritative optional selection test only',
      '[]'::jsonb,'test://lf-p0/rollback-only',999,false
    );
    v_optional_request:=public.lf_profile_policy_selection_prepare_v1(v_read_id);
    IF v_optional_request->>'status' IS DISTINCT FROM 'READY'
       OR v_optional_request->>'candidate_count' IS DISTINCT FROM '1'
       OR v_optional_request#>>'{candidate_policies,0,required}' IS DISTINCT FROM 'false' THEN
       RAISE EXCEPTION 'LF_P0_C09_OPTIONAL_DISCOVERY_FAILED:%',v_optional_request;
    END IF;
    v_result:=public.lf_profile_policy_selection_finalize_v1(
      v_optional_request,jsonb_build_object(
        'decision','NONE','selected_policy_codes','[]'::jsonb,
        'reason','optional selection may be empty'));
    IF v_result->>'status' IS DISTINCT FROM 'VALID'
       OR v_result->>'selected_policy_count' IS DISTINCT FROM '0' THEN
       RAISE EXCEPTION 'LF_P0_C09_OPTIONAL_POLICY_OMISSION_BLOCKED:%',v_result;
    END IF;
    v_assertions:=v_assertions+1;

    -- C10. A valid optional-only selection is also permitted.
    v_result:=public.lf_profile_policy_selection_finalize_v1(
      v_optional_request,jsonb_build_object(
        'decision','SELECTED','selected_policy_codes',jsonb_build_array(v_optional_policy),
        'reason','optional selection positive control'));
    IF v_result->>'status' IS DISTINCT FROM 'VALID'
       OR v_result->>'selected_policy_count' IS DISTINCT FROM '1' THEN
       RAISE EXCEPTION 'LF_P0_C10_OPTIONAL_SELECTION_REJECTED:%',v_result;
    END IF;
    v_assertions:=v_assertions+1;

    -- The deliberate exception rolls back ALL above fixtures/changes even
    -- when the assertions pass. Never change this into a normal return.
    RAISE EXCEPTION 'LF_P0_FIXTURE_ROLLBACK_SENTINEL';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS DISTINCT FROM 'LF_P0_FIXTURE_ROLLBACK_SENTINEL' THEN
      RAISE;
    END IF;
    v_rollback_verified:=true;
  END;

  -- C11: rollback confirmation in the outer transaction (no fixture leakage).
  IF v_rollback_verified IS NOT TRUE
     OR v_assertions<>10
     OR EXISTS (
       SELECT 1 FROM public.lf_operation_execution
       WHERE execution_id IN (v_visual_id,v_read_id)
     )
     OR EXISTS (
       SELECT 1 FROM private.lf_reusable_policy_registry_v1
       WHERE policy_code=v_optional_policy
     ) THEN
    RAISE EXCEPTION 'LF_P0_C11_ROLLBACK_OR_ASSERTION_COUNT_FAILED';
  END IF;

  RAISE NOTICE 'LF_P0_POLICY_TRANSACTIONAL_PROOF PASS assertions=11 fixtures_persisted=0';
END;
$lf_p0_verify$;

COMMIT;