-- LF / Profile Input Governance: deterministic screen shortlist + mandatory semantic selection.
-- The deterministic matcher never selects a screen. GPT Native selects SELECTED/AMBIGUOUS/NO_MATCH,
-- the result is bound to the exact shortlist, then input_validate resumes in the same execution_id.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
     )) <> '9938173f4000548fb6e70413d7e17832' THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_INPUT_VALIDATE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
     )) <> '08f667a0ff12d3b6e5763c2821bce92d' THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_BRIDGE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)'::regprocedure
     )) <> '662c87ca4fd520331294e95c8665fa7f' THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_IG_RESOLVER_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)'::regprocedure
     )) <> '33e3c6d33e795afae706c54f1f104aa9' THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_CHANNEL_CONTEXT_SOURCE_DRIFT';
  END IF;
END
$precheck$;

CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(
  p_literal_request text,
  p_scope jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $fn$
DECLARE
  v_literal text:=nullif(btrim(coalesce(p_literal_request,'')),'');
  v_scope jsonb:=coalesce(p_scope,'{}'::jsonb);
  v_hint text:=nullif(btrim(coalesce(p_scope->>'target_hint','')),'');
  v_hint_like text;
  v_req text;
  v_candidates jsonb:='[]'::jsonb;
  v_request_sha text;
  v_catalog_sha text;
BEGIN
  IF v_literal IS NULL THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_LITERAL_REQUIRED';
  END IF;

  IF upper(coalesce(v_scope->>'target_type',''))<>'PANTALLA' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_REQUEST_V1',
      'status','NOT_APPLICABLE',
      'blocking_code','PROFILE_SCREEN_SELECTOR_SCOPE_NOT_SCREEN',
      'literal_request',v_literal,
      'scope',v_scope,
      'candidate_screen_count',0,
      'candidate_screens','[]'::jsonb,
      'route_authority',false,
      'effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;

  v_hint_like:=nullif(replace(replace(coalesce(v_hint,''),'%',''),'_',''),'');
  v_req:=' '||btrim(regexp_replace(lower(v_literal),'[^a-z0-9_]+',' ','g'))||' ';

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'screen_id',q.id,
      'screen_code',q.codigo,
      'screen_name',q.nombre,
      'screen_status',q.estado,
      'screen_version',q.version,
      'module_code',q.module_code,
      'app_shell_code',q.app_shell_code,
      'match',jsonb_build_object(
        'exact_code',q.exact_code,
        'exact_name',q.exact_name,
        'partial_code',q.partial_code,
        'partial_name',q.partial_name,
        'hint_contains_code',q.hint_contains_code,
        'hint_contains_name',q.hint_contains_name,
        'code_in_literal',q.code_in_literal,
        'name_in_literal',q.name_in_literal
      )
    )
    ORDER BY q.match_rank,q.codigo
  ),'[]'::jsonb)
  INTO v_candidates
  FROM (
    SELECT
      p.id,p.codigo,p.nombre,p.estado,p.version,
      m.module_code,s.app_shell_code,
      (v_hint IS NOT NULL AND upper(p.codigo)=upper(v_hint)) AS exact_code,
      (v_hint IS NOT NULL AND upper(p.nombre)=upper(v_hint)) AS exact_name,
      (v_hint_like IS NOT NULL AND length(v_hint_like)>=2
        AND upper(p.codigo) LIKE '%'||upper(v_hint_like)||'%') AS partial_code,
      (v_hint_like IS NOT NULL AND length(v_hint_like)>=2
        AND upper(p.nombre) LIKE '%'||upper(v_hint_like)||'%') AS partial_name,
      (v_hint_like IS NOT NULL AND length(v_hint_like)>=2
        AND upper(v_hint_like) LIKE '%'||upper(p.codigo)||'%') AS hint_contains_code,
      (v_hint_like IS NOT NULL AND length(v_hint_like)>=2
        AND upper(v_hint_like) LIKE '%'||upper(p.nombre)||'%') AS hint_contains_name,
      (strpos(
        v_req,
        ' '||btrim(regexp_replace(lower(p.codigo),'[^a-z0-9_]+',' ','g'))||' '
      )>0) AS code_in_literal,
      (length(btrim(regexp_replace(lower(p.nombre),'[^a-z0-9_]+',' ','g')))>=3
       AND strpos(
        v_req,
        ' '||btrim(regexp_replace(lower(p.nombre),'[^a-z0-9_]+',' ','g'))||' '
      )>0) AS name_in_literal,
      CASE
        WHEN v_hint IS NOT NULL AND upper(p.codigo)=upper(v_hint) THEN 1
        WHEN v_hint IS NOT NULL AND upper(p.nombre)=upper(v_hint) THEN 2
        WHEN strpos(
          v_req,
          ' '||btrim(regexp_replace(lower(p.codigo),'[^a-z0-9_]+',' ','g'))||' '
        )>0 THEN 3
        WHEN length(btrim(regexp_replace(lower(p.nombre),'[^a-z0-9_]+',' ','g')))>=3
         AND strpos(
          v_req,
          ' '||btrim(regexp_replace(lower(p.nombre),'[^a-z0-9_]+',' ','g'))||' '
        )>0 THEN 4
        ELSE 5
      END AS match_rank
    FROM lf_ops.pantallas p
    JOIN lf_ops.modulos m ON m.module_id=p.module_id
    JOIN lf_ops.app_shells s ON s.app_shell_id=m.app_shell_id
    WHERE p.activa
      AND (
        (v_hint IS NOT NULL AND (
          upper(p.codigo)=upper(v_hint)
          OR upper(p.nombre)=upper(v_hint)
        ))
        OR (v_hint_like IS NOT NULL AND length(v_hint_like)>=2 AND (
          upper(p.codigo) LIKE '%'||upper(v_hint_like)||'%'
          OR upper(p.nombre) LIKE '%'||upper(v_hint_like)||'%'
          OR upper(v_hint_like) LIKE '%'||upper(p.codigo)||'%'
          OR upper(v_hint_like) LIKE '%'||upper(p.nombre)||'%'
        ))
        OR strpos(
          v_req,
          ' '||btrim(regexp_replace(lower(p.codigo),'[^a-z0-9_]+',' ','g'))||' '
        )>0
        OR (
          length(btrim(regexp_replace(lower(p.nombre),'[^a-z0-9_]+',' ','g')))>=3
          AND strpos(
            v_req,
            ' '||btrim(regexp_replace(lower(p.nombre),'[^a-z0-9_]+',' ','g'))||' '
          )>0
        )
      )
  ) q;

  v_request_sha:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'literal_request',v_literal,
          'scope',v_scope
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  v_catalog_sha:=encode(
    extensions.digest(convert_to(v_candidates::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_REQUEST_V1',
    'status','READY',
    'selector','PROFILE_SCREEN_SELECTOR_LF',
    'literal_request',v_literal,
    'scope',v_scope,
    'target_hint',v_hint,
    'request_sha256',v_request_sha,
    'catalog_sha256',v_catalog_sha,
    'candidate_screen_count',jsonb_array_length(v_candidates),
    'candidate_screens',v_candidates,
    'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
    'deterministic_selection_performed',false,
    'allowed_decisions',jsonb_build_array('SELECTED','AMBIGUOUS','NO_MATCH'),
    'semantic_rules',jsonb_build_array(
      'COMPARE_LITERAL_AND_TARGET_HINT_AGAINST_ALL_CANDIDATE_SCREENS',
      'DETERMINISTIC_MATCHES_ARE_CANDIDATES_NOT_AUTHORITY',
      'DO_NOT_SELECT_SOLELY_BECAUSE_ONLY_ONE_CANDIDATE_EXISTS',
      'SELECTED_REQUIRES_ONE_SEMANTICALLY_SUPPORTED_SCREEN',
      'AMBIGUOUS_REQUIRES_TWO_OR_MORE_MATERIAL_CANDIDATES',
      'NO_MATCH_WHEN_NO_CANDIDATE_SEMANTICALLY_FITS',
      'DO_NOT_INVENT_SCREEN_OUTSIDE_CANDIDATE_SCREENS',
      'NO_ROUTE_OR_EFFECT_AUTHORITY'
    ),
    'semantic_output_contract',jsonb_build_object(
      'decision','SELECTED|AMBIGUOUS|NO_MATCH',
      'selected_screen_code','string|null',
      'ambiguous_screen_codes','array<string>',
      'reason','non-empty string',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object(
          'screen_code','candidate screen code',
          'evidence_field','screen_name|screen_code|module_code|app_shell_code|match'
        )
      ),
      'material_ambiguities','array<object>'
    ),
    'route_authority',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
END
$fn$;

COMMENT ON FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(text,jsonb) IS
'Builds a deterministic screen shortlist for profile Input Governance. It never chooses a screen; GPT Native must return SELECTED, AMBIGUOUS or NO_MATCH.';

REVOKE ALL ON FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(text,jsonb)
  TO service_role,supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(
  p_request jsonb,
  p_result jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
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
  IF p_request IS NULL
     OR p_result IS NULL
     OR jsonb_typeof(p_request)<>'object'
     OR jsonb_typeof(p_result)<>'object' THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_VALIDATION_V1',
      'status','BLOCKED',
      'blocking_codes',jsonb_build_array('PROFILE_SCREEN_SELECTOR_OBJECT_REQUIRED'),
      'route_authority',false,
      'effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;

  BEGIN
    v_current:=public.lf_profile_screen_selector_semantic_prepare_v1(
      p_request->>'literal_request',
      p_request->'scope'
    );
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_VALIDATION_V1',
      'status','BLOCKED',
      'blocking_codes',jsonb_build_array('PROFILE_SCREEN_SELECTOR_CURRENT_CATALOG_UNAVAILABLE'),
      'route_authority',false,
      'effect_authority',false,
      'downstream_execution_allowed',false
    );
  END;

  IF p_request->>'schema_version'<>'LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_REQUEST_V1'
     OR p_request->>'status'<>'READY'
     OR p_request->>'selector'<>'PROFILE_SCREEN_SELECTOR_LF'
     OR p_request->>'request_sha256' IS DISTINCT FROM v_current->>'request_sha256'
     OR p_request->>'catalog_sha256' IS DISTINCT FROM v_current->>'catalog_sha256'
     OR p_request->'candidate_screens' IS DISTINCT FROM v_current->'candidate_screens'
     OR p_request->>'candidate_screen_count' IS DISTINCT FROM v_current->>'candidate_screen_count'
  THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_REQUEST_STALE_OR_INVALID');
  END IF;

  IF p_result ?| ARRAY[
       'operation_code','action_code','candidate_action_code',
       'executor','executor_mode','router_action_binding',
       'route_authority','effect_authority','downstream_execution_allowed'
     ] THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_RESULT_AUTHORITY_FIELD_FORBIDDEN');
  END IF;

  IF p_result->>'schema_version'<>'LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_RESULT_V1'
     OR p_result->>'request_sha256' IS DISTINCT FROM p_request->>'request_sha256'
     OR p_result->>'catalog_sha256' IS DISTINCT FROM p_request->>'catalog_sha256'
     OR p_result->>'candidate_screen_count' IS DISTINCT FROM p_request->>'candidate_screen_count'
  THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_RESULT_BINDING_INVALID');
  END IF;

  v_decision:=upper(coalesce(p_result->>'decision',''));
  v_selected:=nullif(btrim(coalesce(p_result->>'selected_screen_code','')),'');
  v_ambiguous:=coalesce(p_result->'ambiguous_screen_codes','[]'::jsonb);
  v_evidence:=coalesce(p_result->'evidence_refs','[]'::jsonb);
  v_material:=coalesce(p_result->'material_ambiguities','[]'::jsonb);
  v_reason:=nullif(btrim(coalesce(p_result->>'reason','')),'');

  IF v_decision NOT IN ('SELECTED','AMBIGUOUS','NO_MATCH')
     OR jsonb_typeof(v_ambiguous)<>'array'
     OR jsonb_typeof(v_evidence)<>'array'
     OR jsonb_typeof(v_material)<>'array'
     OR v_reason IS NULL
  THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_RESULT_SHAPE_INVALID');
  END IF;

  IF v_selected IS NOT NULL AND NOT EXISTS(
    SELECT 1
    FROM jsonb_array_elements(p_request->'candidate_screens') s
    WHERE s->>'screen_code'=v_selected
  ) THEN
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_SELECTED_OUTSIDE_CATALOG');
  END IF;

  IF jsonb_typeof(v_ambiguous)='array' THEN
    SELECT count(*) INTO v_bad
    FROM jsonb_array_elements(v_ambiguous) x(item)
    WHERE jsonb_typeof(x.item)<>'string'
       OR NOT EXISTS(
          SELECT 1
          FROM jsonb_array_elements(p_request->'candidate_screens') s
          WHERE s->>'screen_code'=x.item#>>'{}'
       );

    IF v_bad>0 THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_AMBIGUOUS_OUTSIDE_CATALOG');
    END IF;

    IF (
      SELECT count(*) FROM (
        SELECT DISTINCT x.item#>>'{}' AS code
        FROM jsonb_array_elements(v_ambiguous) x(item)
      ) q
    ) <> jsonb_array_length(v_ambiguous) THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_AMBIGUOUS_DUPLICATE');
    END IF;
  END IF;

  IF jsonb_typeof(v_evidence)='array' THEN
    SELECT count(*) INTO v_bad
    FROM jsonb_array_elements(v_evidence) e(item)
    WHERE jsonb_typeof(e.item)<>'object'
       OR nullif(e.item->>'screen_code','') IS NULL
       OR nullif(e.item->>'evidence_field','') IS NULL
       OR e.item->>'evidence_field' NOT IN (
            'screen_name','screen_code','module_code','app_shell_code','match'
          )
       OR NOT EXISTS(
          SELECT 1
          FROM jsonb_array_elements(p_request->'candidate_screens') s
          WHERE s->>'screen_code'=e.item->>'screen_code'
       );

    IF v_bad>0 THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_EVIDENCE_REF_INVALID');
    END IF;
  END IF;

  IF v_decision='SELECTED' THEN
    IF v_selected IS NULL
       OR jsonb_array_length(v_ambiguous)<>0
       OR jsonb_array_length(v_material)<>0
       OR NOT EXISTS(
          SELECT 1
          FROM jsonb_array_elements(v_evidence) e(item)
          WHERE e.item->>'screen_code'=v_selected
       )
    THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_SELECTED_CONTRACT_INVALID');
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
            WHERE e.item->>'screen_code'=x.item#>>'{}'
          )
       )
    THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_AMBIGUOUS_CONTRACT_INVALID');
    END IF;
  ELSIF v_decision='NO_MATCH' THEN
    IF v_selected IS NOT NULL OR jsonb_array_length(v_ambiguous)<>0 THEN
      v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_NO_MATCH_CONTRACT_INVALID');
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
    v_blocking:=v_blocking||jsonb_build_array('PROFILE_SCREEN_SELECTOR_SEMANTIC_RECEIPT_INVALID');
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_VALIDATION_V1',
    'status',case when jsonb_array_length(v_blocking)=0 then 'VALID' else 'BLOCKED' end,
    'decision',v_decision,
    'selected_screen_code',v_selected,
    'ambiguous_screen_codes',v_ambiguous,
    'blocking_codes',v_blocking,
    'request_sha256',p_request->>'request_sha256',
    'catalog_sha256',p_request->>'catalog_sha256',
    'candidate_screen_count',p_request->>'candidate_screen_count',
    'route_authority',false,
    'effect_authority',false,
    'downstream_execution_allowed',false,
    'next_action',case
      when jsonb_array_length(v_blocking)>0 then 'STAY_BLOCKED'
      when v_decision='SELECTED' then 'SCREEN_SELECTION_READY_FOR_INPUT_GOVERNANCE'
      when v_decision='AMBIGUOUS' then 'HUMAN_OR_CALLER_DECISION_REQUIRED'
      else 'NO_SCREEN_MATCH_BLOCKED'
    end
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(jsonb,jsonb)
  TO service_role,supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_finalize_v1(
  p_request jsonb,
  p_draft jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  v_result jsonb;
  v_receipt text;
  v_validation jsonb;
BEGIN
  IF p_draft IS NULL OR jsonb_typeof(p_draft)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','PROFILE_SCREEN_SELECTOR_DRAFT_NOT_OBJECT'
    );
  END IF;

  IF p_draft ?| ARRAY[
       'schema_version','request_sha256','catalog_sha256','candidate_screen_count',
       'semantic_receipt_sha256','operation_code','action_code','candidate_action_code',
       'executor','executor_mode','router_action_binding',
       'route_authority','effect_authority','downstream_execution_allowed'
     ] THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','PROFILE_SCREEN_SELECTOR_DRAFT_CONTROL_FIELD_FORBIDDEN'
    );
  END IF;

  v_result:=jsonb_build_object(
    'schema_version','LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_RESULT_V1',
    'request_sha256',p_request->>'request_sha256',
    'catalog_sha256',p_request->>'catalog_sha256',
    'candidate_screen_count',coalesce((p_request->>'candidate_screen_count')::integer,0),
    'decision',upper(coalesce(p_draft->>'decision','')),
    'selected_screen_code',case
      when nullif(btrim(coalesce(p_draft->>'selected_screen_code','')),'') is null
        then null
      else p_draft->>'selected_screen_code'
    end,
    'ambiguous_screen_codes',coalesce(p_draft->'ambiguous_screen_codes','[]'::jsonb),
    'reason',p_draft->>'reason',
    'evidence_refs',coalesce(p_draft->'evidence_refs','[]'::jsonb),
    'material_ambiguities',coalesce(p_draft->'material_ambiguities','[]'::jsonb)
  );

  v_receipt:=encode(
    extensions.digest(convert_to(v_result::text,'UTF8'),'sha256'),
    'hex'
  );
  v_result:=v_result||jsonb_build_object('semantic_receipt_sha256',v_receipt);

  v_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
    p_request,v_result
  );

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_SCREEN_SELECTOR_SEMANTIC_FINALIZE_V1',
    'status',v_validation->>'status',
    'result',v_result,
    'validation',v_validation
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_screen_selector_semantic_finalize_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_screen_selector_semantic_finalize_v1(jsonb,jsonb)
  TO service_role,supabase_read_only_user;


CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_submit_v1(
  p_execution_id text,
  p_draft jsonb,
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_handoff jsonb;
  v_handoff_validation jsonb;
  v_request jsonb;
  v_final jsonb;
  v_existing jsonb;
  v_actor text;
BEGIN
  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id
  FOR UPDATE;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_SCREEN_SELECTOR_EXECUTION_INVALID'
    );
  END IF;

  v_handoff:=e.manifest->'router_profile_handoff';
  v_handoff_validation:=public.lf_router_profile_execution_handoff_validate_v1(
    v_handoff,
    v_handoff->>'literal_request',
    e.target_code
  );

  IF coalesce((v_handoff_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_SCREEN_SELECTOR_HANDOFF_INVALID',
      'handoff_validation',v_handoff_validation
    );
  END IF;

  v_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
    v_handoff->>'literal_request',
    v_handoff->'scope'
  );

  IF v_request->>'status'<>'READY'
     OR coalesce((v_request->>'candidate_screen_count')::integer,0)<=0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_SCREEN_SELECTOR_NO_CANDIDATES',
      'screen_selection_request',v_request
    );
  END IF;

  v_final:=public.lf_profile_screen_selector_semantic_finalize_v1(
    v_request,p_draft
  );

  IF v_final->>'status'<>'VALID' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_SCREEN_SELECTOR_SEMANTIC_INVALID',
      'finalize',v_final
    );
  END IF;

  v_existing:=e.manifest->'screen_selection_result';
  IF jsonb_typeof(v_existing)='object' THEN
    IF v_existing->>'semantic_receipt_sha256'
         IS NOT DISTINCT FROM v_final#>>'{result,semantic_receipt_sha256}' THEN
      RETURN jsonb_build_object(
        'status','ALREADY_BOUND',
        'execution_id',p_execution_id,
        'screen_selection_result',v_existing,
        'screen_selection_validation',v_final->'validation',
        'next_action','RETRY_SAME_NATIVE_BRIDGE_PREPARE',
        'router_reentry_required',false
      );
    END IF;

    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_SCREEN_SELECTOR_ALREADY_BOUND_DIFFERENT_RESULT',
      'execution_id',p_execution_id
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);

  UPDATE public.lf_operation_execution
  SET manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object(
        'screen_selection_schema_version','LF_PROFILE_SCREEN_SELECTOR_BINDING_V1',
        'screen_selection_request_sha256',v_request->>'request_sha256',
        'screen_selection_catalog_sha256',v_request->>'catalog_sha256',
        'screen_selection_result',v_final->'result',
        'screen_selection_validation',v_final->'validation',
        'screen_selection_bound_by',v_actor,
        'screen_selection_bound_at',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ),
      updated_by_execution_id=v_actor,
      updated_at=clock_timestamp()
  WHERE execution_id=p_execution_id
    AND status='IN_PROGRESS';

  RETURN jsonb_build_object(
    'status','BOUND',
    'execution_id',p_execution_id,
    'screen_selection_result',v_final->'result',
    'screen_selection_validation',v_final->'validation',
    'next_action',case
      when v_final#>>'{result,decision}'='SELECTED'
        then 'RETRY_SAME_NATIVE_BRIDGE_PREPARE'
      when v_final#>>'{result,decision}'='AMBIGUOUS'
        then 'HUMAN_OR_CALLER_DECISION_REQUIRED'
      else 'NO_SCREEN_MATCH_BLOCKED'
    end,
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_screen_selector_semantic_submit_v1(text,jsonb,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_screen_selector_semantic_submit_v1(text,jsonb,text)
  TO service_role;


CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_submit_raw_v1(
  p_execution_id text,
  p_raw text,
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_parse jsonb;
BEGIN
  v_parse:=public.lf_parse_semantic_judge_output_v1(p_raw);

  IF v_parse->>'status'<>'PASS' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_SCREEN_SELECTOR_MODEL_OUTPUT_INVALID',
      'parse',v_parse
    );
  END IF;

  RETURN public.lf_profile_screen_selector_semantic_submit_v1(
    p_execution_id,
    v_parse->'payload',
    p_actor_execution_id
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_screen_selector_semantic_submit_raw_v1(text,text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_screen_selector_semantic_submit_raw_v1(text,text,text)
  TO service_role;


-- Harden the final Input Governance resolver: it no longer interprets LIKE or text.
-- It accepts only a canonical screen backed by a valid semantic selector receipt.
CREATE OR REPLACE FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(
  p_request_text text,
  p_profile_code text,
  p_scope jsonb DEFAULT NULL,
  p_consumer text DEFAULT 'CONTEXT_PACK'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $fn$
DECLARE
  v_bound boolean:=false;
  v_screen_count integer:=0;
  v_pantalla_id integer;
  v_screen_code text:=nullif(btrim(coalesce(p_scope->>'resolved_screen_code','')),'');
  v_screen_request jsonb:=p_scope->'screen_selection_request';
  v_screen_result jsonb:=p_scope->'screen_selection_result';
  v_screen_validation jsonb;
  v_result jsonb;
  v_worker jsonb;
BEGIN
  SELECT EXISTS(
    SELECT 1
    FROM public.lf_activo_relaciones r
    JOIN public.lf_activos a
      ON a.codigo_activo=r.codigo_activo
     AND a.archived_at IS NULL
     AND a.tipo_activo='PERFIL'
    WHERE r.codigo_activo=p_profile_code
      AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND r.relacion_tipo='GOBERNADO_POR'
      AND a.metadata->>'input_governance_binding_mode'='DIRECT_PROFILE'
      AND a.metadata->>'input_governance_consumer'=p_consumer
  ) INTO v_bound;

  IF NOT v_bound THEN
    RETURN jsonb_build_object(
      'applicable',false,
      'status','NOT_REQUIRED',
      'decision','N/A',
      'continuation_allowed',true,
      'profile_code',p_profile_code,
      'binding_mode','NO_DIRECT_PROFILE_BINDING',
      'router_reentry_required',false
    );
  END IF;

  IF upper(coalesce(p_scope->>'resolution_status',''))<>'RESOLVED'
     OR p_scope->>'resolution_method'<>'DETERMINISTIC_SHORTLIST_THEN_SEMANTIC'
     OR v_screen_code IS NULL
     OR v_screen_request IS NULL
     OR v_screen_result IS NULL
     OR jsonb_typeof(v_screen_request)<>'object'
     OR jsonb_typeof(v_screen_result)<>'object'
     OR v_screen_request->>'literal_request' IS DISTINCT FROM p_request_text
  THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_NOT_SEMANTICALLY_RESOLVED',
      'decision','BLOCKED',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'router_reentry_required',false
    );
  END IF;

  v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
    v_screen_request,v_screen_result
  );

  IF v_screen_validation->>'status'<>'VALID'
     OR v_screen_result->>'decision'<>'SELECTED'
     OR v_screen_result->>'selected_screen_code' IS DISTINCT FROM v_screen_code
  THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_SEMANTIC_RECEIPT_INVALID',
      'decision','BLOCKED',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'screen_selection_validation',v_screen_validation,
      'router_reentry_required',false
    );
  END IF;

  SELECT count(*),min(id),min(codigo)
    INTO v_screen_count,v_pantalla_id,v_screen_code
  FROM lf_ops.pantallas
  WHERE activa
    AND upper(codigo)=upper(v_screen_code);

  IF v_screen_count<>1 THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','BLOCKED',
      'blocking_code',case
        when v_screen_count=0 then 'BLOCK_PROFILE_INPUT_GOVERNANCE_CANONICAL_SCREEN_NOT_FOUND'
        else 'BLOCK_PROFILE_INPUT_GOVERNANCE_CANONICAL_SCREEN_AMBIGUOUS'
      end,
      'decision','BLOCKED',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'router_reentry_required',false
    );
  END IF;

  v_result:=public.fn_input_governance_execute(v_pantalla_id,p_consumer);

  IF v_result->>'status'='READY' THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','READY',
      'blocking_code',null,
      'decision','PASS',
      'continuation_allowed',true,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'screen_selection_receipt_sha256',v_screen_result->>'semantic_receipt_sha256',
      'run_id',v_result->'run_id',
      'governance_output_sha256',v_result->'output_sha256',
      'context_manifest',v_result->'context_manifest',
      'governance_result',v_result,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_result->>'status' IN ('CURATOR_RUNTIME_REQUIRED','VALIDATOR_RUNTIME_REQUIRED') THEN
    v_worker:=coalesce(
      v_result->'worker_spec',
      public.fn_input_governance_worker_spec(v_pantalla_id,p_consumer)
    );
    RETURN jsonb_build_object(
      'applicable',true,
      'status','INPUT_GOVERNANCE_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_REQUIRED',
      'decision','PENDING',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'screen_selection_receipt_sha256',v_screen_result->>'semantic_receipt_sha256',
      'agent_status',v_result->>'status',
      'worker_spec',v_worker,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  IF v_result->>'status'='HUMAN_DECISION_REQUIRED' THEN
    RETURN jsonb_build_object(
      'applicable',true,
      'status','HUMAN_DECISION_REQUIRED',
      'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED',
      'decision','PARTIAL',
      'continuation_allowed',false,
      'profile_code',p_profile_code,
      'consumer',p_consumer,
      'binding_mode','DIRECT_PROFILE',
      'pantalla_id',v_pantalla_id,
      'screen_code',v_screen_code,
      'screen_selection_receipt_sha256',v_screen_result->>'semantic_receipt_sha256',
      'governance_result',v_result,
      'resume_via','EJECUCION_PERFIL_LF/input_validate',
      'router_reentry_required',false
    );
  END IF;

  RETURN jsonb_build_object(
    'applicable',true,
    'status','BLOCKED',
    'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE',
    'decision','BLOCKED',
    'continuation_allowed',false,
    'profile_code',p_profile_code,
    'consumer',p_consumer,
    'binding_mode','DIRECT_PROFILE',
    'pantalla_id',v_pantalla_id,
    'screen_code',v_screen_code,
    'screen_selection_receipt_sha256',v_screen_result->>'semantic_receipt_sha256',
    'governance_result',v_result,
    'resume_via','EJECUCION_PERFIL_LF/input_validate',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text)
  TO service_role;

COMMENT ON FUNCTION programacion.fn_lf_profile_input_governance_resolve_v1(text,text,jsonb,text) IS
'Final profile Input Governance resolver. Requires a canonical screen selected semantically from a deterministic shortlist and validates the semantic receipt before invoking Input Governance.';


CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1(
  p_execution_id text,
  p_input_literal text,
  p_input_source_ref text,
  p_handoff jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion'
AS $fn$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_handoff_validation jsonb;
  v_scope jsonb;
  v_adapters jsonb:='[]'::jsonb;
  v_ig jsonb;
  v_direct_profile_ig boolean:=false;
  v_task_requirement jsonb;
  v_screen_request jsonb;
  v_screen_result jsonb;
  v_screen_validation jsonb;
  v_resolved_scope jsonb;
BEGIN
  SELECT * INTO v_exec
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR v_exec.operation_code<>'EJECUCION_PERFIL_LF'
     OR v_exec.target_type<>'PERFIL'
     OR v_exec.status<>'IN_PROGRESS' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_EXECUTION_INVALID',
      'router_reentry_required',false
    );
  END IF;

  v_handoff_validation:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,p_input_literal,v_exec.target_code
  );
  IF coalesce((v_handoff_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_HANDOFF_INVALID',
      'handoff_validation',v_handoff_validation,
      'router_reentry_required',false
    );
  END IF;

  v_scope:=public.lf_profile_execution_scope_authority_packet_v1(
    p_execution_id,p_input_literal,p_input_source_ref
  );
  IF v_scope->>'status' IS DISTINCT FROM 'READY'
     OR jsonb_typeof(v_scope->'scope_authority_packet')<>'object'
     OR nullif(v_scope->>'scope_packet_sha256','') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_SCOPE_NOT_READY',
      'scope_result',v_scope,
      'router_reentry_required',false
    );
  END IF;

  v_task_requirement:=public.lf_profile_input_governance_requirement_v1(p_handoff);
  IF v_task_requirement->>'status'='BLOCKED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_task_requirement->>'blocking_code','BLOCK_PROFILE_IG_TASK_BINDING_INVALID'),
      'input_governance_task',v_task_requirement,
      'router_reentry_required',false
    );
  END IF;

  IF v_task_requirement->>'status'='NOT_REQUIRED' THEN
    v_ig:=jsonb_build_object(
      'applicable',false,
      'status','NOT_REQUIRED',
      'blocking_code',null,
      'decision','SKIP',
      'continuation_allowed',true,
      'binding_mode','DIRECT_PROFILE_CAPABILITY_NOT_INVOKED',
      'profile_task_intent',v_task_requirement->>'profile_task_intent',
      'input_governance_requirement',v_task_requirement->>'input_governance_requirement',
      'reason',v_task_requirement->>'reason'
    );
  ELSE
    SELECT EXISTS(
      SELECT 1
      FROM public.lf_activo_relaciones r
      WHERE r.codigo_activo=v_exec.target_code
        AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        AND r.relacion_tipo='GOBERNADO_POR'
    ) INTO v_direct_profile_ig;

    IF v_direct_profile_ig THEN
      IF upper(coalesce(p_handoff#>>'{scope,target_type}',''))<>'PANTALLA' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_SCOPE_REQUIRED',
          'router_reentry_required',false
        );
      END IF;

      v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
        p_input_literal,
        p_handoff->'scope'
      );

      IF v_screen_request->>'status'<>'READY'
         OR coalesce((v_screen_request->>'candidate_screen_count')::integer,0)<=0 THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_NO_MATCH',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_NO_CANDIDATES',
          'screen_selection_request',v_screen_request,
          'router_reentry_required',false,
          'next_action','REFINE_OR_CLARIFY_SCREEN_SCOPE'
        );
      END IF;

      v_screen_result:=v_exec.manifest->'screen_selection_result';

      IF v_screen_result IS NULL OR jsonb_typeof(v_screen_result)<>'object' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'screen_selection_request',v_screen_request,
          'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'semantic_selection_required',true,
          'submit_entrypoint','public.lf_profile_screen_selector_semantic_submit_v1',
          'submit_raw_entrypoint','public.lf_profile_screen_selector_semantic_submit_raw_v1',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false,
          'next_action','RUN_SCREEN_SEMANTIC_SELECTION_AND_SUBMIT'
        );
      END IF;

      v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
        v_screen_request,v_screen_result
      );

      IF v_screen_validation->>'status'<>'VALID' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_RECEIPT_INVALID',
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false
        );
      END IF;

      IF v_screen_result->>'decision'='AMBIGUOUS' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_AMBIGUOUS',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_AMBIGUOUS',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result,
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false,
          'next_action','HUMAN_OR_CALLER_DECISION_REQUIRED'
        );
      ELSIF v_screen_result->>'decision'='NO_MATCH' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_NO_MATCH',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_NO_MATCH',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result,
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false,
          'next_action','REFINE_OR_CLARIFY_SCREEN_SCOPE'
        );
      ELSIF v_screen_result->>'decision'<>'SELECTED' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_DECISION_INVALID',
          'screen_selection_result',v_screen_result,
          'router_reentry_required',false
        );
      END IF;

      v_resolved_scope:=coalesce(p_handoff->'scope','{}'::jsonb)
        ||jsonb_build_object(
          'target_hint',v_screen_result->>'selected_screen_code',
          'resolution_status','RESOLVED',
          'resolved_screen_code',v_screen_result->>'selected_screen_code',
          'resolution_method','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result
        );

      v_ig:=programacion.fn_lf_profile_input_governance_resolve_v1(
        p_input_literal,
        v_exec.target_code,
        v_resolved_scope,
        'CONTEXT_PACK'
      );

      v_ig:=v_ig||jsonb_build_object(
        'screen_selection',jsonb_build_object(
          'request_sha256',v_screen_request->>'request_sha256',
          'catalog_sha256',v_screen_request->>'catalog_sha256',
          'decision',v_screen_result->>'decision',
          'selected_screen_code',v_screen_result->>'selected_screen_code',
          'semantic_receipt_sha256',v_screen_result->>'semantic_receipt_sha256'
        )
      );
    ELSE
      SELECT coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb)
        INTO v_adapters
      FROM public.v_lf_router_adapter_bindings x
      WHERE x.target_asset_code=v_exec.target_code;

      IF jsonb_array_length(v_adapters)>0 THEN
        v_ig:=programacion.fn_lf_router_input_governance_resolve_v1(
          p_input_literal,v_adapters,'CONTEXT_PACK'
        );
      ELSE
        v_ig:=jsonb_build_object(
          'applicable',false,
          'status','NOT_REQUIRED',
          'blocking_code',null,
          'decision','N/A',
          'continuation_allowed',true,
          'required_by_adapters','[]'::jsonb,
          'binding_mode','NONE'
        );
      END IF;
    END IF;
  END IF;

  IF coalesce((v_ig->>'applicable')::boolean,false)
     AND coalesce((v_ig->>'continuation_allowed')::boolean,false) IS NOT TRUE THEN

    IF v_ig->>'status'='INPUT_GOVERNANCE_REQUIRED'
       AND v_ig->>'decision'='PENDING'
       AND v_ig->>'consumer'='CONTEXT_PACK'
       AND coalesce(v_ig->>'pantalla_id','') ~ '^[0-9]+$'
    THEN
      v_ig:=v_ig||jsonb_build_object(
        'dispatch',
        programacion.fn_input_governance_queue_submit_v1(
          (v_ig->>'pantalla_id')::integer,
          'CONTEXT_PACK'
        ),
        'dispatch_owner','INPUT_GOVERNANCE_INTERNAL_RUNTIME',
        'dispatch_transport','POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1'
      );
    END IF;

    RETURN jsonb_build_object(
      'status',coalesce(v_ig->>'status','BLOCKED'),
      'blocking_code',coalesce(v_ig->>'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_NOT_READY'),
      'input_governance',
        v_ig||jsonb_build_object(
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        ),
      'scope_authority_packet',v_scope->'scope_authority_packet',
      'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
      'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
      'router_reentry_required',false,
      'next_action','RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'
    );
  END IF;

  RETURN jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'server_validated',true,
    'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
    'activation_trigger_match',true,
    'scope_authority_packet',v_scope->'scope_authority_packet',
    'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
    'input_governance',
      coalesce(v_ig,'{}'::jsonb)||jsonb_build_object(
        'resume_via','EJECUCION_PERFIL_LF/input_validate',
        'router_reentry_required',false
      ),
    'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb) IS
'Canonical EJECUCION_PERFIL_LF input gate. For screen-scoped direct Input Governance, deterministic discovery must be followed by a validated GPT Native semantic screen selection before IG may run.';


CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(
  p_execution_id text,
  p_source_revision text,
  p_source_digest text,
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_handoff jsonb;
  v_valid jsonb;
  v_actor text;
  v_slug text;
  v_source_ref text;
  v_existing text;
  v_step jsonb;
  v_input jsonb;
  v_base_context jsonb;
  v_context jsonb;
  v_baseline jsonb;
  v_clean integer;
  v_policy_selection jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR coalesce(p_source_revision,'') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_source_digest,'') !~ '^sha256:[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_SOURCE_BINDING_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTION_INVALID'
    );
  END IF;

  v_handoff:=e.manifest->'router_profile_handoff';
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    v_handoff,
    v_handoff->>'literal_request',
    e.target_code
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  SELECT metadata->>'profile_slug' INTO v_slug
  FROM public.lf_activos
  WHERE codigo_activo=e.target_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL;

  IF nullif(v_slug,'') IS NULL
     OR nullif(e.target_repo,'') IS NULL
     OR nullif(e.target_path,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_UNRESOLVED'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_source_ref:='github://'||e.target_repo||'@'||p_source_revision||'/'||e.target_path;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_resolve';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_resolve',
      'supabase://public.lf_activos/'||e.target_code,
      jsonb_build_object(
        'exact_profile_resolved',true,
        'codigo_activo',e.target_code,
        'profile_slug',v_slug
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_RESOLVE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_source_read';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_source_read',
      v_source_ref,
      jsonb_build_object(
        'profile_source_ref',v_source_ref,
        'source_revision',p_source_revision,
        'profile_source_digest',p_source_digest,
        'profile_source_path',e.target_path
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input IS NULL THEN
    v_input:=public.lf_profile_execution_input_validate_v1(
      p_execution_id,
      v_handoff->>'literal_request',
      v_source_ref,
      v_handoff
    );

    IF v_input->>'status'<>'READY' THEN
      IF v_input->>'status'='SCREEN_SELECTION_REQUIRED'
         AND v_input->>'next_action'='RUN_SCREEN_SEMANTIC_SELECTION_AND_SUBMIT'
         AND jsonb_typeof(v_input->'screen_selection_request')='object'
      THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'screen_selection_request',v_input->'screen_selection_request',
          'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'semantic_selection_required',true,
          'submit_entrypoint','public.lf_profile_screen_selector_semantic_submit_v1',
          'submit_raw_entrypoint','public.lf_profile_screen_selector_semantic_submit_raw_v1',
          'next_action','SUBMIT_SCREEN_SELECTION_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;

      IF v_input->>'status'='INPUT_GOVERNANCE_REQUIRED'
         AND v_input->>'next_action'='RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'
         AND v_input#>>'{input_governance,dispatch,status}'='QUEUED'
      THEN
        RETURN jsonb_build_object(
          'status','INPUT_GOVERNANCE_PENDING',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'input_validate',v_input,
          'input_governance_request_id',
            v_input#>'{input_governance,dispatch,request_id}',
          'input_governance_transport',
            v_input#>>'{input_governance,dispatch_transport}',
          'next_action','RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;

      RETURN jsonb_build_object(
        'status',coalesce(v_input->>'status','BLOCKED'),
        'blocking_code',coalesce(
          v_input->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_VALIDATE_NOT_READY'
        ),
        'execution_id',p_execution_id,
        'input_validate',v_input,
        'router_reentry_required',false
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'input_validate',
      'supabase://public.lf_profile_execution_input_validate_v1/'||p_execution_id,
      v_input,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context IS NULL THEN
    v_base_context:=public.lf_profile_execution_context_admission_v1(p_execution_id);
    IF v_base_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_base_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_BASE_CONTEXT_NOT_READY'
        ),
        'base_context',v_base_context
      );
    END IF;

    v_context:=public.lf_profile_execution_channel_context_v1(
      p_execution_id,
      v_base_context,
      v_handoff
    );
    IF v_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_NOT_READY'
        ),
        'channel_context',v_context
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'context_admission',
      v_context->>'context_receipt_ref',
      v_context,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_baseline IS NULL THEN
    v_baseline:=public.lf_profile_execution_research_baseline_v1(
      p_execution_id,
      NULL,
      v_actor
    );
    IF coalesce(v_baseline->>'outcome','') NOT IN (
         'STEP_RECORDED',
         'STEP_ALREADY_RECORDED'
       )
       AND NOT EXISTS(
         SELECT 1
         FROM public.lf_operation_execution_steps
         WHERE execution_id=p_execution_id
           AND step_id='research_baseline_freeze'
           AND status='STEP_PASS_WITH_EVIDENCE'
       ) THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_BASELINE_NOT_READY',
        'baseline_result',v_baseline
      );
    END IF;

    SELECT evidence_payload INTO v_baseline
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id
      AND step_id='research_baseline_freeze'
      AND status='STEP_PASS_WITH_EVIDENCE';
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>7 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',7
    );
  END IF;

  v_policy_selection:=public.lf_profile_policy_selection_prepare_v1(p_execution_id);

  IF v_policy_selection->>'status'<>'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_policy_selection->>'blocking_code','BLOCK_PROFILE_POLICY_SELECTION_PREPARE_FAILED'),
      'policy_selection',v_policy_selection
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_MODEL_INPUT_READY',
    'execution_id',p_execution_id,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',e.target_code,
    'profile_slug',v_slug,
    'profile_source_ref',v_source_ref,
    'profile_source_digest',p_source_digest,
    'literal_request',v_handoff->>'literal_request',
    'input_governance',v_input->'input_governance',
    'context_receipt_ref',v_context->>'context_receipt_ref',
    'context_receipt_digest',v_context->>'context_receipt_digest',
    'context_capsule',v_context->'context_capsule',
    'research_baseline',v_baseline,
    'policy_resolution_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
    'policy_selection_request',v_policy_selection,
    'repair_execution_authority',
      e.manifest->'repair_execution_authority',
    'execution_write_mode',
      case
        when coalesce((e.manifest->>'governed_repair_write')::boolean,false)
          then 'GOVERNED_REPAIR_WRITE'
        else 'READ_ONLY'
      end,
    'clean_step_count',v_clean,
    'next_step','execute_profile',
    'next_action','EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT',
    'semantic_judge_after_output','INDEPENDENT_CONTEXT_REQUIRED',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text) IS
'Prepares governed GPT_NATIVE profile execution. Screen-scoped Input Governance pauses for deterministic-shortlist + semantic screen selection, then resumes the same execution_id before IG dispatch.';


CREATE OR REPLACE FUNCTION public.lf_profile_execution_channel_context_v1(
  p_execution_id text,
  p_base_context jsonb,
  p_handoff jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private','extensions','lf_ops','lf_design'
AS $fn$
DECLARE
  v_valid jsonb;
  v_pc jsonb;
  v_capsule jsonb;
  v_bytes bigint;
  v_tokens bigint;
  v_soft bigint;
  v_hard bigint;
  v_status text;
  v_event_id bigint;
  v_budget_event_id bigint;
  v_digest text;
  v_task_intent text;
  v_ig_requirement text;
  v_screen_id integer;
  v_screen_code text;
  v_screen_name text;
  v_screen_status text;
  v_screen_version text;
  v_module_code text;
  v_shell_code text;
  v_direct_rules jsonb:='[]'::jsonb;
  v_category_counts jsonb:='{}'::jsonb;
  v_effective_rule_count integer:=0;
  v_product_scope jsonb;
  v_screen_selection_result jsonb;
  v_screen_selection_request jsonb;
  v_screen_selection_validation jsonb;
BEGIN
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,
    p_handoff->>'literal_request',
    p_handoff->>'profile_code'
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_CHANNEL_CONTEXT_HANDOFF_INVALID',
      'handoff_validation',v_valid,
      'server_validated',false
    );
  END IF;

  IF p_handoff->>'channel'<>'PRODUCTO' THEN
    RETURN p_base_context||jsonb_build_object(
      'channel_context_mode','NOT_REQUIRED',
      'channel',p_handoff->>'channel'
    );
  END IF;

  v_task_intent:=upper(coalesce(
    p_handoff#>>'{semantic_request,router_action_binding,profile_task_intent}',
    ''
  ));
  v_ig_requirement:=upper(coalesce(
    p_handoff#>>'{semantic_request,router_action_binding,input_governance_requirement}',
    ''
  ));

  v_product_scope:=coalesce(p_handoff->'scope','{}'::jsonb);

  IF v_ig_requirement='REQUIRED_BY_TASK'
     AND upper(coalesce(p_handoff#>>'{scope,target_type}',''))='PANTALLA' THEN

    SELECT manifest->'screen_selection_result'
      INTO v_screen_selection_result
    FROM public.lf_operation_execution
    WHERE execution_id=p_execution_id
      AND operation_code='EJECUCION_PERFIL_LF'
      AND status='IN_PROGRESS';

    v_screen_selection_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
      p_handoff->>'literal_request',
      p_handoff->'scope'
    );

    IF v_screen_selection_result IS NULL
       OR jsonb_typeof(v_screen_selection_result)<>'object' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_SCREEN_SELECTION_MISSING',
        'server_validated',false
      );
    END IF;

    v_screen_selection_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
      v_screen_selection_request,
      v_screen_selection_result
    );

    IF v_screen_selection_validation->>'status'<>'VALID'
       OR v_screen_selection_result->>'decision'<>'SELECTED'
       OR nullif(v_screen_selection_result->>'selected_screen_code','') IS NULL THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_SCREEN_SELECTION_INVALID',
        'screen_selection_validation',v_screen_selection_validation,
        'server_validated',false
      );
    END IF;

    v_product_scope:=v_product_scope||jsonb_build_object(
      'target_hint',v_screen_selection_result->>'selected_screen_code',
      'resolution_status','RESOLVED',
      'resolved_screen_code',v_screen_selection_result->>'selected_screen_code',
      'resolution_method','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC'
    );
  END IF;

  IF v_task_intent='READ_PRODUCT_DEFINITION'
     AND v_ig_requirement='NOT_REQUIRED_CANONICAL_READ' THEN

    SELECT p.id,p.codigo,p.nombre,p.estado,p.version,p.module_code,m.app_shell_code
      INTO v_screen_id,v_screen_code,v_screen_name,v_screen_status,v_screen_version,
           v_module_code,v_shell_code
    FROM lf_ops.pantallas p
    JOIN lf_ops.modulos m ON m.module_code=p.module_code
    WHERE p.activa
      AND (
        upper(p.codigo)=upper(coalesce(p_handoff#>>'{scope,target_hint}',''))
        OR upper(p.nombre)=upper(coalesce(p_handoff#>>'{scope,target_hint}',''))
      );

    IF v_screen_id IS NULL THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PRODUCT_CANONICAL_READ_SUBJECT_NOT_RESOLVED',
        'target_hint',p_handoff#>>'{scope,target_hint}',
        'server_validated',false
      );
    END IF;

    SELECT coalesce(
      jsonb_agg(
        jsonb_build_array(r.codigo,r.titulo,r.estado)
        ORDER BY r.categoria,r.codigo
      ),
      '[]'::jsonb
    )
      INTO v_direct_rules
    FROM lf_ops.reglas_pantallas rp
    JOIN lf_ops.reglas r ON r.id=rp.regla_id
    WHERE rp.pantalla_id=v_screen_id;

    SELECT coalesce(jsonb_object_agg(q.categoria,q.cnt ORDER BY q.categoria),'{}'::jsonb)
      INTO v_category_counts
    FROM (
      SELECT r.categoria,count(*)::integer cnt
      FROM lf_ops.reglas_pantallas rp
      JOIN lf_ops.reglas r ON r.id=rp.regla_id
      WHERE rp.pantalla_id=v_screen_id
      GROUP BY r.categoria
    ) q;

    SELECT jsonb_array_length(coalesce(sc.contract->'rules','[]'::jsonb))
      INTO v_effective_rule_count
    FROM lf_ops.fn_screen_contract_v1(
      v_shell_code,v_module_code,v_screen_code
    ) sc
    LIMIT 1;

    v_pc:=jsonb_build_object(
      'schema_version','LF_PRODUCT_CANONICAL_RULE_READ_V1',
      'status','RESOLVED',
      'subject_ref',v_screen_code,
      'subject_name',v_screen_name,
      'screen_status',v_screen_status,
      'screen_version',v_screen_version,
      'task_intent',v_task_intent,
      'input_governance_requirement',v_ig_requirement,
      'direct_rule_count',jsonb_array_length(v_direct_rules),
      'effective_rule_count',coalesce(v_effective_rule_count,0),
      'rule_tuple_schema',jsonb_build_array('code','title','status'),
      'direct_rules',v_direct_rules,
      'category_counts',v_category_counts,
      'direct_rules_ref','supabase://lf_ops.reglas_pantallas/'||v_screen_code,
      'effective_rules_ref',
        'supabase://lf_ops.fn_screen_contract_v1/'||
        v_shell_code||'/'||v_module_code||'/'||v_screen_code||'#rules',
      'projection_mode','COMPACT_DIRECT_RULES_EFFECTIVE_AGGREGATE_LAZY',
      'canonical_read_only',true
    );
  ELSE
    v_pc:=public.lf_router_product_context_v1(
      p_handoff->>'literal_request',
      v_product_scope
    );
    IF v_pc->>'status' IS DISTINCT FROM 'RESOLVED' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_NOT_RESOLVED',
        'product_context_summary',v_pc-'product_context',
        'server_validated',false
      );
    END IF;
  END IF;

  v_capsule:=coalesce(p_base_context->'context_capsule','{}'::jsonb)
    ||jsonb_build_object(
      'channel_context',
      jsonb_build_object(
        'channel','PRODUCTO',
        'screen_selection_receipt_sha256',
          case
            when jsonb_typeof(v_screen_selection_result)='object'
              then v_screen_selection_result->>'semantic_receipt_sha256'
            else null
          end,
        'source',case
          when v_pc->>'schema_version'='LF_PRODUCT_CANONICAL_RULE_READ_V1'
            then 'lf_ops.reglas_pantallas + lf_ops.fn_screen_contract_v1#rule_count'
          else 'public.lf_router_product_context_v1'
        end,
        'product_context',v_pc
      )
    );

  v_bytes:=octet_length(v_capsule::text);
  v_tokens:=ceil(v_bytes/4.0)::bigint;
  v_soft:=coalesce((p_base_context->>'soft_limit_tokens')::bigint,1500);
  v_hard:=coalesce((p_base_context->>'hard_limit_tokens')::bigint,3000);
  v_status:=case
    when v_tokens>v_hard then 'RED'
    when v_tokens>v_soft then 'YELLOW'
    else 'GREEN'
  end;

  IF v_status='RED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_BUDGET_RED',
      'context_projection_schema',v_pc->>'schema_version',
      'estimated_tokens',v_tokens,
      'hard_limit_tokens',v_hard,
      'server_validated',false
    );
  END IF;

  v_capsule:=jsonb_set(
    v_capsule,
    '{context_budget}',
    jsonb_build_object(
      'estimated_tokens',v_tokens,
      'soft_limit_tokens',v_soft,
      'hard_limit_tokens',v_hard,
      'status',v_status
    ),
    true
  );

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,
    created_by_execution_id
  ) VALUES (
    'SESION_INICIO','ACTIVO','ACT-0001',
    'Channel-specific context hydration for governed profile execution.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'producer','lf_profile_execution_channel_context_v1',
      'purpose','Hydrate bounded channel-specific Product context for governed profile execution.',
      'occurred_at',clock_timestamp(),
      'execution_id',p_execution_id,
      'acceptance_declared',false,
      'channel','PRODUCTO',
      'base_context_receipt_ref',p_base_context->>'context_receipt_ref',
      'context_receipt',v_capsule
    ),
    'DB_FUNCTION',
    p_execution_id
  ) RETURNING id INTO v_event_id;

  INSERT INTO private.lf_context_budget_events_v2(
    execution_id,estimated_tokens,context_status,source,recommendation,
    evidence_event_id
  ) VALUES (
    p_execution_id,v_tokens,v_status,
    'lf_profile_execution_channel_context_v1',
    case
      when v_status='YELLOW'
        then 'Prefer lazy reads for any additional Product detail.'
      else null
    end,
    v_event_id
  )
  RETURNING id INTO v_budget_event_id;

  v_digest:='sha256:'||encode(
    extensions.digest(convert_to(v_capsule::text,'UTF8'),'sha256'),'hex'
  );

  RETURN p_base_context
    ||jsonb_build_object(
      'status','READY',
      'blocking_code',null,
      'server_validated',true,
      'channel','PRODUCTO',
      'channel_context_mode',
        case
          when v_pc->>'schema_version'='LF_PRODUCT_CANONICAL_RULE_READ_V1'
            then 'CANONICAL_READ_COMPACT'
          else 'HYDRATED_BY_EXECUTION'
        end,
      'context_event_id',v_event_id,
      'context_budget_event_id',v_budget_event_id,
      'context_receipt_ref',
        'supabase://public.lf_eventos/'||v_event_id::text||'#context_receipt',
      'context_receipt_digest',v_digest,
      'context_budget_status',v_status,
      'context_capsule_estimated_tokens',v_tokens,
      'context_capsule_bytes',v_bytes,
      'context_capsule',v_capsule
    );
END
$fn$;

COMMENT ON FUNCTION public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb) IS
'Channel context hydrator for EJECUCION_PERFIL_LF. Exact canonical Product reads receive a compact direct-rule projection with the inherited/effective aggregate lazy; change/analysis tasks retain the full governed Product context path.';


DO $regression$
DECLARE
  req jsonb;
  fin jsonb;
  broad jsonb;
  c1 text;
  c2 text;
  amb jsonb;
  bad jsonb;
  blocked jsonb;
  src text;
BEGIN
  req:=public.lf_profile_screen_selector_semantic_prepare_v1(
    'Revisa las reglas de la pantalla Iniciar sesión B2B de LF y evalúa si están completas y son consistentes.',
    jsonb_build_object(
      'target_type','PANTALLA',
      'target_hint','Iniciar sesión B2B',
      'resolution_status','UNRESOLVED'
    )
  );

  IF req->>'status'<>'READY'
     OR (req->>'candidate_screen_count')::integer<>1
     OR req#>>'{candidate_screens,0,screen_code}'<>'B2B-AUTH-001'
     OR coalesce((req->>'deterministic_selection_performed')::boolean,true) IS TRUE
  THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_LOGIN_SHORTLIST_REGRESSION:%',left(req::text,1800);
  END IF;

  fin:=public.lf_profile_screen_selector_semantic_finalize_v1(
    req,
    jsonb_build_object(
      'decision','SELECTED',
      'selected_screen_code','B2B-AUTH-001',
      'ambiguous_screen_codes','[]'::jsonb,
      'reason','The request is about the B2B sign-in screen and the sole deterministic candidate is semantically consistent with that intent.',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object('screen_code','B2B-AUTH-001','evidence_field','screen_name')
      ),
      'material_ambiguities','[]'::jsonb
    )
  );

  IF fin->>'status'<>'VALID'
     OR fin#>>'{result,decision}'<>'SELECTED'
     OR fin#>>'{validation,next_action}'<>'SCREEN_SELECTION_READY_FOR_INPUT_GOVERNANCE'
  THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_LOGIN_SEMANTIC_REGRESSION:%',left(fin::text,1800);
  END IF;

  broad:=public.lf_profile_screen_selector_semantic_prepare_v1(
    'Revisa B2B',
    jsonb_build_object(
      'target_type','PANTALLA',
      'target_hint','B2B',
      'resolution_status','UNRESOLVED'
    )
  );

  IF broad->>'status'<>'READY'
     OR (broad->>'candidate_screen_count')::integer<=1 THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_BROAD_CANDIDATES_REGRESSION:%',left(broad::text,1800);
  END IF;

  c1:=broad#>>'{candidate_screens,0,screen_code}';
  c2:=broad#>>'{candidate_screens,1,screen_code}';

  amb:=public.lf_profile_screen_selector_semantic_finalize_v1(
    broad,
    jsonb_build_object(
      'decision','AMBIGUOUS',
      'selected_screen_code',null,
      'ambiguous_screen_codes',jsonb_build_array(c1,c2),
      'reason','The request is too broad to distinguish at least two B2B screens.',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object('screen_code',c1,'evidence_field','screen_code'),
        jsonb_build_object('screen_code',c2,'evidence_field','screen_code')
      ),
      'material_ambiguities',jsonb_build_array(
        jsonb_build_object('code','B2B_SCOPE_TOO_BROAD')
      )
    )
  );

  IF amb->>'status'<>'VALID'
     OR amb#>>'{result,decision}'<>'AMBIGUOUS'
     OR amb#>>'{validation,next_action}'<>'HUMAN_OR_CALLER_DECISION_REQUIRED'
  THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_AMBIGUITY_REGRESSION:%',left(amb::text,1800);
  END IF;

  bad:=public.lf_profile_screen_selector_semantic_finalize_v1(
    req,
    jsonb_build_object(
      'decision','SELECTED',
      'selected_screen_code','B2B-NOT-A-REAL-SCREEN',
      'ambiguous_screen_codes','[]'::jsonb,
      'reason','negative',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object('screen_code','B2B-AUTH-001','evidence_field','screen_name')
      ),
      'material_ambiguities','[]'::jsonb
    )
  );

  IF bad->>'status'<>'BLOCKED'
     OR NOT ((bad#>'{validation,blocking_codes}') ? 'PROFILE_SCREEN_SELECTOR_SELECTED_OUTSIDE_CATALOG')
  THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_OUTSIDE_CATALOG_NEGATIVE_FAILED:%',left(bad::text,1800);
  END IF;

  blocked:=programacion.fn_lf_profile_input_governance_resolve_v1(
    'Revisa las reglas de la pantalla Iniciar sesión B2B de LF',
    'PERFIL-PRODUCT-DIRECTOR-LF',
    jsonb_build_object(
      'target_type','PANTALLA',
      'target_hint','Iniciar sesión B2B',
      'resolution_status','UNRESOLVED'
    ),
    'CONTEXT_PACK'
  );

  IF blocked->>'status'<>'BLOCKED'
     OR blocked->>'blocking_code'<>'BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_NOT_SEMANTICALLY_RESOLVED'
  THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_DIRECT_RESOLVER_BYPASS_NOT_CLOSED:%',left(blocked::text,1800);
  END IF;

  src:=pg_get_functiondef(
    'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
  );
  IF strpos(src,'lf_profile_screen_selector_semantic_prepare_v1')=0
     OR strpos(src,'SCREEN_SELECTION_REQUIRED')=0
     OR strpos(src,'DETERMINISTIC_SHORTLIST_THEN_SEMANTIC')=0 THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_INPUT_VALIDATE_POSTCHECK_FAILED';
  END IF;

  src:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );
  IF strpos(src,'SUBMIT_SCREEN_SELECTION_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE')=0
     OR strpos(src,'lf_profile_screen_selector_semantic_submit_v1')=0 THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_BRIDGE_POSTCHECK_FAILED';
  END IF;

  src:=pg_get_functiondef(
    'public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)'::regprocedure
  );
  IF strpos(src,'BLOCK_PRODUCT_CHANNEL_CONTEXT_SCREEN_SELECTION_MISSING')=0
     OR strpos(src,'v_product_scope')=0
     OR strpos(src,'screen_selection_receipt_sha256')=0 THEN
    RAISE EXCEPTION 'PROFILE_SCREEN_SELECTOR_CHANNEL_CONTEXT_POSTCHECK_FAILED';
  END IF;
END
$regression$;

COMMIT;
