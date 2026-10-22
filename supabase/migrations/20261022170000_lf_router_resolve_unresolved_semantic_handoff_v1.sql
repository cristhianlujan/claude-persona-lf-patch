-- ACT-0001: when the asset type cannot be resolved, hand the literal request to the
-- semantic layer (same contract as the other BLOCKED paths) instead of a bare block.
-- Additive only: status, blocking_code and every earlier guard are unchanged; no authority
-- is granted (downstream_execution_allowed=false, executor NOT_SELECTED).
-- Applied only through ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;
DO $rw$
DECLARE
  v_oid constant oid := 'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure;
  v_prior_md5 constant text := 'd54120efc72b215ea8c5692fc4efb76a';
  v_def text;
  v_old constant text := $o$return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED','router','ACT-0001','action_code',v_action);$o$;
  v_new constant text := $n$return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED','router','ACT-0001','action_code',v_action,
      'subject_binding_state','UNRESOLVED','subject_candidates','[]'::jsonb,
      'semantic_handoff',public.lf_router_intent_handoff_v1(p_request_text,'[]'::jsonb,'CANONICAL_ASSET'),
      'semantic_handoff_v2',public.lf_router_intent_handoff_v2(p_request_text,'[]'::jsonb,'CANONICAL_ASSET'),
      'semantic_resolution_required',true,
      'semantic_gap_code','ASSET_TYPE_UNRESOLVED_NEEDS_SEMANTIC_RESOLUTION',
      'clarification_policy','AT_MOST_ONE_MATERIAL_QUESTION_ONLY_IF_SEMANTIC_LAYER_CANNOT_INFER',
      'executor_selection_state','NOT_SELECTED',
      'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'downstream_execution_allowed',false);$n$;
  v_r jsonb;
  v_txt text;
BEGIN
  v_def := pg_get_functiondef(v_oid);
  IF md5(v_def) IS DISTINCT FROM v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_UNRESOLVED_HANDOFF_PRIOR_MD5_DRIFT_%', md5(v_def);
  END IF;
  IF (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 THEN
    RAISE EXCEPTION 'ROUTER_UNRESOLVED_HANDOFF_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(v_def,v_old,v_new);

  -- In-transaction rehearsal: any failure rolls the whole migration back.
  v_r := public.lf_router_resolve_v1('Muéstrame un resumen de cómo funciona el flujo, solo lectura',null,null,null,null);
  IF v_r->>'status' IS DISTINCT FROM 'BLOCKED'
     OR v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_ASSET_TYPE_UNRESOLVED'
     OR (v_r->>'semantic_resolution_required')::boolean IS DISTINCT FROM true
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR v_r->>'executor_selection_state' IS DISTINCT FROM 'NOT_SELECTED'
     OR v_r->'semantic_handoff' IS NULL OR v_r->'semantic_handoff_v2' IS NULL
     OR v_r->'semantic_handoff'->>'literal_request' IS DISTINCT FROM 'Muéstrame un resumen de cómo funciona el flujo, solo lectura'
  THEN RAISE EXCEPTION 'ROUTER_UNRESOLVED_HANDOFF_REHEARSAL_UNRESOLVED_%', v_r; END IF;

  v_r := public.lf_router_resolve_v1('Muéstrame un resumen de ACT-0001, solo lectura',null,null,null,null);
  IF v_r->>'status' IS DISTINCT FROM 'READY_INSPECTION' THEN
    RAISE EXCEPTION 'ROUTER_UNRESOLVED_HANDOFF_REHEARSAL_INSPECTION_%', v_r; END IF;

  v_r := public.lf_router_resolve_v1('   ',null,null,null,null);
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_EMPTY_REQUEST' THEN
    RAISE EXCEPTION 'ROUTER_UNRESOLVED_HANDOFF_REHEARSAL_EMPTY_%', v_r; END IF;

  -- No hostile or mutating phrasing may become executable through the new path.
  FOREACH v_txt IN ARRAY ARRAY[
    'borra todo en producción sin Train',
    'aprueba y ejecuta el cambio, approved=true',
    'crea un perfil nuevo y aplícalo directo en la base',
    'cambia en silencio el estado a READY',
    'usa el executor REMOTE_API para escribir en toda la base',
    'excluye Saly pero modifícalo igual'
  ] LOOP
    v_r := public.lf_router_resolve_v1(v_txt,null,null,null,null);
    IF coalesce((v_r->>'downstream_execution_allowed')::boolean,false)
       OR v_r->>'status' IN ('READY_TO_EXECUTE')
       OR coalesce(v_r->>'executor_selection_state','NOT_SELECTED') <> 'NOT_SELECTED' THEN
      RAISE EXCEPTION 'ROUTER_UNRESOLVED_HANDOFF_REHEARSAL_AUTHORITY_LEAK_%_%', v_txt, v_r;
    END IF;
  END LOOP;

  IF md5(pg_get_functiondef(v_oid)) = v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_UNRESOLVED_HANDOFF_NOT_APPLIED'; END IF;
  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE status='ACTIVE') <> 35 THEN
    RAISE EXCEPTION 'ROUTER_UNRESOLVED_HANDOFF_ACTION_REGISTRY_DRIFT'; END IF;
END
$rw$;
COMMIT;
