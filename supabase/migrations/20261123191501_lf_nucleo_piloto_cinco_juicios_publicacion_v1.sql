-- Piloto único, cinco veredictos PASS de juez externo. Hash versión != hash paquete (pruebas).
-- Fuente: sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_piloto_v1.json
BEGIN;
DO $pilot$
DECLARE p jsonb; code text; ver int; hv text; hp text; got_tests int; jr jsonb; ev jsonb; promoted jsonb; res text;
 oldlegacy jsonb; oldcore jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldchecks jsonb; oldekb bigint;
 n int:=0; auto_count int:=0; manual_count int:=0; blocked_count int:=0; new_published int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldcore FROM lf_ops.nucleo_reglas r
  WHERE r.codigo NOT IN ('M1-C03','M2-C05','M2-C06','M3-C01','M3-C02');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r
  WHERE r.regla NOT IN ('M1-C03','M2-C05','M2-C06','M3-C01','M3-C02');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldchecks FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007';
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 RAISE NOTICE 'PILOT_PREFLIGHT legacy_rows=% publicadas=%', (SELECT count(*) FROM lf_ops.reglas),(SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA');
 IF (SELECT count(*) FROM lf_ops.reglas)<1 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
   OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>2
   OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla IN ('M1-C03','M2-C05','M2-C06','M3-C01','M3-C02')
     AND modo='INDEPENDIENTE' AND veredicto='PASS')<>0
 THEN RAISE EXCEPTION 'PILOT_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"M1-C03","version":2,"hash_suministrado":"abcd1de4e4d9d98a7e977832d742665432465ef37b1badc8a911a3af50cfc28d","hash_version_observado":"abcd1de4e4d9d98a7e977832d742665432465ef37b1badc8a911a3af50cfc28d","hash_paquete_ultima_evaluacion":"88037d12c84e63878831844bf176ed595db947ab4215b20af316abd54ca0f141","veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — según Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.9,"observacion":"Descripción larga que mezcla la regla con pendientes de Paulo."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Cercana a REG_CHK_005 pero distinta (emisión de recibo vs pantalla de éxito)."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.85,"observacion":"La descripción añade el registro de incidencia, pendiente de Paulo, que la condición no aplica."},"COH_EFECTO":{"puntaje":1}},"hash_version_atestado":"abcd1de4e4d9d98a7e977832d742665432465ef37b1badc8a911a3af50cfc28d","hash_paquete_atestado":"88037d12c84e63878831844bf176ed595db947ab4215b20af316abd54ca0f141","pruebas_atestadas":7,"procedencia":"Claude atesta revisión separada de GPT productor, Claude Sonnet 5.5 Anthropic, 1 llamada; source hash version y paquete arriba."},{"codigo":"M2-C05","version":1,"hash_suministrado":"9dbb758a6d6076b3f45b87e72e2c0d1e31bbb76e8e18f131a495781b32c121cd","hash_version_observado":"9dbb758a6d6076b3f45b87e72e2c0d1e31bbb76e8e18f131a495781b32c121cd","hash_paquete_ultima_evaluacion":"831eb9cc95a03ea8a6910e3f910b011317cd038c1b4d53b46fc85c34bae475a3","veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — según Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Relacionada con M2-C02 y REG_CHK_007 pero de alcance distinto."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.85,"observacion":"Que no bloqueen las ofertas no seleccionadas depende de la definición del hecho m2_oferta_seleccionada_sin_modalidad y las 3 pruebas no cubren una oferta no seleccionada sin modalidad."},"COH_EFECTO":{"puntaje":1}},"hash_version_atestado":"9dbb758a6d6076b3f45b87e72e2c0d1e31bbb76e8e18f131a495781b32c121cd","hash_paquete_atestado":"831eb9cc95a03ea8a6910e3f910b011317cd038c1b4d53b46fc85c34bae475a3","pruebas_atestadas":3,"procedencia":"Claude atesta revisión separada de GPT productor, Claude Sonnet 5.5 Anthropic, 1 llamada; source hash version y paquete arriba."},{"codigo":"M2-C06","version":1,"hash_suministrado":"55705ea6f841c64cdccca0018e678e34ea8e6387dea4f887f541a90894ba7256","hash_version_observado":"55705ea6f841c64cdccca0018e678e34ea8e6387dea4f887f541a90894ba7256","hash_paquete_ultima_evaluacion":"35f1c4da34ff1c7a13ae3cf5ee8d429b854910ceaa496c491ac004c74f0af714","veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — según Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.9,"observacion":"El texto nombra PASO3_CUOTAS_DESGLOSE_V2 pero la condición solo usa el hecho de intento, sin verificar la pantalla."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}},"hash_version_atestado":"55705ea6f841c64cdccca0018e678e34ea8e6387dea4f887f541a90894ba7256","hash_paquete_atestado":"35f1c4da34ff1c7a13ae3cf5ee8d429b854910ceaa496c491ac004c74f0af714","pruebas_atestadas":3,"procedencia":"Claude atesta revisión separada de GPT productor, Claude Sonnet 5.5 Anthropic, 1 llamada; source hash version y paquete arriba."},{"codigo":"M3-C01","version":1,"hash_suministrado":"664a8302b33256e3597c535609c51e39ca4b6c876ebc545d12639401eb73aa69","hash_version_observado":"664a8302b33256e3597c535609c51e39ca4b6c876ebc545d12639401eb73aa69","hash_paquete_ultima_evaluacion":"13bfde2b3e30b853dd3a31fe290ba69a4e2acd38112148a88ab743af01386071","veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — según Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.9,"observacion":"''checkout, confirmación o documento'' es amplio y se resuelve solo por el hecho de intento, con binding pendiente de Paulo."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}},"hash_version_atestado":"664a8302b33256e3597c535609c51e39ca4b6c876ebc545d12639401eb73aa69","hash_paquete_atestado":"13bfde2b3e30b853dd3a31fe290ba69a4e2acd38112148a88ab743af01386071","pruebas_atestadas":3,"procedencia":"Claude atesta revisión separada de GPT productor, Claude Sonnet 5.5 Anthropic, 1 llamada; source hash version y paquete arriba."},{"codigo":"M3-C02","version":1,"hash_suministrado":"262b5c0b559015c3a9013fb304a9648becbdb879dbb87181e50682a8475878e5","hash_version_observado":"262b5c0b559015c3a9013fb304a9648becbdb879dbb87181e50682a8475878e5","hash_paquete_ultima_evaluacion":"17d78c7a41191d75d627292fa15f825682112c570223e434e620c95c33942e21","veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — según Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto expresa el pago no confirmado de dos formas y la condición lo unifica."},"COH_EFECTO":{"puntaje":1}},"hash_version_atestado":"262b5c0b559015c3a9013fb304a9648becbdb879dbb87181e50682a8475878e5","hash_paquete_atestado":"17d78c7a41191d75d627292fa15f825682112c570223e434e620c95c33942e21","pruebas_atestadas":6,"procedencia":"Claude atesta revisión separada de GPT productor, Claude Sonnet 5.5 Anthropic, 1 llamada; source hash version y paquete arriba."}]'::jsonb) LOOP
  code:=p->>'codigo'; ver:=(p->>'version')::integer;
  SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v
    WHERE v.regla=code AND v.version=ver AND v.estado='CANDIDATA';
  IF hv IS DISTINCT FROM p->>'hash_version_atestado' THEN
   RAISE EXCEPTION 'PILOT_VERSION_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_version_atestado',hv;
  END IF;
  SELECT count(*) INTO got_tests FROM lf_ops.nucleo_regla_pruebas
    WHERE regla=code AND version=ver;
  IF got_tests IS DISTINCT FROM (p->>'pruebas_atestadas')::integer THEN
   RAISE EXCEPTION 'PILOT_TEST_COUNT_MISMATCH code=% want=% got=%',code,p->>'pruebas_atestadas',got_tests;
  END IF;
  hp:=lf_ops.nucleo_hash_paquete_v1(code,ver);
  IF hp IS DISTINCT FROM p->>'hash_paquete_atestado' THEN
   RAISE EXCEPTION 'PILOT_PACKAGE_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_paquete_atestado',hp;
  END IF;
  jr:=jsonb_build_object('regla',code,'hash_evaluado',hp,'veredicto','PASS','puntajes',p->'puntajes',
     'juez','Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude',
     'modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_piloto_v1.json#'||code);
  -- Negativo: hash alterado jamás puede admitirse.
  BEGIN
   PERFORM lf_ops.nucleo_juicio_registrar_v1(jr||jsonb_build_object('hash_evaluado',repeat('0',64)));
   RAISE EXCEPTION 'PILOT_BAD_HASH_ACCEPTED %',code;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
  END;
  PERFORM lf_ops.nucleo_juicio_registrar_v1(jr);
  ev:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  res:=ev->>'decision'; promoted:=NULL;
  IF res='AUTO' THEN
   promoted:=lf_ops.nucleo_regla_promover_v1(code);
   IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
     RAISE EXCEPTION 'PILOT_AUTO_PROMOTION_FAILED % %',code,promoted;
   END IF;
   auto_count:=auto_count+1;
  ELSIF res='MANUAL' THEN manual_count:=manual_count+1;
  ELSE blocked_count:=blocked_count+1; END IF;
  RAISE NOTICE 'PILOT_RESULT %',jsonb_build_object('regla',code,'version',ver,
    'hash_version',hv,'hash_paquete',hp,'decision',res,'nota',ev->'nota',
    'motivos',ev->'motivos','promocion',COALESCE(promoted->>'resultado','NO_PROMOVIDA'));
  n:=n+1;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-PILOTO-5-HASH-VERSION-VS-PAQUETE-20261123-001') THEN
  RAISE EXCEPTION 'PILOT_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
     primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-PILOTO-5-HASH-VERSION-VS-PAQUETE-20261123-001','NUCLEO_REGLAS',
   'Juicio externo: identidad del hash de version y hash de paquete',
   'El hash de version no incluye pruebas. Para juicio, calcular nucleo_hash_paquete_v1 en la misma transaccion y comparar contra hash de paquete atestado por el revisor externo.',
   'Se entrego inicialmente version.hash en lugar del hash de paquete.',
   'PILOT_HASH_VERSION_VS_PACKAGE',
   'Preflight version.hash, count de pruebas y nucleo_hash_paquete_v1 exactos. Si difiere abortar, no sustituir ni forzar. Registrar solo veredicto atestado.',
   'Cinco juicios independientes, negativo de hash mutado, ruta registrar/evaluar/promover solo AUTO, PG17 rollback y readback.',
   'MEDIUM',1,now(),now(),'PILOTO-JUICIOS-20261123','ACTIVO',
   'sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_piloto_v1.json; docs/nucleo/LF_PILOTO_JUICIOS_5_HASH_PREFLIGHT_BLOQUEADO_20261123.md');
 IF n<>5 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r
   WHERE r.codigo NOT IN ('M1-C03','M2-C05','M2-C06','M3-C01','M3-C02')) IS DISTINCT FROM oldcore
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r
   WHERE r.regla NOT IN ('M1-C03','M2-C05','M2-C06','M3-C01','M3-C02')) IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007') IS DISTINCT FROM oldchecks
  OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>2+auto_count
 THEN RAISE EXCEPTION 'PILOT_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'PILOT_PASS 5/5 judged; auto=% manual=% blocked=%; legadas sin drift; 0 deprecaciones',auto_count,manual_count,blocked_count;
END $pilot$;
COMMIT;
