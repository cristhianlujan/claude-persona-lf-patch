-- RW1-04_C2 semantic V2 implementation. Atomic: failed assertions roll back all changes.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_intent_handoff_v2(
 p_request_text text,p_candidates jsonb,p_reference_kind text,
 p_conditions jsonb DEFAULT '[]'::jsonb,p_source_currentness jsonb DEFAULT NULL::jsonb
) RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'pg_catalog','public' AS $f$
WITH c AS (
 SELECT CASE WHEN jsonb_typeof(coalesce(p_candidates,'[]'::jsonb))='array'
   THEN coalesce(p_candidates,'[]'::jsonb) ELSE '[]'::jsonb END a
), refs AS (
 SELECT coalesce(jsonb_agg(to_jsonb(ref) ORDER BY ord) FILTER(WHERE ref IS NOT NULL),'[]'::jsonb) a
 FROM c LEFT JOIN LATERAL jsonb_array_elements(c.a) WITH ORDINALITY x(item,ord) ON true
 LEFT JOIN LATERAL (SELECT nullif(coalesce(
   x.item->>'asset_code',x.item->>'artifact_ref',x.item->>'path',x.item->>'screen_code',
   x.item->>'operation_code',x.item->>'codigo_activo',x.item->>'code',x.item->>'name'),'') ref) r ON true
), src AS (
 SELECT jsonb_build_object(
   'status','CURRENT',
   'router_source_md5',md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)),
   'authority','ACT-0001_DB_CURRENT') j
)
SELECT jsonb_build_object(
 'schema_version','LF_ROUTER_SEMANTIC_REQUEST_V1','router','ACT-0001',
 'literal_request',p_request_text,
 'request_sha256',encode(extensions.digest(convert_to(coalesce(p_request_text,''),'UTF8'),'sha256'),'hex'),
 'reference_kind',p_reference_kind,'candidate_subjects',(SELECT a FROM c),
 'positive_target_refs','[]'::jsonb,'excluded_target_refs','[]'::jsonb,
 'allowed_scope',(SELECT a FROM refs),'forbidden_scope','[]'::jsonb,
 'conditions',CASE WHEN jsonb_typeof(coalesce(p_conditions,'[]'::jsonb))='array'
                   THEN coalesce(p_conditions,'[]'::jsonb) ELSE jsonb_build_array(p_conditions) END,
 'source_currentness',
   (CASE WHEN jsonb_typeof(coalesce(p_source_currentness,'{}'::jsonb))='object'
         THEN coalesce(p_source_currentness,'{}'::jsonb) ELSE '{}'::jsonb END)||(SELECT j FROM src)
);
$f$;

REVOKE ALL ON FUNCTION public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)
 TO postgres,service_role,supabase_read_only_user;

CREATE OR REPLACE FUNCTION public.lf_router_semantic_resume_validate_v1(p_request jsonb,p_result jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog','public' AS $f$
DECLARE
 c jsonb:='[]'::jsonb; bad int:=0; h text; cur text; ok boolean:=true; d text;
BEGIN
 IF jsonb_typeof(p_request)<>'object' OR jsonb_typeof(p_result)<>'object' THEN ok:=false; END IF;
 IF ok AND (NOT(p_request ?& ARRAY['schema_version','router','literal_request','request_sha256','reference_kind',
   'candidate_subjects','positive_target_refs','excluded_target_refs','allowed_scope','forbidden_scope','conditions','source_currentness'])
   OR NOT(p_result ?& ARRAY['schema_version','request_sha256','decision','positive_target_refs','excluded_target_refs',
   'allowed_scope','forbidden_scope','conditions','material_ambiguities','clarification_question','semantic_receipt_sha256']))
 THEN ok:=false; END IF;
 IF ok AND (p_request->>'schema_version'<>'LF_ROUTER_SEMANTIC_REQUEST_V1'
   OR p_request->>'router'<>'ACT-0001' OR p_result->>'schema_version'<>'LF_ROUTER_SEMANTIC_RESULT_V1') THEN ok:=false; END IF;
 IF ok AND (jsonb_typeof(p_request->'candidate_subjects')<>'array'
   OR jsonb_typeof(p_request->'excluded_target_refs')<>'array' OR jsonb_typeof(p_request->'allowed_scope')<>'array'
   OR jsonb_typeof(p_request->'forbidden_scope')<>'array' OR jsonb_typeof(p_request->'conditions')<>'array'
   OR jsonb_typeof(p_request->'source_currentness')<>'object'
   OR jsonb_typeof(p_result->'positive_target_refs')<>'array' OR jsonb_typeof(p_result->'excluded_target_refs')<>'array'
   OR jsonb_typeof(p_result->'allowed_scope')<>'array' OR jsonb_typeof(p_result->'forbidden_scope')<>'array'
   OR jsonb_typeof(p_result->'conditions')<>'array' OR jsonb_typeof(p_result->'material_ambiguities')<>'array') THEN ok:=false; END IF;
 IF ok AND p_result ?| ARRAY['operation_code','executor','effect_authority','downstream_execution_allowed','route_authority'] THEN ok:=false; END IF;

 IF ok THEN
   h:=encode(extensions.digest(convert_to(coalesce(p_request->>'literal_request',''),'UTF8'),'sha256'),'hex');
   cur:=md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure));
   IF p_request->>'request_sha256'<>h OR p_result->>'request_sha256'<>h
      OR p_request#>>'{source_currentness,status}'<>'CURRENT'
      OR p_request#>>'{source_currentness,router_source_md5}'<>cur THEN ok:=false; END IF;
 END IF;

 IF ok THEN
   SELECT coalesce(jsonb_agg(to_jsonb(ref) ORDER BY ord) FILTER(WHERE ref IS NOT NULL),'[]'::jsonb) INTO c
   FROM jsonb_array_elements(p_request->'candidate_subjects') WITH ORDINALITY x(item,ord)
   LEFT JOIN LATERAL (SELECT nullif(coalesce(x.item->>'asset_code',x.item->>'artifact_ref',x.item->>'path',
     x.item->>'screen_code',x.item->>'operation_code',x.item->>'codigo_activo',x.item->>'code',x.item->>'name'),'') ref) r ON true;

   SELECT count(*) INTO bad FROM jsonb_array_elements_text(p_result->'positive_target_refs') z(v)
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(c) q(v) WHERE q.v=z.v);
   IF bad>0 THEN ok:=false; END IF;
   SELECT count(*) INTO bad FROM jsonb_array_elements_text(p_result->'allowed_scope') z(v)
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_request->'allowed_scope') q(v) WHERE q.v=z.v);
   IF bad>0 THEN ok:=false; END IF;
   SELECT count(*) INTO bad FROM jsonb_array_elements_text(p_request->'excluded_target_refs') z(v)
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_result->'excluded_target_refs') q(v) WHERE q.v=z.v);
   IF bad>0 THEN ok:=false; END IF;
   SELECT count(*) INTO bad FROM jsonb_array_elements_text(p_request->'forbidden_scope') z(v)
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_result->'forbidden_scope') q(v) WHERE q.v=z.v);
   IF bad>0 THEN ok:=false; END IF;
   SELECT count(*) INTO bad FROM jsonb_array_elements_text(p_result->'positive_target_refs') p(v)
    JOIN jsonb_array_elements_text(p_result->'excluded_target_refs') e(v) ON e.v=p.v;
   IF bad>0 OR NOT((p_result->'conditions') @> (p_request->'conditions')) THEN ok:=false; END IF;
 END IF;

 d:=p_result->>'decision';
 IF ok AND d NOT IN('RESOLVED','CLARIFICATION_REQUIRED','BLOCKED') THEN ok:=false; END IF;
 IF ok AND coalesce(p_result->>'semantic_receipt_sha256','')!~'^[0-9a-f]{64}$' THEN ok:=false; END IF;
 IF ok AND d='CLARIFICATION_REQUIRED' AND nullif(btrim(coalesce(p_result->>'clarification_question','')),'') IS NULL THEN ok:=false; END IF;
 IF ok AND d='RESOLVED' AND jsonb_array_length(p_result->'material_ambiguities')<>0 THEN ok:=false; END IF;

 RETURN jsonb_build_object(
  'schema_version','LF_ROUTER_SEMANTIC_RESUME_VALIDATION_V1',
  'status',CASE WHEN ok THEN 'VALID' ELSE 'BLOCKED' END,
  'router_resume_allowed',(ok AND d='RESOLVED'),'route_authority',false,'effect_authority',false,
  'downstream_execution_allowed',false,'request_sha256',p_request->>'request_sha256',
  'next_action',CASE WHEN NOT ok THEN 'STAY_BLOCKED' WHEN d='RESOLVED' THEN 'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
                     WHEN d='CLARIFICATION_REQUIRED' THEN 'CALLER_INTERACTION_REQUIRED' ELSE 'STAY_BLOCKED' END
 );
END
$f$;

REVOKE ALL ON FUNCTION public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)
 TO postgres,service_role,supabase_read_only_user;

DO $patch$
DECLARE d text;o text;n text;k int;v1 int;v2 int;
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))<>'d45f5bddb693791b6459bbe3acfd4ed3'
    OR md5(pg_get_functiondef('public.lf_router_intent_handoff_v1(text,jsonb,text)'::regprocedure))<>'540bc1b60caf2e3f9d81461f99c509ef'
 THEN RAISE EXCEPTION 'RW104_C2_SOURCE_DRIFT'; END IF;
 d:=pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure);
 v1:=(length(d)-length(replace(d,'lf_router_intent_handoff_v1(','')))/length('lf_router_intent_handoff_v1(');
 v2:=(length(d)-length(replace(d,'lf_router_intent_handoff_v2(','')))/length('lf_router_intent_handoff_v2(');
 IF v1<>6 OR v2<>0 THEN RAISE EXCEPTION 'RW104_C2_PRECOUNT:v1=% v2=%',v1,v2; END IF;

 o:=$a$'semantic_handoff',public.lf_router_intent_handoff_v1(
          p_request_text,v_exact_asset_candidates,'CANONICAL_ASSET'),$a$;
 n:=o||E'\n        '||$a$'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
          p_request_text,v_exact_asset_candidates,'CANONICAL_ASSET'),$a$;
 k:=(length(d)-length(replace(d,o,'')))/length(o); IF k<>1 THEN RAISE EXCEPTION 'RW104_P0:%',k;END IF; d:=replace(d,o,n);

 o:=$b$'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,v_artifact_discovery->'matches','REPOSITORY_ARTIFACT'),$b$;
 n:=o||E'\n      '||$b$'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,v_artifact_discovery->'matches','REPOSITORY_ARTIFACT'),$b$;
 k:=(length(d)-length(replace(d,o,'')))/length(o); IF k<>1 THEN RAISE EXCEPTION 'RW104_P1:%',k;END IF; d:=replace(d,o,n);

 o:=$c$'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,case when v_asset_found then
          jsonb_build_array(jsonb_build_object(
            'asset_code',v_asset.codigo_activo,
            'asset_type',v_asset.tipo_activo))
          else '[]'::jsonb end,'CANONICAL_ASSET'),$c$;
 n:=o||E'\n      '||$c$'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,case when v_asset_found then
          jsonb_build_array(jsonb_build_object(
            'asset_code',v_asset.codigo_activo,
            'asset_type',v_asset.tipo_activo))
          else '[]'::jsonb end,'CANONICAL_ASSET'),$c$;
 k:=(length(d)-length(replace(d,o,'')))/length(o); IF k<>2 THEN RAISE EXCEPTION 'RW104_P2:%',k;END IF; d:=replace(d,o,n);

 o:=$e$'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,v_screen_subjects,'CANONICAL_SCREEN'),$e$;
 n:=o||E'\n      '||$e$'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,v_screen_subjects,'CANONICAL_SCREEN'),$e$;
 k:=(length(d)-length(replace(d,o,'')))/length(o); IF k<>1 THEN RAISE EXCEPTION 'RW104_P3:%',k;END IF; d:=replace(d,o,n);

 o:=$g$'semantic_handoff',public.lf_router_intent_handoff_v1(
        p_request_text,
        case when v_asset_found then jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
        'CANONICAL_ASSET'),$g$;
 n:=o||E'\n      '||$g$'semantic_handoff_v2',public.lf_router_intent_handoff_v2(
        p_request_text,
        case when v_asset_found then jsonb_build_array(jsonb_build_object(
          'asset_code',v_asset.codigo_activo,'asset_type',v_asset.tipo_activo))
        else '[]'::jsonb end,
        'CANONICAL_ASSET'),$g$;
 k:=(length(d)-length(replace(d,o,'')))/length(o); IF k<>1 THEN RAISE EXCEPTION 'RW104_P4:%',k;END IF; d:=replace(d,o,n);

 v1:=(length(d)-length(replace(d,'lf_router_intent_handoff_v1(','')))/length('lf_router_intent_handoff_v1(');
 v2:=(length(d)-length(replace(d,'lf_router_intent_handoff_v2(','')))/length('lf_router_intent_handoff_v2(');
 IF v1<>6 OR v2<>6 THEN RAISE EXCEPTION 'RW104_C2_POSTCOUNT:v1=% v2=%',v1,v2;END IF;
 EXECUTE d;
END
$patch$;

DO $test$
DECLARE q jsonb;r jsonb;x jsonb;cases jsonb;item jsonb;neg int:=0;sm jsonb;s text;v1 int;v2 int;
BEGIN
 q:=public.lf_router_intent_handoff_v2(
   'Actualizar ACT-0053 pero no ACT-0052',
   jsonb_build_array(jsonb_build_object('asset_code','ACT-0053','asset_type','SKILL'),
                     jsonb_build_object('asset_code','ACT-0052','asset_type','SKILL')),
   'CANONICAL_ASSET',jsonb_build_array(jsonb_build_object('kind','ONLY_IF','value','CURRENT')),NULL);
 r:=jsonb_build_object(
   'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1','request_sha256',q->>'request_sha256','decision','RESOLVED',
   'positive_target_refs',jsonb_build_array('ACT-0053'),'excluded_target_refs',jsonb_build_array('ACT-0052'),
   'allowed_scope',jsonb_build_array('ACT-0053'),'forbidden_scope',jsonb_build_array('ACT-0052'),
   'conditions',q->'conditions','material_ambiguities','[]'::jsonb,'clarification_question',NULL,
   'semantic_receipt_sha256',repeat('a',64));
 x:=public.lf_router_semantic_resume_validate_v1(q,r);
 IF q->>'schema_version'<>'LF_ROUTER_SEMANTIC_REQUEST_V1' OR x->>'status'<>'VALID'
    OR x->>'next_action'<>'ACT0001_REDERIVE_ROUTE_AND_AUTHORITY'
    OR coalesce((x->>'route_authority')::boolean,true) OR coalesce((x->>'downstream_execution_allowed')::boolean,true)
 THEN RAISE EXCEPTION 'RW104_C2_POSITIVE_FAIL:q=% x=%',q,x; END IF;

 cases:=jsonb_build_array(
  jsonb_build_object('q',q,'r',jsonb_set(r,'{request_sha256}',to_jsonb(repeat('0',64)),true)),
  jsonb_build_object('q',jsonb_set(q,'{source_currentness,router_source_md5}',to_jsonb(repeat('0',32)),true),'r',r),
  jsonb_build_object('q',q,'r',jsonb_set(r,'{positive_target_refs}',jsonb_build_array('ACT-9999'),true)),
  jsonb_build_object('q',q,'r',jsonb_set(r,'{allowed_scope}',jsonb_build_array('ACT-0053','ACT-9999'),true)),
  jsonb_build_object('q',q,'r',r||jsonb_build_object('operation_code','ACTUALIZACION_DB_LF')),
  jsonb_build_object('q',q,'r',r||jsonb_build_object('executor','service_role')),
  jsonb_build_object('q',q,'r',r||jsonb_build_object('effect_authority',true)),
  jsonb_build_object('q',q,'r',r||jsonb_build_object('downstream_execution_allowed',true)),
  jsonb_build_object('q',q,'r',jsonb_set(r,'{conditions}','[]'::jsonb,true)),
  jsonb_build_object('q',jsonb_set(q,'{excluded_target_refs}',jsonb_build_array('ACT-0052'),true),
                         'r',jsonb_set(r,'{excluded_target_refs}','[]'::jsonb,true)),
  jsonb_build_object('q',jsonb_set(q,'{forbidden_scope}',jsonb_build_array('ACT-0052'),true),
                         'r',jsonb_set(r,'{forbidden_scope}','[]'::jsonb,true)),
  jsonb_build_object('q',q,'r',r||jsonb_build_object('route_authority',true))
 );
 FOR item IN SELECT value FROM jsonb_array_elements(cases) LOOP
   x:=public.lf_router_semantic_resume_validate_v1(item->'q',item->'r');
   IF x->>'status'='BLOCKED' THEN neg:=neg+1; ELSE RAISE EXCEPTION 'RW104_C2_NEG_FALSE_PASS:%',item; END IF;
 END LOOP;
 IF neg<10 THEN RAISE EXCEPTION 'RW104_C2_NEG_COUNT:%',neg;END IF;

 IF has_function_privilege('anon','public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)','EXECUTE')
 OR has_function_privilege('anon','public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_router_semantic_resume_validate_v1(jsonb,jsonb)','EXECUTE')
 OR NOT has_function_privilege('service_role','public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)','EXECUTE')
 OR NOT has_function_privilege('supabase_read_only_user','public.lf_router_intent_handoff_v2(text,jsonb,text,jsonb,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'RW104_C2_ACL_FAIL';END IF;

 sm:=public.lf_router_resolve_v1('Actualizar ACT-0053 y ACT-0052',NULL,NULL,NULL,NULL);
 IF sm->>'status'<>'BLOCKED' OR sm#>>'{semantic_handoff,schema_version}'<>'LF_ROUTER_INTENT_HANDOFF_V1'
 OR sm#>>'{semantic_handoff_v2,schema_version}'<>'LF_ROUTER_SEMANTIC_REQUEST_V1'
 OR sm#>>'{semantic_handoff_v2,source_currentness,status}'<>'CURRENT'
 THEN RAISE EXCEPTION 'RW104_C2_ROUTER_SMOKE_FAIL:%',sm;END IF;

 s:=pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure);
 v1:=(length(s)-length(replace(s,'lf_router_intent_handoff_v1(','')))/length('lf_router_intent_handoff_v1(');
 v2:=(length(s)-length(replace(s,'lf_router_intent_handoff_v2(','')))/length('lf_router_intent_handoff_v2(');
 IF v1<>6 OR v2<>6 OR md5(pg_get_functiondef(
    'programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure))<>'72e153a7fbfe7b10a8c9ae694a61b334'
 OR (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE')<>35
 THEN RAISE EXCEPTION 'RW104_C2_FINAL_READBACK_FAIL:v1=% v2=%',v1,v2;END IF;
END
$test$;

COMMIT;
