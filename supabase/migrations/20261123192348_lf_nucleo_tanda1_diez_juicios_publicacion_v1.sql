-- Tanda 1: diez veredictos PASS de juez externo. Hash versión != hash paquete (pruebas).
-- Fuente: sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda1_v1.json
BEGIN;
DO $pilot$
DECLARE p jsonb; code text; ver int; hv text; hp text; got_tests int; jr jsonb; ev jsonb; promoted jsonb; res text;
 oldlegacy jsonb; oldcore jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldchecks jsonb; oldekb bigint;
 n int:=0; auto_count int:=0; manual_count int:=0; blocked_count int:=0; new_published int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldcore FROM lf_ops.nucleo_reglas r
  WHERE r.codigo NOT IN ('M1-C01','M1-C02','M1-C04','M1-C05','M1-C06','M2-C01','M2-C02','M2-C03','M2-C04','M3-C03');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r
  WHERE r.regla NOT IN ('M1-C01','M1-C02','M1-C04','M1-C05','M1-C06','M2-C01','M2-C02','M2-C03','M2-C04','M3-C03');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldchecks FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007';
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 RAISE NOTICE 'TANDA1_PREFLIGHT legacy_rows=% publicadas=%', (SELECT count(*) FROM lf_ops.reglas),(SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA');
 IF (SELECT count(*) FROM lf_ops.reglas)<1 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
   OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>7
   OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla IN ('M1-C01','M1-C02','M1-C04','M1-C05','M1-C06','M2-C01','M2-C02','M2-C03','M2-C04','M3-C03')
     AND modo='INDEPENDIENTE' AND veredicto='PASS')<>0
 THEN RAISE EXCEPTION 'TANDA1_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"M1-C01","version":2,"hash_version_atestado":"d4dfeb37f3e7b3e90b3e8de76317c61fdb32e23b878918a8a45b01d1ae7ea435","hash_paquete_atestado":"0c1886f3b8a014178adad84a80e834800a5c9c934e93f189b957fdc7840832e8","pruebas_atestadas":5,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.9,"observacion":"El texto habla de bloquear la aceptación y la condición se activa por la presentación del resumen, sin evaluar un intento de aceptar."},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Relacionada con REG_CHK_002 (suma consolidada) pero cubre unicidad y detalle por oferta."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"Aceptación vs presentación, igual que el alcance."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M1-C02","version":2,"hash_version_atestado":"6f47b5ecbfc49774c91fd5e4570470954058c0fcd1b7f1340eb2cb32870086a5","hash_paquete_atestado":"d9fd5881bf48ec368880db1cfc09b61081f38cc167392671ccbed735483758c7","pruebas_atestadas":6,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.9,"observacion":"Mezcla la regla con pendientes (Yape cuotas, aviso residual de UI)."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Las aclaraciones ''cancelar no liquida deuda ni genera carta'' no las evalúa la condición."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M1-C04","version":2,"hash_version_atestado":"4234e6d8c57c87e6491785ab7000d7073a29b1c450d3c83050f73014242ae0bd","hash_paquete_atestado":"52a9727b08794e47e85cfe041c34dc934b50559b2f11aac8429e2271e724d088","pruebas_atestadas":6,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.95,"observacion":"Las aclaraciones sobre hechos lógicos alargan la descripción."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M1-C05","version":2,"hash_version_atestado":"9a0e158d956caac1b78d62bd4649321516e87f629eebeb10e0833ed9788de45e","hash_paquete_atestado":"15b8da29a0a3cc5a979919e599eaf8d507a954ff9c1ad845a44bee01818580eb","pruebas_atestadas":6,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.9,"observacion":"El texto nombra PANTALLA-1 y PANTALLA-2 pero la condición solo usa el hecho de captura inicial."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"El banner literal está en la descripción y la condición verifica un hecho con ese nombre."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M1-C06","version":2,"hash_version_atestado":"713190113d535dc20ab557cd631ad56a79dc37047405ee543845183cf95560b2","hash_paquete_atestado":"37858858c39254ae6af08742bad0b4dc8b82794303d080ff6f56defdde24aed2","pruebas_atestadas":8,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Relacionada con REG_TEC_009 (idempotencia de checkout) pero esta cubre onboarding."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"UUID v4 y X-Idempotency-Key se exigen en el texto pero la condición no los evalúa (binding pendiente)."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2-C01","version":1,"hash_version_atestado":"e4fb10c4ace5e82266e3ee9fdd2569b90fd7b8733912ce70d2f5896faf13a040","hash_paquete_atestado":"eeac9622455d17c0b1499a16fa4a2640490370c05acaee76f1b0d3b81484101f","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2-C02","version":1,"hash_version_atestado":"db9e5d87f1766b5a95df5d2b876f236a0bf3c5f4805635555316f48fe9dfa8d2","hash_paquete_atestado":"c4f782baef9d61739b7076345c830b0cd6741d8e708dc20c378110975231fb04","pruebas_atestadas":5,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Se solapa parcialmente con M2-C05 en continuar sin modalidad elegida, en pantalla distinta."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2-C03","version":1,"hash_version_atestado":"70cf59dc1bb5e402d47182e82090db240d0701daa8981d4ced15942fb123581a","hash_paquete_atestado":"73dfef90e4b73a742c382dc028cb195f57dbc9e4a9d07cd4cb253e4b4a7dd9b0","pruebas_atestadas":5,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"El texto añade que las alternativas no se duplican por modalidad y la condición no lo evalúa."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2-C04","version":1,"hash_version_atestado":"f303f56646e5060dd09c580e366a272e532285ec1b96d3edb5ea4dbae5bcc8e9","hash_paquete_atestado":"9a0025615d215d98cfdf5a2bbb87107b50cf704fe9cf0dfd1c56625c1ede023b","pruebas_atestadas":3,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"La procedencia ''autorizadas por backend'' vive en la definición del hecho, no en la condición."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M3-C03","version":1,"hash_version_atestado":"5cb60945198456663556ba5e08826aa21b89a220a3ccddf67f61ed32f5bc53cc","hash_paquete_atestado":"8897bb7c54db499f10b799571430a16287b3f9d8e90a0d0e31169770aa5aad6d","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic), atribución y revisión atestadas por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.9,"observacion":"El texto nombra HOME_001 o comunicación de oferta y la condición usa solo el hecho de intento."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"La nota sobre reconciliación de copy pendiente no la evalúa la condición."},"COH_EFECTO":{"puntaje":1}}}]'::jsonb) LOOP
  code:=p->>'codigo'; ver:=(p->>'version')::integer;
  SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v
    WHERE v.regla=code AND v.version=ver AND v.estado='CANDIDATA';
  IF hv IS DISTINCT FROM p->>'hash_version_atestado' THEN
   RAISE EXCEPTION 'TANDA1_VERSION_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_version_atestado',hv;
  END IF;
  SELECT count(*) INTO got_tests FROM lf_ops.nucleo_regla_pruebas
    WHERE regla=code AND version=ver;
  IF got_tests IS DISTINCT FROM (p->>'pruebas_atestadas')::integer THEN
   RAISE EXCEPTION 'TANDA1_TEST_COUNT_MISMATCH code=% want=% got=%',code,p->>'pruebas_atestadas',got_tests;
  END IF;
  hp:=lf_ops.nucleo_hash_paquete_v1(code,ver);
  IF hp IS DISTINCT FROM p->>'hash_paquete_atestado' THEN
   RAISE EXCEPTION 'TANDA1_PACKAGE_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_paquete_atestado',hp;
  END IF;
  jr:=jsonb_build_object('regla',code,'hash_evaluado',hp,'veredicto','PASS','puntajes',p->'puntajes',
     'juez','Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude',
     'modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda1_v1.json#'||code);
  -- Negativo: hash alterado jamás puede admitirse.
  BEGIN
   PERFORM lf_ops.nucleo_juicio_registrar_v1(jr||jsonb_build_object('hash_evaluado',repeat('0',64)));
   RAISE EXCEPTION 'TANDA1_BAD_HASH_ACCEPTED %',code;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
  END;
  PERFORM lf_ops.nucleo_juicio_registrar_v1(jr);
  ev:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  res:=ev->>'decision'; promoted:=NULL;
  IF res='AUTO' THEN
   promoted:=lf_ops.nucleo_regla_promover_v1(code);
   IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
     RAISE EXCEPTION 'TANDA1_AUTO_PROMOTION_FAILED % %',code,promoted;
   END IF;
   auto_count:=auto_count+1;
  ELSIF res='MANUAL' THEN manual_count:=manual_count+1;
  ELSE blocked_count:=blocked_count+1; END IF;
  RAISE NOTICE 'TANDA1_RESULT %',jsonb_build_object('regla',code,'version',ver,
    'hash_version',hv,'hash_paquete',hp,'decision',res,'nota',ev->'nota',
    'motivos',ev->'motivos','promocion',COALESCE(promoted->>'resultado','NO_PROMOVIDA'));
  n:=n+1;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-TANDA1-10-JUICIOS-INDEPENDIENTES-20261123-001') THEN
  RAISE EXCEPTION 'TANDA1_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
     primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-TANDA1-10-JUICIOS-INDEPENDIENTES-20261123-001','NUCLEO_REGLAS',
   'Escalamiento de juicio independiente por tandas sin forzar publicacion',
   'Diez juicios externos PASS vinculados a hash de paquete, siete criterios y notas independientes; publicar solo AUTO y conservar MANUAL o BLOQUEADA en candidata.',
   'El puntaje de juicio no sustituye el contrato de evaluacion, profundidad y dependencias.',
   'NUCLEO_TANDA1_INDEPENDENT_JUDGE',
   'Antes del juicio, comparar version.hash, numero de pruebas y nucleo_hash_paquete_v1 con atestacion; negativo de hash; solo promover AUTO; verificar legadas y otras candidatas intactas.',
   'PG17 exacto, mutante hash, BEGIN ROLLBACK, 17 regresiones, Merge Train y readback Supabase.',
   'MEDIUM',1,now(),now(),'TANDA1-JUICIOS-20261123','ACTIVO',
   'sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda1_v1.json; docs/nucleo/LF_TANDA1_JUICIOS_INDEPENDIENTES_10_20261123.md');
 IF n<>10 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r
   WHERE r.codigo NOT IN ('M1-C01','M1-C02','M1-C04','M1-C05','M1-C06','M2-C01','M2-C02','M2-C03','M2-C04','M3-C03')) IS DISTINCT FROM oldcore
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r
   WHERE r.regla NOT IN ('M1-C01','M1-C02','M1-C04','M1-C05','M1-C06','M2-C01','M2-C02','M2-C03','M2-C04','M3-C03')) IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007') IS DISTINCT FROM oldchecks
  OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>7+auto_count
 THEN RAISE EXCEPTION 'TANDA1_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'TANDA1_PASS 10/10 judged; auto=% manual=% blocked=%; legadas sin drift; 0 deprecaciones',auto_count,manual_count,blocked_count;
END $pilot$;
COMMIT;
