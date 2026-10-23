-- ACT-0001: lf_router_resolve_v1 ya no deja la modificacion de una pantalla sin camino.
-- Hallazgo: con "Cambiar unicamente el texto del boton principal de la pantalla Iniciar sesion B2B a Acceder, sin modificar ...",
-- el Router resuelve la pantalla B2B-AUTH-001 y el perfil PERFIL-UI-ARCHITECT (READ_ONLY) y termina en
-- BLOCKED/BLOCK_EXECUTOR_CAPABILITY_UNATTESTED sin indicar que sigue; el agente se detiene.
-- Cambio ADITIVO: agrega el campo siguiente_paso (operacion EJECUCION_PERFIL_LF, GPT_NATIVE, solo lectura, sin escribir) solo cuando
-- la pantalla esta resuelta y hay perfil candidato. status, blocking_code, executor_selection_state y downstream_execution_allowed no cambian
-- (BLOCKED sigue significando que el Router no autoriza efectos). Aplica solo por ACTUALIZACION_DB_LF / Merge Train.
BEGIN;

DO $rw$
DECLARE
  v_oid constant oid := 'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure;
  v_prior_md5 constant text := '8edf5c708b339d004e694664d172bb99';
  v_def text;
  v_old constant text := $o$      'semantic_gap_code','TARGET_VS_EXECUTOR_ROLE_UNATTESTED',$o$;
  v_new constant text := $n$      'semantic_gap_code','TARGET_VS_EXECUTOR_ROLE_UNATTESTED',
      'siguiente_paso',case
        when v_screen_subject_count=1 and jsonb_array_length(v_executor_candidates)>0 then jsonb_build_object(
          'operation_code','EJECUCION_PERFIL_LF',
          'entrypoint','ROUTER_ONLY',
          'flujo',jsonb_build_array('ACT-0001','EJECUCION_PERFIL_LF',v_executor_candidates->0->>'asset_code'),
          'executor_mode','GPT_NATIVE',
          'read_only',true,
          'no_write',true,
          'profile_source_mode','JIT_BY_REF',
          'input_literal',p_request_text,
          'alcance_permitido',(SELECT coalesce(jsonb_agg(s->>'screen_code'),'[]'::jsonb) FROM jsonb_array_elements(v_screen_subjects) s),
          'nota_es','BLOQUEADO significa que el Router no autoriza efectos; no impide que el perfil trabaje en solo lectura. Abrir esta operacion con la frase literal: el perfil devuelve una propuesta y no escribe. Aplicar el cambio es otra operacion que autoriza el usuario.')
        else null end,$n$;
  v_r jsonb;
BEGIN
  v_def := pg_get_functiondef(v_oid);
  IF md5(v_def) IS DISTINCT FROM v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_SIGUIENTE_PASO_PRIOR_MD5_DRIFT_%', md5(v_def); END IF;
  IF (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 THEN
    RAISE EXCEPTION 'ROUTER_SIGUIENTE_PASO_ANCHOR_NOT_UNIQUE'; END IF;
  EXECUTE replace(v_def,v_old,v_new);

  -- Ensayo (cualquier fallo revierte la migracion completa).
  v_r := public.lf_router_resolve_v1('Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.',null,null,null,null);
  IF v_r->>'status' IS DISTINCT FROM 'BLOCKED'
     OR v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED'
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR v_r#>>'{siguiente_paso,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_r#>>'{siguiente_paso,flujo,2}' IS DISTINCT FROM 'PERFIL-UI-ARCHITECT'
     OR v_r#>>'{siguiente_paso,executor_mode}' IS DISTINCT FROM 'GPT_NATIVE'
     OR (v_r#>>'{siguiente_paso,no_write}')::boolean IS DISTINCT FROM true
     OR v_r#>'{siguiente_paso,alcance_permitido}' IS DISTINCT FROM '["B2B-AUTH-001"]'::jsonb
     OR v_r#>>'{siguiente_paso,input_literal}' IS DISTINCT FROM 'Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.'
  THEN RAISE EXCEPTION 'ROUTER_SIGUIENTE_PASO_REHEARSAL_B2B_%', v_r; END IF;

  -- Controles: sin pantalla resuelta no hay siguiente_paso, y nada gana autoridad.
  v_r := public.lf_router_resolve_v1('Ayúdame con lo de la semana pasada',null,null,null,null);
  IF v_r->'siguiente_paso' IS NOT NULL AND v_r->'siguiente_paso' <> 'null'::jsonb
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'ROUTER_SIGUIENTE_PASO_REHEARSAL_VAGUE_%', v_r; END IF;

  v_r := public.lf_router_resolve_v1('Muéstrame un resumen de ACT-0001, solo lectura',null,null,null,null);
  IF v_r->>'status' IS DISTINCT FROM 'READY_INSPECTION' THEN
    RAISE EXCEPTION 'ROUTER_SIGUIENTE_PASO_REHEARSAL_INSPECTION_%', v_r; END IF;

  IF md5(pg_get_functiondef(v_oid)) = v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_SIGUIENTE_PASO_NOT_APPLIED'; END IF;
END
$rw$;

COMMIT;
