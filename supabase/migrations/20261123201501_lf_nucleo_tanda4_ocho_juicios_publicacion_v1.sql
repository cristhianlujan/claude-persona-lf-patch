-- Tanda 4: ocho veredictos PASS de juez externo. Hash versión != hash paquete (pruebas).
-- Fuente: sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda4_v1.json
BEGIN;
DO $pilot$
DECLARE p jsonb; code text; ver int; hv text; hp text; got_tests int; jr jsonb; ev jsonb; promoted jsonb; res text;
 oldlegacy jsonb; oldcore jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldchecks jsonb; oldekb bigint;
 n int:=0; auto_count int:=0; manual_count int:=0; blocked_count int:=0; new_published int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldcore FROM lf_ops.nucleo_reglas r
  WHERE r.codigo NOT IN ('M4-B01','M4-B02','M4-B03','M4-B04','M4-B05','M4-B06','M4-B07','M4-B08');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r
  WHERE r.regla NOT IN ('M4-B01','M4-B02','M4-B03','M4-B04','M4-B05','M4-B06','M4-B07','M4-B08');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldchecks FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007';
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 RAISE NOTICE 'TANDA4_PREFLIGHT legacy_rows=% publicadas=%', (SELECT count(*) FROM lf_ops.reglas),(SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA');
 IF (SELECT count(*) FROM lf_ops.reglas)<1 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
   OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>34
   OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla IN ('M4-B01','M4-B02','M4-B03','M4-B04','M4-B05','M4-B06','M4-B07','M4-B08')
     AND modo='INDEPENDIENTE' AND veredicto='PASS')<>0
 THEN RAISE EXCEPTION 'TANDA4_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"M4-B01","version":1,"hash_version_atestado":"e10eb5988e1c2da9b8d4f76cf5934a79077517e1ab1f773ace053c16cc825f8a","hash_paquete_atestado":"d1708f425fb4d78d84f4054bb5e4c5f025a9e4423433fc721860fbad964aa6c6","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto exige que la sesión quede ABANDONED y la condición solo evalúa el hecho de sesión vencida."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-B02","version":1,"hash_version_atestado":"9c17ba09a0e06a0b965b0475228885d7ebbbfba057d8691e0f9e2e03d1f19ef5","hash_paquete_atestado":"4419f2f4526c02cfe7d0b0fa4d5537c0d09bde8e86b6118812a80e86281bbd55","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Se acerca a M4-B01 (sesión expirada), pero B02 trata la precarga de datos y B01 la reanudación del OTP."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Exigir inicio desde Paso 1 figura en el texto y la condición no lo evalúa."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-B03","version":1,"hash_version_atestado":"7dc4c8c3af97f840594053fd93fc2ad0c1238c6ba8d6301cc0d7bbbd6aae228e","hash_paquete_atestado":"daa3023fa3aec253ea89b0857f7a042192980add1952ef3c0a9b7edc009865fb","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-B04","version":1,"hash_version_atestado":"b9deb6d43f4f98c3f5088892394f12ca951fe680a04a002b92e97a670dfd255b","hash_paquete_atestado":"b6cb9b5640847664c00fedf3771a82a8323416ed6363b4532dd0d2af5bba5516","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.95,"observacion":"Dos cooldowns (ordinario y de agotamiento) en una sola frase."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa con M4-B05 (timer ordinario en UI) y M4-B06 (cooldown tras agotar reenvíos); B04 es el bloqueo de backend."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Ambos cooldowns colapsan en un hecho agregado."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-B05","version":1,"hash_version_atestado":"5331b1910cb72d713251d5f844d52b8753d941ceed37fa0a8e61f6310e14b121","hash_paquete_atestado":"95f2db493088dafe83cd6658e95bb780096c46bba918d265fb6398bca1b698ac","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa con el cooldown ordinario de M4-B04 (UI vs backend, el texto lo aclara)."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El tiempo server-side se evalúa dentro del hecho."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-B06","version":1,"hash_version_atestado":"c34791d662d96ef44e435a37d6ee01f9cbbcd4290219177c130f0d6c201e4fa4","hash_paquete_atestado":"dc9c027110359174e2fd7fb391b865c209946fa89e38bab392d0df452e32a86f","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"El cooldown por agotamiento se parece al de M4-B04 pero usa OTP_MAX_RESENDS y no OTP_MAX_ATTEMPTS."},"SEM_NO_CONTRADICE":{"puntaje":0.95,"observacion":"Dos contadores de agotamiento (intentos y reenvíos) con cooldown de 120 s y 2 min podrían producir reglas redundantes si Paulo los une; no hay contradicción hoy."},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto cita parámetros y la condición un hecho agregado."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-B07","version":1,"hash_version_atestado":"6a9c8ff107164633f25049135135427fe0d33d6e6a6954ad4f9b243c57ace8a6","hash_paquete_atestado":"594781cbff38161d663a4fbab45575eaa800742701e260755e8443967a9e8345","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El mensaje de soporte figura en el texto y la condición no lo evalúa."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M4-B08","version":1,"hash_version_atestado":"0237ed6d71ffe268934fdda266e354af156c83f84a2f3b56ebe60792b2198567","hash_paquete_atestado":"8d8cbf05853d25c8b673b1dfddc264fbc716d62856fcdb2318aa1741babcac19","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}}]'::jsonb) LOOP
  code:=p->>'codigo'; ver:=(p->>'version')::integer;
  SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v
    WHERE v.regla=code AND v.version=ver AND v.estado='CANDIDATA';
  IF hv IS DISTINCT FROM p->>'hash_version_atestado' THEN
   RAISE EXCEPTION 'TANDA4_VERSION_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_version_atestado',hv;
  END IF;
  SELECT count(*) INTO got_tests FROM lf_ops.nucleo_regla_pruebas
    WHERE regla=code AND version=ver;
  IF got_tests IS DISTINCT FROM (p->>'pruebas_atestadas')::integer THEN
   RAISE EXCEPTION 'TANDA4_TEST_COUNT_MISMATCH code=% want=% got=%',code,p->>'pruebas_atestadas',got_tests;
  END IF;
  hp:=lf_ops.nucleo_hash_paquete_v1(code,ver);
  IF hp IS DISTINCT FROM p->>'hash_paquete_atestado' THEN
   RAISE EXCEPTION 'TANDA4_PACKAGE_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_paquete_atestado',hp;
  END IF;
  jr:=jsonb_build_object('regla',code,'hash_evaluado',hp,'veredicto','PASS','puntajes',p->'puntajes',
     'juez','Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude',
     'modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda4_v1.json#'||code);
  -- Negativo: hash alterado jamás puede admitirse.
  BEGIN
   PERFORM lf_ops.nucleo_juicio_registrar_v1(jr||jsonb_build_object('hash_evaluado',repeat('0',64)));
   RAISE EXCEPTION 'TANDA4_BAD_HASH_ACCEPTED %',code;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
  END;
  PERFORM lf_ops.nucleo_juicio_registrar_v1(jr);
  ev:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  res:=ev->>'decision'; promoted:=NULL;
  IF res='AUTO' THEN
   promoted:=lf_ops.nucleo_regla_promover_v1(code);
   IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
     RAISE EXCEPTION 'TANDA4_AUTO_PROMOTION_FAILED % %',code,promoted;
   END IF;
   auto_count:=auto_count+1;
  ELSIF res='MANUAL' THEN manual_count:=manual_count+1;
  ELSE blocked_count:=blocked_count+1; END IF;
  RAISE NOTICE 'TANDA4_RESULT %',jsonb_build_object('regla',code,'version',ver,
    'hash_version',hv,'hash_paquete',hp,'decision',res,'nota',ev->'nota',
    'motivos',ev->'motivos','promocion',COALESCE(promoted->>'resultado','NO_PROMOVIDA'));
  n:=n+1;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-TANDA4-8-INDEPENDIENTES-20261123-001') THEN RAISE EXCEPTION 'TANDA4_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-TANDA4-8-INDEPENDIENTES-20261123-001','NUCLEO_REGLAS','Tanda 4 ocho juicios independientes M4B','Ocho juicios PASS con hash paquete atestado; publicar solo AUTO y no forzar MANUAL o BLOQUEADA.',
  'Hechos agregados de cooldown, reenvío y expiración no acreditan runtime; claves AUTH deben mantenerse en configuración.',
  'NUCLEO_TANDA4_JUICIO_INDEPENDIENTE',
  'Comparar hash versión, 4 pruebas, hash paquete y parámetros AUTH; negativo hash alterado; conservar IG, REG_CHK_007 y 586 legadas.',
  'PG17 BEGIN ROLLBACK, 8 casos y negativos, 17 regresiones, 14 lectura IG, Train y readback.', 'MEDIUM',1,now(),now(),'TANDA4-JUICIOS-20261123','ACTIVO',
  'sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda4_v1.json; docs/nucleo/LF_TANDA4_JUICIOS_INDEPENDIENTES_8_20261123.md');
 IF n<>8 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r
   WHERE r.codigo NOT IN ('M4-B01','M4-B02','M4-B03','M4-B04','M4-B05','M4-B06','M4-B07','M4-B08')) IS DISTINCT FROM oldcore
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r
   WHERE r.regla NOT IN ('M4-B01','M4-B02','M4-B03','M4-B04','M4-B05','M4-B06','M4-B07','M4-B08')) IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007') IS DISTINCT FROM oldchecks
  OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>34+auto_count
 THEN RAISE EXCEPTION 'TANDA4_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'TANDA4_PASS 8/8 judged; auto=% manual=% blocked=%; legadas sin drift; 0 deprecaciones',auto_count,manual_count,blocked_count;
END $pilot$;
COMMIT;
