-- Tanda 5: ocho veredictos PASS de juez externo. Hash versión != hash paquete (pruebas).
-- Fuente: sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda5_v1.json
BEGIN;
DO $pilot$
DECLARE p jsonb; code text; ver int; hv text; hp text; got_tests int; jr jsonb; ev jsonb; promoted jsonb; res text;
 oldlegacy jsonb; oldcore jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldchecks jsonb; oldekb bigint;
 n int:=0; auto_count int:=0; manual_count int:=0; blocked_count int:=0; new_published int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldcore FROM lf_ops.nucleo_reglas r
  WHERE r.codigo NOT IN ('M4C-C01','M4C-C02','M4C-C03','M4C-C04','M4C-C05','M4C-C06','M4C-C07','M4C-C08');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r
  WHERE r.regla NOT IN ('M4C-C01','M4C-C02','M4C-C03','M4C-C04','M4C-C05','M4C-C06','M4C-C07','M4C-C08');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldchecks FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007';
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 RAISE NOTICE 'TANDA5_PREFLIGHT legacy_rows=% publicadas=%', (SELECT count(*) FROM lf_ops.reglas),(SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA');
 IF (SELECT count(*) FROM lf_ops.reglas)<1 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
   OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>42
   OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla IN ('M4C-C01','M4C-C02','M4C-C03','M4C-C04','M4C-C05','M4C-C06','M4C-C07','M4C-C08')
     AND modo='INDEPENDIENTE' AND veredicto='PASS')<>0
 THEN RAISE EXCEPTION 'TANDA5_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"M4C-C01","version":1,"hash_version_atestado":"10790d4161ff57cc8899db5cb7fd2a7eb445a9de875d5232a1d0302daff0e5a6","hash_paquete_atestado":"245ede30538eeb6c0444160185ef80871558e8629d48c678b3ee43e887cb5a97","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto enumera usuario activo, recurso, empresa, permiso y transición y la condición usa un solo hecho agregado de autorización incompleta."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4C-C02","version":1,"hash_version_atestado":"5327ab9e4d4c6eaaad762505aab723920aaaad1caa39dcaa4a8ed3e03e71669b","hash_paquete_atestado":"92429a620998731e8134eda6116a40e26616afe295c383b762b61570c77db948","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa parcialmente con M4C-C01 en autorización de empresa; C02 trata aislamiento entre empresas y C01 la denegación por defecto."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto aclara que company_id del navegador no basta y que no se concede por IP o grupo; la condición solo evalúa el hecho de empresa fuera de alcance."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4C-C03","version":1,"hash_version_atestado":"0bb2c1d0982be1036ceb24537e1bc57ca5b1df525e50107d5a981ff7dfaf2b67","hash_paquete_atestado":"c575f1aa5cfdfb0653252dddcfad0eabbfbae42448aa97235a65816d68c163b7","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Extensión, MIME, tamaño, checksum, plantilla y malware colapsan en un hecho agregado; los límites quedan pendientes de Paulo, correcto no fijarlos."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4C-C04","version":1,"hash_version_atestado":"fd8d1e3197af65d8c5baef1fa8622ef5c843dc911b100d29c03f9be344e06126","hash_paquete_atestado":"233cfa0babea5d392d04a5f7af3321923bc7bae402bdbf0e635d35cb45f3ead2","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Se parece a M4-C04 y M4-C05 publicadas (no enumerar), pero esta cubre Login B2B."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Existencia, estado y factor fallido colapsan en un hecho."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4C-C05","version":1,"hash_version_atestado":"c29e473567049f497b5dd89c26636ae8ccce6e864c22926d676b94bda3331bec","hash_paquete_atestado":"6a71c964679df100b438c1ea8bc6b4541655a301b3fa595d34076e61865a7b4c","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa parcialmente con M4C-C06 (secreto a telemetría) y con M4-C01 (PII en logs), distinto dato."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto permite el envío transitorio necesario para autenticar y la condición no lo evalúa."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4C-C06","version":1,"hash_version_atestado":"5fc4495a3c6fe0bc89a63a98ae19ff4ae3c3c1df03fdfe5b7164e8cdea0b64af","hash_paquete_atestado":"2ae952cbc1cc7b6a3cb72320b7192055da5ade29f37e9c7e81749406349343b9","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa con M4C-C05 en emitir el secreto a telemetría; C06 se limita al toggle."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Alterar valor, perder contenido o emitir a telemetría colapsan en un hecho."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4C-C07","version":1,"hash_version_atestado":"3461b7e5540acd07a23bea960dac9c06febc75fb00dd99fc75e200a3aa71f1ea","hash_paquete_atestado":"598966557372b9539613608895573dafa5e3cf9e9b00196297855a7d4a2aedb3","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.95,"observacion":"Pegado, autocomplete y desmontaje del input durante la divulgación progresiva van en un solo hecho de incompatibilidad."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Igual."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4C-C08","version":1,"hash_version_atestado":"93b620a291664fcc3fd3bdd1444d2a988846505a2b3a7e7b8c9ac0a6b5c3fb4c","hash_paquete_atestado":"22967b48dad84f3a0acf1bd74041decfc4b58941320c271631d0ea0b9761cc8d","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.95,"observacion":"Mezcla la regla con obligaciones residuales de UI (validación local, foco, correo lectura, aria-live)."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Autenticar una sola vez con correo y contraseña figura en el texto y la condición evalúa solo el hecho de autenticación prematura o duplicada."},"COH_EFECTO":{"puntaje":1}}}]'::jsonb) LOOP
  code:=p->>'codigo'; ver:=(p->>'version')::integer;
  SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v
    WHERE v.regla=code AND v.version=ver AND v.estado='CANDIDATA';
  IF hv IS DISTINCT FROM p->>'hash_version_atestado' THEN
   RAISE EXCEPTION 'TANDA5_VERSION_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_version_atestado',hv;
  END IF;
  SELECT count(*) INTO got_tests FROM lf_ops.nucleo_regla_pruebas
    WHERE regla=code AND version=ver;
  IF got_tests IS DISTINCT FROM (p->>'pruebas_atestadas')::integer THEN
   RAISE EXCEPTION 'TANDA5_TEST_COUNT_MISMATCH code=% want=% got=%',code,p->>'pruebas_atestadas',got_tests;
  END IF;
  hp:=lf_ops.nucleo_hash_paquete_v1(code,ver);
  IF hp IS DISTINCT FROM p->>'hash_paquete_atestado' THEN
   RAISE EXCEPTION 'TANDA5_PACKAGE_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_paquete_atestado',hp;
  END IF;
  jr:=jsonb_build_object('regla',code,'hash_evaluado',hp,'veredicto','PASS','puntajes',p->'puntajes',
     'juez','Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude',
     'modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda5_v1.json#'||code);
  -- Negativo: hash alterado jamás puede admitirse.
  BEGIN
   PERFORM lf_ops.nucleo_juicio_registrar_v1(jr||jsonb_build_object('hash_evaluado',repeat('0',64)));
   RAISE EXCEPTION 'TANDA5_BAD_HASH_ACCEPTED %',code;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
  END;
  PERFORM lf_ops.nucleo_juicio_registrar_v1(jr);
  ev:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  res:=ev->>'decision'; promoted:=NULL;
  IF res='AUTO' THEN
   promoted:=lf_ops.nucleo_regla_promover_v1(code);
   IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
     RAISE EXCEPTION 'TANDA5_AUTO_PROMOTION_FAILED % %',code,promoted;
   END IF;
   auto_count:=auto_count+1;
  ELSIF res='MANUAL' THEN manual_count:=manual_count+1;
  ELSE blocked_count:=blocked_count+1; END IF;
  RAISE NOTICE 'TANDA5_RESULT %',jsonb_build_object('regla',code,'version',ver,
    'hash_version',hv,'hash_paquete',hp,'decision',res,'nota',ev->'nota',
    'motivos',ev->'motivos','promocion',COALESCE(promoted->>'resultado','NO_PROMOVIDA'));
  n:=n+1;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-TANDA5-8-INDEPENDIENTES-20261123-001') THEN RAISE EXCEPTION 'TANDA5_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-TANDA5-8-INDEPENDIENTES-20261123-001','NUCLEO_REGLAS','Tanda 5 ocho juicios independientes M4C B2B','Ocho juicios PASS M4C con hash paquete atestado; publicar solo AUTO, preservar MANUAL o BLOQUEADA.',
  'Hechos agregados de autenticación y permisos no acreditan runtime; límites de archivos aún pendientes de Paulo.',
  'NUCLEO_TANDA5_JUICIO_INDEPENDIENTE',
  'Verificar hash versión, cuatro pruebas y hash canónico en una misma transacción; negativo hash alterado; conservar IG, REG_CHK_007, otras candidatas y legadas.',
  'PG17 exacto BEGIN ROLLBACK, ocho positivos y ocho negativos, 17 regresiones, 14 lectura IG, Train y readback.',
  'MEDIUM',1,now(),now(),'TANDA5-JUICIOS-20261123','ACTIVO','sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda5_v1.json; docs/nucleo/LF_TANDA5_JUICIOS_INDEPENDIENTES_8_20261123.md');
 IF n<>8 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r
   WHERE r.codigo NOT IN ('M4C-C01','M4C-C02','M4C-C03','M4C-C04','M4C-C05','M4C-C06','M4C-C07','M4C-C08')) IS DISTINCT FROM oldcore
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r
   WHERE r.regla NOT IN ('M4C-C01','M4C-C02','M4C-C03','M4C-C04','M4C-C05','M4C-C06','M4C-C07','M4C-C08')) IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007') IS DISTINCT FROM oldchecks
  OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>42+auto_count
 THEN RAISE EXCEPTION 'TANDA5_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'TANDA5_PASS 8/8 judged; auto=% manual=% blocked=%; legadas sin drift; 0 deprecaciones',auto_count,manual_count,blocked_count;
END $pilot$;
COMMIT;
