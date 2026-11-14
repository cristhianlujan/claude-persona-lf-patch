-- LF / skill selector owner decision: 2026-11-14 04:20 America/Lima.
-- Owner instruction in the current LF conversation: all 18 existing rows of
-- public.lf_skill_selector_policy_v1 become enabled=true,
-- owner_decision_required=false; preserve per-skill modes, permissions and applicability.
-- SOURCE_FIRST, one data migration, no changes to RUNs, Step40 or skill sources.
-- Documentary owner decision; does NOT claim cryptographically verified identity.
-- Evidence identifier for the decision in this migration:
-- owner-decision://lf/2026-11-14T04:20:00-05:00/lf_skill_selector_policy_v1/enable-18
--
-- IMPORTANT: the present live baseline has INPUT_GOVERNANCE_CONTEXT_PACK DRAFT,
-- descriptor STALE_SOURCE_CHANGED, missing handler
-- public.lf_skill_h_input_governance_context_pack_v1(jsonb), and no CURRENT
-- descriptor for SCREEN_RULES_SNAPSHOT. Enabling policies before those actual
-- dependencies become READY would turn the previously working 0-enabled Step40
-- compatibility result into SKILL_DETERMINISTIC_POLICY_OR_CATALOG_INVALID.
-- The atomic preflight deliberately refuses to mutate policy rows in that state.
-- This migration does NOT forge a handler or promote stale descriptor source.

DO $lf_skill_owner_activation_18_v1$
DECLARE
  v_all integer;
  v_pre integer;
  v_post integer;
  v_bad integer;
  v_probe jsonb;
  v_choice_revision text;
  v_evidence constant text :=
    'owner-decision://lf/2026-11-14T04:20:00-05:00/lf_skill_selector_policy_v1/enable-18';
BEGIN
  -- A consistent source snapshot and row lock prevent a split update.
  LOCK TABLE public.lf_skill_selector_policy_v1 IN SHARE ROW EXCLUSIVE MODE;

  SELECT count(*),
         count(*) FILTER (WHERE enabled IS FALSE AND owner_decision_required IS TRUE)
    INTO v_all, v_pre
    FROM public.lf_skill_selector_policy_v1;
  IF v_all <> 18 OR v_pre <> 18 THEN
    RAISE EXCEPTION 'LF_SKILL_OWNER_POLICY_PREIMAGE_DRIFT:all=%,disabled_pending=%',
      v_all,v_pre USING ERRCODE='P0001';
  END IF;

  IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK') <> 10
     OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='SCREEN_RULES_SNAPSHOT') <> 7
     OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='PROFILE_UPDATE_APPLY') <> 1
     OR (SELECT count(*) FROM
      (SELECT DISTINCT profile_code,skill_code,required_operation
       FROM public.lf_skill_selector_policy_v1) t) <> 18
  THEN RAISE EXCEPTION 'LF_SKILL_OWNER_POLICY_BINDING_DRIFT'
       USING ERRCODE='P0001';
  END IF;

  -- Existing selector requires catalog READY, matching effects/operations,
  -- CURRENT descriptors and the separate write authority where applicable.
  SELECT count(*) INTO v_bad
    FROM public.lf_skill_selector_policy_v1 p
    LEFT JOIN public.lf_skill_catalog_v1 c ON c.skill_code=p.skill_code
    LEFT JOIN public.lf_skill_selection_registry_v1 d ON d.skill_code=p.skill_code
    WHERE c.skill_code IS NULL OR c.status<>'READY'
       OR c.required_operation<>p.required_operation
       OR NOT(c.effect=ANY(p.allowed_effects))
       OR d.skill_code IS NULL OR d.descriptor_status<>'CURRENT'
       OR d.descriptor->>'schema_version'<>'LF_SKILL_SELECTION_DESCRIPTOR_V1'
       OR nullif(btrim(coalesce(d.source_revision,'')),'') IS NULL
       OR (c.effect='WRITE_GOVERNED' AND NOT EXISTS (
         SELECT 1 FROM public.lf_profile_write_authority_v1 a
         WHERE a.profile_code=p.profile_code
           AND a.operation_code=c.required_operation AND a.status='ACTIVE'));
  IF v_bad<>0 THEN
    RAISE EXCEPTION 'LF_SKILL_OWNER_POLICY_DEPENDENCY_NOT_READY:invalid_bindings=%',
      v_bad USING ERRCODE='P0001';
  END IF;

  IF to_regprocedure(
    'public.lf_skill_h_input_governance_context_pack_v1(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'LF_SKILL_OWNER_POLICY_IG_HANDLER_MISSING'
      USING ERRCODE='P0001';
  END IF;

  UPDATE public.lf_skill_selector_policy_v1
     SET enabled=TRUE,
         owner_decision_required=FALSE,
         policy_evidence_ref=v_evidence,
         updated_at=clock_timestamp()
   WHERE enabled IS FALSE AND owner_decision_required IS TRUE;
  GET DIAGNOSTICS v_post=ROW_COUNT;
  IF v_post<>18 THEN
    RAISE EXCEPTION 'LF_SKILL_OWNER_POLICY_WRITE_COUNT_MISMATCH:%',v_post
      USING ERRCODE='P0001';
  END IF;
  IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE enabled AND NOT owner_decision_required
        AND policy_evidence_ref=v_evidence)<>18 THEN
    RAISE EXCEPTION 'LF_SKILL_OWNER_POLICY_READBACK_MISMATCH'
      USING ERRCODE='P0001';
  END IF;

  -- A semantic option needs an actual explicit selection: a no-input call
  -- correctly returns SEMANTIC_SELECTION_REQUIRED, not READY.
  SELECT d.source_revision INTO v_choice_revision
    FROM public.lf_skill_selection_registry_v1 d
   WHERE d.skill_code='SCREEN_RULES_SNAPSHOT' AND d.descriptor_status='CURRENT';
  SELECT public.lf_profile_skill_selection_prepare_v1(
    'PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',
    jsonb_build_object(
      'selected_skill_code','SCREEN_RULES_SNAPSHOT',
      'reason','OWNER_ACTIVATED_SEMANTIC_OPTION_WITH_CURRENT_SOURCE',
      'review_mode','CURRENT_CONTEXT_REVIEW',
      'descriptor_revision',v_choice_revision,
      'evidence_refs',jsonb_build_array(v_evidence)
    )
  ) INTO v_probe;
  IF v_probe->>'status'<>'READY'
     OR (SELECT count(*) FROM jsonb_array_elements(coalesce(v_probe->'skills','[]'::jsonb)) x
         WHERE x->>'skill_code' IN (
          'INPUT_GOVERNANCE_CONTEXT_PACK','SCREEN_RULES_SNAPSHOT'))<>2
  THEN
    RAISE EXCEPTION 'LF_SKILL_OWNER_POLICY_POST_READY_FAILED:status=%',
      coalesce(v_probe->>'status','NULL') USING ERRCODE='P0001';
  END IF;
END;
$lf_skill_owner_activation_18_v1$;
