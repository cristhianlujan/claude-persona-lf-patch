-- ACT-0001 / SALY product pilot
-- Owner-authorized: allow SALY in PRODUCTO Router profile derivation only.
-- No changes to LF, no SALY PROGRAMACION/OPERACIONES, no write authority,
-- no profile/skill registration, no mockup generation, no extra RUN.
-- Mandatory: PR -> PASE -> ready-to-merge -> LF Migration Merge Train.
BEGIN;

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.lf_router_business_catalog_v1)<>2
     OR (SELECT count(*) FROM public.lf_router_business_catalog_v1
           WHERE business_code='LF' AND status='ENABLED')<>1
     OR (SELECT count(*) FROM public.lf_router_business_catalog_v1
           WHERE business_code='SALY' AND status='RECOGNIZED_NOT_ENABLED')<>1
  THEN RAISE EXCEPTION 'SALY_ROUTER_BUSINESS_CATALOG_PREIMAGE_DRIFT'; END IF;

  IF EXISTS (
    SELECT 1 FROM (
      VALUES
        ('public.lf_router_route_v1(jsonb,jsonb,boolean)', '25dc0c8dbf49873cca1c096eccb0b584'),
        ('public.lf_router_profile_after_selection_v1(jsonb,jsonb)', 'f0ddcd722b945535dff348a563a6e6cd'),
        ('public.lf_router_profile_after_selection_raw_v1(jsonb,text)', 'b958f032e79fcbd55b8bcb1bd21ab63a'),
        ('public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)', '29e87b314e879fee1bbfe6fe34fff423'),
        ('public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)', 'a6a8afb7a1f7936d6b56bf50c33f8747')
    ) AS expected(signature,source_md5)
    WHERE md5(pg_get_functiondef(expected.signature::regprocedure))<>expected.source_md5
  ) THEN
     RAISE EXCEPTION 'SALY_ROUTER_PROFILE_FUNCTION_PREIMAGE_DRIFT';
  END IF;
END $preflight$;

DO $patch$
DECLARE
  r record;
  ddl text;
  hit_count integer;
BEGIN
  -- The existing business catalog records the enabled business. The Router
  -- independently enforces the allowed channel. Other consumers only use this
  -- catalog for classification of a known code.
  UPDATE public.lf_router_business_catalog_v1
     SET status='ENABLED'
   WHERE business_code='SALY' AND status='RECOGNIZED_NOT_ENABLED';
  IF NOT FOUND THEN RAISE EXCEPTION 'SALY_ROUTER_ENABLE_NOT_UPDATED'; END IF;

  FOR r IN
    SELECT * FROM (VALUES
      (
        'public.lf_router_route_v1(jsonb,jsonb,boolean)',
        $oldroute$IF NOT EXISTS (SELECT 1 FROM public.lf_router_business_catalog_v1 b WHERE b.business_code=v_business AND b.status='ENABLED') THEN$oldroute$,
        $newroute$IF NOT EXISTS (SELECT 1 FROM public.lf_router_business_catalog_v1 b WHERE b.business_code=v_business AND b.status='ENABLED')
       OR (v_business='SALY' AND v_channel<>'PRODUCTO') THEN$newroute$
      ),
      (
        'public.lf_router_profile_after_selection_v1(jsonb,jsonb)',
        $oldafter$OR p_stage1->>'negocio_codigo'<>'LF'$oldafter$,
        $newafter$OR NOT (p_stage1->>'negocio_codigo'='LF'
             OR (p_stage1->>'negocio_codigo'='SALY' AND v_channel='PRODUCTO'))$newafter$
      ),
      (
        'public.lf_router_profile_after_selection_raw_v1(jsonb,text)',
        $oldraw$OR p_stage1->>'negocio_codigo'<>'LF'$oldraw$,
        $newraw$OR NOT (p_stage1->>'negocio_codigo'='LF'
             OR (p_stage1->>'negocio_codigo'='SALY' AND v_channel='PRODUCTO'))$newraw$
      ),
      (
        'public.lf_router_profile_execution_handoff_v1(jsonb,jsonb,text,text,jsonb)',
        $oldhandoff$OR upper(coalesce(p_business,'')) <> 'LF' THEN$oldhandoff$,
        $newhandoff$OR NOT (upper(coalesce(p_business,''))='LF'
             OR (upper(coalesce(p_business,''))='SALY'
                 AND upper(coalesce(p_channel,''))='PRODUCTO')) THEN$newhandoff$
      ),
      (
        'public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)',
        $oldvalidate$OR p_handoff->>'business' IS DISTINCT FROM 'LF'$oldvalidate$,
        $newvalidate$OR NOT (p_handoff->>'business'='LF'
             OR (p_handoff->>'business'='SALY'
                 AND p_handoff->>'channel'='PRODUCTO'))$newvalidate$
      )
    ) t(signature,old_fragment,new_fragment)
  LOOP
    ddl:=pg_get_functiondef(r.signature::regprocedure);
    hit_count:=(length(ddl)-length(replace(ddl,r.old_fragment,''))) / nullif(length(r.old_fragment),0);
    IF hit_count IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'SALY_ROUTER_PATCH_ANCHOR_DRIFT:%:%',r.signature,hit_count;
    END IF;
    EXECUTE replace(ddl,r.old_fragment,r.new_fragment);
  END LOOP;

  -- Update old LF-only messages only where the exact preimage exists.
  ddl:=pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure);
  IF strpos(ddl,'''La fase actual del Router atiende exclusivamente LF.''')=0
     OR strpos(ddl,'''La fase actual esta cerrada a LF.''')=0 THEN
    RAISE EXCEPTION 'SALY_ROUTER_OLD_MESSAGE_PREIMAGE_DRIFT';
  END IF;
  ddl:=replace(ddl,
    '''La fase actual del Router atiende exclusivamente LF.''',
    '''Negocio o canal no habilitado para esta ruta.''');
  ddl:=replace(ddl,
    '''La fase actual esta cerrada a LF.''',
    '''Solicitud multinegocio requiere validacion de autoridad por separado.''');
  EXECUTE ddl;
END $patch$;

DO $postflight$
DECLARE
  stage jsonb;
  r jsonb;
  candidate_count integer;
BEGIN
  IF (SELECT count(*) FROM public.lf_router_business_catalog_v1
      WHERE business_code IN ('LF','SALY') AND status='ENABLED') <> 2
  THEN RAISE EXCEPTION 'SALY_ROUTER_ENABLE_STATUS_NOT_PERSISTED'; END IF;

  stage:=jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original','SALY: preparar prototipos y mockups de pantallas de APP con el perfil UI.',
    'es_operacion',true,'respuesta_directa',false,'ambiguo',false,
    'accion','preparar prototipos','sujeto','pantallas SALY APP',
    'formas_busqueda',jsonb_build_array('mockups SALY','prototipos de app SALY'),
    'alternativas','[]'::jsonb,'correcciones','[]'::jsonb,
    'pregunta_usuario',NULL,'capability_hint',NULL,
    'downstream_execution_allowed',false,'canal_candidato','PRODUCTO',
    'negocio_codigo','SALY','negocios_afectados','[]'::jsonb,
    'razon_seleccion','La solicitud menciona SALY y prototipos APP.',
    'alcance',jsonb_build_object('target_type','SCREEN','resolution_status','UNRESOLVED')
  );
  IF public.lf_router_stage1_validate_v2(stage)->>'valid'<>'true' THEN
    RAISE EXCEPTION 'SALY_ROUTER_STAGE1_PRODUCTO_INVALID';
  END IF;
  r:=public.lf_router_route_v1(stage,'{}'::jsonb,false);
  IF r->>'paso'<>'PRODUCTO_PROFILE_SELECTION_REQUIRED'
    OR r->>'negocio_codigo'<>'SALY'
    OR r->>'canal_candidato'<>'PRODUCTO'
    OR r->>'downstream_execution_allowed'<>'false'
    OR r->>'router_work_mode'<>'DERIVATION_ONLY'
    OR jsonb_typeof(r->'profile_selection_request')<>'object'
  THEN RAISE EXCEPTION 'SALY_ROUTER_PRODUCTO_PROFILE_DERIVATION_FAILED:%',left(r::text,1000); END IF;

  candidate_count:=coalesce((r->>'profile_selection_candidate_count')::integer,0);
  IF candidate_count<1 OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(r#>'{profile_selection_request,candidate_profiles}') p
      WHERE p->>'profile_code'='PERFIL-UI-ARCHITECT'
        AND p->>'descriptor_status'='CURRENT'
  ) THEN
    RAISE EXCEPTION 'SALY_ROUTER_UI_NOT_IN_DETERMINISTIC_DISCOVERY';
  END IF;

  -- SALY cannot use other channels through this pilot.
  r:=public.lf_router_route_v1(
    jsonb_set(stage,'{canal_candidato}','"PROGRAMACION"'::jsonb),'{}'::jsonb,false);
  IF r->>'paso'<>'NEGOCIO_NO_HABILITADO'
     OR r->>'downstream_execution_allowed'<>'false'
     OR r ? 'profile_selection_request' THEN
    RAISE EXCEPTION 'SALY_PROGRAMACION_NOT_BLOCKED';
  END IF;
  r:=public.lf_router_route_v1(
    jsonb_set(stage,'{canal_candidato}','"OPERACIONES"'::jsonb),'{}'::jsonb,false);
  IF r->>'paso'<>'NEGOCIO_NO_HABILITADO'
     OR r->>'downstream_execution_allowed'<>'false'
     OR r ? 'profile_selection_request' THEN
    RAISE EXCEPTION 'SALY_OPERACIONES_NOT_BLOCKED';
  END IF;

  -- LF remains unchanged on the same channel.
  r:=public.lf_router_route_v1(
    jsonb_set(stage,'{negocio_codigo}','"LF"'::jsonb),'{}'::jsonb,false);
  IF r->>'paso'<>'PRODUCTO_PROFILE_SELECTION_REQUIRED'
     OR r->>'negocio_codigo'<>'LF'
     OR r->>'downstream_execution_allowed'<>'false' THEN
    RAISE EXCEPTION 'LF_PRODUCTO_ROUTING_REGRESSION';
  END IF;

  -- Multibusiness remains blocked without explicit authority.
  stage:=jsonb_set(stage,'{negocio_codigo}','null'::jsonb);
  stage:=jsonb_set(stage,'{negocios_afectados}','["LF","SALY"]'::jsonb);
  r:=public.lf_router_route_v1(stage,'{}'::jsonb,false);
  IF r->>'paso'<>'MULTINEGOCIO_PENDIENTE'
     OR r->>'downstream_execution_allowed'<>'false' THEN
    RAISE EXCEPTION 'SALY_MULTIBUSINESS_ROUTING_REGRESSION';
  END IF;

  -- No router RUN, no downstream effect authority and no skill activation.
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_profile_selection_registry_v1
      WHERE profile_code='PERFIL-UI-ARCHITECT' AND descriptor_status='CURRENT'
  ) THEN RAISE EXCEPTION 'SALY_UI_PROFILE_CATALOG_MISSING'; END IF;
END $postflight$;

COMMENT ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) IS
'ACT-0001 V2: LF derivation preserved; SALY PRODUCTO permitted for read-only profile selection only. SALY PROGRAMACION and OPERACIONES remain blocked. Router does not start profile RUN or grant effect authority.';

COMMIT;
