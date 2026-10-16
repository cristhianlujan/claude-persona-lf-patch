-- ACT-0001 transversal role separation: executor vs subject vs auxiliary adapter.
-- No UI mutation, no profile promotion, no new operation or selector service.
-- EKB first: LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001,
-- LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002,
-- LF-ROUTER-ACT0001-SCREEN-SHORTCIRCUIT-20261016-003.
-- Canonical: ACT-0001 -> ACTUALIZACION_DB_LF -> Merge Train.
BEGIN;
SAVEPOINT actor_role_probe;
DO $apply$
DECLARE
 v_def text;
 v_new text;
BEGIN
 SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO v_def;
 IF md5(v_def)<>'0c41d9fb4e27c6ddfebbc356a7f22d66' THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_SOURCE_DRIFT:%',md5(v_def); END IF;
 IF (length(v_def)-length(replace(v_def,'  v_req text;','')))<>length('  v_req text;')
 OR (length(v_def)-length(replace(v_def,$old_a$    where (v_type_hint is null or b.tipo_activo=v_type_hint)
    order by$old_a$,'')))<>length($old_a$    where (v_type_hint is null or b.tipo_activo=v_type_hint)
    order by$old_a$)
 OR (length(v_def)-length(replace(v_def,$old_b$  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE')$old_b$,'')))<>length($old_b$  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE')$old_b$)
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_MARKER_NON_UNIQUE'; END IF;
 v_new:=replace(v_def,'  v_req text;',$new_decl$  v_req text;
  v_executor_candidates jsonb := '[]'::jsonb;$new_decl$);
 v_new:=replace(v_new,$old_a$    where (v_type_hint is null or b.tipo_activo=v_type_hint)
    order by$old_a$,$new_a$    where (v_type_hint is null or b.tipo_activo=v_type_hint)
      and (v_type_hint is not null or b.tipo_activo <> 'ADAPTER')
    order by$new_a$);
 v_new:=replace(v_new,$old_b$  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE')$old_b$,$new_b$  -- Actor-role guard after canonical discovery, before operation resolution.
  -- A screen / subject change does not update a profile, skill or adapter.
  -- Lexical matches are evidence candidates, never execution authority.
  IF nullif(btrim(coalesce(p_target_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_asset_type_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_action_hint,'')),'') IS NULL
     AND v_type_hint IN ('PERFIL','SKILL','ADAPTER')
     AND v_req ~ '^(por favor )?(cambiar|cambia|modificar|modifica|actualizar|actualiza|corregir|corrige|ajustar|ajusta|editar|edita|reemplazar|reemplaza|renombrar|renombra)( |$)'
     AND NOT v_req ~ '(^| )(perfil|profile|skill|adapter)( |$)'
     AND NOT EXISTS (
       SELECT 1 FROM public.v_lf_fuente_operativa_busqueda b
       WHERE b.codigo_activo=v_asset.codigo_activo
         AND (
           position(' '||btrim(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
           OR position(' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
           OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
               WHERE length(btrim(al))>=8
                 AND position(' '||btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0)
         )
     )
  THEN
    SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.keyword_match_count DESC,c.asset_code),'[]'::jsonb)
      INTO v_executor_candidates
    FROM (
      SELECT b.codigo_activo AS asset_code, b.tipo_activo AS asset_type,
             b.estado_operativo AS operational_status,
             count(DISTINCT kw.keyword) AS keyword_match_count,
             jsonb_agg(DISTINCT kw.keyword) AS matching_keywords
      FROM public.v_lf_fuente_operativa_busqueda b
      CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw(keyword)
      WHERE b.tipo_activo IN ('PERFIL','SKILL')
        AND length(btrim(kw.keyword))>=3
        AND position(' '||btrim(regexp_replace(translate(lower(kw.keyword),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
      GROUP BY b.codigo_activo,b.tipo_activo,b.estado_operativo
      ORDER BY count(DISTINCT kw.keyword) DESC,b.codigo_activo
      LIMIT 5
    ) c;
    RETURN jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_EXECUTOR_CAPABILITY_UNATTESTED',
      'asset_type',NULL,'action_code','UPDATE','operation_code',NULL,
      'subject_binding_state','UNRESOLVED',
      'executor_selection_state','CANDIDATES_ONLY_NOT_AUTHORIZED',
      'executor_candidates',v_executor_candidates,
      'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'semantic_resolution_required',true,
      'semantic_gap_code','TARGET_VS_EXECUTOR_ROLE_UNATTESTED',
      'downstream_execution_allowed',false
    );
  END IF;

  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE')$new_b$);
 IF md5(v_new)<>'ba72b08cc747373d86a1cac155f9983b' THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_TARGET_DRIFT:%',md5(v_new); END IF;
 EXECUTE v_new;
END $apply$;
DO $test$
DECLARE v jsonb; c jsonb;
BEGIN
 v:=public.lf_router_resolve_v1('Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.');
 IF v->>'status'<>'BLOCKED' OR v->>'blocking_code'<>'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED'
   OR v->>'operation_code' IS NOT NULL OR v->>'asset_type' IS NOT NULL
   OR v->>'downstream_execution_allowed'<>'false'
   OR v->>'request_sha256' IS NULL
   OR v->>'executor_selection_state'<>'CANDIDATES_ONLY_NOT_AUTHORIZED'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_B2B_FAIL:%',v; END IF;
 SELECT j INTO c FROM jsonb_array_elements(v->'executor_candidates') j
 WHERE j->>'asset_code'='PERFIL-UI-ARCHITECT' LIMIT 1;
 IF c IS NULL OR c->>'asset_type'<>'PERFIL'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(v->'executor_candidates') j WHERE j->>'asset_type'='ADAPTER')
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_CANDIDATE_FAIL:%',v; END IF;
 v:=public.lf_router_resolve_v1('Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”.');
 IF v->>'status'<>'BLOCKED' OR v->>'blocking_code'<>'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_NO_NEGATION_FAIL:%',v; END IF;
 v:=public.lf_router_resolve_v1('Inspeccionar el perfil PERFIL-UI-ARCHITECT para revisar una pantalla',NULL,'ASSET_INSPECTION');
 IF v->>'status'<>'READY_INSPECTION' OR v->>'asset_type'<>'PERFIL'
  OR v#>>'{asset,codigo_activo}'<>'PERFIL-UI-ARCHITECT'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_PROFILE_REGRESSION:%',v; END IF;
 v:=public.lf_router_resolve_v1('Inspeccionar la skill ACT-0045 para revisar una pantalla',NULL,'ASSET_INSPECTION');
 IF v->>'status'<>'READY_INSPECTION' OR v->>'asset_type'<>'SKILL'
   OR v#>>'{asset,codigo_activo}'<>'ACT-0045'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_SKILL_REGRESSION:%',v; END IF;
 v:=public.lf_router_resolve_v1('Vincular la regla B2B-RULE-AUTH-012 a la pantalla Iniciar sesión B2B.');
 IF v->>'operation_code'<>'VINCULACION_REGLA_PANTALLA_LF'
  OR v->>'action_code'<>'REGLA_PANTALLA_LINK'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_RELATION_REGRESSION:%',v; END IF;
 v:=public.lf_router_resolve_v1('Modificar una funcion SQL de base de datos',NULL,'UPDATE','DB','ROUTER');
 IF v->>'status'<>'READY_TO_EXECUTE' OR v->>'operation_code'<>'ACTUALIZACION_DB_LF'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_DB_REGRESSION:%',v; END IF;
 v:=public.lf_router_resolve_v1('Inspeccionar el adapter ADAPTER-LF-SHELL-PROFILE-20260827',NULL,'ASSET_INSPECTION');
 IF v->>'status'<>'READY_INSPECTION' OR v->>'asset_type'<>'ADAPTER'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_EXPLICIT_ADAPTER_REGRESSION:%',v; END IF;
 IF (SELECT COUNT(*) FROM public.lf_router_action_registry WHERE asset_type='PANTALLA' AND status='ACTIVE')<>0
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_UNEXPECTED_SCREEN_OPERATION'; END IF;
END $test$;
ROLLBACK TO SAVEPOINT actor_role_probe;
DO $dry$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))<>'0c41d9fb4e27c6ddfebbc356a7f22d66'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_DRYRUN_RESIDUE'; END IF;
END $dry$;
RELEASE SAVEPOINT actor_role_probe;
DO $apply$
DECLARE
 v_def text;
 v_new text;
BEGIN
 SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO v_def;
 IF md5(v_def)<>'0c41d9fb4e27c6ddfebbc356a7f22d66' THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_SOURCE_DRIFT:%',md5(v_def); END IF;
 IF (length(v_def)-length(replace(v_def,'  v_req text;','')))<>length('  v_req text;')
 OR (length(v_def)-length(replace(v_def,$old_a$    where (v_type_hint is null or b.tipo_activo=v_type_hint)
    order by$old_a$,'')))<>length($old_a$    where (v_type_hint is null or b.tipo_activo=v_type_hint)
    order by$old_a$)
 OR (length(v_def)-length(replace(v_def,$old_b$  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE')$old_b$,'')))<>length($old_b$  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE')$old_b$)
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_MARKER_NON_UNIQUE'; END IF;
 v_new:=replace(v_def,'  v_req text;',$new_decl$  v_req text;
  v_executor_candidates jsonb := '[]'::jsonb;$new_decl$);
 v_new:=replace(v_new,$old_a$    where (v_type_hint is null or b.tipo_activo=v_type_hint)
    order by$old_a$,$new_a$    where (v_type_hint is null or b.tipo_activo=v_type_hint)
      and (v_type_hint is not null or b.tipo_activo <> 'ADAPTER')
    order by$new_a$);
 v_new:=replace(v_new,$old_b$  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE')$old_b$,$new_b$  -- Actor-role guard after canonical discovery, before operation resolution.
  -- A screen / subject change does not update a profile, skill or adapter.
  -- Lexical matches are evidence candidates, never execution authority.
  IF nullif(btrim(coalesce(p_target_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_asset_type_hint,'')),'') IS NULL
     AND nullif(btrim(coalesce(p_action_hint,'')),'') IS NULL
     AND v_type_hint IN ('PERFIL','SKILL','ADAPTER')
     AND v_req ~ '^(por favor )?(cambiar|cambia|modificar|modifica|actualizar|actualiza|corregir|corrige|ajustar|ajusta|editar|edita|reemplazar|reemplaza|renombrar|renombra)( |$)'
     AND NOT v_req ~ '(^| )(perfil|profile|skill|adapter)( |$)'
     AND NOT EXISTS (
       SELECT 1 FROM public.v_lf_fuente_operativa_busqueda b
       WHERE b.codigo_activo=v_asset.codigo_activo
         AND (
           position(' '||btrim(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
           OR position(' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
           OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
               WHERE length(btrim(al))>=8
                 AND position(' '||btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0)
         )
     )
  THEN
    SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.keyword_match_count DESC,c.asset_code),'[]'::jsonb)
      INTO v_executor_candidates
    FROM (
      SELECT b.codigo_activo AS asset_code, b.tipo_activo AS asset_type,
             b.estado_operativo AS operational_status,
             count(DISTINCT kw.keyword) AS keyword_match_count,
             jsonb_agg(DISTINCT kw.keyword) AS matching_keywords
      FROM public.v_lf_fuente_operativa_busqueda b
      CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw(keyword)
      WHERE b.tipo_activo IN ('PERFIL','SKILL')
        AND length(btrim(kw.keyword))>=3
        AND position(' '||btrim(regexp_replace(translate(lower(kw.keyword),'áéíóúüñ','aeiouun'),'[^a-z0-9_ -]+',' ','g'))||' ' IN ' '||v_req||' ')>0
      GROUP BY b.codigo_activo,b.tipo_activo,b.estado_operativo
      ORDER BY count(DISTINCT kw.keyword) DESC,b.codigo_activo
      LIMIT 5
    ) c;
    RETURN jsonb_build_object(
      'router','ACT-0001','source','SUPABASE','status','BLOCKED',
      'blocking_code','BLOCK_EXECUTOR_CAPABILITY_UNATTESTED',
      'asset_type',NULL,'action_code','UPDATE','operation_code',NULL,
      'subject_binding_state','UNRESOLVED',
      'executor_selection_state','CANDIDATES_ONLY_NOT_AUTHORIZED',
      'executor_candidates',v_executor_candidates,
      'request_sha256',encode(extensions.digest(convert_to(p_request_text,'UTF8'),'sha256'),'hex'),
      'semantic_resolution_required',true,
      'semantic_gap_code','TARGET_VS_EXECUTOR_ROLE_UNATTESTED',
      'downstream_execution_allowed',false
    );
  END IF;

  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE')$new_b$);
 IF md5(v_new)<>'ba72b08cc747373d86a1cac155f9983b' THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_TARGET_DRIFT:%',md5(v_new); END IF;
 EXECUTE v_new;
END $apply$;
DO $test$
DECLARE v jsonb; c jsonb;
BEGIN
 v:=public.lf_router_resolve_v1('Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.');
 IF v->>'status'<>'BLOCKED' OR v->>'blocking_code'<>'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED'
   OR v->>'operation_code' IS NOT NULL OR v->>'asset_type' IS NOT NULL
   OR v->>'downstream_execution_allowed'<>'false'
   OR v->>'request_sha256' IS NULL
   OR v->>'executor_selection_state'<>'CANDIDATES_ONLY_NOT_AUTHORIZED'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_B2B_FAIL:%',v; END IF;
 SELECT j INTO c FROM jsonb_array_elements(v->'executor_candidates') j
 WHERE j->>'asset_code'='PERFIL-UI-ARCHITECT' LIMIT 1;
 IF c IS NULL OR c->>'asset_type'<>'PERFIL'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(v->'executor_candidates') j WHERE j->>'asset_type'='ADAPTER')
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_CANDIDATE_FAIL:%',v; END IF;
 v:=public.lf_router_resolve_v1('Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”.');
 IF v->>'status'<>'BLOCKED' OR v->>'blocking_code'<>'BLOCK_EXECUTOR_CAPABILITY_UNATTESTED'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_NO_NEGATION_FAIL:%',v; END IF;
 v:=public.lf_router_resolve_v1('Inspeccionar el perfil PERFIL-UI-ARCHITECT para revisar una pantalla',NULL,'ASSET_INSPECTION');
 IF v->>'status'<>'READY_INSPECTION' OR v->>'asset_type'<>'PERFIL'
  OR v#>>'{asset,codigo_activo}'<>'PERFIL-UI-ARCHITECT'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_PROFILE_REGRESSION:%',v; END IF;
 v:=public.lf_router_resolve_v1('Inspeccionar la skill ACT-0045 para revisar una pantalla',NULL,'ASSET_INSPECTION');
 IF v->>'status'<>'READY_INSPECTION' OR v->>'asset_type'<>'SKILL'
   OR v#>>'{asset,codigo_activo}'<>'ACT-0045'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_SKILL_REGRESSION:%',v; END IF;
 v:=public.lf_router_resolve_v1('Vincular la regla B2B-RULE-AUTH-012 a la pantalla Iniciar sesión B2B.');
 IF v->>'operation_code'<>'VINCULACION_REGLA_PANTALLA_LF'
  OR v->>'action_code'<>'REGLA_PANTALLA_LINK'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_RELATION_REGRESSION:%',v; END IF;
 v:=public.lf_router_resolve_v1('Modificar una funcion SQL de base de datos',NULL,'UPDATE','DB','ROUTER');
 IF v->>'status'<>'READY_TO_EXECUTE' OR v->>'operation_code'<>'ACTUALIZACION_DB_LF'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_DB_REGRESSION:%',v; END IF;
 v:=public.lf_router_resolve_v1('Inspeccionar el adapter ADAPTER-LF-SHELL-PROFILE-20260827',NULL,'ASSET_INSPECTION');
 IF v->>'status'<>'READY_INSPECTION' OR v->>'asset_type'<>'ADAPTER'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_EXPLICIT_ADAPTER_REGRESSION:%',v; END IF;
 IF (SELECT COUNT(*) FROM public.lf_router_action_registry WHERE asset_type='PANTALLA' AND status='ACTIVE')<>0
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_UNEXPECTED_SCREEN_OPERATION'; END IF;
END $test$;
DO $readback$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))<>'ba72b08cc747373d86a1cac155f9983b'
 THEN RAISE EXCEPTION 'ACT0001_ROLE_GUARD_LIVE_CHECKSUM_FAIL'; END IF;
END $readback$;
INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,lote_origen,estado,source_ref,lifecycle_phase,root_cause_family,detectability,source_context,evidencia)
SELECT 'LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005','ROUTER_GOVERNANCE',
 'Router confunde un adapter auxiliar con el ejecutor de un cambio de pantalla',
 'A la solicitud B2B, adapter obtuvo 304 puntos por pantalla+B2B y UI Architect 302 por pantalla; una negacion sin modificar produjo ADAPTER_UPDATE antes de la reversion.',
 'Scoring lexical mezcla roles de ejecutor (PERFIL/SKILL) y auxiliar (ADAPTER), no vincula sujeto de trabajo ni capacidad atestada. La semantica de la negacion no era interpretada.',
 'CROSSROLE_KEYWORD_SCORING_WITHOUT_TASK_AUTHORITY',
 'Prohibir ADAPTER en descubrimiento implícito de ejecutor. Cuando una modificación de sujeto no identifica ejecutor/autorización, conservar candidates read-only, bloquear sin escoger. En futura version integrar selector semantico versionado y guard pre-escritura, sin atajos de pantalla.',
 'Verificar original y sin negacion: BLOCK_EXECUTOR_CAPABILITY_UNATTESTED, sin adapter en candidates, nunca READY_TO_EXECUTE; verificar perfiles, skills, operaciones de regla y DB positivas y checksum readback del Router.',
 'High','ACT0001-ROLE-CAPABILITY-20261016','ACTIVO',
 'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261016052000_lf_router_executor_subject_role_guard_v1.sql',
 'router_discovery','R2_NO_VE','SILENT','ACT-0001/lf_router_resolve_v1 role discovery',
 'Pre-change scores adapter 304 vs UI Architect 302. Candidate-only behavior is not automatic profile selection or authorization. No frontal UI edit.'
WHERE NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-ROUTER-ACT0001-CROSSROLE-LEXICAL-20261016-005');
COMMIT;
