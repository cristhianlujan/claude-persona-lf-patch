-- P0: Attest current policy shortlist and enforce required candidate policies.
-- No new registry, routing stage, or profile execution step.
BEGIN;
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
COMMIT;
