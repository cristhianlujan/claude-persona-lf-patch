-- AM: migration candidate and legacy coexistence. No legacy writes, no pilot publication.
-- Compatibility retains the complete original legacy rows; matching/linked/migration-origin
-- core proposals remain separately visible in native core tables and are not a reader cutover.
BEGIN;
DO $pre$ BEGIN IF md5(pg_get_viewdef('lf_ops.v_reglas_compat_v1'::regclass,true)) <> 'a413d691d6c4682793086027e90366ce' THEN RAISE EXCEPTION 'AM_COEX_VIEW_BASE_DRIFT'; END IF; END $pre$;
CREATE OR REPLACE VIEW lf_ops.v_reglas_compat_v1 AS
 SELECT r.id,
    r.codigo,
    r.categoria,
    r.titulo,
    r.descripcion,
    r.razon,
    r.valor_config,
    r.es_transversal,
    r.estado,
    r.origen,
    r.created_at,
    r.updated_at,
    r.pendiente_decision,
    r.pendiente_detalle,
    r.created_by
   FROM lf_ops.reglas r
UNION ALL
 SELECT n.regla_legacy_id AS id,
    n.codigo,
    n.familia AS categoria,
    v.titulo,
    v.descripcion,
    NULL::text AS razon,
    jsonb_build_object('nucleo', true, 'version', v.version, 'condicion', v.condicion, 'efecto', v.efecto) AS valor_config,
    COALESCE(a.nivel = ANY (ARRAY['GLOBAL'::text, 'AMBITO'::text]), false) AS es_transversal,
        CASE n.estado
            WHEN 'VIGENTE'::text THEN 'VIGENTE'::text
            ELSE 'CANDIDATO'::text
        END AS estado,
    v.origen ->> 'ref'::text AS origen,
    n.created_at,
    v.created_at AS updated_at,
    false AS pendiente_decision,
    NULL::text AS pendiente_detalle,
    v.origen ->> 'solicitante'::text AS created_by
   FROM lf_ops.nucleo_reglas n
     JOIN LATERAL ( SELECT x.regla,
            x.version,
            x.titulo,
            x.descripcion,
            x.condicion,
            x.efecto,
            x.autoridad,
            x.publicada_desde,
            x.exigible_desde,
            x.vigente_hasta,
            x.hash,
            x.created_at,
            x.estado,
            x.impacto,
            x.origen,
            x.ficha,
            x.plazo_dias
           FROM lf_ops.nucleo_regla_versiones x
          WHERE x.regla = n.codigo AND x.estado <> 'DESCARTADA'::text
          ORDER BY (x.estado = 'PUBLICADA'::text AND x.vigente_hasta IS NULL) DESC, x.version DESC
         LIMIT 1) v ON true
     LEFT JOIN LATERAL ( SELECT nn.nivel
           FROM lf_ops.nucleo_aplicaciones ap
             JOIN lf_ops.nucleo_nodos nn ON nn.codigo = ap.nodo
          WHERE ap.regla = n.codigo
          ORDER BY ap.nodo
         LIMIT 1) a ON true
  WHERE n.estado = ANY (ARRAY['CANDIDATA'::text, 'VIGENTE'::text])
    AND n.regla_legacy_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM lf_ops.reglas old WHERE old.codigo = n.codigo)
    ;
CREATE OR REPLACE FUNCTION lf_ops.lf_puente_autotest_v1()
 RETURNS text LANGUAGE plpgsql SET search_path TO 'pg_catalog','lf_ops','public'
AS $test$
DECLARE
 v_id integer; v_codigo text; v_old jsonb; p jsonb; r jsonb; pts jsonb; e jsonb;
 old_count bigint;
BEGIN
 -- V1 legacy-facing identity stays unique; physical parity is independently tested
 -- in the migration and in the PG17 suite, without a new direct legacy reader.
 IF EXISTS(SELECT codigo FROM v_reglas_compat_v1 GROUP BY codigo HAVING count(*)>1) OR
    EXISTS(SELECT id FROM v_reglas_compat_v1 WHERE id IS NOT NULL GROUP BY id HAVING count(*)>1)
 THEN RAISE EXCEPTION 'AM_COEX_V1_DUPLICATE'; END IF;
 -- V2 the public legacy shape is unchanged.
 IF (SELECT string_agg(column_name||':'||data_type,',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='lf_ops' AND table_name='reglas')
    IS DISTINCT FROM (SELECT string_agg(column_name||':'||data_type,',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='lf_ops' AND table_name='v_reglas_compat_v1')
 THEN RAISE EXCEPTION 'AM_COEX_V2_SHAPE'; END IF;
 SELECT id,codigo,to_jsonb(v) INTO v_id,v_codigo,v_old FROM v_reglas_compat_v1 v
 WHERE id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM nucleo_reglas n WHERE n.codigo=v.codigo)
 ORDER BY id LIMIT 1;
 IF v_id IS NULL THEN RAISE EXCEPTION 'AM_COEX_FIXTURE_NO_LEGACY'; END IF;
 SELECT count(*) INTO old_count FROM v_reglas_compat_v1;
 BEGIN
  PERFORM nucleo_autotest_datos_v1();
  p:=jsonb_build_object('codigo','ZZT-AM-COEX-1','clave','zzt_am_coex1','titulo','Regla de prueba de coexistencia',
    'descripcion','Bloquear el reenvío de prueba al alcanzar el parámetro de la instancia',
    'familia','ZZT_FAM','naturaleza','CONDUCTA','autoridad','ZZT-Q','dueno','PRUEBA','alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA',
    'efecto','BLOQUEAR','impacto','IMPLEMENTAR','origen',jsonb_build_object('tipo','CHAT','ref','autotest-am-coex','solicitante','autotest'),
    'condicion',jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
    'pruebas',jsonb_build_array(
      jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
      jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
      jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true)));
  r:=nucleo_regla_proponer_v1(p);
  -- V3 unmatched new core code is still projected.
  IF r->>'resultado'<>'CANDIDATA' OR NOT EXISTS(SELECT 1 FROM v_reglas_compat_v1 WHERE codigo='ZZT-AM-COEX-1' AND estado='CANDIDATO' AND id IS NULL)
     OR (SELECT count(*) FROM v_reglas_compat_v1)<>old_count+1
  THEN RAISE EXCEPTION 'AM_COEX_V3_UNMATCHED %',r; END IF;
  -- V4 linking a synthetic candidate cannot remove or overwrite the legacy row.
  -- Test only: this FK mutation is rolled back; no actual pilot or legacy is modified.
  UPDATE nucleo_reglas SET regla_legacy_id=v_id WHERE codigo='ZZT-AM-COEX-1';
  IF (SELECT to_jsonb(v) FROM v_reglas_compat_v1 v WHERE id=v_id) IS DISTINCT FROM v_old OR
     EXISTS(SELECT 1 FROM v_reglas_compat_v1 WHERE codigo='ZZT-AM-COEX-1') OR
     (SELECT count(*) FROM v_reglas_compat_v1)<>old_count
  THEN RAISE EXCEPTION 'AM_COEX_V4_LEGACY_HIDDEN'; END IF;
  -- V5 same-code candidates, even without FK, are native-only.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo',v_codigo,'clave','zzt_am_coex2'));
  IF r->>'resultado'<>'CANDIDATA' OR NOT EXISTS(SELECT 1 FROM nucleo_regla_versiones WHERE regla=v_codigo AND estado='CANDIDATA') OR
     (SELECT count(*) FROM v_reglas_compat_v1 WHERE codigo=v_codigo)<>1 OR
     (SELECT to_jsonb(v) FROM v_reglas_compat_v1 v WHERE codigo=v_codigo) IS DISTINCT FROM v_old
  THEN RAISE EXCEPTION 'AM_COEX_V5_SAME_CODE_DUPLICATE %',r; END IF;
  -- V6 migration with new code and legacy provenance but no FK is native-only.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-AM-COEX-3','clave','zzt_am_coex3','origen',jsonb_build_object('tipo','MIGRACION','ref','lf_ops.reglas/'||v_id,'solicitante','autotest')));
  IF r->>'resultado'<>'CANDIDATA' OR NOT EXISTS(SELECT 1 FROM nucleo_regla_versiones WHERE regla='ZZT-AM-COEX-3' AND estado='CANDIDATA') OR
     EXISTS(SELECT 1 FROM v_reglas_compat_v1 WHERE codigo='ZZT-AM-COEX-3')
  THEN RAISE EXCEPTION 'AM_COEX_V6_ORIGIN_DUPLICATE %',r; END IF;
  -- V7 synthetic publication follows canonical evaluation; old reader still sees legacy only.
  SELECT jsonb_object_agg(codigo,jsonb_build_object('puntaje',1)) INTO pts FROM nucleo_rubrica WHERE estado='ACTIVO';
  e:=nucleo_regla_evaluar_v1('ZZT-AM-COEX-1',false);
  PERFORM nucleo_juicio_registrar_v1(jsonb_build_object('regla','ZZT-AM-COEX-1','hash_evaluado',e->>'hash_paquete','veredicto','PASS','juez','AUTOTEST',
    'modo','CONTEXTO_ACTUAL','revisor_es_productor',true,'llamadas_modelo',0,'evidencia_ref','autotest coexistencia fixture','puntajes',pts));
  e:=nucleo_regla_promover_v1('ZZT-AM-COEX-1');
  IF e->>'resultado'<>'PROMOVIDA_AUTO' OR NOT EXISTS(SELECT 1 FROM nucleo_regla_versiones WHERE regla='ZZT-AM-COEX-1' AND estado='PUBLICADA') OR
     (SELECT to_jsonb(v) FROM v_reglas_compat_v1 v WHERE id=v_id) IS DISTINCT FROM v_old OR
     EXISTS(SELECT 1 FROM v_reglas_compat_v1 WHERE codigo='ZZT-AM-COEX-1')
  THEN RAISE EXCEPTION 'AM_COEX_V7_PUBLICATION_HIDES_LEGACY %',e; END IF;
  -- V8 no way to revise first unpublished candidate by the current canonical paths:
  -- demonstrate the actual blocker without changing any pilot.
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-AM-COEX-4','clave','zzt_am_coex4'));
  IF r->>'resultado'<>'CANDIDATA' THEN RAISE EXCEPTION 'AM_COEX_V8_FIXTURE %',r; END IF;
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-AM-COEX-4','clave','zzt_am_coex4','tipo','CAMBIO','titulo','Nueva revisión de prueba'),false);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n'='0' AND (x->>'bloqueante')::boolean AND (x->>'ok')::boolean=false AND x->>'detalle' LIKE '%versión candidata abierta%')
  THEN RAISE EXCEPTION 'AM_COEX_V8_OPEN_CANDIDATE_CONTROL %',r; END IF;
  PERFORM nucleo_version_descartar_v1('ZZT-AM-COEX-4','ZZT-Q','Descarte de sonda no publicada dentro del autotest');
  r:=nucleo_regla_proponer_v1(p||jsonb_build_object('codigo','ZZT-AM-COEX-4','clave','zzt_am_coex4','tipo','CAMBIO','titulo','Nueva revisión de prueba'),false);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'controles') x WHERE x->>'n'='0' AND (x->>'bloqueante')::boolean AND (x->>'ok')::boolean=false AND x->>'detalle' LIKE '%RETIRADA%')
  THEN RAISE EXCEPTION 'AM_COEX_V8_RETIRED_CONTROL %',r; END IF;
  RAISE NOTICE 'AM_REVISION_BLOCKED: CAMBIO with candidate open; discard first candidate => RETIRADA; CAMBIO rejected';
  RAISE EXCEPTION 'AM_COEX_ROLLBACK_OK';
 EXCEPTION WHEN others THEN
  IF SQLERRM<>'AM_COEX_ROLLBACK_OK' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM nucleo_reglas WHERE codigo IN('ZZT-AM-COEX-1','ZZT-AM-COEX-3','ZZT-AM-COEX-4',v_codigo)) OR
    (SELECT count(*) FROM v_reglas_compat_v1)<>old_count OR
    (SELECT to_jsonb(v) FROM v_reglas_compat_v1 v WHERE id=v_id) IS DISTINCT FROM v_old
 THEN RAISE EXCEPTION 'AM_COEX_ROLLBACK_LEAK'; END IF;
 RETURN 'PUENTE 8/8';
END $test$;

DO $parity$
BEGIN
 IF EXISTS(SELECT * FROM lf_ops.reglas EXCEPT ALL SELECT * FROM lf_ops.v_reglas_compat_v1 WHERE id IS NOT NULL) OR
    EXISTS(SELECT * FROM lf_ops.v_reglas_compat_v1 WHERE id IS NOT NULL EXCEPT ALL SELECT * FROM lf_ops.reglas)
 THEN RAISE EXCEPTION 'AM_COEX_LEGACY_PARITY_FAILED'; END IF;
 IF EXISTS(SELECT codigo FROM lf_ops.v_reglas_compat_v1 GROUP BY codigo HAVING count(*)>1)
 THEN RAISE EXCEPTION 'AM_COEX_DUPLICATE_CODE'; END IF;
 RAISE NOTICE 'AM_COEX_LEGACY_PARITY_OK';
END $parity$;

DO $verify$
BEGIN
 IF lf_ops.lf_puente_autotest_v1() IS DISTINCT FROM 'PUENTE 8/8' THEN RAISE EXCEPTION 'AM_COEX_TEST_FAILED'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones v JOIN lf_ops.nucleo_reglas r ON r.codigo=v.regla WHERE r.familia='PAYMENTS_CHECKOUT' AND v.estado='PUBLICADA') THEN RAISE EXCEPTION 'AM_COEX_UNAUTHORIZED_PILOT_PUBLICATION'; END IF;
 RAISE NOTICE 'AM_COEX_PASS PUENTE 8/8; legacy intact; zero pilot publication';
END $verify$;
COMMIT;
