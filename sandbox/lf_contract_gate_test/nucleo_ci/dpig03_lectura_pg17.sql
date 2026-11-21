-- SOLO PG17 aislado. Fixture legada y publicación sintética, no LF real.
BEGIN;
INSERT INTO lf_ops.app_shells(app_shell_id,app_shell_code) VALUES (900001,'ZZT-DPIG03-SHELL');
INSERT INTO lf_ops.modulos(module_id,app_shell_id,module_code) VALUES (900001,900001,'ZZT-DPIG03-MODULE');
UPDATE lf_ops.pantallas SET module_id=900001,module_code='ZZT-DPIG03-MODULE' WHERE id IN (59,43);
INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,estado,es_transversal,valor_config) VALUES
 (900001,'ZZT-DPIG03-DIRECT','checkout','Regla directa candidata','Fixture directa candidata sin publicación','CANDIDATO',false,NULL),
 (900002,'ZZT-DPIG03-DECL','checkout','Regla declarativa vigente','Fixture declarativa con selector de pantalla','VIGENTE',false,
 '{"applicability_v1":{"schema_version":"lf-rule-applicability/v1","status":"ACTIVE","consumer_roles":["INPUT_GOVERNANCE"],"all":[{"path":["target","screen","id"],"op":"EQ","value":59}]}}'),
 (900003,'ZZT-DPIG03-GLOBAL','checkout','Regla heredada vigente','Fixture de herencia legada por uso observado','VIGENTE',false,NULL);
INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id) VALUES (900001,59);
INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id)
 SELECT 900003,p.id FROM lf_ops.pantallas p WHERE p.id<>59 ORDER BY p.id LIMIT 25;
DO $verify$
DECLARE
 a jsonb; exp jsonb; b jsonb; ok boolean; base jsonb; result jsonb; pts jsonb;
BEGIN
 -- 1. Firma original intacta, sin nuevo acceso por consumidores no habilitados.
 IF md5(pg_get_functiondef('lf_ops.nucleo_reglas_efectivas_v1(text,timestamptz)'::regprocedure)) IS DISTINCT FROM '6a7f47636bb1150d650d61214d93152b'
  OR has_function_privilege('anon','lf_ops.nucleo_reglas_efectivas_v1(integer,text,text)','EXECUTE')
  OR has_function_privilege('authenticated','lf_ops.nucleo_reglas_efectivas_v1(integer,text,text)','EXECUTE')
  OR has_function_privilege('service_role','lf_ops.nucleo_reglas_efectivas_v1(integer,text,text)','EXECUTE')
  OR NOT has_function_privilege('supabase_read_only_user','lf_ops.nucleo_reglas_efectivas_v1(integer,text,text)','EXECUTE')
  OR EXISTS(SELECT 1 FROM pg_proc WHERE oid='lf_ops.nucleo_reglas_efectivas_v1(integer,text,text)'::regprocedure AND (prosecdef OR provolatile<>'s'))
 THEN RAISE EXCEPTION 'DPIG03_TEST_01_PRIVILEGIOS'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 01 ACL y firma';
 -- 2. Directas: filas legadas exactas, incluso CANDIDATO, sin promoción.
 SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.categoria,r.codigo,r.id),'[]'::jsonb) INTO exp
 FROM lf_ops.reglas_pantallas rp JOIN lf_ops.reglas r ON r.id=rp.regla_id WHERE rp.pantalla_id=59;
 a:=lf_ops.nucleo_reglas_efectivas_v1(59,'INPUT_GOVERNANCE','DIRECTAS');
 IF a->>'estado' IS DISTINCT FROM 'RESPALDO_COMPAT' OR a->'reglas' IS DISTINCT FROM exp
   OR NOT (a->'reglas' @> '[{"codigo":"ZZT-DPIG03-DIRECT","estado":"CANDIDATO"}]')
   OR a->'nativas'<>'[]'::jsonb THEN RAISE EXCEPTION 'DPIG03_TEST_02_DIRECTAS %',a; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 02 directas';
 -- 3. Selección IG, con las tres rutas; oráculo legada real extraído.
 SELECT coalesce(jsonb_agg(jsonb_build_object('binding_source',l.binding_source,'regla',to_jsonb(r)) ORDER BY r.codigo,l.binding_source,r.id),'[]'::jsonb) INTO exp
 FROM programacion.fn_input_effective_rule_links_v1(59,'INPUT_GOVERNANCE') l JOIN lf_ops.reglas r ON r.id=l.regla_id;
 a:=lf_ops.nucleo_reglas_efectivas_v1(59,'INPUT_GOVERNANCE','IG_EFECTIVAS');
 IF a->'reglas' IS DISTINCT FROM exp OR NOT (exp @> '[{"binding_source":"LEGACY_EXPLICIT","regla":{"codigo":"ZZT-DPIG03-DIRECT"}},{"binding_source":"DECLARATIVE_APPLICABILITY_V1","regla":{"codigo":"ZZT-DPIG03-DECL"}},{"binding_source":"DERIVED_GLOBAL","regla":{"codigo":"ZZT-DPIG03-GLOBAL"}}]')
 THEN RAISE EXCEPTION 'DPIG03_TEST_03_EFECTIVAS'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 03 efectivas';
 -- 4. Consumer distinto no recibe selector declarativo ajeno.
 b:=lf_ops.nucleo_reglas_efectivas_v1(59,'ZZT-OTHER','IG_EFECTIVAS');
 IF b->'reglas' @> '[{"regla":{"codigo":"ZZT-DPIG03-DECL"}}]' THEN RAISE EXCEPTION 'DPIG03_TEST_04_CONSUMER'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 04 selector consumer';
 -- 5. Proyección de contrato legacy (directas + solo DERIVED_GLOBAL).
 WITH attached AS(
 SELECT r.* FROM lf_ops.reglas_pantallas rp JOIN lf_ops.reglas r ON r.id=rp.regla_id WHERE rp.pantalla_id=59
 UNION ALL SELECT r.* FROM programacion.fn_input_effective_rule_links_v1(59,'INPUT_GOVERNANCE') l JOIN lf_ops.reglas r ON r.id=l.regla_id WHERE l.binding_source='DERIVED_GLOBAL')
 SELECT coalesce(jsonb_agg(jsonb_build_object('rule_id',r.id,'rule_code',r.codigo,'category',r.categoria,
 'title',r.titulo,'description',r.descripcion,'reason',r.razon,'config',r.valor_config,'transversal',r.es_transversal,
 'status',r.estado,'origin',r.origen,'pending_decision',r.pendiente_decision,'pending_detail',r.pendiente_detalle) ORDER BY r.codigo),'[]'::jsonb)
 INTO exp FROM attached r;
 a:=lf_ops.nucleo_reglas_efectivas_v1(59,'ZZT-PROFILE','CONTRATO_PANTALLA');
 IF a->'reglas' IS DISTINCT FROM exp OR exp @> '[{"rule_code":"ZZT-DPIG03-DECL"}]' THEN RAISE EXCEPTION 'DPIG03_TEST_05_CONTRATO'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 05 contrato pantalla';
 -- 6. Mutaciones del resultado deben romper equivalencia.
 IF jsonb_array_length(exp)=0 OR (a->'reglas' - 0) IS NOT DISTINCT FROM exp THEN RAISE EXCEPTION 'DPIG03_TEST_06_NEGATIVO'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 06 pérdida detectada';
 -- 7/8. Pantalla fuera de árbol conocida vs inexistente; no inventar nodo.
 a:=lf_ops.nucleo_reglas_efectivas_v1(99999,'INPUT_GOVERNANCE','DIRECTAS');
 IF a->>'estado' IS DISTINCT FROM 'RESPALDO_SIN_NODO' OR a->'nodo' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'DPIG03_TEST_07_SIN_NODO'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 07 fuera árbol';
 ok:=false;
 BEGIN PERFORM lf_ops.nucleo_reglas_efectivas_v1(-1,'INPUT_GOVERNANCE','DIRECTAS');
 EXCEPTION WHEN invalid_parameter_value THEN ok:=SQLERRM LIKE 'DP_IG_03_PANTALLA_INEXISTENTE%'; END;
 IF NOT ok THEN RAISE EXCEPTION 'DPIG03_TEST_08_PANTALLA'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 08 inexistente';
 -- 9. Sin contrato legado no se hace pasar por conjunto vacío.
 a:=lf_ops.nucleo_reglas_efectivas_v1(99999,'INPUT_GOVERNANCE','CONTRATO_PANTALLA');
 IF a->>'estado' IS DISTINCT FROM 'SIN_CONTRATO_LEGADO' OR a->'reglas' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'DPIG03_TEST_09_SIN_CONTRATO'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 09 sin contrato';
 -- 10/11. Argumentos inválidos.
 ok:=false; BEGIN PERFORM lf_ops.nucleo_reglas_efectivas_v1(59,'INPUT_GOVERNANCE','ZZT'); EXCEPTION WHEN invalid_parameter_value THEN ok:=SQLERRM LIKE 'DP_IG_03_PROYECCION_INVALIDA%'; END;
 IF NOT ok THEN RAISE EXCEPTION 'DPIG03_TEST_10_PROYECCION'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 10 proyección inválida';
 ok:=false; BEGIN PERFORM lf_ops.nucleo_reglas_efectivas_v1(59,NULL,'DIRECTAS'); EXCEPTION WHEN invalid_parameter_value THEN ok:=SQLERRM LIKE 'DP_IG_03_CONSUMER_INVALIDO%'; END;
 IF NOT ok THEN RAISE EXCEPTION 'DPIG03_TEST_11_CONSUMER'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 11 consumer inválido';

 -- 12–14. Publicación sintética por puertas reales, solo en esta transacción aislada.
 PERFORM lf_ops.nucleo_autotest_datos_v1();
 INSERT INTO lf_ops.pantallas(id,codigo,nombre) VALUES (900010,'ZZT-DPIG03-PURE','Fixture pure'),(900011,'ZZT-DPIG03-MIXED','Fixture mixed');
 INSERT INTO lf_ops.nucleo_nodos(codigo,padre,nivel,pantalla_id) VALUES ('PANTALLA-900010','ZZT-MOD-1','PANTALLA',900010),('PANTALLA-900011','ZZT-MOD-1','PANTALLA',900011);
 INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id) VALUES (900001,900011);
 base:=jsonb_build_object('codigo','ZZT-DPIG03-NATIVE','clave','zzt_dpig03_otp','titulo','Bloqueo por reenvíos de OTP',
 'descripcion','Bloquea el reenvío de OTP al alcanzar el máximo de reenvíos configurado','familia','ZZT_FAM','naturaleza','CONDUCTA',
 'autoridad','ZZT-Q','dueno','LF_GOVERNANCE','alcance','ZZT-AMB','modo','HEREDA','clase','PANTALLA','efecto','BLOQUEAR','impacto','IMPLEMENTAR','plazo_dias',10,
 'origen',jsonb_build_object('tipo','CHAT','ref','dpig03-isolated-test','solicitante','autotest'),
 'condicion',jsonb_build_object('op','>=','izq',jsonb_build_object('hecho','zzt_intentos'),'der',jsonb_build_object('param','ZZT.MAX_INTENTOS')),
 'pruebas',jsonb_build_array(
 jsonb_build_object('casuistica','EN_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS')),'esperado',true),
 jsonb_build_object('casuistica','BAJO_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',-1)),'esperado',false),
 jsonb_build_object('casuistica','SOBRE_EL_LIMITE','entrada',jsonb_build_object('zzt_intentos',jsonb_build_object('param','ZZT.MAX_INTENTOS','mas',1)),'esperado',true)));
 result:=lf_ops.nucleo_regla_proponer_v1(base);
 IF result->>'resultado' IS DISTINCT FROM 'CANDIDATA' THEN RAISE EXCEPTION 'DPIG03_TEST_12_CANDIDATE %',result; END IF;
 a:=lf_ops.nucleo_reglas_efectivas_v1(900010,'INPUT_GOVERNANCE','DIRECTAS');
 IF a->'nativas' IS DISTINCT FROM '[]'::jsonb OR a->'reglas' IS DISTINCT FROM '[]'::jsonb THEN RAISE EXCEPTION 'DPIG03_TEST_12_CANDIDATE_VISIBLE'; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 12 candidata no efectiva';
 result:=lf_ops.nucleo_regla_evaluar_v1('ZZT-DPIG03-NATIVE',false);
 SELECT jsonb_object_agg(codigo,jsonb_build_object('puntaje',1)) INTO pts FROM lf_ops.nucleo_rubrica WHERE estado='ACTIVO';
 PERFORM lf_ops.nucleo_juicio_registrar_v1(jsonb_build_object('regla','ZZT-DPIG03-NATIVE','hash_evaluado',result->>'hash_paquete','veredicto','PASS','puntajes',pts,'juez','AUTOTEST','modo','CONTEXTO_ACTUAL','revisor_es_productor',true,'llamadas_modelo',0,'evidencia_ref','DPIG03 isolated test'));
 result:=lf_ops.nucleo_regla_promover_v1('ZZT-DPIG03-NATIVE');
 IF result->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' THEN RAISE EXCEPTION 'DPIG03_TEST_13_PROMOTE %',result; END IF;
 a:=lf_ops.nucleo_reglas_efectivas_v1(900010,'INPUT_GOVERNANCE','DIRECTAS');
 IF a->>'estado' IS DISTINCT FROM 'NUCLEO_DISPONIBLE' OR a->'reglas' IS DISTINCT FROM a->'nativas'
  OR NOT (a->'nativas' @> '[{"resolucion":{"regla":"ZZT-DPIG03-NATIVE","version":1},"version":{"estado":"PUBLICADA"}}]')
 THEN RAISE EXCEPTION 'DPIG03_TEST_13_NATIVE %',a; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 13 nativa publicada';
 a:=lf_ops.nucleo_reglas_efectivas_v1(900011,'INPUT_GOVERNANCE','DIRECTAS');
 IF a->>'estado' IS DISTINCT FROM 'PARIDAD_MIXTA_PENDIENTE' OR a->'reglas' IS DISTINCT FROM 'null'::jsonb
  OR NOT (a->'respaldo' @> '[{"codigo":"ZZT-DPIG03-DIRECT"}]') OR jsonb_array_length(a->'nativas')=0
 THEN RAISE EXCEPTION 'DPIG03_TEST_14_MIXED %',a; END IF;
 RAISE NOTICE 'DPIG03_TEST_PASS 14 mixto no certificado';
END $verify$;
ROLLBACK;
DO $readback$ BEGIN
 IF EXISTS(SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo='ZZT-DPIG03-NATIVE')
    OR EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id BETWEEN 900001 AND 900003)
    OR EXISTS(SELECT 1 FROM lf_ops.pantallas WHERE id IN (900010,900011))
    OR EXISTS(SELECT 1 FROM lf_ops.nucleo_nodos WHERE codigo IN ('PANTALLA-900010','PANTALLA-900011'))
 THEN RAISE EXCEPTION 'DPIG03_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'DPIG03_ROLLBACK_PASS 14/14';
END $readback$;
