-- LF M3: 16 source legacy -> 15 groups; five eligible candidate-only groups.
-- Exact source: sandbox/lf_contract_gate_test/nucleo_ci/m3_5_candidatas_v1.json
BEGIN;
DO $m2$
DECLARE p jsonb; dry jsonb; applied jsonb; eval jsonb; t jsonb; truth jsonb; n integer:=0;
 total_tests integer:=0; cases integer; mut jsonb; mutant_truth jsonb; bad jsonb;
 oldlegacy jsonb; oldrules jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; ref_text text;
 oldeffective jsonb; oldekb integer; actual_sources integer; ref_id integer; code text;
BEGIN
 SELECT count(*) INTO actual_sources FROM lf_ops.nucleo_regla_familia f
 JOIN lf_ops.v_reglas_compat_v1 v ON v.id=f.regla_id WHERE f.familia='FINANCIAL_INTEGRITY_RECONCILIATION';
 IF actual_sources<>16
 OR EXISTS (SELECT 1 FROM lf_ops.nucleo_reglas WHERE codigo LIKE 'M3-C0%')
 THEN RAISE EXCEPTION 'M3_SOURCE_OR_ID_DRIFT count=%',actual_sources; END IF;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) INTO oldrules FROM lf_ops.nucleo_reglas r;
 SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) INTO oldversions FROM lf_ops.nucleo_regla_versiones v;
 SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones d;
 SELECT jsonb_agg(to_jsonb(a) ORDER BY regla,nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones a;
 SELECT jsonb_agg(jsonb_build_object('nodo',nd.codigo,'r',to_jsonb(e)) ORDER BY nd.codigo,e.regla)
 INTO oldeffective FROM lf_ops.nucleo_nodos nd CROSS JOIN LATERAL lf_ops.nucleo_reglas_efectivas_v1(nd.codigo,now()) e;
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 -- Facts are explicitly logical, typed, not a claim of an installed runtime binding.
 FOR code IN SELECT jsonb_array_elements_text($facts$["m3_intento_mostrar_referencia_operacion","m3_referencia_reservada_o_emitida_backend","m3_intento_marcar_deuda_settled_confirmed","m3_importes_exigibles_acuerdo_confirmados","m3_settlement_externo_contractualmente_requerido","m3_settlement_externo_confirmado","m3_intento_afirmar_carta_disponible","m3_deuda_settled_confirmed_verificada","m3_carta_elegible_segun_estado","m3_intento_exponer_o_liquidar_pago_b2b","m3_pago_atribuido_a_deuda_empresa_verificado","m3_intento_declarar_conciliado","m3_evidencia_financiera_externa_verificada","m3_contraste_interno_externo_coincide","m3_diferencia_financiera_detectada","m3_diferencia_con_excepcion_trazable"]$facts$::jsonb) LOOP
  IF EXISTS (SELECT 1 FROM lf_ops.nucleo_hechos WHERE codigo=code)
  THEN RAISE EXCEPTION 'M3_FACT_COLLISION %',code; END IF;
  INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion)
  VALUES(code,'boolean','ninguna','Hecho lógico M3 FINANCIAL_INTEGRITY_RECONCILIATION; tabla_ref y columna_ref NULL; fuente técnica/binding Paulo PENDIENTE.');
  INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen)
  VALUES('FINANCIAL_INTEGRITY_RECONCILIATION',code,'CURADO');
 END LOOP;
 -- Same fact already exists globally as typed text; whitelist for M3 without new physical binding.
 IF NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_hechos WHERE codigo='estado_pago_normalizado' AND tipo_dato='text')
 THEN RAISE EXCEPTION 'M3_EXISTING_PAYMENT_STATE_FACT_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.nucleo_familia_vocabulario WHERE familia='FINANCIAL_INTEGRITY_RECONCILIATION' AND hecho='estado_pago_normalizado')
 THEN RAISE EXCEPTION 'M3_PAYMENT_STATE_VOCAB_ALREADY_EXISTS'; END IF;
 INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen)
 VALUES('FINANCIAL_INTEGRITY_RECONCILIATION','estado_pago_normalizado','CURADO');
 FOR p IN SELECT value FROM jsonb_array_elements($packs$[{"tipo":"NUEVA","codigo":"M3-C01","clave":"m3_m3_g04","titulo":"Impedir referencias de operación no canónicas","descripcion":"Cuando se intenta mostrar una referencia de operación en checkout, confirmación o documento, BLOQUEAR la exposición de identificadores no emitidos ni reservados por backend/ledger canónico. Si aún no se intenta mostrar referencia en estado transitorio, no bloquear pantalla ni inventar otra referencia. La comprobación de procedencia es hecho lógico sin binding de Paulo.","familia":"FINANCIAL_INTEGRITY_RECONCILIATION","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"CLIENT_PAYMENTS","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m3_intento_mostrar_referencia_operacion"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m3_referencia_reservada_o_emitida_backend"},"der":{"lit":false}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/317","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_mostrar_referencia_operacion":true,"m3_referencia_reservada_o_emitida_backend":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_mostrar_referencia_operacion":true,"m3_referencia_reservada_o_emitida_backend":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_mostrar_referencia_operacion":false,"m3_referencia_reservada_o_emitida_backend":false},"esperado":false}]},{"tipo":"NUEVA","codigo":"M3-C02","clave":"m3_m3_g05","titulo":"No declarar deuda liquidada sin confirmación financiera completa","descripcion":"Solo al intentar transicionar una deuda al estado SETTLED_CONFIRMED, BLOQUEAR si el pago que pretende justificarlo sigue PAYMENT_PENDING_CONFIRMATION o no está PAYMENT_CONFIRMED, si no constan todos los importes exigibles confirmados en el ledger del acuerdo aceptado, o si falta el settlement externo cuando sea contractual. El pago inicial y el paso de tiempo no acreditan liquidación; frontend nunca puede promover el estado. Hechos lógicos de ledger y contrato sin binding de Paulo.","familia":"FINANCIAL_INTEGRITY_RECONCILIATION","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"BACKEND","modo":"HEREDA","clase":"BACKEND","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m3_intento_marcar_deuda_settled_confirmed"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"!=","izq":{"hecho":"estado_pago_normalizado"},"der":{"lit":"PAYMENT_CONFIRMED"}},"der":{"op":"=","izq":{"hecho":"m3_importes_exigibles_acuerdo_confirmados"},"der":{"lit":false}}},"der":{"op":"y","izq":{"op":"=","izq":{"hecho":"m3_settlement_externo_contractualmente_requerido"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m3_settlement_externo_confirmado"},"der":{"lit":false}}}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/533","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_marcar_deuda_settled_confirmed":true,"estado_pago_normalizado":"PAYMENT_PENDING_CONFIRMATION","m3_importes_exigibles_acuerdo_confirmados":true,"m3_settlement_externo_contractualmente_requerido":false,"m3_settlement_externo_confirmado":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_marcar_deuda_settled_confirmed":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","m3_importes_exigibles_acuerdo_confirmados":false,"m3_settlement_externo_contractualmente_requerido":false,"m3_settlement_externo_confirmado":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_marcar_deuda_settled_confirmed":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","m3_importes_exigibles_acuerdo_confirmados":true,"m3_settlement_externo_contractualmente_requerido":true,"m3_settlement_externo_confirmado":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_marcar_deuda_settled_confirmed":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","m3_importes_exigibles_acuerdo_confirmados":true,"m3_settlement_externo_contractualmente_requerido":true,"m3_settlement_externo_confirmado":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_marcar_deuda_settled_confirmed":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","m3_importes_exigibles_acuerdo_confirmados":true,"m3_settlement_externo_contractualmente_requerido":false,"m3_settlement_externo_confirmado":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_marcar_deuda_settled_confirmed":false,"estado_pago_normalizado":"PAYMENT_PENDING_CONFIRMATION","m3_importes_exigibles_acuerdo_confirmados":false,"m3_settlement_externo_contractualmente_requerido":true,"m3_settlement_externo_confirmado":false},"esperado":false}]},{"tipo":"NUEVA","codigo":"M3-C03","clave":"m3_m3_g06","titulo":"No presentar Carta de No Adeudo como disponible antes de liquidación","descripcion":"En HOME_001 o comunicación de una oferta, BLOQUEAR un intento de afirmar disponibilidad inmediata de Carta de No Adeudo sin deuda en SETTLED_CONFIRMED o sin gestión de carta elegible. El título visual «Carta de No Adeudo incluida» no autoriza promesa universal de emisión; su reconciliación de copy sigue pendiente de aprobación. Estos hechos lógicos no implementan emisión ni validan estado real sin Paulo.","familia":"FINANCIAL_INTEGRITY_RECONCILIATION","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"CLIENT_HOME","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m3_intento_afirmar_carta_disponible"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"=","izq":{"hecho":"m3_deuda_settled_confirmed_verificada"},"der":{"lit":false}},"der":{"op":"=","izq":{"hecho":"m3_carta_elegible_segun_estado"},"der":{"lit":false}}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/548","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_afirmar_carta_disponible":true,"m3_deuda_settled_confirmed_verificada":false,"m3_carta_elegible_segun_estado":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_afirmar_carta_disponible":true,"m3_deuda_settled_confirmed_verificada":true,"m3_carta_elegible_segun_estado":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_afirmar_carta_disponible":true,"m3_deuda_settled_confirmed_verificada":true,"m3_carta_elegible_segun_estado":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_afirmar_carta_disponible":false,"m3_deuda_settled_confirmed_verificada":false,"m3_carta_elegible_segun_estado":false},"esperado":false}]},{"tipo":"NUEVA","codigo":"M3-C04","clave":"m3_m3_g10","titulo":"Solo presentar pago confirmado y atribuible por deuda/empresa","descripcion":"En Portal Empresa, BLOQUEAR presentar como pago confirmado o habilitar su asignación/liquidación cuando el outcome normalizado no sea PAYMENT_CONFIRMED o la atribución por oferta/deuda/empresa no esté validada server-side. PAYMENT_PENDING_CONFIRMATION no es terminal, nunca apto para liquidación. El frontend B2B no promueve estados ni calcula netos. Binding proveedor/empresa pendiente de Paulo, sin inventar ledger físico.","familia":"FINANCIAL_INTEGRITY_RECONCILIATION","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"B2B","modo":"HEREDA","clase":"PANTALLA","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m3_intento_exponer_o_liquidar_pago_b2b"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"!=","izq":{"hecho":"estado_pago_normalizado"},"der":{"lit":"PAYMENT_CONFIRMED"}},"der":{"op":"=","izq":{"hecho":"m3_pago_atribuido_a_deuda_empresa_verificado"},"der":{"lit":false}}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/604","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_exponer_o_liquidar_pago_b2b":true,"estado_pago_normalizado":"PAYMENT_PENDING_CONFIRMATION","m3_pago_atribuido_a_deuda_empresa_verificado":true},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_exponer_o_liquidar_pago_b2b":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","m3_pago_atribuido_a_deuda_empresa_verificado":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_exponer_o_liquidar_pago_b2b":true,"estado_pago_normalizado":"PAYMENT_CONFIRMED","m3_pago_atribuido_a_deuda_empresa_verificado":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_exponer_o_liquidar_pago_b2b":false,"estado_pago_normalizado":"PAYMENT_PENDING_CONFIRMATION","m3_pago_atribuido_a_deuda_empresa_verificado":false},"esperado":false}]},{"tipo":"NUEVA","codigo":"M3-C05","clave":"m3_m3_g13","titulo":"Conciliación exige contraste financiero independiente y diferencias trazables","descripcion":"Únicamente ante intento de declarar CONCILIADO un pago o liquidación, BLOQUEAR si no existe contraste verificable entre la fuente financiera interna y evidencia independiente del proveedor/banco/canal, si no coinciden los importes/operación verificados, o si una diferencia carece de excepción trazable. Una marca interna aislada no autoriza conciliación; outcomes ambiguos permanecen PAYMENT_PENDING_CONFIRMATION. Los hechos son lógicos y el adaptador de evidencia de Paulo sigue pendiente.","familia":"FINANCIAL_INTEGRITY_RECONCILIATION","naturaleza":"CONDUCTA","autoridad":"LEG-PRODUCTO","dueno":"PRODUCTO","alcance":"BACKEND","modo":"HEREDA","clase":"BACKEND","condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"m3_intento_declarar_conciliado"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"=","izq":{"hecho":"m3_evidencia_financiera_externa_verificada"},"der":{"lit":false}},"der":{"op":"=","izq":{"hecho":"m3_contraste_interno_externo_coincide"},"der":{"lit":false}}},"der":{"op":"y","izq":{"op":"=","izq":{"hecho":"m3_diferencia_financiera_detectada"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"m3_diferencia_con_excepcion_trazable"},"der":{"lit":false}}}}},"efecto":"BLOQUEAR","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/607","solicitante":"migracion-nucleo"},"pruebas":[{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_declarar_conciliado":true,"m3_evidencia_financiera_externa_verificada":false,"m3_contraste_interno_externo_coincide":true,"m3_diferencia_financiera_detectada":false,"m3_diferencia_con_excepcion_trazable":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_declarar_conciliado":true,"m3_evidencia_financiera_externa_verificada":true,"m3_contraste_interno_externo_coincide":false,"m3_diferencia_financiera_detectada":true,"m3_diferencia_con_excepcion_trazable":true},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"m3_intento_declarar_conciliado":true,"m3_evidencia_financiera_externa_verificada":true,"m3_contraste_interno_externo_coincide":true,"m3_diferencia_financiera_detectada":true,"m3_diferencia_con_excepcion_trazable":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_declarar_conciliado":true,"m3_evidencia_financiera_externa_verificada":true,"m3_contraste_interno_externo_coincide":true,"m3_diferencia_financiera_detectada":false,"m3_diferencia_con_excepcion_trazable":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"m3_intento_declarar_conciliado":false,"m3_evidencia_financiera_externa_verificada":false,"m3_contraste_interno_externo_coincide":false,"m3_diferencia_financiera_detectada":true,"m3_diferencia_con_excepcion_trazable":false},"esperado":false}]}]$packs$::jsonb) LOOP
  code:=p->>'codigo';
  -- Every source legacy ID remains present and mapped to M3; no source is assumed published by nucleus.
  FOR ref_text IN SELECT unnest(string_to_array(split_part(p->'origen'->>'ref','/',2),',')) LOOP
   ref_id:=ref_text::integer;
   IF NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_regla_familia f JOIN lf_ops.v_reglas_compat_v1 v ON v.id=f.regla_id
      WHERE f.familia='FINANCIAL_INTEGRITY_RECONCILIATION' AND v.id=ref_id)
   THEN RAISE EXCEPTION 'M3_UNGROUNDED_SOURCE % %',code,ref_id; END IF;
  END LOOP;
  dry:=lf_ops.nucleo_regla_proponer_v1(p,false);
  IF dry->>'resultado'<>'EVALUADA_SIN_ESCRIBIR' OR (dry->>'bloqueantes')::integer<>0
  THEN RAISE EXCEPTION 'M3_PREFLIGHT_REJECTED % %',code,dry; END IF;
  cases:=0;
  FOR t IN SELECT value FROM jsonb_array_elements(p->'pruebas') LOOP
   truth:=lf_ops.nucleo_eval_v1(p->'condicion',t->'entrada');
   IF truth IS DISTINCT FROM t->'esperado'
   THEN RAISE EXCEPTION 'M3_CASE_WRONG_CONTROL % % expected=% actual=%',code,cases,t->'esperado',truth; END IF;
   cases:=cases+1;
  END LOOP;
  IF cases<3 THEN RAISE EXCEPTION 'M3_CASE_COVERAGE_LOW %',code; END IF;
  -- Mutant removes the scoped guard. It must FAIL exactly the no-activity negative
  -- for this rule, by returning true where the correctly guarded tree returns false.
  SELECT value INTO bad FROM jsonb_array_elements(p->'pruebas') WITH ORDINALITY x(value,ord)
    WHERE ord=(SELECT count(*) FROM jsonb_array_elements(p->'pruebas'));
  IF bad->'esperado' IS DISTINCT FROM 'false'::jsonb
  THEN RAISE EXCEPTION 'M3_LAST_CASE_NOT_NEGATIVE %',code; END IF;
  mutant_truth:=lf_ops.nucleo_eval_v1(p->'condicion'->'der',bad->'entrada');
  IF mutant_truth IS DISTINCT FROM 'true'::jsonb
  THEN RAISE EXCEPTION 'M3_MUTANT_MISSED_GUARD % actual=%',code,mutant_truth; END IF;
  RAISE NOTICE 'M3_CASES % count=% guard_mutant_detected=true',code,cases;
  applied:=lf_ops.nucleo_regla_proponer_v1(p,true);
  IF applied->>'resultado'<>'CANDIDATA' OR applied->>'version'<>'1'
  THEN RAISE EXCEPTION 'M3_CANONICAL_DOOR_REJECTED % %',code,applied; END IF;
  eval:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  IF eval->>'decision'<>'BLOQUEADA'
    OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(eval->'motivos') m WHERE m->>'dimension'='JUICIO')
  THEN RAISE EXCEPTION 'M3_UNJUDGED_CANDIDATE_MUST_BLOCK % %',code,eval; END IF;
  IF NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_reglas r JOIN lf_ops.nucleo_regla_versiones v ON v.regla=r.codigo
      WHERE r.codigo=code AND r.estado='CANDIDATA' AND r.regla_legacy_id IS NULL
       AND v.version=1 AND v.estado='CANDIDATA' AND v.publicada_desde IS NULL AND v.exigible_desde IS NULL)
  THEN RAISE EXCEPTION 'M3_CANDIDATE_WRITTEN_AS_PUBLISHED %',code; END IF;
  RAISE NOTICE 'M3_CANDIDATE %',jsonb_build_object('code',code,'cases',cases,'decision',eval->>'decision',
            'hash',lf_ops.nucleo_hash_paquete_v1(code,1),'estado','CANDIDATA');
  n:=n+1;
  total_tests:=total_tests+cases;
 END LOOP;
 -- New finding: family keyword matching included unrelated education and Simula semantics.
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='LF-NUCLEO-M3-FINANCIAL-FAMILY-KEYWORD-BLEED-20261123-001')
 THEN RAISE EXCEPTION 'M3_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
 validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-M3-FINANCIAL-FAMILY-KEYWORD-BLEED-20261123-001','NUCLEO_REGLAS',
 'FINANCIAL_INTEGRITY_RECONCILIATION agrupa contenido UI ajeno por palabra clave',
 'Inventario M3 detectó cuatro fuentes UI educativas y de navegación ajenas a la obligación financiera entre 16 legadas.',
 'Clasificación lexical sin verificación semántica de pertinencia de familia','FAMILY_KEYWORD_BLEED',
 'Conservar asociación original, marcar pendiente_validacion y clasificar por obligación antes de crear candidatas; no migrar contenido lateral por palabra clave.',
 'Inventario de 16 fuentes en 15 grupos; cinco grupos migrables; otros requieren definición, migración posterior o Paulo.',
 'HIGH',1,now(),now(),'M3-FINANCIAL-INTEGRITY-20261123','ACTIVO',
 'docs/nucleo/LF_M3_INVENTARIO_16_15_GRUPOS_20261123.md');
 -- EKB: distinct CI defects observed on M3 and protected before merge.
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
   validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES
 ('LF-NUCLEO-M3-CI-LEGACY-FIXTURE-ID-COLLISION-20261123-001','NUCLEO_REGLAS',
  'PG17 fixture de familia nueva colisiona con legadas sintéticas ya sembradas',
  'El primer CI M3 falló por duplicate key en lf_ops.reglas(id) 533, compartida con semillas de regresión anteriores.',
  'Fixture sucesivo que inserta IDs legacy ya presentes en la misma BD aislada.',
  'PG17_FIXTURE_LEGACY_ID_COLLISION',
  'Reusar legadas ya sembradas mediante ON CONFLICT DO NOTHING; validar los 16 enlaces de familia sin escribir datos reales.',
  'PG17 16 IDs, BEGIN/ROLLBACK, readback de fuentes y regresión 17/17 en CI.',
  'HIGH',1,now(),now(),'M3-FINANCIAL-INTEGRITY-20261123','ACTIVO',
  'sandbox/lf_contract_gate_test/nucleo_ci/m3_16_fixture_pg17.sql'),
 ('LF-NUCLEO-M3-CROSS-FAMILY-VOCAB-MISSING-20261123-001','NUCLEO_REGLAS',
  'Hecho tipado global requiere membresía de vocabulario de familia M3',
  'El segundo CI M3 falló en control 4 Datos dentro del vocabulario: estado_pago_normalizado no pertenecía a FINANCIAL_INTEGRITY_RECONCILIATION.',
  'Reutilización de hecho global tipado sin registrar asociación por familia nueva.',
  'NUCLEO_CROSS_FAMILY_VOCAB_MISSING',
  'Antes de proponer regla reusando un hecho global, comprobar tipo y registrar membresía de la familia por la ruta gobernada, sin inventar binding físico.',
  'CI de la misma propuesta en PG17 supera control 4, 22/22 casos y rollback.',
  'HIGH',1,now(),now(),'M3-FINANCIAL-INTEGRITY-20261123','ACTIVO',
  'supabase/migrations/20261123174500_lf_nucleo_m3_financial_candidatas_v1.sql');
 IF (SELECT count(*) FROM public.lf_error_knowledge
     WHERE codigo IN ('LF-NUCLEO-M3-CI-LEGACY-FIXTURE-ID-COLLISION-20261123-001',
       'LF-NUCLEO-M3-CROSS-FAMILY-VOCAB-MISSING-20261123-001'))<>2
 THEN RAISE EXCEPTION 'M3_EKB_INCIDENTS_NOT_RECORDED'; END IF;
 IF n<>5 OR total_tests<>22 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+3
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r WHERE codigo NOT LIKE 'M3-C0%') IS DISTINCT FROM oldrules
  OR (SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones v WHERE regla NOT LIKE 'M3-C0%') IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones d) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(a) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones a WHERE regla NOT LIKE 'M3-C0%') IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(jsonb_build_object('nodo',nd.codigo,'r',to_jsonb(e)) ORDER BY nd.codigo,e.regla)
      FROM lf_ops.nucleo_nodos nd CROSS JOIN LATERAL lf_ops.nucleo_reglas_efectivas_v1(nd.codigo,now()) e)
      IS DISTINCT FROM oldeffective
  OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo='REG_CHK_007')<>'CANDIDATA'
 THEN RAISE EXCEPTION 'M3_UNAUTHORIZED_OR_COVERAGE_DRIFT % %',n,total_tests; END IF;
 RAISE NOTICE 'M3_PASS 5/5 candidate-only; 22/22 positive-negative-boundary, 5 guard mutants; 16 source legadas intactas; 0 deprecations';
END $m2$;
COMMIT;
