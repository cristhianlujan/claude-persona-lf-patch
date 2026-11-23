-- LF M1 C03 V2: guarded receipt emission, candidate only, PG17 ROLLBACK-tested.
BEGIN;
DO $m1c03$
DECLARE v1 lf_ops.nucleo_regla_versiones%ROWTYPE; p jsonb; dry jsonb; got jsonb; ev jsonb; c jsonb; prev jsonb; h2 text;
 legacy jsonb; rules jsonb; others jsonb; apps jsonb; deprec jsonb; oldtests jsonb; oldjudges jsonb; i integer;
BEGIN
 SELECT * INTO STRICT v1 FROM lf_ops.nucleo_regla_versiones WHERE regla='M1-C03' AND version=1 AND estado='CANDIDATA';
 IF v1.hash<>'dcc801935528905869de21d85a99ef1cb306f1dac5c011a90b3387bb49eb85fa'
    OR v1.origen->>'ref'<>'lf_ops.reglas/13126'
    OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo='M1-C03')<>'CANDIDATA'
 THEN RAISE EXCEPTION 'M1_C03_BASE_DRIFT'; END IF;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) INTO legacy FROM lf_ops.reglas x;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY x.codigo) INTO rules FROM lf_ops.nucleo_reglas x;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY x.regla,x.version) INTO others FROM lf_ops.nucleo_regla_versiones x WHERE x.regla<>'M1-C03';
 SELECT jsonb_agg(to_jsonb(x) ORDER BY x.regla,x.nodo) INTO apps FROM lf_ops.nucleo_aplicaciones x;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY x.regla,x.version) INTO deprec FROM lf_ops.nucleo_deprecaciones x;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY x.n) INTO oldtests FROM lf_ops.nucleo_regla_pruebas x WHERE x.regla='M1-C03' AND x.version=1;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) INTO oldjudges FROM lf_ops.nucleo_juicios x WHERE x.regla='M1-C03' AND x.version=1;
 IF EXISTS (SELECT 1 FROM lf_ops.nucleo_hechos WHERE codigo='m1_intento_emision_recibo')
 THEN RAISE EXCEPTION 'M1_C03_FACT_ALREADY_EXISTS'; END IF;
 INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion)
 VALUES ('m1_intento_emision_recibo','boolean','ninguna','Hecho lógico de intento de emitir recibo; sin tabla_ref/columna_ref, binding Paulo PENDIENTE.');
 INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES
 ('PAYMENTS_CHECKOUT','m1_intento_emision_recibo','CURADO');
 p:=v1.ficha || $patch${"titulo":"Bloquear emisión de recibo inválido sin bloquear otro backend","descripcion":"SOLO si se intenta emitir un recibo: BLOQUEAR la emisión cuando falte PAYMENT_CONFIRMED confirmado por evidencia autoritativa, o cuando falte el correo real registrado y validado del cliente. Ante cualquier rechazo de emisión se debe registrar incidencia trazable; el mecanismo real de persistencia de esa incidencia queda PENDIENTE de fuente y binding de Paulo, y esta regla lógica no prueba que la incidencia haya sido registrada. Si no hay intento de emisión, no bloquear otras operaciones de BACKEND aunque el pago esté pendiente o el correo falte. customer_email no es niubiz_technical_email; no enviar al identificador técnico Niubiz ni a correo genérico o de rebotes. PAGOS/NIUBIZ_EMAIL_TEMPLATE y PAGOS/NIUBIZ_EMAIL_DOMAIN son referencias de configuración, no fuentes de correo real. No inferir confirmación de un rebote técnico.","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m1_intento_emision_recibo"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"!=","izq":{"hecho":"estado_pago_normalizado"},"der":{"lit":"PAYMENT_CONFIRMED"}},"der":{"op":"=","izq":{"hecho":"evidencia_autoritativa_pago"},"der":{"lit":false}}},"der":{"op":"=","izq":{"hecho":"m1_destinatario_recibo_real_validado"},"der":{"lit":false}}}},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m1_intento_emision_recibo":true,"estado_pago_normalizado":"PAYMENT_PENDING_CONFIRMATION","evidencia_autoritativa_pago":true,"m1_destinatario_recibo_real_validado":true},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m1_intento_emision_recibo":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","evidencia_autoritativa_pago":false,"m1_destinatario_recibo_real_validado":true},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m1_intento_emision_recibo":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","evidencia_autoritativa_pago":true,"m1_destinatario_recibo_real_validado":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m1_intento_emision_recibo":true,"estado_pago_normalizado":"PAYMENT_PENDING_CONFIRMATION","evidencia_autoritativa_pago":false,"m1_destinatario_recibo_real_validado":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m1_intento_emision_recibo":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","evidencia_autoritativa_pago":true,"m1_destinatario_recibo_real_validado":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m1_intento_emision_recibo":false,"estado_pago_normalizado":"PAYMENT_PENDING_CONFIRMATION","evidencia_autoritativa_pago":false,"m1_destinatario_recibo_real_validado":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m1_intento_emision_recibo":false,"estado_pago_normalizado":"PAYMENT_CONFIRMED","evidencia_autoritativa_pago":true,"m1_destinatario_recibo_real_validado":false},"esperado":false}]}$patch$::jsonb ||
 jsonb_build_object('tipo','REVISION','version_anterior',1,'hash_anterior',v1.hash,
 'motivo_revision','Acotar bloqueos a intento de emisión; no afectar backend ajeno. Incidencia pendiente de binding Paulo.');
 IF p->'origen' IS DISTINCT FROM v1.origen OR p->>'autoridad' IS DISTINCT FROM v1.autoridad
 OR p->>'codigo'<>'M1-C03' OR p->>'alcance'<>'BACKEND' THEN
 RAISE EXCEPTION 'M1_C03_AUTHORITY_DRIFT'; END IF;
 dry:=lf_ops.nucleo_regla_proponer_v1(p,false);
 IF dry->>'resultado'<>'EVALUADA_SIN_ESCRIBIR' OR (dry->>'bloqueantes')::int<>0
 THEN RAISE EXCEPTION 'M1_C03_PREFLIGHT_REJECTED %',dry; END IF;
 FOR i IN 0..6 LOOP
  SELECT value INTO c FROM jsonb_array_elements(p->'pruebas') WITH ORDINALITY x(value,ord) WHERE ord=i+1;
  IF lf_ops.nucleo_eval_v1(p->'condicion',c->'entrada') IS DISTINCT FROM (c->>'esperado')::boolean
  THEN RAISE EXCEPTION 'M1_C03_CASE_FAIL %',i; END IF;
 END LOOP;
 SELECT value INTO c FROM jsonb_array_elements(p->'pruebas') WITH ORDINALITY x(value,ord) WHERE ord=6;
 IF lf_ops.nucleo_eval_v1(p->'condicion'->'der',c->'entrada') IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'M1_C03_GUARD_MUTANT_SURVIVED'; END IF;
 RAISE NOTICE 'M1_C03_TESTS_PASS 7/7 and negative no-guard mutant detected';
 got:=lf_ops.nucleo_regla_proponer_v1(p,true);
 IF got->>'resultado'<>'CANDIDATA' OR got->>'version'<>'2'
 THEN RAISE EXCEPTION 'M1_C03_DOOR_REJECTED %',got; END IF;
 SELECT jsonb_agg(jsonb_build_object('casuistica',casuistica,'entrada',entrada,'esperado',esperado) ORDER BY n)
 INTO prev FROM lf_ops.nucleo_regla_pruebas WHERE regla='M1-C03' AND version=2;
 IF prev IS DISTINCT FROM p->'pruebas'
 OR (SELECT estado FROM lf_ops.nucleo_regla_versiones WHERE regla='M1-C03' AND version=1)<>'DESCARTADA'
 OR (SELECT estado FROM lf_ops.nucleo_regla_versiones WHERE regla='M1-C03' AND version=2)<>'CANDIDATA'
 OR (SELECT publicada_desde FROM lf_ops.nucleo_regla_versiones WHERE regla='M1-C03' AND version=2) IS NOT NULL
 OR (SELECT exigible_desde FROM lf_ops.nucleo_regla_versiones WHERE regla='M1-C03' AND version=2) IS NOT NULL
 OR (SELECT to_jsonb(x)-'estado' FROM lf_ops.nucleo_regla_versiones x WHERE x.regla='M1-C03' AND x.version=1)
    IS DISTINCT FROM to_jsonb(v1)-'estado'
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.n) FROM lf_ops.nucleo_regla_pruebas x WHERE x.regla='M1-C03' AND x.version=1) IS DISTINCT FROM oldtests
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM lf_ops.nucleo_juicios x WHERE x.regla='M1-C03' AND x.version=1) IS DISTINCT FROM oldjudges
 THEN RAISE EXCEPTION 'M1_C03_REVISION_HISTORY_DRIFT'; END IF;
 h2:=lf_ops.nucleo_hash_paquete_v1('M1-C03',2);
 IF h2 IS NULL OR h2=lf_ops.nucleo_hash_paquete_v1('M1-C03',1)
 THEN RAISE EXCEPTION 'M1_C03_HASH_INVALID'; END IF;
 ev:=lf_ops.nucleo_regla_evaluar_v1('M1-C03',true);
 IF ev->>'decision' NOT IN('BLOQUEADA','DEVUELTA') OR EXISTS(SELECT 1 FROM lf_ops.nucleo_juicios WHERE regla='M1-C03' AND version=2)
 THEN RAISE EXCEPTION 'M1_C03_UNAUTHORIZED_PROMOTION %',ev; END IF;
 dry:=lf_ops.nucleo_regla_proponer_v1(p,false);
 IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(dry->'controles') x
 WHERE x->>'n'='0' AND x->>'detalle'='REVISION_VERSION_OBSOLETA' AND x->>'ok'='false')
 THEN RAISE EXCEPTION 'M1_C03_STALE_REPLAY_ACCEPTED %',dry; END IF;
 RAISE NOTICE 'M1_C03_STALE_REPLAY_REJECTED';
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-M1-C03-BACKEND-GUARD-20261123-001')
 THEN RAISE EXCEPTION 'M1_C03_EKB_ALREADY_EXISTS'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES ('LF-NUCLEO-M1-C03-BACKEND-GUARD-20261123-001','NUCLEO_REGLAS',
 'Regla de recibo bloquea backend sin intento de emisión',
 'V1 M1-C03 aplicaba bloqueo sobre estado de pago/correo incluso sin emitir recibo.',
 'Guard de evento omitido para regla BACKEND','RECIBO_EMISION_GUARD_AUSENTE',
 'Exigir hecho booleano de intento y probar no-emisión con backend inválido; no inferir persistencia de incidencia sin binding.',
 'V2 por REVISION canónica; siete casos sintéticos y mutante sin guard; PG17/rollback.',
 'HIGH',1,now(),now(),'M1-C03-V2-20261123','ACTIVO','docs/nucleo/LF_M1_C03_REVISION_V2_20261123.md; sandbox/lf_contract_gate_test/nucleo_ci/m1_c03_revision_v2.json');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-M1-C03-BACKEND-GUARD-20261123-001')<>1
 THEN RAISE EXCEPTION 'M1_C03_EKB_WRITE_FAIL'; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM lf_ops.reglas x) IS DISTINCT FROM legacy
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.codigo) FROM lf_ops.nucleo_reglas x) IS DISTINCT FROM rules
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.regla,x.version) FROM lf_ops.nucleo_regla_versiones x WHERE x.regla<>'M1-C03') IS DISTINCT FROM others
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.regla,x.nodo) FROM lf_ops.nucleo_aplicaciones x) IS DISTINCT FROM apps
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.regla,x.version) FROM lf_ops.nucleo_deprecaciones x) IS DISTINCT FROM deprec
 OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo='REG_CHK_007')<>'CANDIDATA'
 THEN RAISE EXCEPTION 'M1_C03_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'M1_C03_V2_PASS version=2 CANDIDATA, legacy untouched, no publication; hash=%; evaluation=%',h2,ev->>'decision';
END $m1c03$;
COMMIT;
