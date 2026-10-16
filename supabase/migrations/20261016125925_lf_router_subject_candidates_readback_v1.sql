-- ACT-0001: distinguish the subject of a request from a possible executor.
-- Only enriches the existing fail-closed actor-role guard with a canonical
-- screen subject readback; it DOES NOT choose/enable a profile or edit a UI.
-- No early screen shortcut, new operation, adapter activation or ACL change.
-- Router ACT-0001 -> ACTUALIZACION_DB_LF -> Migration Merge Train only.
-- EKB first: LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003
-- and LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005.
BEGIN;

DO $router_subject_patch$
DECLARE
  v_source text;
  v_old_decl text := $old_decl$  v_executor_candidates jsonb := '[]'::jsonb;$old_decl$;
  v_new_decl text := $new_decl$  v_executor_candidates jsonb := '[]'::jsonb;
  v_screen_subjects jsonb := '[]'::jsonb;
  v_screen_subject_count integer := 0;$new_decl$;
  v_old_return text := $old_ret$    RETURN jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_EXECUTOR_CAPABILITY_UNATTESTED',$old_ret$;
  v_new_return text := $new_ret$    -- Subject discovery is not executor selection. Match canonical screen
    -- names as complete normalized phrases, not individual lexical keywords.
    SELECT count(*),
           coalesce(jsonb_agg(jsonb_build_object(
             'screen_code',p.codigo,
             'pantalla_id',p.id,
             'screen_name',p.nombre,
             'screen_state',p.estado,
             'module_code',p.module_code
           ) ORDER BY p.codigo),'[]'::jsonb)
      INTO v_screen_subject_count,v_screen_subjects
    FROM lf_ops.pantallas p
    WHERE p.activa
      AND length(btrim(p.nombre))>=8
      AND position(
        ' '||btrim(regexp_replace(
          translate(lower(p.nombre),'áéíóúüñ','aeiouun'),
          '[^a-z0-9_]+',' ','g'
        ))||' '
        IN ' '||v_req||' '
      )>0;

    RETURN jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_EXECUTOR_CAPABILITY_UNATTESTED',$new_ret$;
  v_old_binding text := $old_bind$      'subject_binding_state','UNRESOLVED',
      'executor_selection_state','CANDIDATES_ONLY_NOT_AUTHORIZED',$old_bind$;
  v_new_binding text := $new_bind$      'subject_binding_state',case
        when v_screen_subject_count=1 then 'RESOLVED'
        when v_screen_subject_count>1 then 'AMBIGUOUS'
        else 'UNRESOLVED'
      end,
      'subject_candidates',v_screen_subjects,
      'executor_selection_state','CANDIDATES_ONLY_NOT_AUTHORIZED',$new_bind$;
BEGIN
  SELECT pg_get_functiondef(
    'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
  ) INTO v_source;
  IF md5(v_source)<>'ba72b08cc747373d86a1cac155f9983b' THEN
    RAISE EXCEPTION 'ACT0001_SCREEN_SUBJECT_SOURCE_DRIFT:%',md5(v_source);
  END IF;
  IF length(v_source)-length(replace(v_source,v_old_decl,''))<>length(v_old_decl)
     OR length(v_source)-length(replace(v_source,v_old_return,''))<>length(v_old_return)
     OR length(v_source)-length(replace(v_source,v_old_binding,''))<>length(v_old_binding)
  THEN
    RAISE EXCEPTION 'ACT0001_SCREEN_SUBJECT_ANCHOR_NOT_UNIQUE';
  END IF;

  EXECUTE replace(replace(replace(
    v_source,
    v_old_decl,v_new_decl
  ),v_old_return,v_new_return),v_old_binding,v_new_binding);
END;
$router_subject_patch$;

-- Positive/negative tests prove subject matching never promotes a candidate
-- to an executor, while unrelated canonical router operations remain intact.
DO $router_subject_tests$
DECLARE v jsonb;
BEGIN
  v:=public.lf_router_resolve_v1(
    'Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.'
  );
  IF v->>'status'<>'BLOCKED'
     OR v->>'blocking_code'<>'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED'
     OR v->>'subject_binding_state'<>'RESOLVED'
     OR jsonb_array_length(v->'subject_candidates')<>1
     OR v#>>'{subject_candidates,0,screen_code}'<>'B2B-AUTH-001'
     OR v->>'executor_selection_state'<>'CANDIDATES_ONLY_NOT_AUTHORIZED'
     OR v->>'downstream_execution_allowed'<>'false'
     OR v->>'operation_code' IS NOT NULL
  THEN RAISE EXCEPTION 'ACT0001_SCREEN_SUBJECT_POSITIVE_FAILED:%',v;
  END IF;

  v:=public.lf_router_resolve_v1('Cambiar el botón principal de una pantalla inexistente.');
  IF v->>'status'<>'BLOCKED'
     OR v->>'subject_binding_state'<>'UNRESOLVED'
     OR v->'subject_candidates'<>'[]'::jsonb
     OR v->>'downstream_execution_allowed'<>'false'
  THEN RAISE EXCEPTION 'ACT0001_SCREEN_SUBJECT_NEGATIVE_FAILED:%',v;
  END IF;

  v:=public.lf_router_resolve_v1(
    'Inspeccionar el perfil PERFIL-UI-ARCHITECT para revisar una pantalla',
    NULL,'ASSET_INSPECTION'
  );
  IF v->>'status'<>'READY_INSPECTION'
     OR v->>'asset_type'<>'PERFIL'
  THEN RAISE EXCEPTION 'ACT0001_SCREEN_SUBJECT_PROFILE_REGRESSION:%',v;
  END IF;

  v:=public.lf_router_resolve_v1(
    'Modificar una funcion SQL de base de datos',NULL,'UPDATE','DB','ROUTER'
  );
  IF v->>'status'<>'READY_TO_EXECUTE'
     OR v->>'operation_code'<>'ACTUALIZACION_DB_LF'
  THEN RAISE EXCEPTION 'ACT0001_SCREEN_SUBJECT_DB_REGRESSION:%',v;
  END IF;
END;
$router_subject_tests$;

DO $router_subject_readback$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
  ) INTO v_definition;
  IF md5(v_definition)='ba72b08cc747373d86a1cac155f9983b'
     OR position('v_screen_subject_count' in v_definition)=0
     OR position('subject_candidates' in v_definition)=0
  THEN RAISE EXCEPTION 'ACT0001_SCREEN_SUBJECT_READBACK_FAILED';
  END IF;
END;
$router_subject_readback$;
COMMIT;
