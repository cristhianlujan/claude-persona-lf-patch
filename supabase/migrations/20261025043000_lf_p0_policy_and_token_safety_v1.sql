-- LF P0 controlled production migration: atomic security patch.
-- One migration per PR as required by official LF Merge Train.
-- Includes read-only verification before COMMIT; any exception rolls back the patch.
BEGIN;

CREATE OR REPLACE FUNCTION lf_design.guard_component_token_bindings_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'lf_design'
AS $function$
DECLARE
  v_checked_bindings jsonb;
  v_key text;
  v_value jsonb;
  v_sval text;
  v_color_status text;
  v_color_keys constant text[] := ARRAY[
    'background','border','text','body_text','title_text',
    'error_text','success_text','error_background',
    'border_focus','border_default','fill','stroke',
    'hero_title_color','hero_subtitle_color','icon_color'
  ];
BEGIN
  IF NEW.token_bindings IS NULL OR jsonb_typeof(NEW.token_bindings)<>'object' THEN
    RAISE EXCEPTION
      USING ERRCODE='23514',
            MESSAGE='DESIGN_TOKEN_BINDINGS_INVALID_SHAPE',
            DETAIL='component_tokens.token_bindings must be a JSON object.';
  END IF;


  -- Only unchanged legacy evidence may retain literal visual observations.
  -- New values or modifications to either evidence field are still rejected.
  v_checked_bindings := NEW.token_bindings;
  IF TG_OP='UPDATE' THEN
    IF OLD.token_bindings ? 'measured_fill'
       AND NEW.token_bindings->'measured_fill' IS NOT DISTINCT FROM OLD.token_bindings->'measured_fill' THEN
      v_checked_bindings := v_checked_bindings - 'measured_fill';
    END IF;
    IF OLD.token_bindings ? 'expected_visible_color_range'
       AND NEW.token_bindings->'expected_visible_color_range' IS NOT DISTINCT FROM OLD.token_bindings->'expected_visible_color_range' THEN
      v_checked_bindings := v_checked_bindings - 'expected_visible_color_range';
    END IF;
  END IF;

  IF v_checked_bindings::text ~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()' THEN
    RAISE EXCEPTION
      USING ERRCODE='23514',
            MESSAGE='DESIGN_TOKEN_LITERAL_COLOR_FORBIDDEN',
            DETAIL='Use registered token names in token_bindings; literal HEX/RGB/HSL colors are forbidden.';
  END IF;

  FOR v_key,v_value IN
    SELECT key,value
    FROM jsonb_each(NEW.token_bindings)
  LOOP
    IF v_key = ANY(v_color_keys)
       AND jsonb_typeof(v_value)='string'
    THEN
      v_sval:=trim(both '"' from v_value::text);

      SELECT status
        INTO v_color_status
      FROM lf_design.color_tokens
      WHERE token_name=v_sval
      LIMIT 1;

      IF v_color_status IS NULL THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_COLOR_TOKEN_REFERENCE_NOT_FOUND',
                DETAIL=format(
                  'component=%s key=%s value=%s is not a registered lf_design.color_tokens.token_name',
                  NEW.component_token_code,v_key,v_sval
                );
      END IF;

      IF v_color_status='DEPRECADO' THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_COLOR_TOKEN_REFERENCE_DEPRECATED',
                DETAIL=format(
                  'component=%s key=%s token=%s is DEPRECADO',
                  NEW.component_token_code,v_key,v_sval
                );
      END IF;

      IF NEW.status='VIGENTE' AND v_color_status<>'VIGENTE' THEN
        RAISE EXCEPTION
          USING ERRCODE='23514',
                MESSAGE='DESIGN_VIGENTE_COMPONENT_REQUIRES_VIGENTE_COLOR_TOKEN',
                DETAIL=format(
                  'component=%s key=%s token=%s status=%s',
                  NEW.component_token_code,v_key,v_sval,v_color_status
                );
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END
$function$;

-- Profile policy source validation & required selection.

ALTER TABLE private.lf_reusable_policy_registry_v1
 ADD COLUMN IF NOT EXISTS required boolean NOT NULL DEFAULT false;
UPDATE private.lf_reusable_policy_registry_v1
 SET required=true,updated_at=clock_timestamp()
 WHERE policy_code='LF-DESIGN-TOKEN-REFERENCE-POLICY-V1' AND status='VIGENTE';

CREATE OR REPLACE FUNCTION public.lf_profile_policy_deterministic_discovery_v1(p_profile_code text, p_business text, p_channel text, p_action text, p_asset_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
DECLARE
  v_caps text[];
  v_action_family text;
  v_candidates jsonb;
  v_digest text;
BEGIN
  IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL THEN
    RAISE EXCEPTION 'LF_POLICY_DISCOVERY_PROFILE_REQUIRED';
  END IF;

  SELECT coalesce(array_agg(capability_code ORDER BY capability_code),ARRAY[]::text[])
  INTO v_caps
  FROM private.lf_profile_capability_registry_v1
  WHERE profile_code=p_profile_code AND status='CURRENT';

  v_action_family:=split_part(upper(coalesce(p_action,'')),'_',1);

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'policy_code',p.policy_code,
      'required',p.required,
      'priority',p.priority,
      'semantic_descriptor',p.semantic_descriptor,
      'execution_constraints',p.execution_constraints,
      'source_ref',p.source_ref,
      'matched_capabilities',(
        SELECT coalesce(jsonb_agg(c ORDER BY c),'[]'::jsonb)
        FROM unnest(v_caps) c WHERE c=ANY(p.capabilities_any)
      )
    ) ORDER BY p.priority,p.policy_code
  ),'[]'::jsonb)
  INTO v_candidates
  FROM private.lf_reusable_policy_registry_v1 p
  WHERE p.status='VIGENTE'
    AND ('GLOBAL'=ANY(p.business_scope) OR upper(coalesce(p_business,''))=ANY(p.business_scope))
    AND ('GLOBAL'=ANY(p.channel_scope) OR upper(coalesce(p_channel,''))=ANY(p.channel_scope))
    AND (cardinality(p.capabilities_any)=0 OR p.capabilities_any && v_caps)
    AND (cardinality(p.action_families_any)=0 OR v_action_family=ANY(p.action_families_any))
    AND (cardinality(p.asset_types_any)=0 OR upper(coalesce(p_asset_type,''))=ANY(p.asset_types_any));

  v_digest:=encode(extensions.digest(convert_to(v_candidates::text,'UTF8'),'sha256'),'hex');

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_POLICY_DETERMINISTIC_DISCOVERY_V1',
    'selection_mode','DETERMINISTIC_DISCOVERY_ONLY',
    'semantic_selection_performed',false,
    'profile_code',p_profile_code,
    'business',upper(coalesce(p_business,'')),
    'channel',upper(coalesce(p_channel,'')),
    'action',upper(coalesce(p_action,'')),
    'action_family',v_action_family,
    'asset_type',upper(coalesce(p_asset_type,'')),
    'profile_capabilities',to_jsonb(v_caps),
    'candidate_count',jsonb_array_length(v_candidates),
    'candidate_policies',v_candidates,
    'candidate_set_sha256',v_digest
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_policy_selection_finalize_v1(p_request jsonb, p_draft jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_current jsonb;
  v_missing_required jsonb;
  v_decision text;
  v_selected jsonb;
  v_invalid jsonb;
  v_final jsonb;
BEGIN
  -- Caller-provided request and digest have no authority.
  IF jsonb_typeof(p_request)<>'object'
     OR nullif(btrim(coalesce(p_request->>'execution_id','')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_EXECUTION_ID_REQUIRED');
  END IF;
  BEGIN
    v_current:=public.lf_profile_policy_selection_prepare_v1(p_request->>'execution_id');
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_CURRENT_SOURCE_UNAVAILABLE');
  END;
  IF v_current->>'status' IS DISTINCT FROM 'READY'
     OR p_request IS DISTINCT FROM v_current THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_REQUEST_STALE_OR_FORGED');
  END IF;

  IF p_request->>'schema_version'<>'LF_PROFILE_POLICY_SEMANTIC_REQUEST_V1'
     OR p_request->>'status'<>'READY'
     OR jsonb_typeof(p_draft)<>'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_INPUT_INVALID');
  END IF;

  v_decision:=upper(coalesce(p_draft->>'decision',''));
  v_selected:=coalesce(p_draft->'selected_policy_codes','[]'::jsonb);

  IF v_decision NOT IN ('SELECTED','NONE')
     OR jsonb_typeof(v_selected)<>'array'
     OR nullif(btrim(coalesce(p_draft->>'reason','')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_DRAFT_INVALID');
  END IF;

  IF EXISTS (
       SELECT 1 FROM jsonb_array_elements(v_selected) s
       WHERE jsonb_typeof(s.value)<>'string'
     )
     OR (SELECT count(*) FROM jsonb_array_elements_text(v_selected)) <>
        (SELECT count(DISTINCT s.value) FROM jsonb_array_elements_text(v_selected) s)
  THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_CODES_INVALID');
  END IF;

  SELECT coalesce(jsonb_agg(x),'[]'::jsonb) INTO v_invalid
  FROM jsonb_array_elements_text(v_selected) x
  WHERE NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_request->'candidate_policies') c
    WHERE c->>'policy_code'=x
  );

  IF jsonb_array_length(v_invalid)>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','POLICY_SELECTION_OUTSIDE_SHORTLIST_FORBIDDEN',
      'invalid_policy_codes',v_invalid
    );
  END IF;

  SELECT coalesce(jsonb_agg(c->>'policy_code'),'[]'::jsonb) INTO v_missing_required
  FROM jsonb_array_elements(v_current->'candidate_policies') c
  WHERE coalesce((c->>'required')::boolean,false)
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(v_selected) s(value)
      WHERE s.value=c->>'policy_code'
    );
  IF jsonb_array_length(v_missing_required)>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','POLICY_SELECTION_REQUIRED_POLICY_OMITTED',
      'missing_policy_codes',v_missing_required
    );
  END IF;

  IF (v_decision='NONE' AND jsonb_array_length(v_selected)<>0)
     OR (v_decision='SELECTED' AND jsonb_array_length(v_selected)=0) THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','POLICY_SELECTION_CARDINALITY_INVALID');
  END IF;

  SELECT coalesce(jsonb_agg(c ORDER BY c->>'policy_code'),'[]'::jsonb) INTO v_final
  FROM jsonb_array_elements(p_request->'candidate_policies') c
  WHERE c->>'policy_code' IN (SELECT jsonb_array_elements_text(v_selected));

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_POLICY_SEMANTIC_RESULT_V1',
    'status','VALID',
    'decision',v_decision,
    'candidate_set_sha256',p_request->>'candidate_set_sha256',
    'selected_policy_count',jsonb_array_length(v_final),
    'selected_policies',v_final,
    'reason',p_draft->>'reason',
    'shortlist_expansion_allowed',false
  );
END
$function$;

REVOKE EXECUTE ON FUNCTION public.lf_profile_policy_deterministic_discovery_v1(text,text,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.lf_profile_policy_selection_prepare_v1(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.lf_profile_policy_selection_finalize_v1(jsonb,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_policy_deterministic_discovery_v1(text,text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_profile_policy_selection_prepare_v1(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_profile_policy_selection_finalize_v1(jsonb,jsonb) TO service_role;

DO $p0_assert$
DECLARE
  d jsonb;
  r jsonb;
BEGIN
  IF NOT '#991B1B' ~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()'
     OR 'error_bg' ~* '(#[0-9a-f]{3,8}([^0-9a-f]|$)|rgba?\s*\(|hsla?\s*\()'
  THEN RAISE EXCEPTION 'LF_P0_REGEX_REGRESSION'; END IF;
  SELECT public.lf_profile_policy_deterministic_discovery_v1(
    'PERFIL-UI-ARCHITECT','LF','PRODUCTO','UPDATE','PANTALLA') INTO d;
  IF coalesce((d->>'candidate_count')::integer,0)<1
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(d->'candidate_policies') c
                    WHERE c->>'policy_code'='LF-DESIGN-TOKEN-REFERENCE-POLICY-V1'
                      AND c->>'required'='true') THEN
    RAISE EXCEPTION 'LF_P0_REQUIRED_DESIGN_POLICY_NOT_DISCOVERED';
  END IF;
  r:=public.lf_profile_policy_selection_finalize_v1(
    jsonb_build_object('schema_version','LF_PROFILE_POLICY_SEMANTIC_REQUEST_V1',
      'status','READY','execution_id','__P0_PRODUCTION_NONEXISTENT_EXECUTION__',
      'candidate_set_sha256','FORGED',
      'candidate_policies',jsonb_build_array(jsonb_build_object('policy_code','INVENTED_POLICY','required',false))),
    jsonb_build_object('decision','SELECTED','selected_policy_codes',jsonb_build_array('INVENTED_POLICY'),
      'reason','transactional provenance guard'));
  IF r->>'status' IS DISTINCT FROM 'BLOCKED' THEN
    RAISE EXCEPTION 'LF_P0_FORGED_POLICY_SELECTION_FALSE_PASS';
  END IF;
  IF has_function_privilege('anon','public.lf_profile_policy_selection_finalize_v1(jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_profile_policy_selection_finalize_v1(jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.lf_profile_policy_selection_prepare_v1(text)','EXECUTE') THEN
    RAISE EXCEPTION 'LF_P0_POLICY_FN_PRIVILEGES_STILL_PUBLIC';
  END IF;
END;
$p0_assert$;

COMMIT;
