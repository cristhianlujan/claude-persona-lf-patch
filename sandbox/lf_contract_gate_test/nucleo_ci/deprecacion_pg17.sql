-- PG17 real aislado; prueba por instancia; no ejecutar fuera del contenedor.
DO $test$
DECLARE
 base jsonb; r jsonb; p jsonb; pts jsonb; h1 text; v_before jsonb; v_after jsonb;
 code text := 'ZZT-DEPRECACION'; before_legacy text; before_count bigint; caught boolean;
BEGIN
 SELECT count(*),md5(string_agg(to_jsonb(l)::text,'|' ORDER BY id)) INTO before_count,before_legacy FROM lf_ops.reglas l;
 PERFORM @SCHEMA@.nucleo_autotest_datos_v1();
 base:=jsonb_build_object('codigo',code,'clave','zzt_f4_conform','titulo','Bloqueo por reenvíos de OTP',
 'descripcion','Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos configurado','familia','ZZT_FAM','naturaleza','CONDUCTA',
 'autoridad','ZZT-Q','dueno','LF_GOVERNANCE','alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','plazo_dias',10,
 'origen',jsonb_build_object('tipo','CHAT','ref','f4-ci-isolated','solicitante','autotest'),
 'condicion',jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
 'pruebas',jsonb_build_array(
 jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
 jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
 jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true)));
 r:=@SCHEMA@.nucleo_regla_proponer_v1(base);
 IF r->>'resultado' IS DISTINCT FROM 'CANDIDATA' THEN RAISE EXCEPTION 'F4_FIXTURE_PROPOSE %',r; END IF;
 SELECT jsonb_object_agg(codigo,jsonb_build_object('puntaje',1)) INTO pts FROM @SCHEMA@.nucleo_rubrica WHERE estado='ACTIVO';
 p:=jsonb_build_object('regla',code,'veredicto','PASS','puntajes',pts,'juez','AUTOTEST','modo','CONTEXTO_ACTUAL','revisor_es_productor',true,'llamadas_modelo',0,'evidencia_ref','F4 isolated CI');
 r:=@SCHEMA@.nucleo_regla_evaluar_v1(code,false);
 PERFORM @SCHEMA@.nucleo_juicio_registrar_v1(p||jsonb_build_object('hash_evaluado',r->>'hash_paquete'));
 r:=@SCHEMA@.nucleo_regla_promover_v1(code);
 IF r->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' THEN RAISE EXCEPTION 'F4_FIXTURE_PROMOTE_1 %',r; END IF;

 SELECT hash,to_jsonb(v) INTO STRICT h1,v_before FROM @SCHEMA@.nucleo_regla_versiones v WHERE regla=code AND version=1;
 IF NOT EXISTS(SELECT 1 FROM @SCHEMA@.nucleo_reglas_efectivas_v1('ZZT-MOD-1',now()) WHERE regla=code AND version=1) THEN RAISE EXCEPTION 'DEP_TEST_NOT_EFFECTIVE'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 01 publicado y efectivo';
 caught:=false; BEGIN PERFORM @SCHEMA@.nucleo_regla_deprecar_v1(code,1,repeat('0',64),'ZZT-Q','Prueba de hash incorrecto');
 EXCEPTION WHEN others THEN IF SQLERRM LIKE 'NUCLEO_DEPRECAR_VERSION_OBSOLETA:%' THEN caught:=true; ELSE RAISE; END IF; END;
 IF NOT caught THEN RAISE EXCEPTION 'DEP_BAD_HASH_ACCEPTED'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 02 hash incorrecto rechazado';
 caught:=false; BEGIN PERFORM @SCHEMA@.nucleo_regla_deprecar_v1(code,1,h1,'ZZT-NO-EXISTE','Prueba autoridad inválida');
 EXCEPTION WHEN others THEN IF SQLERRM LIKE 'NUCLEO_DEPRECAR_AUTORIDAD_NO_VIGENTE:%' THEN caught:=true; ELSE RAISE; END IF; END;
 IF NOT caught THEN RAISE EXCEPTION 'DEP_BAD_AUTHORITY_ACCEPTED'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 03 autoridad inválida';
 caught:=false; BEGIN PERFORM @SCHEMA@.nucleo_regla_deprecar_v1(code,1,h1,'ZZT-Q','x');
 EXCEPTION WHEN others THEN IF SQLERRM='NUCLEO_DEPRECAR_SIN_MOTIVO' THEN caught:=true; ELSE RAISE; END IF; END;
 IF NOT caught THEN RAISE EXCEPTION 'DEP_BAD_REASON_ACCEPTED'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 04 motivo inválido';
 r:=@SCHEMA@.nucleo_regla_deprecar_v1(code,1,h1,'ZZT-Q','Deprecación sintética autorizada en fixture');
 SELECT to_jsonb(v) INTO STRICT v_after FROM @SCHEMA@.nucleo_regla_versiones v WHERE regla=code AND version=1;
 IF r->>'estado' IS DISTINCT FROM 'DEPRECADA' OR (SELECT estado FROM @SCHEMA@.nucleo_reglas WHERE codigo=code) IS DISTINCT FROM 'DEPRECADA'
 OR v_after->>'estado' IS DISTINCT FROM 'PUBLICADA' OR v_after->>'vigente_hasta' IS NULL
 OR (v_before-'vigente_hasta') IS DISTINCT FROM (v_after-'vigente_hasta') THEN RAISE EXCEPTION 'DEP_HISTORY_MUTATED %',r; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 05 cierre inmutable';
 IF EXISTS(SELECT 1 FROM @SCHEMA@.nucleo_reglas_efectivas_v1('ZZT-MOD-1',now()) WHERE regla=code)
 OR EXISTS(SELECT 1 FROM @SCHEMA@.nucleo_cola_trabajo_v1('ZZT-MOD-1',now()) WHERE regla=code)
 THEN RAISE EXCEPTION 'DEP_STILL_EFFECTIVE'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 06 deja de exigirse';
 IF NOT EXISTS(SELECT 1 FROM @SCHEMA@.nucleo_deprecaciones WHERE regla=code AND version=1 AND hash_version=h1 AND autoridad='ZZT-Q'
 AND motivo='Deprecación sintética autorizada en fixture' AND vigente_hasta=now())
 THEN RAISE EXCEPTION 'DEP_NO_HISTORY'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 07 historial';
 caught:=false; BEGIN PERFORM @SCHEMA@.nucleo_regla_deprecar_v1(code,1,h1,'ZZT-Q','No se puede deprecar dos veces');
 EXCEPTION WHEN others THEN IF SQLERRM LIKE 'NUCLEO_DEPRECAR_NO_VIGENTE:%' THEN caught:=true; ELSE RAISE; END IF; END;
 IF NOT caught THEN RAISE EXCEPTION 'DEP_REPEAT_ACCEPTED'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 08 no vigente rechazada';
 IF (SELECT count(*) FROM lf_ops.reglas)<>before_count OR (SELECT md5(string_agg(to_jsonb(l)::text,'|' ORDER BY id)) FROM lf_ops.reglas l) IS DISTINCT FROM before_legacy
 OR EXISTS(SELECT * FROM lf_ops.reglas EXCEPT ALL SELECT * FROM lf_ops.v_reglas_compat_v1)
 OR EXISTS(SELECT * FROM lf_ops.v_reglas_compat_v1 EXCEPT ALL SELECT * FROM lf_ops.reglas)
 THEN RAISE EXCEPTION 'DEP_LEGACY_CHANGED'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 09 legado y compat intactos';
 IF has_function_privilege('service_role','@SCHEMA@.nucleo_regla_deprecar_v1(text,integer,text,text,text)','EXECUTE')
 OR has_function_privilege('anon','@SCHEMA@.nucleo_regla_deprecar_v1(text,integer,text,text,text)','EXECUTE')
 OR has_function_privilege('authenticated','@SCHEMA@.nucleo_regla_deprecar_v1(text,integer,text,text,text)','EXECUTE')
 OR has_function_privilege('supabase_read_only_user','@SCHEMA@.nucleo_regla_deprecar_v1(text,integer,text,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'DEP_ACL_LEAK'; END IF;
 RAISE NOTICE 'DEP_PASS @SCHEMA@ 10 permisos';
END $test$;
