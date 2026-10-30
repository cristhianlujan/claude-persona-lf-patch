-- Candidate: LF selector, deterministic filtered discovery then full-active fallback.
BEGIN;
DO $guard$
BEGIN
 IF to_regprocedure('public.lf_profile_screen_selector_semantic_prepare_v1(text,jsonb)') IS NULL
 OR md5(pg_get_functiondef('public.lf_profile_screen_selector_semantic_prepare_v1(text,jsonb)'::regprocedure)) <> '7fefd902c745d18bf469b01b3280fe63' THEN
 RAISE EXCEPTION 'BLOCK_PROFILE_SCREEN_SELECTOR_SOURCE_DRIFT';
 END IF;
END;
$guard$;
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
  v_filtered_count integer:=0;
  v_discovery_mode text:='FILTERED_DETERMINISTIC';
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
  v_filtered_count:=jsonb_array_length(v_candidates);
  IF v_filtered_count=0 THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
       'screen_id',p.id,'screen_code',p.codigo,'screen_name',p.nombre,
       'screen_status',p.estado,'screen_version',p.version,
       'module_code',m.module_code,'app_shell_code',sh.app_shell_code,
       'match',jsonb_build_object(
         'exact_code',false,'exact_name',false,
         'partial_code',false,'partial_name',false,
         'hint_contains_code',false,'hint_contains_name',false,
         'code_in_literal',false,'name_in_literal',false
       )
    ) ORDER BY p.codigo),'[]'::jsonb) INTO v_candidates
    FROM lf_ops.pantallas p JOIN lf_ops.modulos m ON m.module_id=p.module_id
    JOIN lf_ops.app_shells sh ON sh.app_shell_id=m.app_shell_id
    WHERE p.activa;
    v_discovery_mode:='FULL_ACTIVE_CATALOG_FALLBACK';
  END IF;

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
    'discovery_mode',v_discovery_mode,
    'deterministic_filtered_candidate_count',v_filtered_count,
    'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
    'deterministic_selection_performed',false,
    'allowed_decisions',jsonb_build_array('SELECTED','AMBIGUOUS','NO_MATCH'),
    'semantic_rules',jsonb_build_array(
      'COMPARE_LITERAL_AND_TARGET_HINT_AGAINST_ALL_CANDIDATE_SCREENS',
      'DETERMINISTIC_MATCHES_ARE_CANDIDATES_NOT_AUTHORITY',
      'FULL_ACTIVE_CATALOG_FALLBACK_REQUIRES_SEMANTIC_DECISION',
      'FALLBACK_DOES_NOT_AUTHORIZE_AUTOMATIC_SELECTION',
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
COMMIT;
