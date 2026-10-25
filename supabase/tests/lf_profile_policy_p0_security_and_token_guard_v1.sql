-- LF P0 policy-selection + design-token guard regression, transactional.
-- Run only after both P0 migrations in an isolated test DB or governed test lane.
-- Explicit ROLLBACK; never leave test components behind.
BEGIN;

DO $suite$
DECLARE
  v_result jsonb;
  v_discovery jsonb;
  v_request jsonb;
  v_current_exec text;
  v_request_current jsonb;
  v_selected jsonb;
  v_error text;
  v_id bigint;
BEGIN
  -- C01: PostgreSQL regex must identify HEX / RGB and leave token codes untouched.
  IF '#FEE2E2' !~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()'
     OR '#991B1B' !~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()'
     OR 'rgba(1,2,3,1)' !~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()'
     OR 'error_bg' ~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()' THEN
    RAISE EXCEPTION 'P0_C01_LITERAL_REGEX_REGRESSION';
  END IF;

  -- C02: a governed binding outside the known color-key list is still rejected.
  v_error:=NULL;
  BEGIN
    INSERT INTO lf_design.component_tokens(
      component_token_code,design_system_code,component_name,component_state,
      token_bindings,allowed_usage,blocked_usage,status,
      source_decision_id,notes,design_system_id,component_token_id
    ) VALUES (
      '__P0_POLICY_HEX_GUARD__','LF_DS_V1','p0_test','default',
      jsonb_build_object('new_visual_property','#991B1B'),
      'p0 test','p0 test','CANDIDATO','__P0_POLICY_TEST__',
      'rollback-only regression check',1,
      (SELECT coalesce(max(component_token_id),0)+1000001 FROM lf_design.component_tokens)
    );
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'DESIGN_TOKEN_LITERAL_COLOR_FORBIDDEN' THEN
    RAISE EXCEPTION 'P0_C02_UNEXPECTED_GUARD_RESPONSE:%',coalesce(v_error,'NO_ERROR');
  END IF;

  -- C03: a real current token reference must still be admitted.
  INSERT INTO lf_design.component_tokens(
    component_token_code,design_system_code,component_name,component_state,
    token_bindings,allowed_usage,blocked_usage,status,
    source_decision_id,notes,design_system_id,component_token_id
  ) VALUES (
    '__P0_POLICY_CANONICAL_GUARD__','LF_DS_V1','p0_test','default',
    jsonb_build_object('background','error_bg','border','error_text','text','error_text'),
    'p0 test','p0 test','CANDIDATO','__P0_POLICY_TEST__',
    'rollback-only regression check',1,
    (SELECT coalesce(max(component_token_id),0)+1000002 FROM lf_design.component_tokens)
  );

  -- C03B: unchanged existing visual evidence is accepted on normal update.
  -- This is a transaction rolled back in full below.
  UPDATE lf_design.component_tokens
  SET token_bindings=token_bindings
  WHERE component_token_code='client_auth_watermark'
    AND token_bindings ? 'expected_visible_color_range';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'P0_C03B_VISUAL_EVIDENCE_FIXTURE_MISSING';
  END IF;

  -- C03C: changing a former evidence literal is not grandfathered.
  v_error:=NULL;
  BEGIN
    UPDATE lf_design.component_tokens
    SET token_bindings=jsonb_set(token_bindings,
      '{expected_visible_color_range,0}',to_jsonb('#001122'::text),true)
    WHERE component_token_code='client_auth_watermark';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'DESIGN_TOKEN_LITERAL_COLOR_FORBIDDEN' THEN
    RAISE EXCEPTION 'P0_C03C_CHANGED_EVIDENCE_FALSE_PASS:%',coalesce(v_error,'NO_ERROR');
  END IF;

  -- C04: canonical discovery labels this governed visual policy as required.
  v_discovery:=public.lf_profile_policy_deterministic_discovery_v1(
    'PERFIL-UI-ARCHITECT','LF','PRODUCTO','UPDATE','PANTALLA');
  IF v_discovery->>'candidate_count'<>'1'
     OR v_discovery#>>'{candidate_policies,0,policy_code}'<>'LF-DESIGN-TOKEN-REFERENCE-POLICY-V1'
     OR v_discovery#>>'{candidate_policies,0,required}'<>'true' THEN
    RAISE EXCEPTION 'P0_C04_MANDATORY_DISCOVERY_REGRESSION:%',v_discovery;
  END IF;

  -- C05: forged or nonexistent execution cannot attest a fabricated shortlist.
  v_request:=jsonb_build_object(
    'schema_version','LF_PROFILE_POLICY_SEMANTIC_REQUEST_V1',
    'status','READY','execution_id','__NO_SUCH_EXECUTION_P0__',
    'candidate_set_sha256','FORGED',
    'candidate_policies',jsonb_build_array(
      jsonb_build_object('policy_code','INVENTED_POLICY','required',false)));
  v_result:=public.lf_profile_policy_selection_finalize_v1(
    v_request,jsonb_build_object('decision','SELECTED',
      'selected_policy_codes',jsonb_build_array('INVENTED_POLICY'),
      'reason','adversarial provenance test'));
  IF v_result->>'status'<>'BLOCKED'
     OR v_result->>'blocking_code'<>'POLICY_SELECTION_REQUEST_STALE_OR_FORGED' THEN
    RAISE EXCEPTION 'P0_C05_FORGED_SHORTLIST_FALSE_PASS:%',v_result;
  END IF;

  -- C06: SALY remains excluded from LF-only policies.
  v_discovery:=public.lf_profile_policy_deterministic_discovery_v1(
    'PERFIL-UI-ARCHITECT','SALY','PRODUCTO','UPDATE','PANTALLA');
  IF v_discovery->>'candidate_count'<>'0' THEN
    RAISE EXCEPTION 'P0_C06_BUSINESS_ISOLATION_FALSE_PASS:%',v_discovery;
  END IF;

  -- C07: do not expose internal SECURITY DEFINER helpers to browser roles.
  IF has_function_privilege('anon','public.lf_profile_policy_selection_finalize_v1(jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_profile_policy_selection_finalize_v1(jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.lf_profile_policy_selection_prepare_v1(text)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_profile_policy_deterministic_discovery_v1(text,text,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'P0_C07_PUBLIC_POLICY_EXECUTE_EXPOSED';
  END IF;

  -- C08-C10: fail closed unless a controlled, authorized, active UI fixture
  -- is explicitly supplied by the isolated DB runner. Never sample arbitrary
  -- production execution records or silently downgrade a missing fixture to PASS.
  v_current_exec:=nullif(btrim(current_setting('lf_p0.fixture_execution_id',true)),'');
  IF v_current_exec IS NULL THEN
    RAISE EXCEPTION 'P0_C08_REQUIRED_POLICY_FIXTURE_NOT_CONFIGURED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution e
    WHERE e.execution_id=v_current_exec
      AND e.operation_code='EJECUCION_PERFIL_LF'
      AND e.target_type='PERFIL'
      AND e.status='IN_PROGRESS'
  ) THEN
    RAISE EXCEPTION 'P0_C08_AUTHORIZED_FIXTURE_NOT_IN_PROGRESS';
  END IF;
  v_request_current:=public.lf_profile_policy_selection_prepare_v1(v_current_exec);
  IF v_request_current->>'status'<>'READY'
     OR NOT EXISTS (
         SELECT 1 FROM jsonb_array_elements(
           coalesce(v_request_current->'candidate_policies','[]'::jsonb)) c
         WHERE c->>'required'='true'
           AND c->>'policy_code'='LF-DESIGN-TOKEN-REFERENCE-POLICY-V1'
       ) THEN
    RAISE EXCEPTION 'P0_C08_REQUIRED_VISUAL_POLICY_FIXTURE_NOT_ELIGIBLE:%',v_request_current;
  END IF;

  -- C08: mandatory policy cannot be semantically removed.
  v_result:=public.lf_profile_policy_selection_finalize_v1(
    v_request_current,jsonb_build_object(
      'decision','NONE','selected_policy_codes','[]'::jsonb,
      'reason','intentional mandatory omission regression'));
  IF v_result->>'status'<>'BLOCKED'
     OR v_result->>'blocking_code'<>'POLICY_SELECTION_REQUIRED_POLICY_OMITTED' THEN
    RAISE EXCEPTION 'P0_C08_REQUIRED_POLICY_FALSE_OMISSION:%',v_result;
  END IF;

  -- C09: selecting every eligible, current policy must succeed.
  SELECT coalesce(jsonb_agg(c->>'policy_code'),'[]'::jsonb) INTO v_selected
  FROM jsonb_array_elements(v_request_current->'candidate_policies') c;
  v_result:=public.lf_profile_policy_selection_finalize_v1(
    v_request_current,jsonb_build_object(
      'decision','SELECTED','selected_policy_codes',v_selected,
      'reason','canonical current mandatory policy selection'));
  IF v_result->>'status'<>'VALID'
     OR v_result->>'selected_policy_count' IS DISTINCT FROM
        (jsonb_array_length(v_selected))::text THEN
    RAISE EXCEPTION 'P0_C09_CANONICAL_REQUEST_FALSE_BLOCK:%',v_result;
  END IF;

  -- C10: even an authentic execution_id may not authorize altered shortlist or hash.
  v_result:=public.lf_profile_policy_selection_finalize_v1(
    jsonb_set(v_request_current,'{candidate_set_sha256}',to_jsonb('FORGED'::text)),
    jsonb_build_object(
      'decision','SELECTED','selected_policy_codes',v_selected,
      'reason','stale or forged shortlist regression'));
  IF v_result->>'status'<>'BLOCKED'
     OR v_result->>'blocking_code'<>'POLICY_SELECTION_REQUEST_STALE_OR_FORGED' THEN
    RAISE EXCEPTION 'P0_C10_AUTHENTIC_EXECUTION_FORGED_DIGEST_FALSE_PASS:%',v_result;
  END IF;

  RAISE NOTICE 'LF P0 assertions C01-C10 PASS in the isolated DB fixture';

END
$suite$;

ROLLBACK;
