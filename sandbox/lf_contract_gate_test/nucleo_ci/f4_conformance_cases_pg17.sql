-- Repetir por instancia en PG17 aislado; @SCHEMA@/@OTHER@ son sustituciones de lista cerrada del runner.
DO $test$
DECLARE
 base jsonb; r jsonb; p jsonb; pts jsonb; h1 text; h2 text; deadline timestamptz;
 claim jsonb; got text; qstate text; code text := 'ZZT-F4-CONFORM';
BEGIN
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
 SELECT hash INTO STRICT h1 FROM @SCHEMA@.nucleo_regla_versiones WHERE regla=code AND version=1;
 claim:=jsonb_build_object('instancia','@SCHEMA@','nodo','ZZT-MOD-1','regla',code,'version',1,'version_hash',h1);
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim),now())->0->>'estado';
 IF got IS DISTINCT FROM 'VERSION_NO_PUBLICADA' THEN RAISE EXCEPTION 'F4_01_CANDIDATA %',got; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 01 candidata rechazada';
 SELECT jsonb_object_agg(codigo,jsonb_build_object('puntaje',1)) INTO pts FROM @SCHEMA@.nucleo_rubrica WHERE estado='ACTIVO';
 p:=jsonb_build_object('regla',code,'veredicto','PASS','puntajes',pts,'juez','AUTOTEST','modo','CONTEXTO_ACTUAL','revisor_es_productor',true,'llamadas_modelo',0,'evidencia_ref','F4 isolated CI');
 r:=@SCHEMA@.nucleo_regla_evaluar_v1(code,false);
 PERFORM @SCHEMA@.nucleo_juicio_registrar_v1(p||jsonb_build_object('hash_evaluado',r->>'hash_paquete'));
 r:=@SCHEMA@.nucleo_regla_promover_v1(code);
 IF r->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' THEN RAISE EXCEPTION 'F4_FIXTURE_PROMOTE_1 %',r; END IF;
 SELECT hash INTO STRICT h1 FROM @SCHEMA@.nucleo_regla_versiones WHERE regla=code AND version=1;
 claim:=claim||jsonb_build_object('version_hash',h1);
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim),now())->0->>'estado';
 IF got IS DISTINCT FROM 'AL_DIA' THEN RAISE EXCEPTION 'F4_02_VALID %',got; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 02 publicación exacta';
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim||jsonb_build_object('version_hash',repeat('0',64))),now())->0->>'estado';
 IF got IS DISTINCT FROM 'HASH_DISTINTO' THEN RAISE EXCEPTION 'F4_03_HASH %',got; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 03 hash alterado';
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim||jsonb_build_object('instancia','@OTHER@')),now())->0->>'estado';
 IF got NOT IN ('NODO_INEXISTENTE','VERSION_NO_PUBLICADA') OR got IS NULL THEN RAISE EXCEPTION 'F4_04_ISOLATION %',got; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 04 aislamiento';
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim||jsonb_build_object('nodo','ZZT-NO-EXISTE')),now())->0->>'estado';
 IF got IS DISTINCT FROM 'NODO_INEXISTENTE' THEN RAISE EXCEPTION 'F4_05_NODE %',got; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 05 nodo inexistente';
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim||jsonb_build_object('nodo','ZZT-AMB')),now())->0->>'estado';
 IF got IS DISTINCT FROM 'NODO_NO_HOJA' THEN RAISE EXCEPTION 'F4_06_NON_LEAF %',got; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 06 nodo no hoja';
 -- Registro de implementación sintético, solo para contrastar el oráculo D4 vigente.
 INSERT INTO @SCHEMA@.nucleo_implementaciones(regla,version,nodo,evidencia_ref) VALUES(code,1,'ZZT-MOD-1','F4 isolated synthetic implementation');
 r:=@SCHEMA@.nucleo_regla_proponer_v1(base||jsonb_build_object('tipo','CAMBIO','descripcion','Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos; aplica a SMS y correo','origen',jsonb_build_object('tipo','CHAT','ref','f4-ci-isolated-v2','solicitante','autotest')));
 IF r->>'resultado' IS DISTINCT FROM 'CANDIDATA' OR (r->>'version')::integer<>2 THEN RAISE EXCEPTION 'F4_FIXTURE_CHANGE %',r; END IF;
 SELECT hash INTO STRICT h2 FROM @SCHEMA@.nucleo_regla_versiones WHERE regla=code AND version=2;
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim||jsonb_build_object('version',2,'version_hash',h2)),now())->0->>'estado';
 IF got IS DISTINCT FROM 'VERSION_NO_PUBLICADA' THEN RAISE EXCEPTION 'F4_07_CANDIDATA_2 %',got; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 07 V2 candidata rechazada';
 r:=@SCHEMA@.nucleo_regla_evaluar_v1(code,false);
 PERFORM @SCHEMA@.nucleo_juicio_registrar_v1(p||jsonb_build_object('hash_evaluado',r->>'hash_paquete'));
 r:=@SCHEMA@.nucleo_regla_promover_v1(code);
 IF r->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' THEN RAISE EXCEPTION 'F4_FIXTURE_PROMOTE_2 %',r; END IF;
 SELECT hash,exigible_desde INTO STRICT h2,deadline FROM @SCHEMA@.nucleo_regla_versiones WHERE regla=code AND version=2;
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim),now())->0->>'estado';
 SELECT estado INTO STRICT qstate FROM @SCHEMA@.nucleo_cola_trabajo_v1('ZZT-MOD-1',now()) WHERE regla=code;
 IF got IS DISTINCT FROM 'EN_PLAZO' OR got IS DISTINCT FROM qstate THEN RAISE EXCEPTION 'F4_08_GRACE % %',got,qstate; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 08 plazo respetado';
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim),deadline)->0->>'estado';
 SELECT estado INTO STRICT qstate FROM @SCHEMA@.nucleo_cola_trabajo_v1('ZZT-MOD-1',deadline) WHERE regla=code;
 IF got IS DISTINCT FROM 'DESFASADO' OR got IS DISTINCT FROM qstate THEN RAISE EXCEPTION 'F4_09_STALE % %',got,qstate; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 09 desfase real detectado';
 got:=pg_temp.f4_conformance_v1(jsonb_build_array(claim||jsonb_build_object('version',2,'version_hash',h2)),deadline)->0->>'estado';
 IF got IS DISTINCT FROM 'AL_DIA' THEN RAISE EXCEPTION 'F4_10_UPDATED %',got; END IF;
 RAISE NOTICE 'F4_CONFORM_PASS @SCHEMA@ 10 código actualizado';
END $test$;
