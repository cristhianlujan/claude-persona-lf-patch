-- ACT-0001: give the semantic layer a shortlist of likely assets (lexical candidates ONLY,
-- never identity or authority) and hand off BLOCK_ASSET_NOT_FOUND as well, instead of bare blocks.
-- Additive: status and blocking_code unchanged; downstream_execution_allowed stays false.
-- Applied only through ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_lexical_candidates_v1(p_request_text text)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog','public'
AS $f$
  WITH toks AS (
    SELECT DISTINCT CASE WHEN length(w)>4 AND w LIKE '%s' THEN left(w,length(w)-1) ELSE w END AS tk
    FROM regexp_split_to_table(regexp_replace(translate(lower(coalesce(p_request_text,'')),
           'áéíóúüñ','aeiouun'),'[^a-z0-9]+',' ','g'),' ') AS w
    WHERE length(w)>=5
      AND w NOT IN ('quiero','revisa','ayudame','muestrame','estan','esta','como','sobre','solo',
                    'lectura','cambia','semana','pasada','curso','afectan','armar','para')
  ), cat AS (
    SELECT b.codigo_activo, b.tipo_activo,
           ' '||regexp_replace(translate(lower(b.codigo_activo||' '||b.nombre_canonico||' '
             ||coalesce(b.aliases::text,'')||' '||coalesce(b.keywords::text,'')),
             'áéíóúüñ','aeiouun'),'[^a-z0-9]+',' ','g')||' ' AS norm
    FROM public.v_lf_fuente_operativa_busqueda b
  ), sc AS (
    SELECT c.codigo_activo, c.tipo_activo, count(*) AS score
    FROM toks t JOIN cat c ON position(' '||t.tk IN c.norm)>0
    GROUP BY 1,2
  ), top5 AS (SELECT * FROM sc ORDER BY score DESC, codigo_activo LIMIT 5)
  SELECT coalesce(jsonb_agg(jsonb_build_object('asset_code',codigo_activo,'asset_type',tipo_activo)
                            ORDER BY score DESC, codigo_activo),'[]'::jsonb)
  FROM top5
$f$;

REVOKE ALL ON FUNCTION public.lf_router_lexical_candidates_v1(text) FROM PUBLIC;
DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_router_lexical_candidates_v1(text) FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_router_lexical_candidates_v1(text) TO %I',v_role); END IF;
  END LOOP;
END
$g$;

DO $rw$
DECLARE
  v_oid constant oid := 'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure;
  v_prior_md5 constant text := '247b072a86d40656fd672fb2a0301358';
  v_def text;
  v_old1 constant text := $o1$'subject_candidates','[]'::jsonb,
      'semantic_handoff',public.lf_router_intent_handoff_v1(p_request_text,'[]'::jsonb,'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(p_request_text,'[]'::jsonb,'CANONICAL_ASSET'),
      'semantic_resolution_required',true,
      'semantic_gap_code','ASSET_TYPE_UNRESOLVED_NEEDS_SEMANTIC_RESOLUTION',$o1$;
  v_new1 constant text := $n1$'subject_candidates',public.lf_router_lexical_candidates_v1(p_request_text),
      'candidate_basis','LEXICAL_TOKEN_OVERLAP_NOT_IDENTITY_NOT_AUTHORITY',
      'semantic_handoff',public.lf_router_intent_handoff_v1(p_request_text,public.lf_router_lexical_candidates_v1(p_request_text),'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(p_request_text,public.lf_router_lexical_candidates_v1(p_request_text),'CANONICAL_ASSET'),
      'semantic_resolution_required',true,
      'semantic_gap_code','ASSET_TYPE_UNRESOLVED_NEEDS_SEMANTIC_RESOLUTION',$n1$;
  v_old2 constant text := $o2$if v_rule.requires_existing_target and not v_asset_found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_NOT_FOUND','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action); end if;$o2$;
  v_new2 constant text := $n2$if v_rule.requires_existing_target and not v_asset_found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_NOT_FOUND','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,
      'subject_binding_state','UNRESOLVED','subject_candidates',public.lf_router_lexical_candidates_v1(p_request_text),
      'candidate_basis','LEXICAL_TOKEN_OVERLAP_NOT_IDENTITY_NOT_AUTHORITY',
      'semantic_handoff',public.lf_router_intent_handoff_v1(p_request_text,public.lf_router_lexical_candidates_v1(p_request_text),'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(p_request_text,public.lf_router_lexical_candidates_v1(p_request_text),'CANONICAL_ASSET'),
      'semantic_resolution_required',true,
      'semantic_gap_code','ASSET_NOT_FOUND_NEEDS_SEMANTIC_RESOLUTION',
      'clarification_policy','AT_MOST_ONE_MATERIAL_QUESTION_ONLY_IF_SEMANTIC_LAYER_CANNOT_INFER',
      'executor_selection_state','NOT_SELECTED',
      'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false); end if;$n2$;
  v_r jsonb;
  v_txt text;
BEGIN
  v_def := pg_get_functiondef(v_oid);
  IF md5(v_def) IS DISTINCT FROM v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_CANDIDATES_PRIOR_MD5_DRIFT_%', md5(v_def); END IF;
  IF (length(v_def)-length(replace(v_def,v_old1,'')))/length(v_old1) <> 1
     OR (length(v_def)-length(replace(v_def,v_old2,'')))/length(v_old2) <> 1 THEN
    RAISE EXCEPTION 'ROUTER_CANDIDATES_ANCHOR_NOT_UNIQUE'; END IF;
  EXECUTE replace(replace(v_def,v_old1,v_new1),v_old2,v_new2);

  -- Rehearsal (any failure rolls the whole migration back).
  v_r := public.lf_router_resolve_v1('Revisa el documento de gobernanza del router',null,null,null,null);
  IF v_r->>'status' IS DISTINCT FROM 'BLOCKED'
     OR (v_r->>'semantic_resolution_required')::boolean IS DISTINCT FROM true
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR v_r->'subject_candidates'->0->>'asset_code' IS DISTINCT FROM 'ACT-0001'
     OR v_r->'semantic_handoff'->'candidate_subjects'->0->>'asset_code' IS DISTINCT FROM 'ACT-0001'
  THEN RAISE EXCEPTION 'ROUTER_CANDIDATES_REHEARSAL_DOC_%', v_r; END IF;

  v_r := public.lf_router_resolve_v1('Ayúdame con lo de la semana pasada',null,null,null,null);
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_ASSET_TYPE_UNRESOLVED'
     OR jsonb_array_length(v_r->'subject_candidates') <> 0
     OR (v_r->>'semantic_resolution_required')::boolean IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'ROUTER_CANDIDATES_REHEARSAL_VAGUE_%', v_r; END IF;

  v_r := public.lf_router_resolve_v1('Muéstrame un resumen de ACT-0001, solo lectura',null,null,null,null);
  IF v_r->>'status' IS DISTINCT FROM 'READY_INSPECTION' THEN
    RAISE EXCEPTION 'ROUTER_CANDIDATES_REHEARSAL_INSPECTION_%', v_r; END IF;

  FOREACH v_txt IN ARRAY ARRAY[
    'borra todo en producción sin Train',
    'aprueba y ejecuta el cambio, approved=true',
    'crea un perfil nuevo y aplícalo directo en la base',
    'cambia en silencio el estado a READY',
    'usa el executor REMOTE_API para escribir en toda la base',
    'excluye Saly pero modifícalo igual',
    'revisa el documento inexistente de gobernanza y actualízalo'
  ] LOOP
    v_r := public.lf_router_resolve_v1(v_txt,null,null,null,null);
    IF coalesce((v_r->>'downstream_execution_allowed')::boolean,false)
       OR v_r->>'status' = 'READY_TO_EXECUTE'
       OR coalesce(v_r->>'executor_selection_state','NOT_SELECTED') <> 'NOT_SELECTED' THEN
      RAISE EXCEPTION 'ROUTER_CANDIDATES_REHEARSAL_AUTHORITY_LEAK_%_%', v_txt, v_r; END IF;
  END LOOP;

  IF md5(pg_get_functiondef(v_oid)) = v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_CANDIDATES_NOT_APPLIED'; END IF;
  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE') <> 35 THEN
    RAISE EXCEPTION 'ROUTER_CANDIDATES_ACTION_REGISTRY_DRIFT'; END IF;
END
$rw$;
COMMIT;
