-- ACT-0001 canonical router: reject unbound lexical update target. Existing function only.
-- Route: ACT-0001 -> ACTUALIZACION_DB_LF -> Migration Merge Train.
-- Source-before-change md5=242732ab80365645e9fa80feac955827. No new function, engine, registry, asset or operation.
-- Candidate discovery may suggest; mutation routing requires canonical code/name/alias grounding.
-- Schema: original function pg_get_functiondef is patched with exactly one guard insertion.
-- ROLLBACK canary ensures no DDL residue before durable change.
BEGIN;
DO $preflight$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-ROUTER-ACT0001-LEXICAL-MISROUTE-20261015-001' AND estado='ACTIVO')
    OR NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-ROUTER-ACT0001-PREWRITE-INTENT-GATE-20261015-002' AND estado='ACTIVO')
  THEN RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_CANONICAL_EKB_NOT_REGISTERED'; END IF;
  IF (SELECT count(*) FROM public.lf_router_action_registry WHERE asset_type='PANTALLA' AND status='ACTIVE')<>0
  THEN RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_SCREEN_OPERATION_CURRENTNESS_CHANGED'; END IF;
END $preflight$;
SAVEPOINT lf_router_write_guard_probe;
DO $router_patch$
DECLARE
  v_source text;
  v_anchor text := $exact_anchor$  if v_type_hint is null then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED','router','ACT-0001','action_code',v_action);
  end if;$exact_anchor$;
  v_guard text := $guard_sql$  -- ACT-0001 R5: lexical candidate discovery is not identity evidence.
  -- Fail closed for inferred mutation targets lacking an exact canonical identity
  -- mention. A governed semantic consumer may resolve a gap and resubmit
  -- explicit typed inputs; this SQL never manufactures semantic authority.
  if v_target_norm=''
     and nullif(btrim(coalesce(p_asset_type_hint,'')),'') is null
     and v_action in ('UPDATE','PROFILE_UPDATE','SKILL_UPDATE','ADAPTER_UPDATE',
                      'REGLA_UPDATE','STRATEGY_UPDATE','APP_SHELL_UPDATE',
                      'RUNTIME_UPDATE')
  then
    if not v_asset_found or not exists (
      select 1
      from public.v_lf_fuente_operativa_busqueda b
      where b.codigo_activo=v_asset.codigo_activo
        and (
          position(
            ' '||btrim(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g'))||' '
            in ' '||v_req||' '
          )>0
          or position(
            ' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g'))||' '
            in ' '||v_req||' '
          )>0
          or exists (
            select 1
            from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
            where length(btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')))>=8
              and btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')) <> lower(b.tipo_activo)
              and position(
                ' '||btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g'))||' '
                in ' '||v_req||' '
              )>0
          )
        )
    ) then
      return jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED',
        'router','ACT-0001',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'candidate_asset_code',case when v_asset_found then v_asset.codigo_activo else null end,
        'semantic_gap_code','NON_DERIVABLE_TARGET_IDENTITY',
        'semantic_resolution_required',true,
        'downstream_execution_allowed',false
      );
    end if;
  end if;$guard_sql$;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO v_source;
  IF md5(v_source)<>'242732ab80365645e9fa80feac955827' THEN
    RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_SOURCE_DRIFT:expected=242732ab80365645e9fa80feac955827 observed=%',md5(v_source);
  END IF;
  IF (length(v_source)-length(replace(v_source,v_anchor,''))) <> length(v_anchor) THEN
    RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(v_source,v_anchor,v_guard||E'\n'||v_anchor);
END $router_patch$;
DO $cases$
DECLARE
  v_c record;
  v_out jsonb;
BEGIN
  FOR v_c IN SELECT * FROM (VALUES
    ('original','Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.'),
    ('equivalent','Actualizar solo el texto del botón de la pantalla Iniciar sesión B2B; no alterar la autenticación ni las validaciones.'),
    ('weak_generic','Actualizar información del sistema B2B sin modificar los adapters'),
    ('screen_code','Modificar texto de la pantalla B2B-AUTH-001 sin tocar autenticación')
  ) AS c(case_name,request_text)
  LOOP
    v_out := public.lf_router_resolve_v1(v_c.request_text);
    IF v_out->>'status'<>'BLOCKED'
      OR v_out->>'blocking_code'<>'BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED'
      OR coalesce((v_out->>'downstream_execution_allowed')::boolean,true) IS DISTINCT FROM false
    THEN
      RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_NEGATIVE_FAILED:%:status=%:code=%:operation=%',v_c.case_name,v_out->>'status',v_out->>'blocking_code',v_out->>'operation_code';
    END IF;
  END LOOP;

  -- Positive identity evidence comes from the canonical catalog, not from
  -- executing an adapter's unrelated Input Governance child flow.
  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_fuente_operativa_busqueda b
    WHERE b.codigo_activo='ADAPTER-LF-SHELL-PROFILE-20260827'
      AND position(
        ' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\\- ]+',' ','g'))||' '
        in ' '||regexp_replace(translate(lower('Actualizar el adapter ADAPTER_LF_SHELL_PROFILE_v0.1_CANDIDATO'),'áéíóúüñ','aeiouun'),'[^a-z0-9_\\- ]+',' ','g')||' '
      )>0
  )
  THEN RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_NAMED_ADAPTER_IDENTITY_REGRESSION'; END IF;

  v_out:=public.lf_router_resolve_v1('Corregir una funcion SQL bajo la operacion de base de datos',NULL,'UPDATE','DB','ROUTER');
  IF v_out->>'status'<>'READY_TO_EXECUTE' OR v_out->>'operation_code'<>'ACTUALIZACION_DB_LF'
  THEN RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_TYPED_DB_REGRESSION:%',v_out; END IF;

  -- Other operation families are intentionally not executed as canaries:
  -- their independently governed Input Governance state is outside this patch.
END $cases$;
ROLLBACK TO SAVEPOINT lf_router_write_guard_probe;
DO $noresidue$
DECLARE v_out jsonb;
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))<>'242732ab80365645e9fa80feac955827'
  THEN RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_ROLLBACK_DDL_RESIDUE'; END IF;
  -- md5(pg_get_functiondef) is the exact rollback proof; do not reexecute
  -- the old known-bad Router route and its unrelated nested consumers.
END $noresidue$;
RELEASE SAVEPOINT lf_router_write_guard_probe;
-- Persist only after a positive candidate probe and a negative no-residue check.
DO $router_patch$
DECLARE
  v_source text;
  v_anchor text := $exact_anchor$  if v_type_hint is null then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED','router','ACT-0001','action_code',v_action);
  end if;$exact_anchor$;
  v_guard text := $guard_sql$  -- ACT-0001 R5: lexical candidate discovery is not identity evidence.
  -- Fail closed for inferred mutation targets lacking an exact canonical identity
  -- mention. A governed semantic consumer may resolve a gap and resubmit
  -- explicit typed inputs; this SQL never manufactures semantic authority.
  if v_target_norm=''
     and nullif(btrim(coalesce(p_asset_type_hint,'')),'') is null
     and v_action in ('UPDATE','PROFILE_UPDATE','SKILL_UPDATE','ADAPTER_UPDATE',
                      'REGLA_UPDATE','STRATEGY_UPDATE','APP_SHELL_UPDATE',
                      'RUNTIME_UPDATE')
  then
    if not v_asset_found or not exists (
      select 1
      from public.v_lf_fuente_operativa_busqueda b
      where b.codigo_activo=v_asset.codigo_activo
        and (
          position(
            ' '||btrim(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g'))||' '
            in ' '||v_req||' '
          )>0
          or position(
            ' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g'))||' '
            in ' '||v_req||' '
          )>0
          or exists (
            select 1
            from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
            where length(btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')))>=8
              and btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')) <> lower(b.tipo_activo)
              and position(
                ' '||btrim(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g'))||' '
                in ' '||v_req||' '
              )>0
          )
        )
    ) then
      return jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED',
        'router','ACT-0001',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'candidate_asset_code',case when v_asset_found then v_asset.codigo_activo else null end,
        'semantic_gap_code','NON_DERIVABLE_TARGET_IDENTITY',
        'semantic_resolution_required',true,
        'downstream_execution_allowed',false
      );
    end if;
  end if;$guard_sql$;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO v_source;
  IF md5(v_source)<>'242732ab80365645e9fa80feac955827' THEN
    RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_SOURCE_DRIFT:expected=242732ab80365645e9fa80feac955827 observed=%',md5(v_source);
  END IF;
  IF (length(v_source)-length(replace(v_source,v_anchor,''))) <> length(v_anchor) THEN
    RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_ANCHOR_NOT_UNIQUE';
  END IF;
  EXECUTE replace(v_source,v_anchor,v_guard||E'\n'||v_anchor);
END $router_patch$;
DO $cases$
DECLARE
  v_c record;
  v_out jsonb;
BEGIN
  FOR v_c IN SELECT * FROM (VALUES
    ('original','Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.'),
    ('equivalent','Actualizar solo el texto del botón de la pantalla Iniciar sesión B2B; no alterar la autenticación ni las validaciones.'),
    ('weak_generic','Actualizar información del sistema B2B sin modificar los adapters'),
    ('screen_code','Modificar texto de la pantalla B2B-AUTH-001 sin tocar autenticación')
  ) AS c(case_name,request_text)
  LOOP
    v_out := public.lf_router_resolve_v1(v_c.request_text);
    IF v_out->>'status'<>'BLOCKED'
      OR v_out->>'blocking_code'<>'BLOCK_ROUTER_WRITE_TARGET_IDENTITY_UNVERIFIED'
      OR coalesce((v_out->>'downstream_execution_allowed')::boolean,true) IS DISTINCT FROM false
    THEN
      RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_NEGATIVE_FAILED:%:status=%:code=%:operation=%',v_c.case_name,v_out->>'status',v_out->>'blocking_code',v_out->>'operation_code';
    END IF;
  END LOOP;

  -- Positive identity evidence comes from the canonical catalog, not from
  -- executing an adapter's unrelated Input Governance child flow.
  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_fuente_operativa_busqueda b
    WHERE b.codigo_activo='ADAPTER-LF-SHELL-PROFILE-20260827'
      AND position(
        ' '||btrim(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\\- ]+',' ','g'))||' '
        in ' '||regexp_replace(translate(lower('Actualizar el adapter ADAPTER_LF_SHELL_PROFILE_v0.1_CANDIDATO'),'áéíóúüñ','aeiouun'),'[^a-z0-9_\\- ]+',' ','g')||' '
      )>0
  )
  THEN RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_NAMED_ADAPTER_IDENTITY_REGRESSION'; END IF;

  v_out:=public.lf_router_resolve_v1('Corregir una funcion SQL bajo la operacion de base de datos',NULL,'UPDATE','DB','ROUTER');
  IF v_out->>'status'<>'READY_TO_EXECUTE' OR v_out->>'operation_code'<>'ACTUALIZACION_DB_LF'
  THEN RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_TYPED_DB_REGRESSION:%',v_out; END IF;

  -- Other operation families are intentionally not executed as canaries:
  -- their independently governed Input Governance state is outside this patch.
END $cases$;
DO $verify$
BEGIN
  IF md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))='242732ab80365645e9fa80feac955827'
  THEN RAISE EXCEPTION 'LF_ROUTER_WRITE_GUARD_FINAL_DEF_UNCHANGED'; END IF;
END $verify$;
COMMIT;
