-- Tanda 3: ocho veredictos PASS de juez externo. Hash versión != hash paquete (pruebas).
-- Fuente: sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda3_v1.json
BEGIN;
DO $pilot$
DECLARE p jsonb; code text; ver int; hv text; hp text; got_tests int; jr jsonb; ev jsonb; promoted jsonb; res text;
 oldlegacy jsonb; oldcore jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldchecks jsonb; oldekb bigint;
 n int:=0; auto_count int:=0; manual_count int:=0; blocked_count int:=0; new_published int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldcore FROM lf_ops.nucleo_reglas r
  WHERE r.codigo NOT IN ('M4-C01','M4-C02','M4-C03','M4-C04','M4-C05','M4-C06','M4-C07','M4-C08');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r
  WHERE r.regla NOT IN ('M4-C01','M4-C02','M4-C03','M4-C04','M4-C05','M4-C06','M4-C07','M4-C08');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldchecks FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007';
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 RAISE NOTICE 'TANDA3_PREFLIGHT legacy_rows=% publicadas=%', (SELECT count(*) FROM lf_ops.reglas),(SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA');
 IF (SELECT count(*) FROM lf_ops.reglas)<1 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
   OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>26
   OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla IN ('M4-C01','M4-C02','M4-C03','M4-C04','M4-C05','M4-C06','M4-C07','M4-C08')
     AND modo='INDEPENDIENTE' AND veredicto='PASS')<>0
 THEN RAISE EXCEPTION 'TANDA3_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"M4-C01","version":1,"hash_version_atestado":"f4298bd204c1f0d72373e2fd39715895f355b94e765bbdfb911aac7c4d272d44","hash_paquete_atestado":"fcdccbac4a180aecb9fc76e708a3bc60971ed91325215acf285832f00e258fea","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa parcialmente con M4-C07 en analytics y replay del DNI, distinto alcance (telemetría general vs paso ONB_003)."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto lista logs, analytics, headers y mensajes de error y la condición usa un solo hecho agregado."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-C02","version":1,"hash_version_atestado":"0bbeee62763297478c2ea1ffd119d687c530a08cd5378dd88b6b45a48e5a1389","hash_paquete_atestado":"13b0aafcb74b8ea0c08d9933241a06329036c0782c3d2314ab09a9c0be698be7","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El transporte autorizado por header o cookie httpOnly figura en el texto y la condición no lo evalúa."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-C03","version":1,"hash_version_atestado":"341b1dfa1bede23e1bac0890eefac503997c6a6925248fb6917619d14029dab5","hash_paquete_atestado":"99eba3acd744025da6e8deea4407c5b03e176d3f9eb1e5a1393936b79c847594","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto permite solo resultado sin secreto y la condición solo evalúa la presencia del otp_code."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-C04","version":1,"hash_version_atestado":"c12b5def17aa97cd1265b2106d014f539a6eee535a73c059c406be8814e0cf13","hash_paquete_atestado":"89bf328afbcefee527e6a154f3dafdd477ddf5fd06e196f6dd4e9e149c8c8185","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa parcialmente con M4-C08 (no revelar existencia de cuenta por DNI), distinta superficie (validación protegida vs resolución ONB_003)."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Registrado, bloqueado y sospechoso colapsan en un hecho."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-C05","version":1,"hash_version_atestado":"6267608343aa70099eea478c1ee72620d9a60628cc089f48c89b694be21f94a2","hash_paquete_atestado":"cb5614ac2890a0fe93e3b09c7beb0d226e88615a9a944216c89bd83a4effa833","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Registrado y bloqueado colapsan en un hecho."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-C06","version":1,"hash_version_atestado":"0029e125d7c9a3c34d3a5bbc73ca4ce686cf981ddb8a3660e81ebb5c8edc4ccd","hash_paquete_atestado":"8f5e6b3f6afa58e7d121f25c566acfa3de8658cc838edd60e31c2f2e6fc0ff08","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.95,"observacion":"No distingue atribuir identidad civil de reasignar cuenta; ambos van en un solo hecho de intento."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Falta de acreditación o de recuperación autorizada se evalúa en un hecho agregado."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-C07","version":1,"hash_version_atestado":"95f9117d079d8fa4a4fd60fa6ea9f46096da608cf9eb1c09c308edf0321169e9","hash_paquete_atestado":"627b7d152fc5d24e424db2a78261111f0582bd5e9f0fc4f7adba8191dd80c68f","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa parcialmente con M4-C01 en analytics y replay."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto lista localStorage, sessionStorage, URL, analytics, replay y caché offline y la condición usa un hecho agregado."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-C08","version":1,"hash_version_atestado":"3aedc3c2fa41b7e54b444ce99ceb119ca6d0f17dc9d328b59267b921ae122f7d","hash_paquete_atestado":"6171ba0a0cd47a57dfeb520b8377e3d893221b1a8454cbf98078a2d90a26039d","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa parcialmente con M4-C04 en no revelar existencia por DNI."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Flags, códigos y mensajes colapsan en un solo hecho."},"COH_EFECTO":{"puntaje":1}}}]'::jsonb) LOOP
  code:=p->>'codigo'; ver:=(p->>'version')::integer;
  SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v
    WHERE v.regla=code AND v.version=ver AND v.estado='CANDIDATA';
  IF hv IS DISTINCT FROM p->>'hash_version_atestado' THEN
   RAISE EXCEPTION 'TANDA3_VERSION_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_version_atestado',hv;
  END IF;
  SELECT count(*) INTO got_tests FROM lf_ops.nucleo_regla_pruebas
    WHERE regla=code AND version=ver;
  IF got_tests IS DISTINCT FROM (p->>'pruebas_atestadas')::integer THEN
   RAISE EXCEPTION 'TANDA3_TEST_COUNT_MISMATCH code=% want=% got=%',code,p->>'pruebas_atestadas',got_tests;
  END IF;
  hp:=lf_ops.nucleo_hash_paquete_v1(code,ver);
  IF hp IS DISTINCT FROM p->>'hash_paquete_atestado' THEN
   RAISE EXCEPTION 'TANDA3_PACKAGE_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_paquete_atestado',hp;
  END IF;
  jr:=jsonb_build_object('regla',code,'hash_evaluado',hp,'veredicto','PASS','puntajes',p->'puntajes',
     'juez','Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude',
     'modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda3_v1.json#'||code);
  -- Negativo: hash alterado jamás puede admitirse.
  BEGIN
   PERFORM lf_ops.nucleo_juicio_registrar_v1(jr||jsonb_build_object('hash_evaluado',repeat('0',64)));
   RAISE EXCEPTION 'TANDA3_BAD_HASH_ACCEPTED %',code;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
  END;
  PERFORM lf_ops.nucleo_juicio_registrar_v1(jr);
  ev:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  res:=ev->>'decision'; promoted:=NULL;
  IF res='AUTO' THEN
   promoted:=lf_ops.nucleo_regla_promover_v1(code);
   IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
     RAISE EXCEPTION 'TANDA3_AUTO_PROMOTION_FAILED % %',code,promoted;
   END IF;
   auto_count:=auto_count+1;
  ELSIF res='MANUAL' THEN manual_count:=manual_count+1;
  ELSE blocked_count:=blocked_count+1; END IF;
  RAISE NOTICE 'TANDA3_RESULT %',jsonb_build_object('regla',code,'version',ver,
    'hash_version',hv,'hash_paquete',hp,'decision',res,'nota',ev->'nota',
    'motivos',ev->'motivos','promocion',COALESCE(promoted->>'resultado','NO_PROMOVIDA'));
  n:=n+1;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-TANDA3-8-INDEPENDIENTES-20261123-001') THEN RAISE EXCEPTION 'TANDA3_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-TANDA3-8-INDEPENDIENTES-20261123-001','NUCLEO_REGLAS','Tanda 3 ocho juicios independientes M4','Juicios externos PASS M4 con hash paquete atestado, publicar exclusivamente AUTO, mantener candidatas no AUTO sin forzar.',
  'Hechos agregados no prueban binding runtime de seguridad. La fixture lectura IG exige pantalla sin nativas.',
  'NUCLEO_TANDA3_JUICIO_INDEPENDIENTE',
  'Verificar hash version, 4 pruebas y nucleo_hash_paquete_v1, negativo hash adulterado, REG_CHK_007 y legadas intactos, 14/14 lectura IG.',
  'PG17 exacto BEGIN ROLLBACK, ocho casos y negativo por caso, 17 regresiones, 14 lectura IG, Train y readback.','MEDIUM',1,now(),now(),'TANDA3-JUICIOS-20261123','ACTIVO',
  'sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda3_v1.json; docs/nucleo/LF_TANDA3_JUICIOS_INDEPENDIENTES_8_20261123.md');
 IF n<>8 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r
   WHERE r.codigo NOT IN ('M4-C01','M4-C02','M4-C03','M4-C04','M4-C05','M4-C06','M4-C07','M4-C08')) IS DISTINCT FROM oldcore
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r
   WHERE r.regla NOT IN ('M4-C01','M4-C02','M4-C03','M4-C04','M4-C05','M4-C06','M4-C07','M4-C08')) IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007') IS DISTINCT FROM oldchecks
  OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>26+auto_count
 THEN RAISE EXCEPTION 'TANDA3_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'TANDA3_PASS 8/8 judged; auto=% manual=% blocked=%; legadas sin drift; 0 deprecaciones',auto_count,manual_count,blocked_count;
END $pilot$;
COMMIT;
