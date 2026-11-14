-- LF sandbox only. Owner 2026-11-14: demonstrate BOTH runs, with and without selected IG.
-- Exact current row (2026-11-14 SELECT): IG was DETERMINISTIC_REQUIRED even though
-- Step40 already generic and owner requires skill semantic selection by task.
-- Preserve caller/Router/handoff/authority contracts and every non-IG skill.
BEGIN;
DO $policy$
DECLARE
  v_row public.lf_skill_selector_policy_v1%ROWTYPE;
  v_count integer;
BEGIN
  SELECT * INTO v_row
  FROM public.lf_skill_selector_policy_v1
  WHERE profile_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
  FOR UPDATE;
  IF NOT FOUND OR v_row.selection_mode<>'DETERMINISTIC_REQUIRED'
    OR v_row.channels<>ARRAY['PRODUCTO']::text[]
    OR v_row.required_operation<>'EJECUCION_PERFIL_LF'
    OR v_row.allowed_effects<>ARRAY['READ_ONLY']::text[]
    OR v_row.enabled IS NOT TRUE OR v_row.owner_decision_required IS NOT FALSE
    OR v_row.applicability_contract<>'{"source":"PROFILE_CURRENT_POLICY","owner_instruction":"2026-11-14","only_if_applicable":false}'::jsonb
    OR v_row.policy_evidence_ref<>'owner://lf/2026-11-14/skill-policy-active-by-design'
  THEN RAISE EXCEPTION 'LF_IG_DUAL_RUN_POLICY_PREIMAGE_DRIFT'; END IF;
  -- NONE means no IG selected; other read-only skill can still be selected.
  -- Selection must be authored by native profile and bound to current descriptor.
  UPDATE public.lf_skill_selector_policy_v1
  SET selection_mode='SEMANTIC_OPTIONAL',
      applicability_contract=jsonb_build_object(
        'source','OWNER_DUAL_RUN_MANDATE_2026_11_14',
        'evaluation','PROFILE_OWNED_SEMANTIC_SKILL_SELECTION',
        'only_if_applicable',true,
        'no_content_block_of_profile',true),
      policy_evidence_ref='owner://lf/2026-11-14/dual-run-ig-selected-versus-not-selected',
      updated_at=now()
  WHERE profile_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_IG_DUAL_RUN_POLICY_WRITE_COUNT_DRIFT'; END IF;
  IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE profile_code='PERFIL-PRODUCT-DIRECTOR-LF' AND skill_code='SCREEN_RULES_SNAPSHOT'
        AND selection_mode='SEMANTIC_OPTIONAL' AND enabled AND NOT owner_decision_required
     )<>1 THEN RAISE EXCEPTION 'LF_IG_DUAL_RUN_OTHER_OPTIONAL_SKILL_DRIFT'; END IF;
END $policy$;
COMMIT;
