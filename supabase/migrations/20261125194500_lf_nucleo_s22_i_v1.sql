-- S22-I proposal only; independent judgment and promotion before coverage; future links UPSERT.
BEGIN;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i01_render_error_pago','boolean','ninguna','render error pago; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i01_render_error_pago','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i01_copy_no_corresponde_outcome','boolean','ninguna','copy no corresponde outcome; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i01_copy_no_corresponde_outcome','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i01_claim_sin_cargo_no_acreditado','boolean','ninguna','claim sin cargo no acreditado; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i01_claim_sin_cargo_no_acreditado','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i01_pendiente_en_error','boolean','ninguna','pendiente en error; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i01_pendiente_en_error','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i02_error_confirmado_o_previo','boolean','ninguna','error confirmado o previo; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i02_error_confirmado_o_previo','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i02_seleccion_vigente_perdida','boolean','ninguna','seleccion vigente perdida; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i02_seleccion_vigente_perdida','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i02_expirado_sin_revalidar','boolean','ninguna','expirado sin revalidar; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i02_expirado_sin_revalidar','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i02_activacion_sin_confirmar','boolean','ninguna','activacion sin confirmar; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i02_activacion_sin_confirmar','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i03_soporte_error_pago','boolean','ninguna','soporte error pago; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i03_soporte_error_pago','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i03_referencia_invalida','boolean','ninguna','referencia invalida; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i03_referencia_invalida','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i03_bloquea_sin_referencia','boolean','ninguna','bloquea sin referencia; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i03_bloquea_sin_referencia','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22i03_claim_disponibilidad_no_acreditado','boolean','ninguna','claim disponibilidad no acreditado; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','s22i03_claim_disponibilidad_no_acreditado','CURADO') ON CONFLICT DO NOTHING;
DO $s22$
DECLARE packs jsonb := $pack$[{"codigo":"S22I-C01","legacy_id":333,"legacy_ids":[333],"relacionadas":["S3-C19"],"residual":"","coberturas":[{"legacy_id":333,"estado_cobertura":"REEMPLAZADA","residual":"","diferencias":"En CHECKOUT_ERROR_PAGO BLOQUEAR copy que no corresponda al outcome server-side. PAYMENT_DECLINED_CONFIRMED: Tu pago no fue aprobado; El intento terminó con un rechazo confirmado. Tu plan aún no fue activado. No afirmar ausencia de cargo sin evidencia. PAYMENT_NOT_SUBMITTED: No pudimos iniciar el pago; El intento no llegó al circuito de pago. Tu plan y tu selección se mantienen. PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT: No pudimos iniciar el pago; El servicio de pago no está disponible antes de enviar el intento. Tu selección se mantiene. PAYMENT_PENDING_CONFIRMATION dirige a CHECKOUT_ESTADO_CONFIRMANDO, nunca a error. Complementa S3-C19, sin redefinir outcome ni implementar binding."}],"hechos":["s22i01_render_error_pago","s22i01_copy_no_corresponde_outcome","s22i01_claim_sin_cargo_no_acreditado","s22i01_pendiente_en_error"],"paquete":{"tipo":"NUEVA","codigo":"S22I-C01","clave":"s22i_legacy_333","familia":"PAYMENTS_CHECKOUT","naturaleza":"CONDUCTA","clase":"PANTALLA","alcance":"CLIENT_PAYMENTS","modo":"HEREDA","dueno":"PRODUCTO","titulo":"Copy de error de pago por outcome autoritativo","descripcion":"En CHECKOUT_ERROR_PAGO BLOQUEAR copy que no corresponda al outcome server-side. PAYMENT_DECLINED_CONFIRMED: Tu pago no fue aprobado; El intento terminó con un rechazo confirmado. Tu plan aún no fue activado. No afirmar ausencia de cargo sin evidencia. PAYMENT_NOT_SUBMITTED: No pudimos iniciar el pago; El intento no llegó al circuito de pago. Tu plan y tu selección se mantienen. PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT: No pudimos iniciar el pago; El servicio de pago no está disponible antes de enviar el intento. Tu selección se mantiene. PAYMENT_PENDING_CONFIRMATION dirige a CHECKOUT_ESTADO_CONFIRMANDO, nunca a error. Complementa S3-C19, sin redefinir outcome ni implementar binding.","efecto":"BLOQUEAR","autoridad":"LEG-PRODUCTO","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/333","solicitante":"Cristhian / Claude S22-I 2026-11-25"},"condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"s22i01_render_error_pago"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"=","izq":{"hecho":"s22i01_copy_no_corresponde_outcome"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"s22i01_claim_sin_cargo_no_acreditado"},"der":{"lit":true}}},"der":{"op":"=","izq":{"hecho":"s22i01_pendiente_en_error"},"der":{"lit":true}}}},"pruebas":[{"casuistica":"NO_SE_CUMPLE","entrada":{"s22i01_render_error_pago":true,"s22i01_copy_no_corresponde_outcome":false,"s22i01_claim_sin_cargo_no_acreditado":false,"s22i01_pendiente_en_error":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"s22i01_render_error_pago":true,"s22i01_copy_no_corresponde_outcome":true,"s22i01_claim_sin_cargo_no_acreditado":false,"s22i01_pendiente_en_error":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22i01_render_error_pago":true,"s22i01_copy_no_corresponde_outcome":false,"s22i01_claim_sin_cargo_no_acreditado":true,"s22i01_pendiente_en_error":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22i01_render_error_pago":true,"s22i01_copy_no_corresponde_outcome":false,"s22i01_claim_sin_cargo_no_acreditado":false,"s22i01_pendiente_en_error":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"s22i01_render_error_pago":false,"s22i01_copy_no_corresponde_outcome":true,"s22i01_claim_sin_cargo_no_acreditado":true,"s22i01_pendiente_en_error":true},"esperado":false}]},"hash":"2fce2d50b506d07b623b45d18c726bf643a124831ad52ef9c25d6bc69e0ca585","hash_paquete":"118762154a8602048f4a549937ea48791b646327c7c02fae666d5f2298c1e8ff","hash_evaluado":"2fce2d50b5","hash_paquete_10":"118762154a","puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S22I-C02","legacy_id":336,"legacy_ids":[336],"relacionadas":["S6-C24","S3-C20"],"residual":"","coberturas":[{"legacy_id":336,"estado_cobertura":"REEMPLAZADA","residual":"","diferencias":"En error PAYMENT_DECLINED_CONFIRMED, PAYMENT_NOT_SUBMITTED o PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT BLOQUEAR pérdida de selección validada, plan y fecha mientras estén vigentes, reintento sin nueva validación backend al expirar quote u oferta, o presentación de plan activado sin PAYMENT_CONFIRMED. Complementa S6-C24 y S3-C20; no autoriza reintento por sí solo ni modifica outcomes. Binding pendiente."}],"hechos":["s22i02_error_confirmado_o_previo","s22i02_seleccion_vigente_perdida","s22i02_expirado_sin_revalidar","s22i02_activacion_sin_confirmar"],"paquete":{"tipo":"NUEVA","codigo":"S22I-C02","clave":"s22i_legacy_336","familia":"PAYMENTS_CHECKOUT","naturaleza":"CONDUCTA","clase":"PANTALLA","alcance":"CLIENT_PAYMENTS","modo":"HEREDA","dueno":"PRODUCTO","titulo":"Preservación de selección válida tras error de pago","descripcion":"En error PAYMENT_DECLINED_CONFIRMED, PAYMENT_NOT_SUBMITTED o PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT BLOQUEAR pérdida de selección validada, plan y fecha mientras estén vigentes, reintento sin nueva validación backend al expirar quote u oferta, o presentación de plan activado sin PAYMENT_CONFIRMED. Complementa S6-C24 y S3-C20; no autoriza reintento por sí solo ni modifica outcomes. Binding pendiente.","efecto":"BLOQUEAR","autoridad":"LEG-PRODUCTO","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/336","solicitante":"Cristhian / Claude S22-I 2026-11-25"},"condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"s22i02_error_confirmado_o_previo"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"=","izq":{"hecho":"s22i02_seleccion_vigente_perdida"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"s22i02_expirado_sin_revalidar"},"der":{"lit":true}}},"der":{"op":"=","izq":{"hecho":"s22i02_activacion_sin_confirmar"},"der":{"lit":true}}}},"pruebas":[{"casuistica":"NO_SE_CUMPLE","entrada":{"s22i02_error_confirmado_o_previo":true,"s22i02_seleccion_vigente_perdida":false,"s22i02_expirado_sin_revalidar":false,"s22i02_activacion_sin_confirmar":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"s22i02_error_confirmado_o_previo":true,"s22i02_seleccion_vigente_perdida":true,"s22i02_expirado_sin_revalidar":false,"s22i02_activacion_sin_confirmar":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22i02_error_confirmado_o_previo":true,"s22i02_seleccion_vigente_perdida":false,"s22i02_expirado_sin_revalidar":true,"s22i02_activacion_sin_confirmar":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22i02_error_confirmado_o_previo":true,"s22i02_seleccion_vigente_perdida":false,"s22i02_expirado_sin_revalidar":false,"s22i02_activacion_sin_confirmar":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"s22i02_error_confirmado_o_previo":false,"s22i02_seleccion_vigente_perdida":true,"s22i02_expirado_sin_revalidar":true,"s22i02_activacion_sin_confirmar":true},"esperado":false}]},"hash":"b38bd8d08ce7a7249255673ce1e252682899b8621ce0baf56f171b4673dc62c2","hash_paquete":"716b2056d0166e741019348b810b6460698294139b364d2164b13c2932abd5cf","hash_evaluado":"b38bd8d08c","hash_paquete_10":"716b2056d0","puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S22I-C03","legacy_id":338,"legacy_ids":[338],"relacionadas":["S5-C18","S14-C02"],"residual":"","coberturas":[{"legacy_id":338,"estado_cobertura":"REEMPLAZADA","residual":"","diferencias":"En CHECKOUT_ERROR_PAGO permitir soporte auxiliar. BLOQUEAR contexto de contacto que invente referencia o incluya una referencia sensible/no canónica; si no existe referencia, iniciar soporte sin identificador. BLOQUEAR afirmar soporte 24/7 sin evidencia operacional. Complementa S5-C18 y S14-C02; no habilita canales no autorizados. Binding pendiente."}],"hechos":["s22i03_soporte_error_pago","s22i03_referencia_invalida","s22i03_bloquea_sin_referencia","s22i03_claim_disponibilidad_no_acreditado"],"paquete":{"tipo":"NUEVA","codigo":"S22I-C03","clave":"s22i_legacy_338","familia":"PAYMENTS_CHECKOUT","naturaleza":"CONDUCTA","clase":"PANTALLA","alcance":"CLIENT_PAYMENTS","modo":"HEREDA","dueno":"PRODUCTO","titulo":"Soporte contextual de error de pago","descripcion":"En CHECKOUT_ERROR_PAGO permitir soporte auxiliar. BLOQUEAR contexto de contacto que invente referencia o incluya una referencia sensible/no canónica; si no existe referencia, iniciar soporte sin identificador. BLOQUEAR afirmar soporte 24/7 sin evidencia operacional. Complementa S5-C18 y S14-C02; no habilita canales no autorizados. Binding pendiente.","efecto":"BLOQUEAR","autoridad":"LEG-PRODUCTO","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/338","solicitante":"Cristhian / Claude S22-I 2026-11-25"},"condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"s22i03_soporte_error_pago"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"=","izq":{"hecho":"s22i03_referencia_invalida"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"s22i03_bloquea_sin_referencia"},"der":{"lit":true}}},"der":{"op":"=","izq":{"hecho":"s22i03_claim_disponibilidad_no_acreditado"},"der":{"lit":true}}}},"pruebas":[{"casuistica":"NO_SE_CUMPLE","entrada":{"s22i03_soporte_error_pago":true,"s22i03_referencia_invalida":false,"s22i03_bloquea_sin_referencia":false,"s22i03_claim_disponibilidad_no_acreditado":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"s22i03_soporte_error_pago":true,"s22i03_referencia_invalida":true,"s22i03_bloquea_sin_referencia":false,"s22i03_claim_disponibilidad_no_acreditado":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22i03_soporte_error_pago":true,"s22i03_referencia_invalida":false,"s22i03_bloquea_sin_referencia":true,"s22i03_claim_disponibilidad_no_acreditado":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22i03_soporte_error_pago":true,"s22i03_referencia_invalida":false,"s22i03_bloquea_sin_referencia":false,"s22i03_claim_disponibilidad_no_acreditado":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"s22i03_soporte_error_pago":false,"s22i03_referencia_invalida":true,"s22i03_bloquea_sin_referencia":true,"s22i03_claim_disponibilidad_no_acreditado":true},"esperado":false}]},"hash":"7ce5b2df285140e1193ef9d7d38b987be7352bfa18a0c59cc31ba1d90104cc97","hash_paquete":"9fb0dffefb093fe18f991722e74cebe454668d3dcb2fbfc21132105c1daf7770","hash_evaluado":"7ce5b2df28","hash_paquete_10":"9fb0dffefb","puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}}]$pack$::jsonb; p jsonb; a jsonb; ans jsonb; cd text; h text; t record; n int:=0; vectors int:=0; b_leg jsonb; b_dep jsonb; b_cfg jsonb; val jsonb; lid int; residual text; diff text; old_desc text; new_desc text; links int:=0; before_replaced int; after_replaced int; direct_hash text; c jsonb;
BEGIN
 SELECT count(DISTINCT legacy_id) INTO before_replaced FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO b_leg FROM lf_ops.reglas x;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY regla,version) INTO b_dep FROM lf_ops.nucleo_deprecaciones x;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) INTO b_cfg FROM public.lf_global_config x;
 FOR p IN SELECT value FROM jsonb_array_elements(packs) LOOP
 a:=p->'paquete'; cd:=p->>'codigo';
 IF EXISTS(WITH RECURSIVE anc AS (SELECT codigo,padre FROM lf_ops.nucleo_nodos WHERE pantalla_id=36 UNION ALL SELECT nn.codigo,nn.padre FROM lf_ops.nucleo_nodos nn JOIN anc z ON nn.codigo=z.padre) SELECT 1 FROM anc WHERE codigo=a->>'alcance') THEN RAISE EXCEPTION 'S22_SCOPE_P36 %',cd; END IF;
 ans:=lf_ops.nucleo_regla_proponer_v1(a,true);
 IF ans->>'resultado' IS DISTINCT FROM 'CANDIDATA' OR (ans->>'version')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'S22_PROPOSAL_FAIL % %',cd,ans; END IF;
 ans:=lf_ops.nucleo_regla_evaluar_v1(cd,true); h:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF h IS DISTINCT FROM p->>'hash_paquete' OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='CANDIDATA' AND hash=p->>'hash') THEN RAISE EXCEPTION 'S22_ATTESTATION_DRIFT %',cd; END IF;
 FOR t IN SELECT entrada,esperado FROM lf_ops.nucleo_regla_pruebas WHERE regla=cd AND version=1 LOOP
 IF lf_ops.nucleo_eval_v1(a->'condicion',t.entrada) IS DISTINCT FROM t.esperado THEN RAISE EXCEPTION 'S22_VECTOR_FAIL %',cd; END IF; vectors:=vectors+1; END LOOP;
 val:=jsonb_build_object('regla',cd,'hash_evaluado',h,'veredicto','PASS','puntajes',p->'puntajes','juez','Claude','modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,'evidencia_ref','PR #4765 / Claude 2026-11-25 14:44 Lima / '||cd||' / hash_paquete_10='||(p->>'hash_paquete_10'));
 BEGIN
 PERFORM lf_ops.nucleo_juicio_registrar_v1(val||jsonb_build_object('hash_evaluado',repeat('0',64)));
 RAISE EXCEPTION 'S22I_NEGATIVE_HASH_ACCEPTED %',cd;
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF; END;
 PERFORM lf_ops.nucleo_juicio_registrar_v1(val);
 ans:=lf_ops.nucleo_regla_evaluar_v1(cd,true);
 IF ans->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'S22I_NOT_AUTO % %',cd,ans; END IF;
 ans:=lf_ops.nucleo_regla_promover_v1(cd);
 IF ans->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22I_PROMOTION_FAIL % %',cd,ans; END IF;
 n:=n+1;
 END LOOP;
 IF n<>3 OR vectors<>15 THEN RAISE EXCEPTION 'S22_VECTOR_COUNT'; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM lf_ops.reglas x) IS DISTINCT FROM b_leg OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones x) IS DISTINCT FROM b_dep OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.lf_global_config x) IS DISTINCT FROM b_cfg THEN RAISE EXCEPTION 'S22_INVARIANT_FAIL'; END IF;
 IF jsonb_array_length(lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS')->'nativas') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'S22_DPIG03_FAIL'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements(packs) LOOP
 cd:=p->>'codigo'; h:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF h IS DISTINCT FROM p->>'hash_paquete' THEN RAISE EXCEPTION 'S22I_COVERAGE_HASH_DRIFT %',cd; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(p->'coberturas') LOOP
 lid:=(c->>'legacy_id')::int; residual:=c->>'residual'; diff:=c->>'diferencias';
 IF length(diff)<30 OR c->>'estado_cobertura' NOT IN ('REEMPLAZADA','PARCIAL') OR (c->>'estado_cobertura'='REEMPLAZADA' AND residual IS DISTINCT FROM '') OR (c->>'estado_cobertura'='PARCIAL' AND coalesce(length(residual),0)<15) THEN RAISE EXCEPTION 'S22I_COVERAGE_CONTRACT %',lid; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,c->>'estado_cobertura',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||(p->'paquete'->>'descripcion')||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:44 Lima'),h,'GPT / Claude S22-I independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22I_SOURCE_MISSING %',lid; END IF;
 END LOOP;
 END LOOP;
 cd:='S6-C13'; lid:=315;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22I_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S6-C13 exige SDK oficial, iframe o campos hospedados autorizados y bloquea captura PAN/CVV por LF.'; residual:='Falta fijar iframe Niubiz exclusivo con fecha, titular, número y CVV sin acceso LF en ningún momento.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22I_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:44 Lima'),direct_hash,'GPT / Claude S22-I independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22I_SOURCE_MISSING %',lid; END IF;
 cd:='REG_CHK_005'; lid:=324;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,3);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=3 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22I_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=3;
 diff:='REG_CHK_005 protege render exitoso con confirmación, referencia, fecha y monto autoritativos.'; residual:='Falta título, subtítulo y copy motivacional literales exclusivos de activación del plan de cuotas.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22I_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,3,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:44 Lima'),direct_hash,'GPT / Claude S22-I independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22I_SOURCE_MISSING %',lid; END IF;
 cd:='REG_CHK_005'; lid:=325;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,3);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=3 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22I_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=3;
 diff:='REG_CHK_005 exige referencia, fecha y monto real verificados antes de éxito; S5-C18 prohíbe referencia inventada.'; residual:='Falta formato de pedido LF-XXXX-XXXX validado, metadatos enmascarados autorizados, últimos cuatro dígitos, solo lectura y formato de fecha/hora.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22I_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,3,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:44 Lima'),direct_hash,'GPT / Claude S22-I independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22I_SOURCE_MISSING %',lid; END IF;
 cd:='S6-C17'; lid:=326;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22I_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S6-C17 permite descarga de cronograma solo si backend dispone del documento oficial.'; residual:='Falta generación backend de los tres PDF y evidencia de disponibilidad inmediata; no prometer documentos inexistentes.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22I_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:44 Lima'),direct_hash,'GPT / Claude S22-I independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22I_SOURCE_MISSING %',lid; END IF;
 cd:='S3-C19'; lid:=334;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22I_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S3-C19 bloquea intentos alternativos o equivalentes mientras resultado sea pendiente de confirmación.'; residual:='Falta contrato UI de flags server-side para mostrar/habilitar reintento y cambio de medio, y soporte auxiliar.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22I_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:44 Lima'),direct_hash,'GPT / Claude S22-I independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22I_SOURCE_MISSING %',lid; END IF;
 cd:='S5-C18'; lid:=335;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22I_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S5-C18 exige referencia canónica emitida o reservada por backend y no la exige en estado transitorio.'; residual:='Falta contrato explícito de CHECKOUT_ERROR_PAGO para monto autoritativo y ausencia de referencia ante falla previa al envío.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22I_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:44 Lima'),direct_hash,'GPT / Claude S22-I independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22I_SOURCE_MISSING %',lid; END IF;
 cd:='REG_CHK_008'; lid:=337;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,3);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=3 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22I_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=3;
 diff:='REG_CHK_008 exige SETTLED_CONFIRMED y estado documental ELIGIBLE para iniciar generación de carta.'; residual:='Falta estado NOT_ELIGIBLE explícito de plan no activado en pantalla de error y prohibición de usarlo como incentivo.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22I_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,3,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:44 Lima'),direct_hash,'GPT / Claude S22-I independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22I_SOURCE_MISSING %',lid; END IF;
 SELECT count(DISTINCT legacy_id) INTO after_replaced FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 IF (SELECT count(*) FROM lf_ops.reglas)=586 AND (links<>10 OR after_replaced<>before_replaced+3) THEN RAISE EXCEPTION 'S22I_COVERAGE_READBACK_FAIL links=% before=% after=%',links,before_replaced,after_replaced; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM lf_ops.reglas x) IS DISTINCT FROM b_leg OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones x) IS DISTINCT FROM b_dep OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.lf_global_config x) IS DISTINCT FROM b_cfg THEN RAISE EXCEPTION 'S22I_POST_COVERAGE_INVARIANT_FAIL'; END IF;
 RAISE NOTICE 'S22I_PASS 3 JUICIOS 3 AUTO 15 VECTORES links=% replaced=% DPIG03=0',links,after_replaced;
END $s22$;
COMMIT;
