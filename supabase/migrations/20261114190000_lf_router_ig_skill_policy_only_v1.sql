-- LF sandbox-only architecture alignment. Owner 2026-11-14 12:50 Lima.
-- IG is policy-selected optional skill, never Router contract/gate.
-- Strict preimage guards; the four original handoff/authority functions are untouched.
BEGIN;
DO $lf$
DECLARE
 v_src text;
 v_old text;
 v_new text;
 v_start integer;
 v_end integer;
 v_count integer;
 v_profile text;
 v_profiles constant text[]:=ARRAY[
 'ACT-0051',
 'PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING',
 'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531',
 'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF',
 'PERFIL-GAMIFICATION-SYSTEM-ARCHITECT',
 'PERFIL-PRODUCT-DIRECTOR-LF',
 'PERFIL-QUALITY-PACK',
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
 'PERFIL-UI-ARCHITECT',
 'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
 ];
 v_router_oid oid;
 v_oid oid;
 v_md5 text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('LF_IG_ROUTER_SKILL_POLICY_ONLY_V1'));
  -- Exactly 10 enabled READ_ONLY IG policies, with 9 mandatory and 1
  -- semantic-optional already applied by #3911. Fail on any unreviewed row.
  IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK')<>10
    OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' AND selection_mode='DETERMINISTIC_REQUIRED')<>9
    OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' AND selection_mode='SEMANTIC_OPTIONAL')<>1
    OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' AND profile_code=ANY(v_profiles)
      AND required_operation='EJECUCION_PERFIL_LF'
      AND enabled AND NOT owner_decision_required
      AND allowed_effects=ARRAY['READ_ONLY']::text[])<>10
    OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
        AND profile_code='PERFIL-PRODUCT-DIRECTOR-LF'
        AND selection_mode='SEMANTIC_OPTIONAL'
        AND applicability_contract->>'evaluation'='PROFILE_OWNED_SEMANTIC_SKILL_SELECTION')<>1
  THEN RAISE EXCEPTION 'LF_IG_POLICY_9_PLUS_1_PREIMAGE_DRIFT'; END IF;
  IF NOT EXISTS (
     SELECT 1 FROM public.lf_skill_catalog_v1 c
     JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
     WHERE c.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
       AND c.status='READY' AND c.effect='READ_ONLY'
       AND d.descriptor_status='CURRENT'
       AND d.descriptor->>'schema_version'='LF_SKILL_SELECTION_DESCRIPTOR_V1'
       AND nullif(d.source_revision,'') IS NOT NULL
  ) THEN RAISE EXCEPTION 'LF_IG_DESCRIPTOR_NOT_CURRENT'; END IF;
  UPDATE public.lf_skill_selector_policy_v1
  SET selection_mode='SEMANTIC_OPTIONAL',
      -- Applicability is now the authenticated native semantic choice in
      -- lf_profile_execution_plan_v1, not EVIDENCE_PAYLOAD or an IG gate.
      -- only_if_applicable=true is unsupported by invoker unless it carries
      -- a Step40 evidence path. Eliminate this false policy-contract block.
      applicability_contract=jsonb_build_object(
        'evaluation','PROFILE_OWNED_SEMANTIC_SKILL_SELECTION',
        'only_if_applicable',false,
        'selection_required',true,
        'no_content_block_of_profile',true,
        'source','OWNER_POLICY_2026_11_14_1250_LIMA'),
      policy_evidence_ref='owner://lf/2026-11-14/router-ig-fully-decoupled-semantic-optional',
      updated_at=now()
  WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
    AND profile_code=ANY(v_profiles);
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>10 THEN RAISE EXCEPTION 'LF_IG_POLICY_WRITE_COUNT_MISMATCH:%',v_count; END IF;
  IF EXISTS (SELECT 1 FROM public.lf_skill_selector_policy_v1
      WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
        AND (selection_mode<>'SEMANTIC_OPTIONAL' OR
             applicability_contract->>'only_if_applicable'<>'false'))
  THEN RAISE EXCEPTION 'LF_IG_POLICY_STILL_MANDATORY'; END IF;

  -- Remove the entire Router IG derivation and blocking branch, for ALL
  -- operations. All operation/contract/policy/adapter/authority gates survive.
  SELECT p.oid,pg_get_functiondef(p.oid) INTO v_router_oid,v_old
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='lf_router_resolve_core_v1';
  IF v_router_oid IS NULL OR md5(v_old)<>'ebb137df72e52c016e0e66c24035aeaf'
  THEN RAISE EXCEPTION 'LF_ROUTER_CORE_PREIMAGE_DRIFT'; END IF;
  v_start:=strpos(v_old,
    E'  if jsonb_array_length(v_adapters)>0\n     and v_operation.operation_code is distinct from ''ACTUALIZACION_PERFIL_LF'' then');
  v_end:=strpos(v_old,
    E'\n  return jsonb_build_object(\n    ''status'',''READY_TO_EXECUTE''');
  IF v_start=0 OR v_end<=v_start OR
      position('fn_lf_router_input_governance_derive_v1' in substr(v_old,v_start,v_end-v_start))=0
  THEN RAISE EXCEPTION 'LF_ROUTER_IG_BLOCK_ANCHOR_DRIFT'; END IF;
  v_new:=substr(v_old,1,v_start-1)
      || E'  -- IG is a selected READ_ONLY skill of the profile, never a Router branch.\n\n'
      || substr(v_old,v_end+1);
  IF position('  v_input_governance jsonb := null;' in v_new)=0
  THEN RAISE EXCEPTION 'LF_ROUTER_IG_DECLARATION_DRIFT'; END IF;
  v_new:=replace(v_new,E'  v_input_governance jsonb := null;\n','');
  IF position(
    E'  ) || case when v_input_governance is null then ''{}''::jsonb else jsonb_build_object(''input_governance'',v_input_governance) end;'
    in v_new)=0 THEN
      RAISE EXCEPTION 'LF_ROUTER_IG_FINAL_RETURN_DRIFT';
  END IF;
  v_new:=replace(v_new,
    E'  ) || case when v_input_governance is null then ''{}''::jsonb else jsonb_build_object(''input_governance'',v_input_governance) end;',
    E'  );');
  IF position('fn_lf_router_input_governance_derive_v1' in v_new)>0
     OR position('v_input_governance' in v_new)>0
  THEN RAISE EXCEPTION 'LF_ROUTER_IG_REFERENCE_LEFTOVER'; END IF;
  EXECUTE v_new;
  IF position('fn_lf_router_input_governance_derive_v1'
       IN pg_get_functiondef(v_router_oid))>0
     OR position('v_input_governance' IN pg_get_functiondef(v_router_oid))>0
  THEN RAISE EXCEPTION 'LF_ROUTER_IG_SOURCE_DEPENDENCY_REMAINED'; END IF;

  -- CONTENT-only ambiguity is a finding, never an effect authority grant.
  -- Keep broken adapter metadata, unauthorized consumers, contract faults and
  -- ACTION_AUTHORIZATION_GATE fail-closed exactly as they were.
  FOR v_profile,v_md5 IN
    SELECT x.fn,x.expected_md5 FROM (VALUES
      ('fn_lf_router_input_governance_derive_v1','4b345c4659c8f7ce4af15064db11b82b'),
      ('fn_lf_profile_adapter_input_governance_resolve_v1','99bd5fa7024987dbe6e4018a9e87d81b')
    ) x(fn,expected_md5)
  LOOP
    SELECT p.oid,pg_get_functiondef(p.oid) INTO v_oid,v_old
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='programacion' AND p.proname=v_profile;
    IF v_oid IS NULL OR md5(v_old)<>v_md5
    THEN RAISE EXCEPTION 'LF_IG_RESOLVER_PREIMAGE_DRIFT:%',v_profile; END IF;
    v_start:=strpos(v_old,'  if v_screen_count > 1 then');
    v_end:=strpos(substr(v_old,v_start),E'\n  end if;');
    IF v_start=0 OR v_end<=0 OR
      position('BLOCK_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS' in substr(v_old,v_start,v_end))=0
    THEN RAISE EXCEPTION 'LF_IG_AMBIGUITY_BLOCK_DRIFT:%',v_profile; END IF;
    v_new:=substr(v_old,1,v_start-1)
      || E'  if v_screen_count > 1 then\n'
      || E'    return jsonb_build_object(\n'
      || E'      ''applicable'',true,''status'',''INPUT_GOVERNANCE_REQUIRED'',\n'
      || E'      ''blocking_code'',''BLOCK_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS'',\n'
      || E'      ''decision'',''FINDING'',''continuation_allowed'',true,\n'
      || E'      ''finding_class'',''INPUT_GOVERNANCE_CONTENT'',\n'
      || E'      ''finding_code'',''BLOCK_INPUT_GOVERNANCE_SUBJECT_AMBIGUOUS'',\n'
      || E'      ''remediation_action'',''RESOLVE_CURRENT_SCREEN_SHORTLIST'',\n'
      || E'      ''analysis_only'',true,''production_authorized'',false,\n'
      || E'      ''promotion_authorized'',false,\n'
      || E'      ''required_by_adapters'',v_required_adapters,\n'
      || E'      ''screen_matches'',v_screen_matches);\n'
      || E'  end if;'
      || substr(v_old,v_start+v_end+length(E'\n  end if;')-1);
    IF position('fn_lf_router_input_governance_derive_v1' in v_new)>0 AND
       v_profile='fn_lf_profile_adapter_input_governance_resolve_v1' THEN
      RAISE EXCEPTION 'LF_IG_ADAPTER_UNEXPECTED_ROUTER_LINK';
    END IF;
    EXECUTE v_new;
    IF position(E'''decision'',''FINDING'',''continuation_allowed'',true'
       in pg_get_functiondef(v_oid))=0 THEN
       RAISE EXCEPTION 'LF_IG_AMBIGUOUS_CONTENT_NOT_FAILOPEN:%',v_profile;
    END IF;
  END LOOP;
  -- The skill-specific resolver may run only after the native invoker
  -- has selected the skill by policy. A redundant DIRECT_PROFILE relation
  -- must never silently veto any of the 10 policy-eligible profiles.
  SELECT p.oid,pg_get_functiondef(p.oid) INTO v_oid,v_old
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion'
    AND p.proname='fn_lf_profile_input_governance_resolve_v1';
  IF v_oid IS NULL OR md5(v_old)<>'1f9881b62d53a44994e108b7ee197cbe'
  THEN RAISE EXCEPTION 'LF_IG_PROFILE_RESOLVER_PREIMAGE_DRIFT'; END IF;
  v_start:=strpos(v_old,'  SELECT EXISTS(');
  v_end:=strpos(v_old,E'\n  IF NOT v_bound THEN');
  IF v_start<=0 OR v_end<=v_start OR
    position('input_governance_binding_mode' in substr(v_old,v_start,v_end-v_start))=0
  THEN RAISE EXCEPTION 'LF_IG_PROFILE_DIRECT_BINDING_ANCHOR_DRIFT'; END IF;
  v_new:=substr(v_old,1,v_start-1)
    || E'  -- Consumer identity is a flow authority, not a content finding.\n'
    || E'  IF p_consumer IS DISTINCT FROM ''CONTEXT_PACK'' THEN\n'
    || E'    RETURN jsonb_build_object(''applicable'',true,''status'',''BLOCKED'',\n'
    || E'      ''blocking_code'',''BLOCK_INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED'',\n'
    || E'      ''decision'',''BLOCKED'',''continuation_allowed'',false,\n'
    || E'      ''flow_block_cause'',''AUTHORITY_INVALID'',''production_authorized'',false);\n'
    || E'  END IF;\n'
    || E'  -- Handler invocation was independently selected by\n'
    || E'  -- public.lf_profile_skill_invoke_selected_v1 (native policy).\n'
    || E'  SELECT EXISTS(SELECT 1 FROM public.lf_skill_selector_policy_v1 p\n'
    || E'    JOIN public.lf_skill_catalog_v1 c USING(skill_code)\n'
    || E'    JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)\n'
    || E'    WHERE p.profile_code=p_profile_code\n'
    || E'      AND p.skill_code=''INPUT_GOVERNANCE_CONTEXT_PACK''\n'
    || E'      AND p.selection_mode=''SEMANTIC_OPTIONAL''\n'
    || E'      AND p.enabled AND NOT p.owner_decision_required\n'
    || E'      AND p.required_operation=''EJECUCION_PERFIL_LF''\n'
    || E'      AND p.allowed_effects=ARRAY[''READ_ONLY'']::text[]\n'
    || E'      AND c.status=''READY'' AND c.effect=''READ_ONLY''\n'
    || E'      AND d.descriptor_status=''CURRENT''\n'
    || E'      AND d.descriptor->>''schema_version''=''LF_SKILL_SELECTION_DESCRIPTOR_V1''\n'
    || E'  ) INTO v_bound;\n'
    || substr(v_old,v_end+1);
  v_new:=replace(v_new,'''NO_DIRECT_PROFILE_BINDING''',
    '''NO_OPTIONAL_IG_POLICY''');
  v_new:=replace(v_new,'''DIRECT_PROFILE''',
    '''SKILL_POLICY_BOUND''');
  IF position('input_governance_binding_mode' in v_new)>0 OR
     position('lf_activo_relaciones' in v_new)>0 OR
     position('DIRECT_PROFILE' in v_new)>0 THEN
    RAISE EXCEPTION 'LF_IG_PROFILE_METADATA_BINDING_REMAINED';
  END IF;
  EXECUTE v_new;
  IF position('lf_activo_relaciones' in pg_get_functiondef(v_oid))>0 OR
     position('DIRECT_PROFILE' in pg_get_functiondef(v_oid))>0 OR
     position('lf_skill_selector_policy_v1' in pg_get_functiondef(v_oid))=0 THEN
    RAISE EXCEPTION 'LF_IG_PROFILE_POLICY_RESOLVER_NOT_EFFECTIVE';
  END IF;
END $lf$;
COMMIT;
