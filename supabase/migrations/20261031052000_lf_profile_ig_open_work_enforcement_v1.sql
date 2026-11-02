BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_ig_open_work_v1(p_execution_id text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_input jsonb;
  v_open jsonb;
  v_result jsonb;
BEGIN
  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input IS NULL
     OR coalesce((v_input#>>'{input_governance,applicable}')::boolean,false) IS NOT TRUE
  THEN
    RETURN '[]'::jsonb;
  END IF;

  v_open:=v_input#>'{input_governance,context_manifest,open_families}';
  IF jsonb_typeof(v_open)<>'array' THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'family_code',x->>'family_code',
      'severity',x->>'severity',
      'implementation_status',x->>'implementation',
      'qa_status',x->>'qa',
      'production_status',x->>'production',
      'primary_blocker_code',x#>>'{blockers,0,code}',
      'blocking_stage',x#>>'{blockers,0,blocking_stage}',
      'uncertainty_type',x#>>'{blockers,0,uncertainty_type}',
      'required_response_statuses',jsonb_build_array(
        'RESUELTA','NO_CORRESPONDE','DEPENDENCIA','DECISIÓN_REQUERIDA'
      )
    )
    ORDER BY CASE x->>'severity'
      WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2
      WHEN 'P3' THEN 3 WHEN 'P4' THEN 4 ELSE 9 END,
      x->>'family_code'
  ),'[]'::jsonb)
  INTO v_result
  FROM jsonb_array_elements(v_open) x
  WHERE x->>'implementation' IS DISTINCT FROM 'READY';

  RETURN coalesce(v_result,'[]'::jsonb);
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_ig_open_work_v1(text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_ig_open_work_v1(text)
TO service_role,supabase_read_only_user;

DO $patch$
DECLARE
  v_src text;
  v_before text;
BEGIN
  SELECT pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  ) INTO v_src;
  IF md5(v_src)<>'82376ccd27cdca638c9ba072a4ca679f' THEN
    RAISE EXCEPTION 'BLOCK_IG_OPEN_WORK_SOURCE_DRIFT:prepare:%',md5(v_src);
  END IF;
  v_before:=v_src;
  v_src:=replace(
    v_src,
    $n$    'input_governance',v_input->'input_governance',
    'context_receipt_ref',v_context->>'context_receipt_ref',$n$,
    $r$    'input_governance',v_input->'input_governance',
    'ig_open_work',public.lf_profile_ig_open_work_v1(p_execution_id),
    'ig_open_work_count',jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id)),
    'ig_open_work_response_contract',jsonb_build_object(
      'required',jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))>0,
      'output_field','ig_open_work_resolution',
      'coverage','EXACT_ONE_RESPONSE_PER_FAMILY',
      'allowed_statuses',jsonb_build_array(
        'RESUELTA','NO_CORRESPONDE','DEPENDENCIA','DECISIÓN_REQUERIDA'
      ),
      'resolved_requires_evidence',true,
      'dependency_or_decision_requires_next_action',true
    ),
    'context_receipt_ref',v_context->>'context_receipt_ref',$r$
  );
  IF v_src=v_before THEN
    RAISE EXCEPTION 'BLOCK_IG_OPEN_WORK_PREPARE_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE v_src;

  SELECT pg_get_functiondef(
    'public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure
  ) INTO v_src;
  IF md5(v_src)<>'d3bb006ad6ac1af6d5e48aa883e49870' THEN
    RAISE EXCEPTION 'BLOCK_IG_OPEN_WORK_SOURCE_DRIFT:record_output:%',md5(v_src);
  END IF;
  v_before:=v_src;
  v_src:=replace(
    v_src,
    $n$  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps$n$,
    $r$  IF jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))>0 THEN
    IF jsonb_typeof(p_profile_output->'ig_open_work_resolution')<>'array'
       OR jsonb_array_length(p_profile_output->'ig_open_work_resolution')
          <> jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_IG_OPEN_WORK_RESOLUTION_REQUIRED',
        'expected_open_work',public.lf_profile_ig_open_work_v1(p_execution_id),
        'required_output_field','ig_open_work_resolution'
      );
    END IF;

    IF (
      SELECT count(DISTINCT r->>'family_code')
      FROM jsonb_array_elements(p_profile_output->'ig_open_work_resolution') r
    ) <> jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))
    OR EXISTS(
      SELECT 1
      FROM jsonb_array_elements(public.lf_profile_ig_open_work_v1(p_execution_id)) w
      WHERE NOT EXISTS(
        SELECT 1
        FROM jsonb_array_elements(p_profile_output->'ig_open_work_resolution') r
        WHERE r->>'family_code'=w->>'family_code'
      )
    )
    OR EXISTS(
      SELECT 1
      FROM jsonb_array_elements(p_profile_output->'ig_open_work_resolution') r
      WHERE NOT EXISTS(
        SELECT 1
        FROM jsonb_array_elements(public.lf_profile_ig_open_work_v1(p_execution_id)) w
        WHERE w->>'family_code'=r->>'family_code'
      )
      OR r->>'status' NOT IN (
        'RESUELTA','NO_CORRESPONDE','DEPENDENCIA','DECISIÓN_REQUERIDA'
      )
      OR nullif(btrim(coalesce(r->>'reason','')),'') IS NULL
      OR (
        r->>'status'='RESUELTA'
        AND (
          jsonb_typeof(r->'evidence_refs')<>'array'
          OR jsonb_array_length(r->'evidence_refs')=0
        )
      )
      OR (
        r->>'status' IN ('DEPENDENCIA','DECISIÓN_REQUERIDA')
        AND nullif(btrim(coalesce(r->>'next_action','')),'') IS NULL
      )
    )
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_IG_OPEN_WORK_RESOLUTION_INVALID',
        'expected_open_work',public.lf_profile_ig_open_work_v1(p_execution_id)
      );
    END IF;
  END IF;

  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps$r$
  );
  IF v_src=v_before THEN
    RAISE EXCEPTION 'BLOCK_IG_OPEN_WORK_RECORD_OUTPUT_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE v_src;
END
$patch$;

DO $verify$
DECLARE
  v_work jsonb;
  v_prepare text;
  v_record text;
BEGIN
  v_work:=public.lf_profile_ig_open_work_v1(
    'EXEC-PROFILE-GATE2-576B053DC0BA08D9218E56A4'
  );
  IF jsonb_typeof(v_work)<>'array'
     OR jsonb_array_length(v_work)<>20 THEN
    RAISE EXCEPTION 'IG_OPEN_WORK_B2B_COUNT_INVALID:%',v_work;
  END IF;

  IF NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_work) x
       WHERE x->>'family_code'='API_DATA_CONTRACT'
     )
     OR NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_work) x
       WHERE x->>'family_code'='MFA_OTP_SSO'
     )
     OR NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_work) x
       WHERE x->>'family_code'='SECURITY'
     )
     OR NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_work) x
       WHERE x->>'family_code'='LOADING_EMPTY_ERROR_STATES'
     )
  THEN
    RAISE EXCEPTION 'IG_OPEN_WORK_B2B_MATERIAL_FAMILIES_MISSING';
  END IF;

  SELECT pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  ) INTO v_prepare;
  SELECT pg_get_functiondef(
    'public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure
  ) INTO v_record;

  IF position('ig_open_work_response_contract' in v_prepare)=0
     OR position('ig_open_work_resolution' in v_record)=0
     OR position('BLOCK_PROFILE_IG_OPEN_WORK_RESOLUTION_REQUIRED' in v_record)=0
     OR position('BLOCK_PROFILE_IG_OPEN_WORK_RESOLUTION_INVALID' in v_record)=0
  THEN
    RAISE EXCEPTION 'IG_OPEN_WORK_COMMON_EXECUTION_ENFORCEMENT_MISSING';
  END IF;
END
$verify$;

COMMIT;
