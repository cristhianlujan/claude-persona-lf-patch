-- ACT-0001: cuando el agente manda target/accion/tipo ademas del texto, el Router responde
-- BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED sin decir que hacer (ChatGPT lo leyo como "no existe ruta PANTALLA/UPDATE").
-- Cambio ADITIVO: ese bloqueo agrega siguiente_paso = repetir la llamada con SOLO el texto literal del usuario (las pistas del
-- agente nunca son evidencia). status, blocking_code, semantic_gap_code y downstream_execution_allowed no cambian.
-- Aplica solo por ACTUALIZACION_DB_LF / Merge Train.
BEGIN;

DO $rw$
DECLARE
  v_oid constant oid := 'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure;
  v_prior_md5 constant text := 'dbd3c661c5d29e37196b6c019169be9d';
  v_def text;
  v_old constant text := $o$      'semantic_gap_code','EXPLICIT_TARGET_IS_NOT_SCOPE_AUTHORITY',$o$;
  v_new constant text := $n$      'semantic_gap_code','EXPLICIT_TARGET_IS_NOT_SCOPE_AUTHORITY',
      'siguiente_paso',jsonb_build_object(
        'tipo','REPETIR_SOLO_CON_TEXTO_LITERAL',
        'llamada_correcta','lf_router_resolve_v1(<texto literal del usuario>)',
        'input_literal',p_request_text,
        'instruccion_es','No envies target, accion ni tipo de activo: el Router no los usa como evidencia. Repite la llamada con SOLO el texto literal del usuario; el Router resuelve la pantalla/activo y el perfil por si mismo y te devuelve el siguiente paso.'),$n$;
  v_r jsonb;
  v_txt constant text := 'Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.';
BEGIN
  v_def := pg_get_functiondef(v_oid);
  IF md5(v_def) IS DISTINCT FROM v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_PISTAS_PRIOR_MD5_DRIFT_%', md5(v_def); END IF;
  IF (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 THEN
    RAISE EXCEPTION 'ROUTER_PISTAS_ANCHOR_NOT_UNIQUE'; END IF;
  EXECUTE replace(v_def,v_old,v_new);

  v_r := public.lf_router_resolve_v1(v_txt,'B2B-AUTH-001','UPDATE','PANTALLA',null);
  IF v_r->>'status' IS DISTINCT FROM 'BLOCKED'
     OR v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED'
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
     OR v_r#>>'{siguiente_paso,tipo}' IS DISTINCT FROM 'REPETIR_SOLO_CON_TEXTO_LITERAL'
     OR v_r#>>'{siguiente_paso,input_literal}' IS DISTINCT FROM v_txt
  THEN RAISE EXCEPTION 'ROUTER_PISTAS_REHEARSAL_HINTS_%', v_r; END IF;

  -- La llamada correcta (solo texto) sigue dando el siguiente paso del cambio anterior.
  v_r := public.lf_router_resolve_v1(v_txt,null,null,null,null);
  IF v_r->>'blocking_code' IS DISTINCT FROM 'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED'
     OR v_r#>>'{siguiente_paso,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR (v_r->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'ROUTER_PISTAS_REHEARSAL_TEXT_ONLY_%', v_r; END IF;

  IF md5(pg_get_functiondef(v_oid)) = v_prior_md5 THEN
    RAISE EXCEPTION 'ROUTER_PISTAS_NOT_APPLIED'; END IF;
END
$rw$;

COMMIT;
