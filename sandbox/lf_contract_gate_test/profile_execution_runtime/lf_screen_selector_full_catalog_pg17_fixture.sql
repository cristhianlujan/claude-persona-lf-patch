-- Only for disposable PostgreSQL 17.6 CI, never production.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS lf_ops;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE lf_ops.app_shells(app_shell_id int PRIMARY KEY,app_shell_code text);
CREATE TABLE lf_ops.modulos(module_id int PRIMARY KEY,module_code text,app_shell_id int REFERENCES lf_ops.app_shells(app_shell_id));
CREATE TABLE lf_ops.pantallas(
 id int PRIMARY KEY,codigo text UNIQUE,nombre text,estado text,version int,
 module_id int REFERENCES lf_ops.modulos(module_id),activa boolean);
INSERT INTO lf_ops.app_shells VALUES (1,'B2B_APP_SHELL'),(2,'B2C_APP_SHELL');
INSERT INTO lf_ops.modulos VALUES (11,'B2B_AUTENTICACION',1),(12,'B2B_CARGAS',1),(21,'B2C_HOME',2);
INSERT INTO lf_ops.pantallas VALUES
 (51,'B2B-AUTH-001','Iniciar sesión','CANDIDATO',1,11,true),
 (52,'B2B-AUTH-002','Recuperar acceso','CANDIDATO',1,11,true),
 (60,'B2C-HOME-001','Inicio','CANDIDATO',1,21,true),
 (55,'B2B-AUTH-005','Configurar verificación','REEMPLAZADO',1,11,false);
SET check_function_bodies=off;
-- ORIGINAL_lf_profile_screen_selector_semantic_prepare_v1 MD5=7fefd902c745d18bf469b01b3280fe63
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(p_literal_request text, p_scope jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'lf_ops', 'extensions'
AS $function$
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
$function$;

-- ORIGINAL_lf_profile_screen_selector_semantic_validate_v1 MD5=e07f1df0665b5f91dccd0a5176ed14ce
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(p_request jsonb, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
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
$function$;

-- ORIGINAL_lf_profile_screen_selector_semantic_finalize_v1 MD5=82fc6028a515beb6061a4d539d7c84ee
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_finalize_v1(p_request jsonb, p_draft jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
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
$function$;
RESET check_function_bodies;
