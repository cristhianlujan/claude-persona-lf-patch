-- COMPENSATING MIGRATION for PR #2781; restore routing precedence without
-- reverting the independent fail-closed write-identity guard introduced in #2780.
-- No permission changes, no registry changes, no adapter/profile mutation.
-- Only public.lf_router_resolve_v1 is patched, through LF Migration Merge Train.
BEGIN;
SAVEPOINT act0001_shortcircuit_reversal_probe;

DO $restore$
DECLARE
  v_def text;
  v_from integer;
  v_to integer;
  v_restored text;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO v_def;
  IF md5(v_def)<>'23d3550b2b1af8a84d64097216c6c544' THEN
     RAISE EXCEPTION 'ACT0001_ROLLBACK_SOURCE_DRIFT expected=23d3550b2b1af8a84d64097216c6c544 got=%',md5(v_def);
  END IF;
  v_from:=strpos(v_def,'  -- ACT-0001 deterministic subject grounding from the canonical screen hierarchy.');
  v_to:=strpos(v_def,'  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint');
  IF v_from=0 OR v_to<=v_from
    OR (length(v_def)-length(replace(v_def,'  -- ACT-0001 deterministic subject grounding from the canonical screen hierarchy.','')))<>length('  -- ACT-0001 deterministic subject grounding from the canonical screen hierarchy.')
    OR (length(v_def)-length(replace(v_def,'  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint','')))<>length('  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint')
  THEN RAISE EXCEPTION 'ACT0001_ROLLBACK_MARKERS_NON_UNIQUE'; END IF;
  v_restored:=left(v_def,v_from-1)||substr(v_def,v_to);
  IF md5(v_restored)<>'0c41d9fb4e27c6ddfebbc356a7f22d66' THEN
    RAISE EXCEPTION 'ACT0001_ROLLBACK_TARGET_MISMATCH expected=0c41d9fb4e27c6ddfebbc356a7f22d66 got=%',md5(v_restored);
  END IF;
  EXECUTE v_restored;
END $restore$;

DO $regression$
DECLARE
 v_result jsonb;
 v_req text;
BEGIN
 -- Bare text (no hints) must first traverse canonical discovery and not the
 -- early-return screen branch. Both explicit asset types must remain intact.
 v_req:='Inspeccionar el perfil PERFIL-UI-ARCHITECT y revisar la pantalla Iniciar sesión B2B.';
 v_result:=public.lf_router_resolve_v1(v_req);
 IF v_result->>'status'<>'READY_INSPECTION'
    OR v_result->>'asset_type'<>'PERFIL'
    OR v_result#>>'{asset,codigo_activo}'<>'PERFIL-UI-ARCHITECT'
 THEN RAISE EXCEPTION 'ACT0001_PROFILE_ROUTE_NOT_RESTORED:%',v_result; END IF;

 v_req:='Inspeccionar la skill ACT-0045 para evaluar la pantalla Iniciar sesión B2B.';
 v_result:=public.lf_router_resolve_v1(v_req);
 IF v_result->>'status'<>'READY_INSPECTION'
    OR v_result->>'asset_type'<>'SKILL'
    OR v_result#>>'{asset,codigo_activo}'<>'ACT-0045'
 THEN RAISE EXCEPTION 'ACT0001_SKILL_ROUTE_NOT_RESTORED:%',v_result; END IF;

 -- Original user request still MUST fail closed; guard from PR #2780 stays.
 v_req:='Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.';
 v_result:=public.lf_router_resolve_v1(v_req);
 IF v_result->>'status'<>'BLOCKED'
    OR v_result->>'blocking_code'<>'BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED'
    OR coalesce((v_result->>'downstream_execution_allowed')::boolean,true)
 THEN RAISE EXCEPTION 'ACT0001_UNSAFE_WRITE_ROUTE_AFTER_ROLLBACK:%',v_result; END IF;

 -- A valid registered relation path must remain untouched.
 v_result:=public.lf_router_resolve_v1('Vincular la regla B2B-RULE-AUTH-012 a la pantalla Iniciar sesión B2B.');
 IF v_result->>'operation_code'<>'VINCULACION_REGLA_PANTALLA_LF'
    OR v_result->>'action_code'<>'REGLA_PANTALLA_LINK'
 THEN RAISE EXCEPTION 'ACT0001_RELATION_ROUTE_REGRESSION:%',v_result; END IF;

 v_result:=public.lf_router_resolve_v1('Corregir una funcion SQL bajo la operacion de base de datos',NULL,'UPDATE','DB','ROUTER');
 IF v_result->>'status'<>'READY_TO_EXECUTE'
    OR v_result->>'operation_code'<>'ACTUALIZACION_DB_LF'
 THEN RAISE EXCEPTION 'ACT0001_DB_TYPED_ROUTE_REGRESSION:%',v_result; END IF;

 IF (SELECT COUNT(*) FROM public.lf_router_action_registry WHERE asset_type='PANTALLA' AND status='ACTIVE')<>0
 THEN RAISE EXCEPTION 'ACT0001_UNEXPECTED_SCREEN_ROUTE_MUTATION'; END IF;
END $regression$;
ROLLBACK TO SAVEPOINT act0001_shortcircuit_reversal_probe;
DO $rollback_proof$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))<>'23d3550b2b1af8a84d64097216c6c544'
 THEN RAISE EXCEPTION 'ACT0001_ROLLBACK_DRYRUN_RESIDUE'; END IF;
END $rollback_proof$;
RELEASE SAVEPOINT act0001_shortcircuit_reversal_probe;

DO $restore$
DECLARE
  v_def text;
  v_from integer;
  v_to integer;
  v_restored text;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO v_def;
  IF md5(v_def)<>'23d3550b2b1af8a84d64097216c6c544' THEN
     RAISE EXCEPTION 'ACT0001_ROLLBACK_SOURCE_DRIFT expected=23d3550b2b1af8a84d64097216c6c544 got=%',md5(v_def);
  END IF;
  v_from:=strpos(v_def,'  -- ACT-0001 deterministic subject grounding from the canonical screen hierarchy.');
  v_to:=strpos(v_def,'  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint');
  IF v_from=0 OR v_to<=v_from
    OR (length(v_def)-length(replace(v_def,'  -- ACT-0001 deterministic subject grounding from the canonical screen hierarchy.','')))<>length('  -- ACT-0001 deterministic subject grounding from the canonical screen hierarchy.')
    OR (length(v_def)-length(replace(v_def,'  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint','')))<>length('  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint')
  THEN RAISE EXCEPTION 'ACT0001_ROLLBACK_MARKERS_NON_UNIQUE'; END IF;
  v_restored:=left(v_def,v_from-1)||substr(v_def,v_to);
  IF md5(v_restored)<>'0c41d9fb4e27c6ddfebbc356a7f22d66' THEN
    RAISE EXCEPTION 'ACT0001_ROLLBACK_TARGET_MISMATCH expected=0c41d9fb4e27c6ddfebbc356a7f22d66 got=%',md5(v_restored);
  END IF;
  EXECUTE v_restored;
END $restore$;

DO $regression$
DECLARE
 v_result jsonb;
 v_req text;
BEGIN
 -- Bare text (no hints) must first traverse canonical discovery and not the
 -- early-return screen branch. Both explicit asset types must remain intact.
 v_req:='Inspeccionar el perfil PERFIL-UI-ARCHITECT y revisar la pantalla Iniciar sesión B2B.';
 v_result:=public.lf_router_resolve_v1(v_req);
 IF v_result->>'status'<>'READY_INSPECTION'
    OR v_result->>'asset_type'<>'PERFIL'
    OR v_result#>>'{asset,codigo_activo}'<>'PERFIL-UI-ARCHITECT'
 THEN RAISE EXCEPTION 'ACT0001_PROFILE_ROUTE_NOT_RESTORED:%',v_result; END IF;

 v_req:='Inspeccionar la skill ACT-0045 para evaluar la pantalla Iniciar sesión B2B.';
 v_result:=public.lf_router_resolve_v1(v_req);
 IF v_result->>'status'<>'READY_INSPECTION'
    OR v_result->>'asset_type'<>'SKILL'
    OR v_result#>>'{asset,codigo_activo}'<>'ACT-0045'
 THEN RAISE EXCEPTION 'ACT0001_SKILL_ROUTE_NOT_RESTORED:%',v_result; END IF;

 -- Original user request still MUST fail closed; guard from PR #2780 stays.
 v_req:='Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.';
 v_result:=public.lf_router_resolve_v1(v_req);
 IF v_result->>'status'<>'BLOCKED'
    OR v_result->>'blocking_code'<>'BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED'
    OR coalesce((v_result->>'downstream_execution_allowed')::boolean,true)
 THEN RAISE EXCEPTION 'ACT0001_UNSAFE_WRITE_ROUTE_AFTER_ROLLBACK:%',v_result; END IF;

 -- A valid registered relation path must remain untouched.
 v_result:=public.lf_router_resolve_v1('Vincular la regla B2B-RULE-AUTH-012 a la pantalla Iniciar sesión B2B.');
 IF v_result->>'operation_code'<>'VINCULACION_REGLA_PANTALLA_LF'
    OR v_result->>'action_code'<>'REGLA_PANTALLA_LINK'
 THEN RAISE EXCEPTION 'ACT0001_RELATION_ROUTE_REGRESSION:%',v_result; END IF;

 v_result:=public.lf_router_resolve_v1('Corregir una funcion SQL bajo la operacion de base de datos',NULL,'UPDATE','DB','ROUTER');
 IF v_result->>'status'<>'READY_TO_EXECUTE'
    OR v_result->>'operation_code'<>'ACTUALIZACION_DB_LF'
 THEN RAISE EXCEPTION 'ACT0001_DB_TYPED_ROUTE_REGRESSION:%',v_result; END IF;

 IF (SELECT COUNT(*) FROM public.lf_router_action_registry WHERE asset_type='PANTALLA' AND status='ACTIVE')<>0
 THEN RAISE EXCEPTION 'ACT0001_UNEXPECTED_SCREEN_ROUTE_MUTATION'; END IF;
END $regression$;
DO $readback$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))<>'0c41d9fb4e27c6ddfebbc356a7f22d66'
 THEN RAISE EXCEPTION 'ACT0001_ROLLBACK_DURABLE_READBACK_MISMATCH'; END IF;
END $readback$;
COMMIT;
