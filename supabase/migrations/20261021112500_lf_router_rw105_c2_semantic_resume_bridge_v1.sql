-- RW1-05_C2: semantic resume bridge back into the SAME ACT-0001 Router.
-- The semantic specialist does not select route/operation/executor/effect.
-- The wrapper validates request/result, asks ACT-0001 for candidate action, then
-- invokes the same Router under a postgres-only transaction-local attestation.
-- p_distribution_mode remains ROUTER so policy selection is unchanged.
BEGIN;

DO $patch_router$
DECLARE
  v_def text;
  v_old text;
  v_new text;
  v_before_md5 text;
BEGIN
  v_before_md5:=md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure));
  IF v_before_md5<>'8cffdd7403c0ae40d5db19890ea4f944' THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_ROUTER_SOURCE_DRIFT:%',v_before_md5;
  END IF;

  v_def:=pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure);

  v_old:=E'  v_discovery_count integer := 0;\nbegin';
  v_new:=E'  v_discovery_count integer := 0;\n  v_semantic_resume_internal boolean := false;\nbegin\n  v_semantic_resume_internal := (\n    current_user = ''postgres''\n    and current_setting(''lf.router_semantic_resume_request_sha'',true) = encode(extensions.digest(convert_to(coalesce(p_request_text,''''),''UTF8''),''sha256''),''hex'')\n    and lower(coalesce(current_setting(''lf.router_semantic_resume_target'',true),'''')) = lower(btrim(coalesce(p_target_hint,'''')))\n    and upper(coalesce(current_setting(''lf.router_semantic_resume_action'',true),'''')) = upper(btrim(coalesce(p_action_hint,'''')))\n    and upper(coalesce(current_setting(''lf.router_semantic_resume_asset_type'',true),'''')) = upper(btrim(coalesce(p_asset_type_hint,'''')))\n  );';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_DECLARATION_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=E'  if nullif(btrim(coalesce(p_target_hint,'''')),'''') is not null\n     and v_action not in (''ASSET_INSPECTION'')';
  v_new:=E'  if not v_semantic_resume_internal\n     and nullif(btrim(coalesce(p_target_hint,'''')),'''') is not null\n     and v_action not in (''ASSET_INSPECTION'')';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_EXPLICIT_GUARD_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  v_old:=E'  if v_action <> ''ASSET_INSPECTION''\n     and v_req ~ ''(^| )(sin|no|excepto|excluye|excluir|excluyendo|excluido|excluida)( |$)''';
  v_new:=E'  if not v_semantic_resume_internal\n     and v_action <> ''ASSET_INSPECTION''\n     and v_req ~ ''(^| )(sin|no|excepto|excluye|excluir|excluyendo|excluido|excluida)( |$)''';
  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_NEGATIVE_GUARD_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old,v_new);

  EXECUTE v_def;
END
$patch_router$;

CREATE OR REPLACE FUNCTION public.lf_router_semantic_resume_route_v1(
  p_request jsonb,
  p_result jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  v_validation jsonb;
  v_target text;
  v_asset_type text;
  v_candidate_count integer:=0;
  v_probe jsonb;
  v_action text;
  v_route jsonb;
  v_request_sha text;
BEGIN
  v_validation:=public.lf_router_semantic_resume_validate_v1(p_request,p_result);

  IF coalesce(v_validation->>'status','')<>'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE
     OR p_result->>'decision'<>'RESOLVED'
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_SEMANTIC_RESUME_INVALID',
      'resume_validation',v_validation,
      'semantic_result_route_authority',false,
      'semantic_result_effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;

  IF jsonb_array_length(p_result->'positive_target_refs')<>1 THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_SEMANTIC_RESUME_TARGET_CARDINALITY',
      'resume_validation',v_validation,
      'semantic_result_route_authority',false,
      'semantic_result_effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;

  v_target:=p_result#>>'{positive_target_refs,0}';
  SELECT count(*),
         min(coalesce(x.item->>'asset_type',
                      case when x.item ? 'operation_code' then 'OPERATION_CODE' else null end))
    INTO v_candidate_count,v_asset_type
  FROM jsonb_array_elements(p_request->'candidate_subjects') x(item)
  WHERE coalesce(
    x.item->>'asset_code',
    x.item->>'operation_code',
    x.item->>'codigo_activo',
    x.item->>'code'
  )=v_target;

  IF v_candidate_count<>1 OR nullif(v_asset_type,'') IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_SEMANTIC_RESUME_TARGET_NOT_CANONICAL_ASSET',
      'resume_validation',v_validation,
      'semantic_result_route_authority',false,
      'semantic_result_effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;

  -- Probe ACT-0001 normally. This is the only source of candidate_action_code.
  v_probe:=public.lf_router_resolve_v1(
    p_request->>'literal_request',
    v_target,
    null,
    v_asset_type,
    'ROUTER'
  );

  IF v_probe->>'blocking_code'<>'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED'
     OR nullif(v_probe->>'candidate_action_code','') IS NULL
     OR v_probe->>'candidate_asset_type' IS DISTINCT FROM v_asset_type
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_SEMANTIC_RESUME_ROUTER_PROBE_UNEXPECTED',
      'resume_validation',v_validation,
      'router_probe',v_probe,
      'semantic_result_route_authority',false,
      'semantic_result_effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;

  v_action:=v_probe->>'candidate_action_code';
  v_request_sha:=p_request->>'request_sha256';

  -- Transaction-local, postgres-only attestation. Direct service_role/read-only
  -- calls to lf_router_resolve_v1 cannot satisfy current_user='postgres'.
  PERFORM set_config('lf.router_semantic_resume_request_sha',v_request_sha,true);
  PERFORM set_config('lf.router_semantic_resume_target',v_target,true);
  PERFORM set_config('lf.router_semantic_resume_action',v_action,true);
  PERFORM set_config('lf.router_semantic_resume_asset_type',v_asset_type,true);

  BEGIN
    v_route:=public.lf_router_resolve_v1(
      p_request->>'literal_request',
      v_target,
      v_action,
      v_asset_type,
      'ROUTER'
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('lf.router_semantic_resume_request_sha','',true);
    PERFORM set_config('lf.router_semantic_resume_target','',true);
    PERFORM set_config('lf.router_semantic_resume_action','',true);
    PERFORM set_config('lf.router_semantic_resume_asset_type','',true);
    RAISE;
  END;

  PERFORM set_config('lf.router_semantic_resume_request_sha','',true);
  PERFORM set_config('lf.router_semantic_resume_target','',true);
  PERFORM set_config('lf.router_semantic_resume_action','',true);
  PERFORM set_config('lf.router_semantic_resume_asset_type','',true);

  IF v_route->>'router' IS DISTINCT FROM 'ACT-0001'
     OR v_route->>'blocking_code' IN (
       'BLOCK_MULTIPLE_EXACT_TARGETS_NEED_SCOPE',
       'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED',
       'BLOCK_SCOPE_SEMANTICS_UNATTESTED',
       'BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED'
     )
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_SEMANTIC_RESUME_ROUTER_REDERIVE_INVALID',
      'resume_validation',v_validation,
      'router_probe',v_probe,
      'router_result',v_route,
      'semantic_result_route_authority',false,
      'semantic_result_effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_ROUTE_RESUME_V1',
    'status','ROUTER_REDERIVED',
    'request_sha256',v_request_sha,
    'validated_target_ref',v_target,
    'router_derived_action_code',v_action,
    'resume_validation',v_validation,
    'router_probe',v_probe,
    'router_result',v_route,
    'semantic_result_route_authority',false,
    'semantic_result_effect_authority',false,
    'downstream_execution_allowed',false,
    'next_action','OBSERVE_ROUTER_RESULT_T2_SHADOW_ONLY'
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_router_semantic_resume_route_v1(jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_semantic_resume_route_v1(jsonb,jsonb)
  TO postgres,service_role,supabase_read_only_user;

COMMENT ON FUNCTION public.lf_router_semantic_resume_route_v1(jsonb,jsonb) IS
'RW1-05_C2 T2 shadow resume bridge. Validates the semantic result, asks ACT-0001 itself for candidate action, then re-enters the same Router under a postgres-only transaction-local attestation. It never makes the specialist route/operation/effect authority and does not authorize downstream effect.';

DO $post$
DECLARE
  v_router_md5 text;
  v_literal text:='Actualiza ACT-0053 y ACT-0052, excepto ACT-0052, solo si la fuente sigue CURRENT.';
  v_sha text;
  v_req jsonb;
  v_res jsonb;
  v_out jsonb;
  v_direct jsonb;
BEGIN
  v_router_md5:=md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure));
  IF v_router_md5='8cffdd7403c0ae40d5db19890ea4f944' THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_ROUTER_PATCH_NOT_APPLIED';
  END IF;

  IF strpos(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure),
            'v_semantic_resume_internal')=0
     OR strpos(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure),
            'lf.router_semantic_resume_request_sha')=0
  THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_ROUTER_PATCH_POSTCHECK_FAILED';
  END IF;

  v_sha:=encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex');
  v_req:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_REQUEST_V1',
    'router','ACT-0001',
    'literal_request',v_literal,
    'request_sha256',v_sha,
    'reference_kind','CANONICAL_ASSET',
    'candidate_subjects',jsonb_build_array(
      jsonb_build_object('asset_code','ACT-0052','asset_type','SKILL'),
      jsonb_build_object('asset_code','ACT-0053','asset_type','SKILL')
    ),
    'positive_target_refs','[]'::jsonb,
    'excluded_target_refs','[]'::jsonb,
    'allowed_scope',jsonb_build_array('ACT-0052','ACT-0053'),
    'forbidden_scope','[]'::jsonb,
    'conditions','[]'::jsonb,
    'source_currentness',jsonb_build_object(
      'status','CURRENT',
      'authority','ACT-0001_DB_CURRENT',
      'router_source_md5',v_router_md5
    )
  );
  v_res:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1',
    'request_sha256',v_sha,
    'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array('ACT-0053'),
    'excluded_target_refs',jsonb_build_array('ACT-0052'),
    'allowed_scope',jsonb_build_array('ACT-0053'),
    'forbidden_scope',jsonb_build_array('ACT-0052'),
    'conditions',jsonb_build_array(jsonb_build_object('kind','ONLY_IF','value','CURRENT')),
    'material_ambiguities','[]'::jsonb,
    'clarification_question',null,
    'semantic_receipt_sha256',repeat('a',64)
  );

  v_out:=public.lf_router_semantic_resume_route_v1(v_req,v_res);
  IF v_out->>'status'<>'ROUTER_REDERIVED'
     OR v_out#>>'{resume_validation,status}'<>'VALID'
     OR v_out#>>'{router_result,router}'<>'ACT-0001'
     OR v_out#>>'{router_probe,candidate_action_code}'<>'SKILL_UPDATE'
     OR coalesce((v_out->>'downstream_execution_allowed')::boolean,true) IS NOT FALSE
     OR coalesce((v_out->>'semantic_result_route_authority')::boolean,true) IS NOT FALSE
     OR coalesce((v_out->>'semantic_result_effect_authority')::boolean,true) IS NOT FALSE
  THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_POSITIVE_POSTCHECK_FAILED:%',v_out::text;
  END IF;

  -- Direct normal Router call remains blocked; only the validated wrapper resumes.
  v_direct:=public.lf_router_resolve_v1(v_literal,'ACT-0053',null,'SKILL','ROUTER');
  IF v_direct->>'blocking_code'<>'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED' THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_DIRECT_ROUTER_BYPASS:%',v_direct::text;
  END IF;

  IF has_function_privilege('anon','public.lf_router_semantic_resume_route_v1(jsonb,jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_router_semantic_resume_route_v1(jsonb,jsonb)','EXECUTE')
  THEN
    RAISE EXCEPTION 'RW105_C2_SEMANTIC_RESUME_ACL_WIDENED';
  END IF;
END
$post$;

COMMIT;
