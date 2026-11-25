-- S22-H proposal only; independent judgment and promotion before coverage; future links UPSERT.
BEGIN;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22h01_presentacion_aliado','boolean','ninguna','presentacion aliado; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('B2B_PARTNERS','s22h01_presentacion_aliado','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22h01_estado_no_aprobado','boolean','ninguna','estado no aprobado; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('B2B_PARTNERS','s22h01_estado_no_aprobado','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22h02_exposicion_api','boolean','ninguna','exposicion api; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('SECURITY','s22h02_exposicion_api','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22h02_contrato_o_binding_no_verificado','boolean','ninguna','contrato o binding no verificado; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('SECURITY','s22h02_contrato_o_binding_no_verificado','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22h02_ruta_o_metodo_no_autorizado','boolean','ninguna','ruta o metodo no autorizado; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('SECURITY','s22h02_ruta_o_metodo_no_autorizado','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22h02_contexto_autorizacion_invalido','boolean','ninguna','contexto autorizacion invalido; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('SECURITY','s22h02_contexto_autorizacion_invalido','CURADO') ON CONFLICT DO NOTHING;
DO $s22$
DECLARE packs jsonb := $pack$[{"codigo":"S22H-C01","legacy_id":232,"legacy_ids":[232],"relacionadas":["S10-C15","S10-C14"],"residual":"","coberturas":[{"legacy_id":232,"estado_cobertura":"REEMPLAZADA","residual":"","diferencias":"Ante presentación de aliado B2B mediante logo, nombre u oferta en producto BLOQUEAR cuando authorization_status no sea approved, incluyendo pending, draft, rejected, unknown o ausencia de evidencia. No inventar estado ni autorización. S10-C15 conserva autorización documentada para prototipos; S10-C14 conserva condiciones de oferta autorizadas. Binding pendiente."}],"hechos":["s22h01_presentacion_aliado","s22h01_estado_no_aprobado"],"paquete":{"tipo":"NUEVA","codigo":"S22H-C01","clave":"s22h_legacy_232","familia":"B2B_PARTNERS","naturaleza":"CONDUCTA","clase":"TRANSVERSAL","alcance":"BACKEND","modo":"HEREDA","dueno":"TECNICO","titulo":"Visibilidad de aliados autorizados","descripcion":"Ante presentación de aliado B2B mediante logo, nombre u oferta en producto BLOQUEAR cuando authorization_status no sea approved, incluyendo pending, draft, rejected, unknown o ausencia de evidencia. No inventar estado ni autorización. S10-C15 conserva autorización documentada para prototipos; S10-C14 conserva condiciones de oferta autorizadas. Binding pendiente.","efecto":"BLOQUEAR","autoridad":"LEG-TECNICO","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/232","solicitante":"Cristhian / Claude S22-H 2026-11-25"},"condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"s22h01_presentacion_aliado"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"s22h01_estado_no_aprobado"},"der":{"lit":true}}},"pruebas":[{"casuistica":"NO_SE_CUMPLE","entrada":{"s22h01_presentacion_aliado":true,"s22h01_estado_no_aprobado":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"s22h01_presentacion_aliado":true,"s22h01_estado_no_aprobado":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"s22h01_presentacion_aliado":false,"s22h01_estado_no_aprobado":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"s22h01_presentacion_aliado":false,"s22h01_estado_no_aprobado":false},"esperado":false}]},"hash":"19efdde10de4c4597b3c00b7f8b1f56713e85efa4cc239a722bf7ee6c6881bc3","hash_paquete":"73ead5ae785a840243e32da3506651409178257e69b5b304c765cd19178312d9","hash_evaluado":"19efdde10d","hash_paquete_10":"73ead5ae78","puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"complementa S10-C14 y S10-C15, declarado"},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S22H-C02","legacy_id":214,"legacy_ids":[214,215,216],"relacionadas":[],"residual":"Falta acreditar que las rutas y métodos históricos coincidan con el contrato canónico vigente de onboarding.","coberturas":[{"legacy_id":214,"estado_cobertura":"PARCIAL","residual":"Falta acreditar que las rutas y métodos históricos coincidan con el contrato canónico vigente de onboarding.","diferencias":"Ante exposición de rutas API de onboarding, ofertas o pagos BLOQUEAR declarar disponibles endpoints históricos sin contrato vigente y binding verificado. En contrato autorizado exigir POST start, verify-otp, resend-otp; PATCH update-phone; GET home-variant de /api/v1/onboarding; GET /api/v1/offers; POST /api/v1/checkout/initiate y confirm; GET /api/v1/checkout/status/{id} y /api/v1/carta-no-adeudo/{offer_id}, únicamente si corresponden a rutas canónicas aprobadas. Start público; verify-otp, resend-otp y update-phone requieren contexto session_id validado server-side; ofertas, checkout y carta requieren autenticación JWT y autorización efectiva de recurso. No convierte session_id aislado en autorización ni certifica endpoints existentes. Binding pendiente."},{"legacy_id":215,"estado_cobertura":"PARCIAL","residual":"Falta acreditar que las rutas y métodos históricos coincidan con el contrato canónico vigente de ofertas, pagos y documentos.","diferencias":"Ante exposición de rutas API de onboarding, ofertas o pagos BLOQUEAR declarar disponibles endpoints históricos sin contrato vigente y binding verificado. En contrato autorizado exigir POST start, verify-otp, resend-otp; PATCH update-phone; GET home-variant de /api/v1/onboarding; GET /api/v1/offers; POST /api/v1/checkout/initiate y confirm; GET /api/v1/checkout/status/{id} y /api/v1/carta-no-adeudo/{offer_id}, únicamente si corresponden a rutas canónicas aprobadas. Start público; verify-otp, resend-otp y update-phone requieren contexto session_id validado server-side; ofertas, checkout y carta requieren autenticación JWT y autorización efectiva de recurso. No convierte session_id aislado en autorización ni certifica endpoints existentes. Binding pendiente."},{"legacy_id":216,"estado_cobertura":"PARCIAL","residual":"Falta verificar contrato runtime de autenticación y autorización de todas las rutas históricas; no se afirma equivalencia física.","diferencias":"Ante exposición de rutas API de onboarding, ofertas o pagos BLOQUEAR declarar disponibles endpoints históricos sin contrato vigente y binding verificado. En contrato autorizado exigir POST start, verify-otp, resend-otp; PATCH update-phone; GET home-variant de /api/v1/onboarding; GET /api/v1/offers; POST /api/v1/checkout/initiate y confirm; GET /api/v1/checkout/status/{id} y /api/v1/carta-no-adeudo/{offer_id}, únicamente si corresponden a rutas canónicas aprobadas. Start público; verify-otp, resend-otp y update-phone requieren contexto session_id validado server-side; ofertas, checkout y carta requieren autenticación JWT y autorización efectiva de recurso. No convierte session_id aislado en autorización ni certifica endpoints existentes. Binding pendiente."}],"hechos":["s22h02_exposicion_api","s22h02_contrato_o_binding_no_verificado","s22h02_ruta_o_metodo_no_autorizado","s22h02_contexto_autorizacion_invalido"],"paquete":{"tipo":"NUEVA","codigo":"S22H-C02","clave":"s22h_legacy_214","familia":"SECURITY","naturaleza":"CONDUCTA","clase":"TRANSVERSAL","alcance":"BACKEND","modo":"HEREDA","dueno":"TECNICO","titulo":"Contratos históricos de rutas API con autorización por contexto","descripcion":"Ante exposición de rutas API de onboarding, ofertas o pagos BLOQUEAR declarar disponibles endpoints históricos sin contrato vigente y binding verificado. En contrato autorizado exigir POST start, verify-otp, resend-otp; PATCH update-phone; GET home-variant de /api/v1/onboarding; GET /api/v1/offers; POST /api/v1/checkout/initiate y confirm; GET /api/v1/checkout/status/{id} y /api/v1/carta-no-adeudo/{offer_id}, únicamente si corresponden a rutas canónicas aprobadas. Start público; verify-otp, resend-otp y update-phone requieren contexto session_id validado server-side; ofertas, checkout y carta requieren autenticación JWT y autorización efectiva de recurso. No convierte session_id aislado en autorización ni certifica endpoints existentes. Binding pendiente.","efecto":"BLOQUEAR","autoridad":"LEG-TECNICO","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/214;lf_ops.reglas/215;lf_ops.reglas/216","solicitante":"Cristhian / Claude S22-H 2026-11-25"},"condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"s22h02_exposicion_api"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"=","izq":{"hecho":"s22h02_contrato_o_binding_no_verificado"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"s22h02_ruta_o_metodo_no_autorizado"},"der":{"lit":true}}},"der":{"op":"=","izq":{"hecho":"s22h02_contexto_autorizacion_invalido"},"der":{"lit":true}}}},"pruebas":[{"casuistica":"NO_SE_CUMPLE","entrada":{"s22h02_exposicion_api":true,"s22h02_contrato_o_binding_no_verificado":false,"s22h02_ruta_o_metodo_no_autorizado":false,"s22h02_contexto_autorizacion_invalido":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"s22h02_exposicion_api":true,"s22h02_contrato_o_binding_no_verificado":true,"s22h02_ruta_o_metodo_no_autorizado":false,"s22h02_contexto_autorizacion_invalido":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22h02_exposicion_api":true,"s22h02_contrato_o_binding_no_verificado":false,"s22h02_ruta_o_metodo_no_autorizado":true,"s22h02_contexto_autorizacion_invalido":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22h02_exposicion_api":true,"s22h02_contrato_o_binding_no_verificado":false,"s22h02_ruta_o_metodo_no_autorizado":false,"s22h02_contexto_autorizacion_invalido":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"s22h02_exposicion_api":false,"s22h02_contrato_o_binding_no_verificado":true,"s22h02_ruta_o_metodo_no_autorizado":true,"s22h02_contexto_autorizacion_invalido":true},"esperado":false}]},"hash":"b4a666d4601e41f6bc10dcf9cac392d1292a3e946a62d463b3f18d47bb5381e1","hash_paquete":"6d1303bcc34eb6b06c6ebf54adf00e058fcbf3a665a524a9942b5d15db49f5a7","hash_evaluado":"b4a666d460","hash_paquete_10":"6d1303bcc3","puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.9,"observacion":"contrato canónico y binding de rutas pendientes de Paulo"},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"relacionada con S9-C21 CORS, declarado"},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}}]$pack$::jsonb; p jsonb; a jsonb; ans jsonb; cd text; h text; t record; n int:=0; vectors int:=0; b_leg jsonb; b_dep jsonb; b_cfg jsonb; val jsonb; lid int; residual text; diff text; old_desc text; new_desc text; links int:=0; before_replaced int; after_replaced int; direct_hash text; c jsonb;
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
 val:=jsonb_build_object('regla',cd,'hash_evaluado',h,'veredicto','PASS','puntajes',p->'puntajes','juez','Claude','modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,'evidencia_ref','PR #4764 / Claude 2026-11-25 14:38 Lima / '||cd||' / hash_paquete_10='||(p->>'hash_paquete_10'));
 BEGIN
 PERFORM lf_ops.nucleo_juicio_registrar_v1(val||jsonb_build_object('hash_evaluado',repeat('0',64)));
 RAISE EXCEPTION 'S22H_NEGATIVE_HASH_ACCEPTED %',cd;
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF; END;
 PERFORM lf_ops.nucleo_juicio_registrar_v1(val);
 ans:=lf_ops.nucleo_regla_evaluar_v1(cd,true);
 IF ans->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'S22H_NOT_AUTO % %',cd,ans; END IF;
 ans:=lf_ops.nucleo_regla_promover_v1(cd);
 IF ans->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22H_PROMOTION_FAIL % %',cd,ans; END IF;
 n:=n+1;
 END LOOP;
 IF n<>2 OR vectors<>9 THEN RAISE EXCEPTION 'S22_VECTOR_COUNT'; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM lf_ops.reglas x) IS DISTINCT FROM b_leg OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones x) IS DISTINCT FROM b_dep OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.lf_global_config x) IS DISTINCT FROM b_cfg THEN RAISE EXCEPTION 'S22_INVARIANT_FAIL'; END IF;
 IF jsonb_array_length(lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS')->'nativas') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'S22_DPIG03_FAIL'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements(packs) LOOP
 cd:=p->>'codigo'; h:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF h IS DISTINCT FROM p->>'hash_paquete' THEN RAISE EXCEPTION 'S22H_COVERAGE_HASH_DRIFT %',cd; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(p->'coberturas') LOOP
 lid:=(c->>'legacy_id')::int; residual:=c->>'residual'; diff:=c->>'diferencias';
 IF length(diff)<30 OR c->>'estado_cobertura' NOT IN ('REEMPLAZADA','PARCIAL') OR (c->>'estado_cobertura'='REEMPLAZADA' AND residual IS DISTINCT FROM '') OR (c->>'estado_cobertura'='PARCIAL' AND coalesce(length(residual),0)<15) THEN RAISE EXCEPTION 'S22H_COVERAGE_CONTRACT %',lid; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,c->>'estado_cobertura',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||(p->'paquete'->>'descripcion')||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:38 Lima'),h,'GPT / Claude S22-H independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22H_SOURCE_MISSING %',lid; END IF;
 END LOOP;
 END LOOP;
 cd:='S10-C06'; lid:=206;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22H_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S10-C06 gobierna transiciones de onboarding con referencias de configuración y movimiento reducido; S8-C21 gobierna Home.'; residual:='Falta acreditar aplicación a componentes y pantallas restantes fuera del alcance de ambas reglas.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22H_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:38 Lima'),direct_hash,'GPT / Claude S22-H independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22H_SOURCE_MISSING %',lid; END IF;
 cd:='S9-C21'; lid:=218;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22H_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S9-C21 prohíbe wildcard productivo y orígenes no autorizados, y exige métodos y headers del contrato vigente.'; residual:='Falta acreditar allowlist exacta de dominios producción y staging, métodos GET POST PATCH y headers Content-Type Authorization X-Idempotency-Key.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22H_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:38 Lima'),direct_hash,'GPT / Claude S22-H independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22H_SOURCE_MISSING %',lid; END IF;
 cd:='S11-C10'; lid:=246;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22H_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S11-C10 exige precio final de backend y mismo checkout desde el modal de detalle.'; residual:='Falta acreditar todos los componentes del precio final, referencias vigentes de comisiones e impuestos y ausencia de costos sorpresa en checkout.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22H_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:38 Lima'),direct_hash,'GPT / Claude S22-H independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22H_SOURCE_MISSING %',lid; END IF;
 cd:='S4-C25'; lid:=248;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,2);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=2 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22H_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=2;
 diff:='S4-C25 gobierna ahorro monetario y porcentual de plan con datos autoritativos y bloquea descuento inexistente.'; residual:='Falta fórmula sobre precio final de oferta y copy Ahorras realmente; no equivale necesariamente a monto_total_plan.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22H_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,2,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:38 Lima'),direct_hash,'GPT / Claude S22-H independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22H_SOURCE_MISSING %',lid; END IF;
 cd:='S22B-C01'; lid:=275;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22H_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S22B-C01 exige autorización contractual de marcas de medios de pago en producción y no habilita Mastercard por defecto.'; residual:='Falta acreditar lista de placeholders Visa Amex Diners de versión prototipo y exclusión específica de Mastercard de esa versión.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22H_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:38 Lima'),direct_hash,'GPT / Claude S22-H independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22H_SOURCE_MISSING %',lid; END IF;
 cd:='S11-C14'; lid:=282;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22H_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S11-C14 exige identificación Procesado de forma segura por Niubiz junto al CTA cuando integración autorizada.'; residual:='Falta texto bajo opciones de tarjeta y logo Niubiz en footer de seguridad con autorización vigente.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22H_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 14:38 Lima'),direct_hash,'GPT / Claude S22-H independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22H_SOURCE_MISSING %',lid; END IF;
 SELECT count(DISTINCT legacy_id) INTO after_replaced FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 IF (SELECT count(*) FROM lf_ops.reglas)=586 AND (links<>10 OR after_replaced<>before_replaced+1) THEN RAISE EXCEPTION 'S22H_COVERAGE_READBACK_FAIL links=% before=% after=%',links,before_replaced,after_replaced; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM lf_ops.reglas x) IS DISTINCT FROM b_leg OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones x) IS DISTINCT FROM b_dep OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.lf_global_config x) IS DISTINCT FROM b_cfg THEN RAISE EXCEPTION 'S22H_POST_COVERAGE_INVARIANT_FAIL'; END IF;
 RAISE NOTICE 'S22H_PASS 2 JUICIOS 2 AUTO 9 VECTORES links=% replaced=% DPIG03=0',links,after_replaced;
END $s22$;
COMMIT;
