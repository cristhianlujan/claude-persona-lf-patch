-- Tanda 8: una veredictos PASS de juez externo. Hash versión != hash paquete (pruebas).
-- Fuente: sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda8_v1.json
BEGIN;
DO $pilot$
DECLARE p jsonb; code text; ver int; hv text; hp text; got_tests int; jr jsonb; ev jsonb; promoted jsonb; res text;
 oldlegacy jsonb; oldcore jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldchecks jsonb; oldekb bigint;
 n int:=0; auto_count int:=0; manual_count int:=0; blocked_count int:=0; new_published int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldcore FROM lf_ops.nucleo_reglas r
  WHERE r.codigo NOT IN ('REG_CHK_007','S1-C01');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r
  WHERE r.regla NOT IN ('REG_CHK_007','S1-C01');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldchecks FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007';
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 RAISE NOTICE 'TANDA8_PREFLIGHT legacy_rows=% publicadas=%', (SELECT count(*) FROM lf_ops.reglas),(SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA');
 IF (SELECT count(*) FROM lf_ops.reglas)<1 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
   OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>57
   OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla IN ('REG_CHK_007','S1-C01')
     AND modo='INDEPENDIENTE' AND veredicto='PASS')<>0
 THEN RAISE EXCEPTION 'TANDA8_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"REG_CHK_007","version":3,"hash_version_atestado":"a17cae5db3a2661695bc1f74541ae8893065cb1bd4aca51c57daca2d4ef88e4b","hash_paquete_atestado":"3f173fcf905cff20835c73d83fb5b22a4c9aaed2cd3ee6d7930e1a98e1b44ea2","pruebas_atestadas":11,"veredicto":"PASS","juez":"Claude Sonnet 5.5","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.9,"observacion":"La descripción es larga y mezcla el bloqueo, el uso de Volver y la definición operativa del pago pendiente."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.95,"observacion":"Se relaciona con REG_CHK_004 publicada (reintento de pago) y con M2-C05 publicada, que ya excluye expresamente a REG_CHK_007; esta regla gobierna modificar la selección y no el reintento ni la modalidad."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Volver sin intento de modificar no es un hecho propio y queda cubierto por intento=false, las pruebas 1 y 3 lo muestran."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S1-C01","version":1,"hash_version_atestado":"ffc5f8e911c6e29a3ca6e49432885eece4ebb8d5cd5273bf83f3faa61c552f65","hash_paquete_atestado":"9c8d1b36dab6d3b8f5d24afca4a5b8f7b760e22f56e6a811a3902b1643cb8b87","pruebas_atestadas":8,"veredicto":"PASS","juez":"Claude Sonnet 5.5","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.95,"observacion":"Se relaciona con M4-C03 publicada, que gobierna que la respuesta API no devuelva el OTP, mientras esta gobierna persistir el OTP sin hash."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El hash del OTP se comprueba en backend antes de emitir el hecho y la condición lo recibe agregado; hay dos pares de pruebas duplicadas (1=5, 2=7) y faltan producción=true,intento=false,sin_hash=false y las tres false; deduplicar en próximas candidatas."},"COH_EFECTO":{"puntaje":1}}}]'::jsonb) LOOP
  code:=p->>'codigo'; ver:=(p->>'version')::integer;
  SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v
    WHERE v.regla=code AND v.version=ver AND v.estado='CANDIDATA';
  IF hv IS DISTINCT FROM p->>'hash_version_atestado' THEN
   RAISE EXCEPTION 'TANDA8_VERSION_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_version_atestado',hv;
  END IF;
  SELECT count(*) INTO got_tests FROM lf_ops.nucleo_regla_pruebas
    WHERE regla=code AND version=ver;
  IF got_tests IS DISTINCT FROM (p->>'pruebas_atestadas')::integer THEN
   RAISE EXCEPTION 'TANDA8_TEST_COUNT_MISMATCH code=% want=% got=%',code,p->>'pruebas_atestadas',got_tests;
  END IF;
  hp:=lf_ops.nucleo_hash_paquete_v1(code,ver);
  IF hp IS DISTINCT FROM p->>'hash_paquete_atestado' THEN
   RAISE EXCEPTION 'TANDA8_PACKAGE_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_paquete_atestado',hp;
  END IF;
  jr:=jsonb_build_object('regla',code,'hash_evaluado',hp,'veredicto','PASS','puntajes',p->'puntajes',
     'juez','Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude',
     'modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda8_v1.json#'||code);
  -- Negativo: hash alterado jamás puede admitirse.
  BEGIN
   PERFORM lf_ops.nucleo_juicio_registrar_v1(jr||jsonb_build_object('hash_evaluado',repeat('0',64)));
   RAISE EXCEPTION 'TANDA8_BAD_HASH_ACCEPTED %',code;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
  END;
  PERFORM lf_ops.nucleo_juicio_registrar_v1(jr);
  ev:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  res:=ev->>'decision'; promoted:=NULL;
  IF res='AUTO' THEN
   IF code IN ('S1-C01','REG_CHK_007') THEN
    -- La publicación en BACKEND / HEREDA hace nativa la pantalla legal 36.
    -- El contrato DPIG03 exige que esa pantalla continúe con 0 nativas.
    -- Subtransacción: solo revierte la promoción incompatible; conserva el juicio PASS.
    BEGIN
     promoted:=lf_ops.nucleo_regla_promover_v1(code);
     IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
      RAISE EXCEPTION 'TANDA8_AUTO_PROMOTION_FAILED % %',code,promoted;
     END IF;
     IF COALESCE(jsonb_array_length((lf_ops.lf_nucleo_lectura_transicion_v1(
          36,'INPUT_GOVERNANCE','DIRECTAS'))->'nativas'),0)<>0 THEN
      RAISE EXCEPTION 'TANDA8_DPiG03_BLOCK_NATIVE_SCREEN36';
     END IF;
     auto_count:=auto_count+1;
    EXCEPTION WHEN raise_exception THEN
     IF SQLERRM<>'TANDA8_DPiG03_BLOCK_NATIVE_SCREEN36' THEN RAISE; END IF;
     promoted:=jsonb_build_object('resultado','NO_PROMOVIDA_POR_DPiG03_SCREEN36');
     blocked_count:=blocked_count+1;
     RAISE NOTICE 'TANDA8_SCOPE_BLOCK % PASS/AUTO juicio conservado; pantalla 36 nativas debe seguir 0',code;
    END;
   ELSE
    promoted:=lf_ops.nucleo_regla_promover_v1(code);
    IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
     RAISE EXCEPTION 'TANDA8_AUTO_PROMOTION_FAILED % %',code,promoted;
    END IF;
    auto_count:=auto_count+1;
   END IF;
  ELSIF res='MANUAL' THEN manual_count:=manual_count+1;
  ELSE blocked_count:=blocked_count+1; END IF;
  RAISE NOTICE 'TANDA8_RESULT %',jsonb_build_object('regla',code,'version',ver,
    'hash_version',hv,'hash_paquete',hp,'decision',res,'nota',ev->'nota',
    'motivos',ev->'motivos','promocion',COALESCE(promoted->>'resultado','NO_PROMOVIDA'));
  n:=n+1;
 END LOOP;
 IF auto_count+manual_count+blocked_count<>2 THEN RAISE EXCEPTION 'TANDA8_DECISION_COUNTER'; END IF;

 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-TANDA8-2-INDEPENDIENTES-20261123-001') THEN RAISE EXCEPTION 'TANDA8_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-TANDA8-2-INDEPENDIENTES-20261123-001','NUCLEO_REGLAS','Tanda 8 dos juicios independientes',
 'REG_CHK_007 v3 y S1-C01 v1 con juicio PASS externo de Claude Sonnet 5.5; promoción solo AUTO. Conservar legadas e IG.',
 'Ambos juicios PASS/AUTO válidos. REG_CHK_007 crea nativa ilegal en pantalla legal 36 y queda CANDIDATA; S1-C01 se promueve con lectura IG intacta. Sin alterar hashes.',
 'NUCLEO_JUICIOS_TANDA8','No promover REG_CHK_007 v3: con alcance actual aparece en pantalla legal 36. Revisar aplicación, reversionar y solicitar juicio nuevo; S1-C01 PASS/AUTO sin drift. No cambiar IG.',
 'PG17 hash positivo/alterado, BEGIN ROLLBACK, regresiones 17/17, lector IG 14/14, readback.',
 'MEDIUM',1,now(),now(),'TANDA8-20261123','ACTIVO','sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda8_v1.json; docs/nucleo/LF_TANDA8_DOS_JUICIOS_INDEPENDIENTES_20261123.md');
 IF auto_count<>1 OR blocked_count<>1 OR n<>2 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r
   WHERE r.codigo NOT IN ('REG_CHK_007','S1-C01')) IS DISTINCT FROM oldcore
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r
   WHERE r.regla NOT IN ('REG_CHK_007','S1-C01')) IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
  OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>57+auto_count
 THEN RAISE EXCEPTION 'TANDA8_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'TANDA8_PASS 2/2 judged; auto=% manual=% blocked=%; legadas sin drift; 0 deprecaciones',auto_count,manual_count,blocked_count;
END $pilot$;
COMMIT;
