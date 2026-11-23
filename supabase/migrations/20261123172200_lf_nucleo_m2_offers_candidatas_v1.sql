-- LF M2: 53 source legacy -> 31 groups; six eligible candidate-only groups.
-- Exact source: sandbox/lf_contract_gate_test/nucleo_ci/m2_6_candidatas_v1.json
BEGIN;
DO $m2$
DECLARE p jsonb; dry jsonb; applied jsonb; eval jsonb; t jsonb; truth jsonb; n integer:=0;
 total_tests integer:=0; cases integer; mut jsonb; mutant_truth jsonb; bad jsonb;
 oldlegacy jsonb; oldrules jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb;
 oldeffective jsonb; oldekb integer; actual_sources integer; ref_id integer; code text;
BEGIN
 SELECT count(*) INTO actual_sources FROM lf_ops.nucleo_regla_familia f
 JOIN lf_ops.v_reglas_compat_v1 v ON v.id=f.regla_id WHERE f.familia='OFFERS_INSTALLMENTS';
 IF actual_sources<>53
 OR EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo LIKE 'M2-C0%')
 THEN RAISE EXCEPTION 'M2_SOURCE_OR_ID_DRIFT count=%',actual_sources; END IF;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) INTO oldrules FROM lf_ops.nucleo_reglas r;
 SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) INTO oldversions FROM lf_ops.nucleo_regla_versiones v;
 SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones d;
 SELECT jsonb_agg(to_jsonb(a) ORDER BY regla,nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones a;
 SELECT jsonb_agg(jsonb_build_object('nodo',nd.codigo,'r',to_jsonb(e)) ORDER BY nd.codigo,e.regla)
 INTO oldeffective FROM lf_ops.nucleo_nodos nd CROSS JOIN LATERAL lf_ops.nucleo_reglas_efectivas_v1(nd.codigo,now()) e;
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 -- Facts are explicitly logical, typed, not a claim of an installed runtime binding.
 FOR t IN SELECT jsonb_array_elements_text($facts$["m2_oferta_activa_en_presentacion","m2_oferta_una_sola_modalidad_disponible","m2_modalidad_unica_autoseleccionada","m2_oferta_ambas_modalidades_disponibles","m2_modalidad_autoseleccionada_sin_cliente","m2_intento_continuar_con_oferta","m2_modalidad_elegida_por_cliente","m2_pantalla_multi_oferta_en_presentacion","m2_seleccion_parcial_incorrectamente_impedida","m2_modalidad_por_oferta_alterada_por_otra","m2_modalidad_visible_fuera_de_disponibles","m2_intento_ingreso_checkout","m2_oferta_seleccionada_sin_modalidad","m2_intento_continuar_plan_cuotas","m2_fecha_debito_seleccionada"]$facts$::jsonb) AS fact LOOP
  code:=t::text;
  IF EXISTS (SELECT 1 FROM lf_ops.nucleo_hechos WHERE codigo=code)
  THEN RAISE EXCEPTION 'M2_FACT_COLLISION %',code; END IF;
  INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion)
  VALUES(code,'boolean','ninguna','Hecho lógico M2 OFFERS_INSTALLMENTS; tabla_ref y columna_ref NULL; fuente técnica/binding Paulo PENDIENTE.');
  INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen)
  VALUES('OFFERS_INSTALLMENTS',code,'CURADO');
 END LOOP;
 FOR p IN SELECT value FROM jsonb_array_elements($packs$[{"tipo":"NUEVA","codigo":"M2-C01","clave":"m2_m2_g02","titulo":"Autoselección solo con modalidad única","descripcion":"En la presentación de una oferta activa, cuando existe exactamente una modalidad habilitada (pago único o cuotas), EXIGIR su selección automática. Se considera incumplimiento si la modalidad única no queda seleccionada. Si existen ambas modalidades, nunca autoseleccionar por esta regla; no presupone fuente runtime ni tabla Paulo.","familia":"OFFERS_INSTALLMENTS","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"CLIENT_HOME","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"y","izq":{"op":"=","izq":{"hecho":"m2_oferta_activa_en_presentacion"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m2_oferta_una_sola_modalidad_disponible"},"der":{"lit":true}}},"der":{"op":"=","izq":{"hecho":"m2_modalidad_unica_autoseleccionada"},"der":{"lit":false}}},"efecto":"EXIGIR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/142,143,149","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_oferta_una_sola_modalidad_disponible":true,"m2_modalidad_unica_autoseleccionada":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_oferta_una_sola_modalidad_disponible":true,"m2_modalidad_unica_autoseleccionada":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_oferta_una_sola_modalidad_disponible":false,"m2_modalidad_unica_autoseleccionada":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":false,"m2_oferta_una_sola_modalidad_disponible":true,"m2_modalidad_unica_autoseleccionada":false},"esperado":false}]},{"tipo":"NUEVA","codigo":"M2-C02","clave":"m2_m2_g03","titulo":"Elección explícita entre modalidades disponibles","descripcion":"En una oferta activa con ambas modalidades disponibles, BLOQUEAR selección automática no consentida y el intento de continuar sin elección del cliente. La obligación se limita a oferta efectivamente mostrada; no interfiere cuando solo hay una modalidad. Los hechos son lógicos, binding de pantalla pendiente de Paulo.","familia":"OFFERS_INSTALLMENTS","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"CLIENT_HOME","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"y","izq":{"op":"=","izq":{"hecho":"m2_oferta_activa_en_presentacion"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m2_oferta_ambas_modalidades_disponibles"},"der":{"lit":true}}},"der":{"op":"o","izq":{"op":"=","izq":{"hecho":"m2_modalidad_autoseleccionada_sin_cliente"},"der":{"lit":true}},"der":{"op":"y","izq":{"op":"=","izq":{"hecho":"m2_intento_continuar_con_oferta"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m2_modalidad_elegida_por_cliente"},"der":{"lit":false}}}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/144,150","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_oferta_ambas_modalidades_disponibles":true,"m2_modalidad_autoseleccionada_sin_cliente":true,"m2_intento_continuar_con_oferta":false,"m2_modalidad_elegida_por_cliente":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_oferta_ambas_modalidades_disponibles":true,"m2_modalidad_autoseleccionada_sin_cliente":false,"m2_intento_continuar_con_oferta":true,"m2_modalidad_elegida_por_cliente":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_oferta_ambas_modalidades_disponibles":true,"m2_modalidad_autoseleccionada_sin_cliente":false,"m2_intento_continuar_con_oferta":true,"m2_modalidad_elegida_por_cliente":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_oferta_ambas_modalidades_disponibles":false,"m2_modalidad_autoseleccionada_sin_cliente":true,"m2_intento_continuar_con_oferta":false,"m2_modalidad_elegida_por_cliente":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":false,"m2_oferta_ambas_modalidades_disponibles":true,"m2_modalidad_autoseleccionada_sin_cliente":true,"m2_intento_continuar_con_oferta":true,"m2_modalidad_elegida_por_cliente":false},"esperado":false}]},{"tipo":"NUEVA","codigo":"M2-C03","clave":"m2_m2_g04","titulo":"Multi oferta parcial e independiente","descripcion":"En la pantalla de dos o más ofertas activas, BLOQUEAR la restricción indebida de elegir solo una parte de las ofertas y la alteración de la modalidad de otra oferta por seleccionar/editar una. Cada oferta conserva selección propia; las alternativas no se duplican por modalidad. Los hechos lógicos no acreditan la implementación real ni la cardinalidad de tablas.","familia":"OFFERS_INSTALLMENTS","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"CLIENT_HOME","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m2_pantalla_multi_oferta_en_presentacion"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"=","izq":{"hecho":"m2_seleccion_parcial_incorrectamente_impedida"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m2_modalidad_por_oferta_alterada_por_otra"},"der":{"lit":true}}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/145,153,154","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m2_pantalla_multi_oferta_en_presentacion":true,"m2_seleccion_parcial_incorrectamente_impedida":true,"m2_modalidad_por_oferta_alterada_por_otra":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m2_pantalla_multi_oferta_en_presentacion":true,"m2_seleccion_parcial_incorrectamente_impedida":false,"m2_modalidad_por_oferta_alterada_por_otra":true},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m2_pantalla_multi_oferta_en_presentacion":true,"m2_seleccion_parcial_incorrectamente_impedida":true,"m2_modalidad_por_oferta_alterada_por_otra":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_pantalla_multi_oferta_en_presentacion":true,"m2_seleccion_parcial_incorrectamente_impedida":false,"m2_modalidad_por_oferta_alterada_por_otra":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_pantalla_multi_oferta_en_presentacion":false,"m2_seleccion_parcial_incorrectamente_impedida":true,"m2_modalidad_por_oferta_alterada_por_otra":true},"esperado":false}]},{"tipo":"NUEVA","codigo":"M2-C04","clave":"m2_m2_g06","titulo":"Modalidades visibles autorizadas por oferta","descripcion":"Al mostrar modalidades de una oferta activa, BLOQUEAR presentar o habilitar una modalidad que no conste entre las modalidades autorizadas de esa oferta. La comprobación debe proceder de disponibilidad de oferta autorizada por backend, binding pendiente Paulo; la regla no crea modalidades ni interpreta la oferta desde UI.","familia":"OFFERS_INSTALLMENTS","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"CLIENT_HOME","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m2_oferta_activa_en_presentacion"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m2_modalidad_visible_fuera_de_disponibles"},"der":{"lit":true}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/148","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_modalidad_visible_fuera_de_disponibles":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":true,"m2_modalidad_visible_fuera_de_disponibles":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_oferta_activa_en_presentacion":false,"m2_modalidad_visible_fuera_de_disponibles":true},"esperado":false}]},{"tipo":"NUEVA","codigo":"M2-C05","clave":"m2_m2_g07","titulo":"Checkout solo con modalidades definidas","descripcion":"En intento de ingreso al checkout con selección de ofertas, BLOQUEAR si alguna oferta seleccionada no tiene modalidad de pago elegida; ninguna oferta no seleccionada debe impedir el paso. No sustituye revalidación de precio/quote, REG_CHK_007 ni la selección server-side. Hechos lógicos sin bindings reales de Paulo.","familia":"OFFERS_INSTALLMENTS","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"CLIENT_PAYMENTS","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m2_intento_ingreso_checkout"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m2_oferta_seleccionada_sin_modalidad"},"der":{"lit":true}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/152","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m2_intento_ingreso_checkout":true,"m2_oferta_seleccionada_sin_modalidad":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_intento_ingreso_checkout":true,"m2_oferta_seleccionada_sin_modalidad":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_intento_ingreso_checkout":false,"m2_oferta_seleccionada_sin_modalidad":true},"esperado":false}]},{"tipo":"NUEVA","codigo":"M2-C06","clave":"m2_m2_g22","titulo":"Fecha de débito seleccionada antes de continuar plan","descripcion":"En PASO3_CUOTAS_DESGLOSE_V2, el intento de continuar con el plan de cuotas debe quedar BLOQUEADO hasta que el cliente seleccione una fecha de débito. No infiere qué fechas son elegibles ni crea calendario; validación server-side de fecha y binding del selector quedan pendientes de Paulo. No afecta flujos fuera de selección de cuotas.","familia":"OFFERS_INSTALLMENTS","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"CLIENT_HOME","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m2_intento_continuar_plan_cuotas"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m2_fecha_debito_seleccionada"},"der":{"lit":false}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/259","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m2_intento_continuar_plan_cuotas":true,"m2_fecha_debito_seleccionada":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_intento_continuar_plan_cuotas":true,"m2_fecha_debito_seleccionada":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m2_intento_continuar_plan_cuotas":false,"m2_fecha_debito_seleccionada":false},"esperado":false}]}]$packs$::jsonb) LOOP
  code:=p->>'codigo';
  -- Every source legacy ID remains present and mapped to M2; no source is assumed published by nucleus.
  FOR t IN SELECT jsonb_array_elements_text(to_jsonb(string_to_array(split_part(p->'origen'->>'ref','/',2),','))) LOOP
   ref_id:=(t#>>'{}')::integer;
   IF NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_regla_familia f JOIN lf_ops.v_reglas_compat_v1 v ON v.id=f.regla_id
      WHERE f.familia='OFFERS_INSTALLMENTS' AND v.id=ref_id)
   THEN RAISE EXCEPTION 'M2_UNGROUNDED_SOURCE % %',code,ref_id; END IF;
  END LOOP;
  dry:=lf_ops.nucleo_regla_proponer_v1(p,false);
  IF dry->>'resultado'<>'EVALUADA_SIN_ESCRIBIR' OR (dry->>'bloqueantes')::integer<>0
  THEN RAISE EXCEPTION 'M2_PREFLIGHT_REJECTED % %',code,dry; END IF;
  cases:=0;
  FOR t IN SELECT value FROM jsonb_array_elements(p->'pruebas') LOOP
   truth:=lf_ops.nucleo_eval_v1(p->'condicion',t->'entrada');
   IF truth IS DISTINCT FROM t->'esperado'
   THEN RAISE EXCEPTION 'M2_CASE_WRONG_CONTROL % % expected=% actual=%',code,cases,t->'esperado',truth; END IF;
   cases:=cases+1;
  END LOOP;
  IF cases<3 THEN RAISE EXCEPTION 'M2_CASE_COVERAGE_LOW %',code; END IF;
  -- Mutant removes the scoped guard. It must FAIL exactly the no-activity negative
  -- for this rule, by returning true where the correctly guarded tree returns false.
  SELECT value INTO bad FROM jsonb_array_elements(p->'pruebas') WITH ORDINALITY x(value,ord)
    WHERE ord=(SELECT count(*) FROM jsonb_array_elements(p->'pruebas'));
  IF bad->'esperado' IS DISTINCT FROM 'false'::jsonb
  THEN RAISE EXCEPTION 'M2_LAST_CASE_NOT_NEGATIVE %',code; END IF;
  mutant_truth:=lf_ops.nucleo_eval_v1(p->'condicion'->'der',bad->'entrada');
  IF mutant_truth IS DISTINCT FROM 'true'::jsonb
  THEN RAISE EXCEPTION 'M2_MUTANT_MISSED_GUARD % actual=%',code,mutant_truth; END IF;
  RAISE NOTICE 'M2_CASES % count=% guard_mutant_detected=true',code,cases;
  applied:=lf_ops.nucleo_regla_proponer_v1(p,true);
  IF applied->>'resultado'<>'CANDIDATA' OR applied->>'version'<>'1'
  THEN RAISE EXCEPTION 'M2_CANONICAL_DOOR_REJECTED % %',code,applied; END IF;
  eval:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  IF eval->>'decision'<>'BLOQUEADA'
    OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(eval->'motivos') m WHERE m->>'dimension'='JUICIO')
  THEN RAISE EXCEPTION 'M2_UNJUDGED_CANDIDATE_MUST_BLOCK % %',code,eval; END IF;
  IF NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_reglas r JOIN lf_ops.nucleo_regla_versiones v ON v.regla=r.codigo
      WHERE r.codigo=code AND r.estado='CANDIDATA' AND r.regla_legacy_id IS NULL
       AND v.version=1 AND v.estado='CANDIDATA' AND v.publicada_desde IS NULL AND v.exigible_desde IS NULL)
  THEN RAISE EXCEPTION 'M2_CANDIDATE_WRITTEN_AS_PUBLISHED %',code; END IF;
  RAISE NOTICE 'M2_CANDIDATE %',jsonb_build_object('code',code,'cases',cases,'decision',eval->>'decision',
            'hash',lf_ops.nucleo_hash_paquete_v1(code,1),'estado','CANDIDATA');
  n:=n+1;
  total_tests:=total_tests+cases;
 END LOOP;
 -- New finding: family keyword matching included unrelated education and Simula semantics.
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-NUCLEO-M2-OFFERS-FAMILY-KEYWORD-BLEED-20261123-001')
 THEN RAISE EXCEPTION 'M2_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
 validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-M2-OFFERS-FAMILY-KEYWORD-BLEED-20261123-001','NUCLEO_REGLAS',
 'OFFERS_INSTALLMENTS agrupa educación, Simula y marketing por palabra clave',
 'Inventario M2 detectó fuentes ajenas a obligación operacional de ofertas/cuotas entre las 53 legadas.',
 'Clasificación lexical sin verificación semántica de pertinencia de familia','FAMILY_KEYWORD_BLEED',
 'Conservar asociación original, marcar pendiente_validacion y clasificar por obligación antes de crear candidatas; no migrar contenido lateral por palabra clave.',
 'Inventario de 53 fuentes en 31 grupos; seis grupos migrables; otros quedan cubiertos parcialmente o pendientes de decisión/Paulo.',
 'HIGH',1,now(),now(),'M2-OFFERS-INSTALLMENTS-20261123','ACTIVO',
 'docs/nucleo/LF_M2_INVENTARIO_53_31_GRUPOS_20261123.md');
 IF n<>6 OR total_tests<>23 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r WHERE codigo NOT LIKE 'M2-C0%') IS DISTINCT FROM oldrules
  OR (SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones v WHERE regla NOT LIKE 'M2-C0%') IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones d) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(a) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones a WHERE regla NOT LIKE 'M2-C0%') IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(jsonb_build_object('nodo',nd.codigo,'r',to_jsonb(e)) ORDER BY nd.codigo,e.regla)
      FROM lf_ops.nucleo_nodos nd CROSS JOIN LATERAL lf_ops.nucleo_reglas_efectivas_v1(nd.codigo,now()) e)
      IS DISTINCT FROM oldeffective
  OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo='REG_CHK_007')<>'CANDIDATA'
 THEN RAISE EXCEPTION 'M2_UNAUTHORIZED_OR_COVERAGE_DRIFT % %',n,total_tests; END IF;
 RAISE NOTICE 'M2_PASS 6/6 candidate-only; 23/23 positive-negative-boundary, 6 guard mutants; 53 source legadas intactas; 0 deprecations';
END $m2$;
COMMIT;
