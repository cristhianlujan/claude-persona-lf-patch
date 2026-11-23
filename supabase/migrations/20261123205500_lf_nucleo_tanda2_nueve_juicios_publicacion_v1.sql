-- Tanda 2: nueve veredictos PASS de juez externo. Hash versión != hash paquete (pruebas).
-- Fuente: sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda2_v1.json
BEGIN;
DO $pilot$
DECLARE p jsonb; code text; ver int; hv text; hp text; got_tests int; jr jsonb; ev jsonb; promoted jsonb; res text;
 oldlegacy jsonb; oldcore jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldchecks jsonb; oldekb bigint;
 n int:=0; auto_count int:=0; manual_count int:=0; blocked_count int:=0; new_published int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldcore FROM lf_ops.nucleo_reglas r
  WHERE r.codigo NOT IN ('M2L2-C01','M2L2-C02','M2L2-C03','M2L2-C04','M2L2-C05','M2L2-C06','M2L2-C07','M3-C04','M3-C05');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r
  WHERE r.regla NOT IN ('M2L2-C01','M2L2-C02','M2L2-C03','M2L2-C04','M2L2-C05','M2L2-C06','M2L2-C07','M3-C04','M3-C05');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldchecks FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007';
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 RAISE NOTICE 'TANDA2_PREFLIGHT legacy_rows=% publicadas=%', (SELECT count(*) FROM lf_ops.reglas),(SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA');
 IF (SELECT count(*) FROM lf_ops.reglas)<1 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
   OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>17
   OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla IN ('M2L2-C01','M2L2-C02','M2L2-C03','M2L2-C04','M2L2-C05','M2L2-C06','M2L2-C07','M3-C04','M3-C05')
     AND modo='INDEPENDIENTE' AND veredicto='PASS')<>0
 THEN RAISE EXCEPTION 'TANDA2_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"M2L2-C01","version":1,"hash_version_atestado":"0e7e2c92ae25d79fa74ed57535686b706dd6cf8609df968ce1cab8f5b32936ce","hash_paquete_atestado":"828366eb5977cab6464a5598e505bd78e0262297051d2f5d37492ad9ef868fb2","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa parcialmente con M2-C03 publicada (alternativas no se duplican por modalidad), distinto momento (materialización vs pantalla)."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto dice que las modalidades comparten identidad de oferta y la condición solo usa el hecho de duplicación."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2L2-C02","version":1,"hash_version_atestado":"2ad9bf09f6425fa8f56663d8bf81e3f097d8ab370c1185a4d5d8679be3e8c2ac","hash_paquete_atestado":"c347ce10400e2b9ed8fb07d6c8dc6b6a085c22e672f2c3c3bde0a8e24668e6ba","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2L2-C03","version":1,"hash_version_atestado":"eb4b65f6100449196020917b215dd45815b0e77ba535e197d90c4e5069c7dcab","hash_paquete_atestado":"dfc12611c59569c61db9ea6bf4fcf2aa2a89341bfd3f684fbaacddbc4fc15151","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.95,"observacion":"Tres estados visuales (sin selección, seleccionada, vencida) agrupados en un solo hecho."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.95,"observacion":"El hecho único oculta cuál estado falla."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"Borde, ahorro, badge y deshabilitado se exigen en el texto y la condición no los distingue."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2L2-C04","version":1,"hash_version_atestado":"1894e82a786292f7cf1cf1145a1b52c779163b25f2767235240602f6fe42ef66","hash_paquete_atestado":"9163b8a997b9d3d846b7e0b8588e0abf591cab74481c034b3fdb77bbb374e24e","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"El texto cubre dos direcciones (falta el copy con ofertas pendientes y copy sobrante con todas elegidas) y la condición usa un solo hecho derivado de ambas."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2L2-C05","version":1,"hash_version_atestado":"49202c30132c852593abc91bb90f507f6d2879365949c6d2707eb7dc4d083bab","hash_paquete_atestado":"38689a9598bbe9f4e19f79ea4c75826bb0091f2c67ffd6574673675a50df6206","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"El texto cubre cierre por X y por Cancelar, y pérdida de selección o navegación involuntaria; la condición los une en un hecho."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2L2-C06","version":1,"hash_version_atestado":"b96a2d95984886d78d22d187a8bdcf14b19075f1d77edc25e7e6519a802acb0b","hash_paquete_atestado":"3afd7312ce1f1a723d6cf32c2a76c30c66b4bb90b14ca8e403d5e924eb3fa4e8","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto exige jerarquía destacada sobre el total y la condición solo evalúa un hecho agregado."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M2L2-C07","version":1,"hash_version_atestado":"a30f4e53bb559e195164faab64ee91252c5cf8db5f4acbcf861678e6cfd7db08","hash_paquete_atestado":"b6e4035dca067f6b7d065a8692eb3282e3fb4149e6ab13ca44ea76230b4f23d3","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El texto fija el copy aprobado y la condición evalúa un hecho de promesa no real, no el copy literal."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M3-C04","version":1,"hash_version_atestado":"81d0a399494f358acca9151de9cd4f504765def64b2c7ead18a87a1bbd6bd8ac","hash_paquete_atestado":"c492b9345fa9a21cfdc8bf59495341d7bbe32941bf85b7164b1b1b40e70e7d28","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Relacionada con M3-C02 publicada (también exige PAYMENT_CONFIRMED) pero esta cubre exposición y asignación en Portal Empresa, no la transición a SETTLED_CONFIRMED."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"M3-C05","version":1,"hash_version_atestado":"182862167d84396a437d19f0331d940d82f60bdae0129325baf1f372fd42d696","hash_paquete_atestado":"f4a7952bd78cf40e22ecc2ff211d5566807fb2ab662542e6ca5eba9e13f7f9ef","pruebas_atestadas":5,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.95,"observacion":"Sin prueba del caso diferencia con excepción trazable y contraste coincidente esperando false; se cubre solo por la condición."},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Se solapa parcialmente con M3-C02 publicada en importes confirmados en ledger, pero esta exige contraste independiente del proveedor."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Importes y operación verificados se colapsan en el hecho de coincidencia."},"COH_EFECTO":{"puntaje":1}}}]'::jsonb) LOOP
  code:=p->>'codigo'; ver:=(p->>'version')::integer;
  SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v
    WHERE v.regla=code AND v.version=ver AND v.estado='CANDIDATA';
  IF hv IS DISTINCT FROM p->>'hash_version_atestado' THEN
   RAISE EXCEPTION 'TANDA2_VERSION_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_version_atestado',hv;
  END IF;
  SELECT count(*) INTO got_tests FROM lf_ops.nucleo_regla_pruebas
    WHERE regla=code AND version=ver;
  IF got_tests IS DISTINCT FROM (p->>'pruebas_atestadas')::integer THEN
   RAISE EXCEPTION 'TANDA2_TEST_COUNT_MISMATCH code=% want=% got=%',code,p->>'pruebas_atestadas',got_tests;
  END IF;
  hp:=lf_ops.nucleo_hash_paquete_v1(code,ver);
  IF hp IS DISTINCT FROM p->>'hash_paquete_atestado' THEN
   RAISE EXCEPTION 'TANDA2_PACKAGE_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_paquete_atestado',hp;
  END IF;
  jr:=jsonb_build_object('regla',code,'hash_evaluado',hp,'veredicto','PASS','puntajes',p->'puntajes',
     'juez','Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude',
     'modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda2_v1.json#'||code);
  -- Negativo: hash alterado jamás puede admitirse.
  BEGIN
   PERFORM lf_ops.nucleo_juicio_registrar_v1(jr||jsonb_build_object('hash_evaluado',repeat('0',64)));
   RAISE EXCEPTION 'TANDA2_BAD_HASH_ACCEPTED %',code;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
  END;
  PERFORM lf_ops.nucleo_juicio_registrar_v1(jr);
  ev:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  res:=ev->>'decision'; promoted:=NULL;
  IF res='AUTO' THEN
   promoted:=lf_ops.nucleo_regla_promover_v1(code);
   IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
     RAISE EXCEPTION 'TANDA2_AUTO_PROMOTION_FAILED % %',code,promoted;
   END IF;
   auto_count:=auto_count+1;
  ELSIF res='MANUAL' THEN manual_count:=manual_count+1;
  ELSE blocked_count:=blocked_count+1; END IF;
  RAISE NOTICE 'TANDA2_RESULT %',jsonb_build_object('regla',code,'version',ver,
    'hash_version',hv,'hash_paquete',hp,'decision',res,'nota',ev->'nota',
    'motivos',ev->'motivos','promocion',COALESCE(promoted->>'resultado','NO_PROMOVIDA'));
  n:=n+1;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-TANDA2-9-INDEPENDIENTES-20261123-001') THEN
  RAISE EXCEPTION 'TANDA2_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
     primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-TANDA2-9-INDEPENDIENTES-20261123-001','NUCLEO_REGLAS',
   'Escalamiento Tanda 2 juicio independiente y publicación condicional',
   'Nueve juicios externos PASS sobre M2L2 y M3 vinculados al hash canónico y rúbrica; publicar únicamente AUTO, conservar MANUAL y BLOQUEADA.',
   'Riesgo de aceptar hash histórico o evaluación con distinta profundidad de pruebas; hechos lógicos sin runtime.',
   'NUCLEO_TANDA2_JUICIO_INDEPENDIENTE',
   'Cotejar version hash, cantidad pruebas y nucleo_hash_paquete_v1 antes del juicio; negativo hash alterado; no deprecar legado ni tocar REG_CHK_007.',
   'PG17 exacto BEGIN ROLLBACK, 9 casos y 9 negativos, 17 regresiones, Train, readback de Supabase.',
   'MEDIUM',1,now(),now(),'TANDA2-JUICIOS-20261123','ACTIVO',
   'sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda2_v1.json; docs/nucleo/LF_TANDA2_JUICIOS_INDEPENDIENTES_9_20261123.md');
 IF n<>9 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r
   WHERE r.codigo NOT IN ('M2L2-C01','M2L2-C02','M2L2-C03','M2L2-C04','M2L2-C05','M2L2-C06','M2L2-C07','M3-C04','M3-C05')) IS DISTINCT FROM oldcore
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r
   WHERE r.regla NOT IN ('M2L2-C01','M2L2-C02','M2L2-C03','M2L2-C04','M2L2-C05','M2L2-C06','M2L2-C07','M3-C04','M3-C05')) IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007') IS DISTINCT FROM oldchecks
  OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>17+auto_count
 THEN RAISE EXCEPTION 'TANDA2_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'TANDA2_PASS 9/9 judged; auto=% manual=% blocked=%; legadas sin drift; 0 deprecaciones',auto_count,manual_count,blocked_count;
END $pilot$;
COMMIT;
