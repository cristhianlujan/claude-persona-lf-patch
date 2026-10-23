-- ACT-0001: actualizar un perfil (ACTUALIZACION_PERFIL_LF) no consume el perfil con su adapter; solo lo edita.
-- Hoy lf_router_resolve_v1 trata toda operacion distinta de EJECUCION_PERFIL_LF como STORY_CREATOR y exige
-- pantalla_id (BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED) a cualquier perfil con adapter (UI Architect, Product Director...).
-- Regla de operacion (no de caso): la gobernanza de entrada de los adapters no aplica a ACTUALIZACION_PERFIL_LF.
-- El resto no cambia: EJECUCION_PERFIL_LF conserva su rama CONTEXT_PACK, las demas operaciones siguen como STORY_CREATOR,
-- los adapters siguen listados en la respuesta y downstream_execution_allowed no se toca.
-- Aplica solo por ACTUALIZACION_DB_LF / Merge Train. El ensayo aborta toda la migracion si algo no se cumple.
BEGIN;

DO $rw$
DECLARE
  v_oid constant oid := 'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure;
  v_prior_md5 constant text := '6b56c7f87b386cf9b7c80849a1270d48';
  v_def text;
  v_old constant text := $o$  if jsonb_array_length(v_adapters)>0 then
    v_input_governance := programacion.fn_lf_router_input_governance_resolve_v1($o$;
  v_new constant text := $n$  if jsonb_array_length(v_adapters)>0
     and v_operation.operation_code is distinct from 'ACTUALIZACION_PERFIL_LF' then
    v_input_governance := programacion.fn_lf_router_input_governance_resolve_v1($n$;
  v_txt constant text := 'Actualizar perfil PERFIL-UI-ARCHITECT';
  v_sha text;
  v_cur text;
  v_req jsonb;
  v_res jsonb;
  v_rt jsonb;
  v_r jsonb;
BEGIN
  v_def := pg_get_functiondef(v_oid);
  IF md5(v_def) IS DISTINCT FROM v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_PRIOR_MD5_DRIFT_%', md5(v_def); END IF;
  IF (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 THEN
    RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_ANCHOR_NOT_UNIQUE'; END IF;
  IF position('''CONTEXT_PACK'' else ''STORY_CREATOR''' in v_def) = 0 THEN
    RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_STORY_CREATOR_BRANCH_MISSING'; END IF;

  -- Antes: el perfil con adapter queda frenado por la gobernanza de entrada.
  v_sha := encode(extensions.digest(convert_to(v_txt,'UTF8'),'sha256'),'hex');
  v_req := jsonb_build_object('schema_version','LF_ROUTER_SEMANTIC_REQUEST_V1','router','ACT-0001',
    'literal_request',v_txt,'request_sha256',v_sha,'reference_kind','EXPLICIT_CODE',
    'candidate_subjects',jsonb_build_array(jsonb_build_object('asset_code','PERFIL-UI-ARCHITECT','asset_type','PERFIL')),
    'excluded_target_refs','[]'::jsonb,'positive_target_refs',jsonb_build_array('PERFIL-UI-ARCHITECT'),
    'allowed_scope',jsonb_build_array('PROFILE_UPDATE'),'forbidden_scope','[]'::jsonb,'conditions','[]'::jsonb,
    'source_currentness',jsonb_build_object('status','CURRENT','router_source_md5',v_prior_md5));
  v_res := jsonb_build_object('schema_version','LF_ROUTER_SEMANTIC_RESULT_V1','request_sha256',v_sha,'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array('PERFIL-UI-ARCHITECT'),'excluded_target_refs','[]'::jsonb,
    'allowed_scope',jsonb_build_array('PROFILE_UPDATE'),'forbidden_scope','[]'::jsonb,'conditions','[]'::jsonb,
    'material_ambiguities','[]'::jsonb,'clarification_question',null,'semantic_receipt_sha256',v_sha);
  v_rt := public.lf_router_semantic_resume_route_v1(v_req,v_res);
  IF v_rt#>>'{router_result,blocking_code}' IS DISTINCT FROM 'BLOCK_INPUT_GOVERNANCE_SUBJECT_UNRESOLVED'
     OR v_rt#>>'{router_result,operation_code}' IS DISTINCT FROM 'ACTUALIZACION_PERFIL_LF' THEN
    RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_REHEARSAL_BEFORE_%', v_rt; END IF;

  EXECUTE replace(v_def,v_old,v_new);

  -- Despues: la actualizacion llega a init_execution, con politicas y adapters intactos, sin autorizar efectos del Router.
  v_cur := md5(pg_get_functiondef(v_oid));
  IF v_cur = v_prior_md5 THEN RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_NOT_APPLIED'; END IF;
  v_req := jsonb_set(v_req,'{source_currentness,router_source_md5}',to_jsonb(v_cur));
  v_rt := public.lf_router_semantic_resume_route_v1(v_req,v_res);
  v_r := v_rt->'router_result';
  IF v_rt->>'status' IS DISTINCT FROM 'ROUTER_REDERIVED'
     OR v_r->>'status' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_r->>'blocking_code' IS NOT NULL
     OR v_r->>'operation_code' IS DISTINCT FROM 'ACTUALIZACION_PERFIL_LF'
     OR v_r->>'action_code' IS DISTINCT FROM 'PROFILE_UPDATE'
     OR v_r#>>'{next_step,step_id}' IS DISTINCT FROM 'init_execution'
     OR (v_r->>'required_policy_count') IS DISTINCT FROM (v_r->>'resolved_policy_count')
     OR jsonb_array_length(coalesce(v_r->'adapters','[]'::jsonb)) = 0
     OR (v_rt->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_REHEARSAL_AFTER_%', v_rt; END IF;

  -- Sin atestacion sigue bloqueado: el cambio no abre una puerta nueva para texto o pistas sueltas.
  v_r := public.lf_router_resolve_v1(v_txt,'PERFIL-UI-ARCHITECT','PROFILE_UPDATE','PERFIL','ROUTER');
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED' THEN
    RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_REHEARSAL_HINTS_%', v_r; END IF;
  v_r := public.lf_router_resolve_v1(v_txt,null,null,null,null);
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED' THEN
    RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_REHEARSAL_PLAIN_%', v_r; END IF;

  -- La ejecucion de perfil (otra operacion) no cambia.
  v_r := public.lf_router_resolve_v1(
    'Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.',
    null,null,null,null);
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED'
     OR v_r#>>'{siguiente_paso,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'ROUTER_UPDATE_NO_IG_REHEARSAL_EXECUTION_UNCHANGED_%', v_r; END IF;
END
$rw$;

COMMIT;
