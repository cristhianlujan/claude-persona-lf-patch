BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_selector_semantic_prepare_v1(
  p_literal_request text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_catalog jsonb;
  v_profiles jsonb;
  v_request_sha text;
  v_catalog_sha text;
BEGIN
  IF nullif(btrim(coalesce(p_literal_request,'')),'') IS NULL THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_LITERAL_REQUEST_REQUIRED';
  END IF;

  v_catalog:=public.lf_profile_selector_catalog_v1();

  IF coalesce((v_catalog->>'all_canonical_descriptors_complete')::boolean,false) IS NOT TRUE
     OR coalesce((v_catalog->>'selectable_profile_count')::integer,0)<=0
     OR v_catalog->>'selection_mode'<>'DETERMINISTIC_DISCOVERY_ONLY'
     OR coalesce((v_catalog->>'semantic_selection_performed')::boolean,true) IS TRUE
  THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_CATALOG_NOT_READY:%',left(v_catalog::text,1200);
  END IF;

  SELECT coalesce(jsonb_agg(p ORDER BY p->>'profile_code'),'[]'::jsonb)
    INTO v_profiles
  FROM jsonb_array_elements(v_catalog->'profiles') p
  WHERE coalesce((p->>'selection_eligible')::boolean,false) IS TRUE
    AND p->>'descriptor_status'='CURRENT'
    AND jsonb_typeof(p->'descriptor')='object'
    AND nullif(btrim(coalesce(p#>>'{descriptor,description}','')),'') IS NOT NULL;

  IF jsonb_array_length(v_profiles)
       <> coalesce((v_catalog->>'selectable_profile_count')::integer,-1)
  THEN
    RAISE EXCEPTION 'LF_PROFILE_SELECTOR_PREPARE_CARDINALITY_DRIFT';
  END IF;

  v_request_sha:=encode(
    extensions.digest(convert_to(p_literal_request,'UTF8'),'sha256'),
    'hex'
  );
  v_catalog_sha:=encode(
    extensions.digest(convert_to(v_profiles::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1',
    'selector','PROFILE_SELECTOR_LF',
    'literal_request',p_literal_request,
    'request_sha256',v_request_sha,
    'catalog_schema_version',v_catalog->>'schema_version',
    'catalog_sha256',v_catalog_sha,
    'catalog_profile_count',jsonb_array_length(v_profiles),
    'candidate_profiles',v_profiles,
    'allowed_decisions',jsonb_build_array('SELECTED','AMBIGUOUS','NO_MATCH'),
    'semantic_rules',jsonb_build_array(
      'COMPARE_LITERAL_REQUEST_AGAINST_ALL_CANDIDATE_DESCRIPTORS',
      'DO_NOT_PRESELECT_BY_KEYWORD_OR_PROFILE_NAME',
      'USE_ONLY_DECLARED_DESCRIPTOR_EVIDENCE',
      'SELECTED_REQUIRES_ONE_PROFILE',
      'AMBIGUOUS_REQUIRES_TWO_OR_MORE_MATERIAL_CANDIDATES',
      'NO_MATCH_WHEN_NO_DECLARED_PROFILE_CAPABILITY_FITS',
      'NO_ROUTE_OR_EFFECT_AUTHORITY'
    ),
    'semantic_output_contract',jsonb_build_object(
      'decision','SELECTED|AMBIGUOUS|NO_MATCH',
      'selected_profile_code','string|null',
      'ambiguous_profile_codes','array<string>',
      'reason','non-empty string',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object(
          'profile_code','candidate profile code',
          'kind','selection_evidence.kind',
          'source_section','selection_evidence.source_section'
        )
      ),
      'material_ambiguities','array<object>'
    ),
    'route_authority',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_selector_semantic_prepare_v1(text) IS
'Builds the semantic profile-selection request from the complete deterministic CURRENT profile catalog. It does not choose a profile.';

REVOKE ALL ON FUNCTION public.lf_profile_selector_semantic_prepare_v1(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_selector_semantic_prepare_v1(text)
  TO service_role, supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_selector_semantic_validate_v1(
  p_request jsonb,
  p_result jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_current jsonb;
  v_decision text;
  v_selected text;
  v_ambiguous jsonb;
  v_evidence jsonb;
  v_material jsonb;
  v_reason text;
  v_expected_receipt text;
  v_blocking jsonb:='[]'::jsonb;
  v_bad integer:=0;
BEGIN
  IF jsonb_typeof(p_request)<>'object'
     OR jsonb_typeof(p_result)<>'object'
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_VALIDATION_V1',
      'status','BLOCKED',
      'blocking_codes',jsonb_build_array('PROFILE_SELECTOR_SEMANTIC_OBJECT_REQUIRED'),
      'route_authority',false,
      'effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;

  BEGIN
    v_current:=public.lf_profile_selector_semantic_prepare_v1(
      p_request->>'literal_request'
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_VALIDATION_V1',
      'status','BLOCKED',
      'blocking_codes',jsonb_build_array('PROFILE_SELECTOR_CURRENT_CATALOG_UNAVAILABLE'),
      'route_authority',false,
      'effect_authority',false,
      'downstream_execution_allowed',false
    );
  END;

  IF p_request->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
     OR p_request->>'selector'<>'PROFILE_SELECTOR_LF'
     OR p_request->>'request_sha256' IS DISTINCT FROM v_current->>'request_sha256'
     OR p_request->>'catalog_sha256' IS DISTINCT FROM v_current->>'catalog_sha256'
     OR p_request->'candidate_profiles' IS DISTINCT FROM v_current->'candidate_profiles'
     OR p_request->>'catalog_profile_count' IS DISTINCT FROM v_current->>'catalog_profile_count'
  THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_REQUEST_STALE_OR_INVALID');
  END IF;

  IF p_result ?| ARRAY[
       'operation_code','action_code','candidate_action_code',
       'executor','executor_mode','router_action_binding',
       'route_authority','effect_authority','downstream_execution_allowed'
     ]
  THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_RESULT_AUTHORITY_FIELD_FORBIDDEN');
  END IF;

  IF p_result->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1'
     OR p_result->>'request_sha256' IS DISTINCT FROM p_request->>'request_sha256'
     OR p_result->>'catalog_sha256' IS DISTINCT FROM p_request->>'catalog_sha256'
     OR p_result->>'catalog_profile_count' IS DISTINCT FROM p_request->>'catalog_profile_count'
  THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_RESULT_BINDING_INVALID');
  END IF;

  v_decision:=upper(coalesce(p_result->>'decision',''));
  v_selected:=nullif(btrim(coalesce(p_result->>'selected_profile_code','')),'');
  v_ambiguous:=coalesce(p_result->'ambiguous_profile_codes','[]'::jsonb);
  v_evidence:=coalesce(p_result->'evidence_refs','[]'::jsonb);
  v_material:=coalesce(p_result->'material_ambiguities','[]'::jsonb);
  v_reason:=nullif(btrim(coalesce(p_result->>'reason','')),'');

  IF v_decision NOT IN ('SELECTED','AMBIGUOUS','NO_MATCH')
     OR jsonb_typeof(v_ambiguous)<>'array'
     OR jsonb_typeof(v_evidence)<>'array'
     OR jsonb_typeof(v_material)<>'array'
     OR v_reason IS NULL
  THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_RESULT_SHAPE_INVALID');
  END IF;

  IF v_selected IS NOT NULL AND NOT EXISTS(
    SELECT 1
    FROM jsonb_array_elements(p_request->'candidate_profiles') p
    WHERE p->>'profile_code'=v_selected
      AND coalesce((p->>'selection_eligible')::boolean,false) IS TRUE
      AND p->>'descriptor_status'='CURRENT'
  ) THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_SELECTED_OUTSIDE_CATALOG');
  END IF;

  IF jsonb_typeof(v_ambiguous)='array' THEN
    SELECT count(*) INTO v_bad
    FROM jsonb_array_elements(v_ambiguous) x(item)
    WHERE jsonb_typeof(x.item)<>'string'
       OR NOT EXISTS(
          SELECT 1
          FROM jsonb_array_elements(p_request->'candidate_profiles') p
          WHERE p->>'profile_code'=x.item#>>'{}'
            AND coalesce((p->>'selection_eligible')::boolean,false) IS TRUE
            AND p->>'descriptor_status'='CURRENT'
       );

    IF v_bad>0 THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_AMBIGUOUS_OUTSIDE_CATALOG');
    END IF;

    IF (
      SELECT count(*) FROM (
        SELECT DISTINCT x.item#>>'{}' AS code
        FROM jsonb_array_elements(v_ambiguous) x(item)
      ) q
    ) <> jsonb_array_length(v_ambiguous)
    THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_AMBIGUOUS_DUPLICATE');
    END IF;
  END IF;

  IF jsonb_typeof(v_evidence)='array' THEN
    SELECT count(*) INTO v_bad
    FROM jsonb_array_elements(v_evidence) e(item)
    WHERE jsonb_typeof(e.item)<>'object'
       OR nullif(e.item->>'profile_code','') IS NULL
       OR nullif(e.item->>'kind','') IS NULL
       OR nullif(e.item->>'source_section','') IS NULL
       OR NOT EXISTS(
          SELECT 1
          FROM jsonb_array_elements(p_request->'candidate_profiles') p,
               LATERAL jsonb_array_elements(p#>'{descriptor,selection_evidence}') se(item)
          WHERE p->>'profile_code'=e.item->>'profile_code'
            AND se.item->>'kind'=e.item->>'kind'
            AND se.item->>'source_section'=e.item->>'source_section'
       );

    IF v_bad>0 THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_EVIDENCE_REF_INVALID');
    END IF;
  END IF;

  IF v_decision='SELECTED' THEN
    IF v_selected IS NULL
       OR jsonb_array_length(v_ambiguous)<>0
       OR jsonb_array_length(v_material)<>0
       OR NOT EXISTS(
          SELECT 1
          FROM jsonb_array_elements(v_evidence) e(item)
          WHERE e.item->>'profile_code'=v_selected
       )
    THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_SELECTED_CONTRACT_INVALID');
    END IF;
  ELSIF v_decision='AMBIGUOUS' THEN
    IF v_selected IS NOT NULL
       OR jsonb_array_length(v_ambiguous)<2
       OR jsonb_array_length(v_material)=0
       OR EXISTS(
          SELECT 1
          FROM jsonb_array_elements(v_ambiguous) x(item)
          WHERE NOT EXISTS(
            SELECT 1
            FROM jsonb_array_elements(v_evidence) e(item)
            WHERE e.item->>'profile_code'=x.item#>>'{}'
          )
       )
    THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_AMBIGUOUS_CONTRACT_INVALID');
    END IF;
  ELSIF v_decision='NO_MATCH' THEN
    IF v_selected IS NOT NULL OR jsonb_array_length(v_ambiguous)<>0 THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_NO_MATCH_CONTRACT_INVALID');
    END IF;
  END IF;

  v_expected_receipt:=encode(
    extensions.digest(
      convert_to((p_result-'semantic_receipt_sha256')::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  IF coalesce(p_result->>'semantic_receipt_sha256','') !~ '^[0-9a-f]{64}$'
     OR p_result->>'semantic_receipt_sha256' IS DISTINCT FROM v_expected_receipt
  THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SELECTOR_SEMANTIC_RECEIPT_INVALID');
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_VALIDATION_V1',
    'status',case when jsonb_array_length(v_blocking)=0 then 'VALID' else 'BLOCKED' end,
    'decision',v_decision,
    'selected_profile_code',v_selected,
    'ambiguous_profile_codes',v_ambiguous,
    'blocking_codes',v_blocking,
    'request_sha256',p_request->>'request_sha256',
    'catalog_sha256',p_request->>'catalog_sha256',
    'catalog_profile_count',p_request->>'catalog_profile_count',
    'route_authority',false,
    'effect_authority',false,
    'downstream_execution_allowed',false,
    'next_action',case
      when jsonb_array_length(v_blocking)>0 then 'STAY_BLOCKED'
      when v_decision='SELECTED' then 'PROFILE_SELECTION_READY_FOR_GATE2'
      when v_decision='AMBIGUOUS' then 'HUMAN_OR_CALLER_DECISION_REQUIRED'
      else 'NO_PROFILE_MATCH_BLOCKED'
    end
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_selector_semantic_validate_v1(jsonb,jsonb) IS
'Validates a semantic profile choice against the exact current deterministic catalog. Semantic output never has route/effect authority.';

REVOKE ALL ON FUNCTION public.lf_profile_selector_semantic_validate_v1(jsonb,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_selector_semantic_validate_v1(jsonb,jsonb)
  TO service_role, supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_selector_semantic_finalize_v1(
  p_request jsonb,
  p_draft jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_result jsonb;
  v_receipt text;
  v_validation jsonb;
BEGIN
  IF jsonb_typeof(p_draft)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','PROFILE_SELECTOR_DRAFT_NOT_OBJECT'
    );
  END IF;

  IF p_draft ?| ARRAY[
       'schema_version','request_sha256','catalog_sha256','catalog_profile_count',
       'semantic_receipt_sha256','operation_code','action_code','candidate_action_code',
       'executor','executor_mode','router_action_binding',
       'route_authority','effect_authority','downstream_execution_allowed'
     ]
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','PROFILE_SELECTOR_DRAFT_CONTROL_FIELD_FORBIDDEN'
    );
  END IF;

  v_result:=jsonb_build_object(
    'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
    'request_sha256',p_request->>'request_sha256',
    'catalog_sha256',p_request->>'catalog_sha256',
    'catalog_profile_count',coalesce((p_request->>'catalog_profile_count')::integer,0),
    'decision',upper(coalesce(p_draft->>'decision','')),
    'selected_profile_code',case
      when nullif(btrim(coalesce(p_draft->>'selected_profile_code','')),'') is null
        then null
      else p_draft->>'selected_profile_code'
    end,
    'ambiguous_profile_codes',coalesce(p_draft->'ambiguous_profile_codes','[]'::jsonb),
    'reason',p_draft->>'reason',
    'evidence_refs',coalesce(p_draft->'evidence_refs','[]'::jsonb),
    'material_ambiguities',coalesce(p_draft->'material_ambiguities','[]'::jsonb)
  );

  v_receipt:=encode(
    extensions.digest(convert_to(v_result::text,'UTF8'),'sha256'),
    'hex'
  );
  v_result:=v_result||jsonb_build_object('semantic_receipt_sha256',v_receipt);

  v_validation:=public.lf_profile_selector_semantic_validate_v1(
    p_request,v_result
  );

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_FINALIZE_V1',
    'status',v_validation->>'status',
    'result',v_result,
    'validation',v_validation
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_selector_semantic_finalize_v1(jsonb,jsonb) IS
'Normalizes a GPT/native semantic draft, binds it to request+catalog, computes receipt, and validates it.';

REVOKE ALL ON FUNCTION public.lf_profile_selector_semantic_finalize_v1(jsonb,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_selector_semantic_finalize_v1(jsonb,jsonb)
  TO service_role, supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_selector_semantic_consume_raw_v1(
  p_request jsonb,
  p_raw text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_parse jsonb;
BEGIN
  v_parse:=public.lf_parse_semantic_judge_output_v1(p_raw);

  IF v_parse->>'status'<>'PASS' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_CONSUME_RAW_V1',
      'status','BLOCKED',
      'blocking_code','PROFILE_SELECTOR_MODEL_OUTPUT_PARSE_FAILED',
      'parse',v_parse
    );
  END IF;

  RETURN public.lf_profile_selector_semantic_finalize_v1(
    p_request,
    v_parse->'payload'
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_selector_semantic_consume_raw_v1(jsonb,text) IS
'Consumes exact JSON model output for semantic profile choice using the existing governed semantic-output parser.';

REVOKE ALL ON FUNCTION public.lf_profile_selector_semantic_consume_raw_v1(jsonb,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_selector_semantic_consume_raw_v1(jsonb,text)
  TO service_role, supabase_read_only_user;


DO $postcheck$
DECLARE
  q jsonb;
  f jsonb;
  d jsonb;
  a jsonb;
  p1 jsonb;
  p2 jsonb;
  e1 jsonb;
  e2 jsonb;
BEGIN
  q:=public.lf_profile_selector_semantic_prepare_v1('PROFILE_SELECTOR_CONTRACT_SMOKE');

  IF q->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
     OR q->>'selector'<>'PROFILE_SELECTOR_LF'
     OR (q->>'catalog_profile_count')::integer<>10
     OR jsonb_array_length(q->'candidate_profiles')<>10
     OR coalesce((q->>'route_authority')::boolean,true)
     OR coalesce((q->>'effect_authority')::boolean,true)
     OR coalesce((q->>'downstream_execution_allowed')::boolean,true)
  THEN
    RAISE EXCEPTION 'PROFILE_SELECTOR_PREPARE_POSTCHECK_FAILED:%',left(q::text,1600);
  END IF;

  p1:=q#>'{candidate_profiles,0}';
  e1:=p1#>'{descriptor,selection_evidence,0}';

  d:=jsonb_build_object(
    'decision','SELECTED',
    'selected_profile_code',p1->>'profile_code',
    'ambiguous_profile_codes','[]'::jsonb,
    'reason','Contract smoke selects one catalog member using declared descriptor evidence.',
    'evidence_refs',jsonb_build_array(jsonb_build_object(
      'profile_code',p1->>'profile_code',
      'kind',e1->>'kind',
      'source_section',e1->>'source_section'
    )),
    'material_ambiguities','[]'::jsonb
  );

  f:=public.lf_profile_selector_semantic_finalize_v1(q,d);
  IF f->>'status'<>'VALID'
     OR f#>>'{validation,next_action}'<>'PROFILE_SELECTION_READY_FOR_GATE2'
  THEN
    RAISE EXCEPTION 'PROFILE_SELECTOR_SELECTED_POSTCHECK_FAILED:%',left(f::text,1600);
  END IF;

  p2:=q#>'{candidate_profiles,1}';
  e2:=p2#>'{descriptor,selection_evidence,0}';

  a:=public.lf_profile_selector_semantic_finalize_v1(
    q,
    jsonb_build_object(
      'decision','AMBIGUOUS',
      'selected_profile_code',null,
      'ambiguous_profile_codes',jsonb_build_array(
        p1->>'profile_code',p2->>'profile_code'
      ),
      'reason','Contract smoke preserves a material tie.',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object(
          'profile_code',p1->>'profile_code',
          'kind',e1->>'kind',
          'source_section',e1->>'source_section'
        ),
        jsonb_build_object(
          'profile_code',p2->>'profile_code',
          'kind',e2->>'kind',
          'source_section',e2->>'source_section'
        )
      ),
      'material_ambiguities',jsonb_build_array(jsonb_build_object(
        'kind','MATERIAL_PROFILE_TIE'
      ))
    )
  );

  IF a->>'status'<>'VALID'
     OR a#>>'{validation,next_action}'<>'HUMAN_OR_CALLER_DECISION_REQUIRED'
  THEN
    RAISE EXCEPTION 'PROFILE_SELECTOR_AMBIGUOUS_POSTCHECK_FAILED:%',left(a::text,1600);
  END IF;

  f:=public.lf_profile_selector_semantic_finalize_v1(
    q,
    jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','PROFILE-NOT-IN-CATALOG',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Negative contract smoke.',
      'evidence_refs','[]'::jsonb,
      'material_ambiguities','[]'::jsonb
    )
  );

  IF f->>'status'<>'BLOCKED'
     OR NOT (f#>'{validation,blocking_codes}') @>
        jsonb_build_array('PROFILE_SELECTOR_SELECTED_OUTSIDE_CATALOG')
  THEN
    RAISE EXCEPTION 'PROFILE_SELECTOR_OUTSIDE_CATALOG_FALSE_PASS:%',left(f::text,1600);
  END IF;

  IF has_function_privilege('anon','public.lf_profile_selector_semantic_prepare_v1(text)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_profile_selector_semantic_prepare_v1(text)','EXECUTE')
     OR has_function_privilege('anon','public.lf_profile_selector_semantic_consume_raw_v1(jsonb,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_profile_selector_semantic_consume_raw_v1(jsonb,text)','EXECUTE')
     OR NOT has_function_privilege('supabase_read_only_user','public.lf_profile_selector_semantic_prepare_v1(text)','EXECUTE')
     OR NOT has_function_privilege('supabase_read_only_user','public.lf_profile_selector_semantic_consume_raw_v1(jsonb,text)','EXECUTE')
  THEN
    RAISE EXCEPTION 'PROFILE_SELECTOR_SEMANTIC_ACL_POSTCHECK_FAILED';
  END IF;

  IF position('PERFIL-PRODUCT-DIRECTOR-LF' in
      pg_get_functiondef('public.lf_profile_selector_semantic_prepare_v1(text)'::regprocedure))>0
     OR position('PERFIL-UI-ARCHITECT' in
      pg_get_functiondef('public.lf_profile_selector_semantic_prepare_v1(text)'::regprocedure))>0
     OR position('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF' in
      pg_get_functiondef('public.lf_profile_selector_semantic_prepare_v1(text)'::regprocedure))>0
  THEN
    RAISE EXCEPTION 'PROFILE_SELECTOR_RUNTIME_PROFILE_HARDCODING_DETECTED';
  END IF;
END
$postcheck$;

COMMIT;
