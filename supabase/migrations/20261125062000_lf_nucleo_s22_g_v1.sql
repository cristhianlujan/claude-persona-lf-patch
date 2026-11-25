-- S22-G proposal only; independent judgment and promotion before coverage; future links UPSERT.
BEGIN;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22g01_publicacion_referencia','boolean','ninguna','publicacion referencia; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('SECURITY','s22g01_publicacion_referencia','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22g01_repositorio_publico','boolean','ninguna','repositorio publico; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('SECURITY','s22g01_repositorio_publico','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22g01_variable_cliente_no_protegida','boolean','ninguna','variable cliente no protegida; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('SECURITY','s22g01_variable_cliente_no_protegida','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22g01_analitica_tercero','boolean','ninguna','analitica tercero; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('SECURITY','s22g01_analitica_tercero','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22g02_instrumentacion_paso1','boolean','ninguna','instrumentacion paso1; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('ANALYTICS','s22g02_instrumentacion_paso1','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22g02_evento_accion_omitido','boolean','ninguna','evento accion omitido; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('ANALYTICS','s22g02_evento_accion_omitido','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22g02_evento_sin_accion','boolean','ninguna','evento sin accion; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('ANALYTICS','s22g02_evento_sin_accion','CURADO') ON CONFLICT DO NOTHING;
INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('s22g02_evento_con_pii','boolean','ninguna','evento con pii; hecho derivado, binding runtime pendiente');
INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('ANALYTICS','s22g02_evento_con_pii','CURADO') ON CONFLICT DO NOTHING;
DO $s22$
DECLARE packs jsonb := $pack$[{"codigo":"S22G-C01","legacy_id":135,"legacy_ids":[135],"relacionadas":["S2-C05"],"residual":"rls_obligatorio de la legada no cubierto por el paquete","coberturas":[{"legacy_id":135,"estado_cobertura":"PARCIAL","residual":"rls_obligatorio de la legada no cubierto por el paquete","diferencias":"Ante publicación de referencias de proyecto Supabase o anon key BLOQUEAR exposición en repositorios públicos, variables cliente sin protección o herramientas de análisis de terceros. No equiparar anon key autorizada a credencial privilegiada ni prohibir su uso legítimo por adaptador cliente autorizado; no inventar mecanismo de protección. Binding pendiente.; rls_obligatorio=true en valor_config de la legada no cubierto por el paquete."}],"hechos":["s22g01_publicacion_referencia","s22g01_repositorio_publico","s22g01_variable_cliente_no_protegida","s22g01_analitica_tercero"],"paquete":{"tipo":"NUEVA","codigo":"S22G-C01","clave":"s22g_legacy_135","familia":"SECURITY","naturaleza":"CONDUCTA","clase":"TRANSVERSAL","alcance":"BACKEND","modo":"HEREDA","dueno":"TECNICO","titulo":"Protección de referencias de infraestructura Supabase","descripcion":"Ante publicación de referencias de proyecto Supabase o anon key BLOQUEAR exposición en repositorios públicos, variables cliente sin protección o herramientas de análisis de terceros. No equiparar anon key autorizada a credencial privilegiada ni prohibir su uso legítimo por adaptador cliente autorizado; no inventar mecanismo de protección. Binding pendiente.","efecto":"BLOQUEAR","autoridad":"LEG-TECNICO","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/135","solicitante":"Cristhian / Claude S22-G 2026-11-25"},"condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"s22g01_publicacion_referencia"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"=","izq":{"hecho":"s22g01_repositorio_publico"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"s22g01_variable_cliente_no_protegida"},"der":{"lit":true}}},"der":{"op":"=","izq":{"hecho":"s22g01_analitica_tercero"},"der":{"lit":true}}}},"pruebas":[{"casuistica":"NO_SE_CUMPLE","entrada":{"s22g01_publicacion_referencia":true,"s22g01_repositorio_publico":false,"s22g01_variable_cliente_no_protegida":false,"s22g01_analitica_tercero":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"s22g01_publicacion_referencia":true,"s22g01_repositorio_publico":true,"s22g01_variable_cliente_no_protegida":false,"s22g01_analitica_tercero":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22g01_publicacion_referencia":true,"s22g01_repositorio_publico":false,"s22g01_variable_cliente_no_protegida":true,"s22g01_analitica_tercero":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22g01_publicacion_referencia":true,"s22g01_repositorio_publico":false,"s22g01_variable_cliente_no_protegida":false,"s22g01_analitica_tercero":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"s22g01_publicacion_referencia":false,"s22g01_repositorio_publico":true,"s22g01_variable_cliente_no_protegida":true,"s22g01_analitica_tercero":true},"esperado":false}]},"hash":"1c9a0a6c88436fe2720f0376b88067c59838591eea877af65fc4510f90e6711c","hash_paquete":"88aa8caa0b3d4a1356b7d92e869d3e17824f5684a7a2787fcc13c3006e0311aa","hash_evaluado":"1c9a0a6c88","hash_paquete_10":"88aa8caa0b","puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.9,"observacion":"RLS obligatorio de la legada y binding pendientes"},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S22G-C02","legacy_id":88,"legacy_ids":[88],"relacionadas":["S9-C06","S9-C07","S15-C05","S8-C07"],"residual":"","coberturas":[{"legacy_id":88,"estado_cobertura":"REEMPLAZADA","residual":"","diferencias":"En instrumentación del Paso 1 de onboarding BLOQUEAR omitir eventos onboarding_started, tipo_documento_seleccionado, paso1_form_submit_attempt, paso1_form_submit_success, paso1_form_submit_error, consent_terms_checked, consent_data_checked o consent_marketing_checked cuando ocurra su acción correspondiente. No emitir eventos por acciones inexistentes ni incluir PII; respetar dataLayer y semántica del embudo S15-C05. Binding pendiente."}],"hechos":["s22g02_instrumentacion_paso1","s22g02_evento_accion_omitido","s22g02_evento_sin_accion","s22g02_evento_con_pii"],"paquete":{"tipo":"NUEVA","codigo":"S22G-C02","clave":"s22g_legacy_88","familia":"ANALYTICS","naturaleza":"CONDUCTA","clase":"TRANSVERSAL","alcance":"BACKEND","modo":"HEREDA","dueno":"TECNICO","titulo":"Eventos funcionales autorizados del primer paso","descripcion":"En instrumentación del Paso 1 de onboarding BLOQUEAR omitir eventos onboarding_started, tipo_documento_seleccionado, paso1_form_submit_attempt, paso1_form_submit_success, paso1_form_submit_error, consent_terms_checked, consent_data_checked o consent_marketing_checked cuando ocurra su acción correspondiente. No emitir eventos por acciones inexistentes ni incluir PII; respetar dataLayer y semántica del embudo S15-C05. Binding pendiente.","efecto":"BLOQUEAR","autoridad":"LEG-TECNICO","impacto":"REVISAR","origen":{"tipo":"MIGRACION","ref":"lf_ops.reglas/88","solicitante":"Cristhian / Claude S22-G 2026-11-25"},"condicion":{"op":"y","izq":{"op":"=","izq":{"hecho":"s22g02_instrumentacion_paso1"},"der":{"lit":true}},"der":{"op":"o","izq":{"op":"o","izq":{"op":"=","izq":{"hecho":"s22g02_evento_accion_omitido"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"s22g02_evento_sin_accion"},"der":{"lit":true}}},"der":{"op":"=","izq":{"hecho":"s22g02_evento_con_pii"},"der":{"lit":true}}}},"pruebas":[{"casuistica":"NO_SE_CUMPLE","entrada":{"s22g02_instrumentacion_paso1":true,"s22g02_evento_accion_omitido":false,"s22g02_evento_sin_accion":false,"s22g02_evento_con_pii":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"s22g02_instrumentacion_paso1":true,"s22g02_evento_accion_omitido":true,"s22g02_evento_sin_accion":false,"s22g02_evento_con_pii":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22g02_instrumentacion_paso1":true,"s22g02_evento_accion_omitido":false,"s22g02_evento_sin_accion":true,"s22g02_evento_con_pii":false},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"s22g02_instrumentacion_paso1":true,"s22g02_evento_accion_omitido":false,"s22g02_evento_sin_accion":false,"s22g02_evento_con_pii":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"s22g02_instrumentacion_paso1":false,"s22g02_evento_accion_omitido":true,"s22g02_evento_sin_accion":true,"s22g02_evento_con_pii":true},"esperado":false}]},"hash":"4ef525e3c06a34bed1e36a3c4386c5d45460a7876bca2a8b6f53ddd4c8c5be69","hash_paquete":"c9a0debe94a8d7d1daebe8f31efa6f083307f522450915fbe9b7055996463dbf","hash_evaluado":"4ef525e3c0","hash_paquete_10":"c9a0debe94","puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"relacionada con S15-C05 y S22F-C01, declarado"},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}}]$pack$::jsonb; p jsonb; a jsonb; ans jsonb; cd text; h text; t record; n int:=0; vectors int:=0; b_leg jsonb; b_dep jsonb; b_cfg jsonb; val jsonb; lid int; residual text; diff text; old_desc text; new_desc text; links int:=0; before_replaced int; after_replaced int; direct_hash text; c jsonb;
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
 val:=jsonb_build_object('regla',cd,'hash_evaluado',h,'veredicto','PASS','puntajes',p->'puntajes','juez','Claude','modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,'evidencia_ref','PR #4762 / Claude 2026-11-25 01:19 Lima / '||cd||' / hash_paquete_10='||(p->>'hash_paquete_10'));
 BEGIN
 PERFORM lf_ops.nucleo_juicio_registrar_v1(val||jsonb_build_object('hash_evaluado',repeat('0',64)));
 RAISE EXCEPTION 'S22G_NEGATIVE_HASH_ACCEPTED %',cd;
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF; END;
 PERFORM lf_ops.nucleo_juicio_registrar_v1(val);
 ans:=lf_ops.nucleo_regla_evaluar_v1(cd,true);
 IF ans->>'decision' IS DISTINCT FROM 'AUTO' THEN RAISE EXCEPTION 'S22G_NOT_AUTO % %',cd,ans; END IF;
 ans:=lf_ops.nucleo_regla_promover_v1(cd);
 IF ans->>'resultado' IS DISTINCT FROM 'PROMOVIDA_AUTO' OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_PROMOTION_FAIL % %',cd,ans; END IF;
 n:=n+1;
 END LOOP;
 IF n<>2 OR vectors<>10 THEN RAISE EXCEPTION 'S22_VECTOR_COUNT'; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM lf_ops.reglas x) IS DISTINCT FROM b_leg OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones x) IS DISTINCT FROM b_dep OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.lf_global_config x) IS DISTINCT FROM b_cfg THEN RAISE EXCEPTION 'S22_INVARIANT_FAIL'; END IF;
 IF jsonb_array_length(lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS')->'nativas') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'S22_DPIG03_FAIL'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements(packs) LOOP
 cd:=p->>'codigo'; h:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF h IS DISTINCT FROM p->>'hash_paquete' THEN RAISE EXCEPTION 'S22G_COVERAGE_HASH_DRIFT %',cd; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements(p->'coberturas') LOOP
 lid:=(c->>'legacy_id')::int; residual:=c->>'residual'; diff:=c->>'diferencias';
 IF length(diff)<30 OR c->>'estado_cobertura' NOT IN ('REEMPLAZADA','PARCIAL') OR (c->>'estado_cobertura'='REEMPLAZADA' AND residual IS DISTINCT FROM '') OR (c->>'estado_cobertura'='PARCIAL' AND coalesce(length(residual),0)<15) THEN RAISE EXCEPTION 'S22G_COVERAGE_CONTRACT %',lid; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,c->>'estado_cobertura',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||(p->'paquete'->>'descripcion')||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),h,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 END LOOP;
 END LOOP;
 cd:='S8-C20'; lid:=13;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S8-C20 regula resolución de Home con skeleton contextual y fallback funcional, sin spinner genérico.'; residual:='Falta acreditar cruce DNI tras OTP y resolución autoritativa de las variantes con_oferta, sin_oferta y pendiente_cruce antes del render.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22G_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),direct_hash,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 cd:='S8-C20'; lid:=35;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S8-C20 regula espera de resolución de Home y fallback sin oferta.'; residual:='Falta acreditar transición histórica onboarding_step=3 con home_variant definido y reconciliación de pasos canónicos actuales.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22G_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),direct_hash,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 cd:='S4-C18'; lid:=41;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S4-C18 gobierna recuperación posterior a OTP sin revelar existencia de cuenta, con asociación de celular y documento autorizado.'; residual:='Falta restricción de unicidad de cuenta completada por DNI y resolución de recuperación por DNI sin crear duplicado.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22G_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),direct_hash,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 cd:='S5-C02'; lid:=43;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S5-C02 conserva la misma sesión activa no expirada y datos capturados al reanudar, reiniciando desafío OTP.'; residual:='Falta acreditar detección por mismo DNI de sesión activa no completada antes de crear una sesión nueva.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22G_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),direct_hash,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 cd:='S11-C04'; lid:=180;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S11-C04 exige código funcional LF_ autorizado por catálogo y mensaje amigable en errores no sensibles, preservando anti-enumeración.'; residual:='Falta acreditar disponibilidad de cada código mínimo legado y conciliación de los códigos sensibles con respuesta externa no reveladora.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22G_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),direct_hash,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 cd:='S14-C01'; lid:=537;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S14-C01 cubre header de Home autenticado y S14-C02 Pagos, con destinos, capacidades, soporte, nombre y badges autorizados.'; residual:='Falta acreditar cobertura de las restantes superficies autenticadas y restricción explícita de claim de soporte permanente sin evidencia.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22G_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),direct_hash,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 cd:='REG_CHK_005'; lid:=541;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,3);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=3 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=3;
 diff:='REG_CHK_005 v3 protege render de éxito con confirmación, referencia, fecha y monto autoritativos; S3-C20 protege efectos postpago.'; residual:='Falta contrato visual exclusivo de activación de cuotas, metadatos enmascarados, cronograma, documentos reales o DEMO identificado y exclusión de pago único.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22G_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,3,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),direct_hash,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 cd:='S4-C16'; lid:=562;
 direct_hash:=lf_ops.nucleo_hash_paquete_v1(cd,1);
 IF direct_hash IS NULL OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1 AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S22G_DIRECT_ATTESTATION_MISSING %',cd; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=1;
 diff:='S4-C16 gobierna persistir plan y fecha válida antes de checkout y revalidar quote; S3-C11 conserva consentimiento recurrente.'; residual:='Falta acreditar plan aún no activado, vigencia de versión/oferta, fecha condicional según configuración y prohibición de invocar proveedor desde detalle.';
 IF length(diff)<30 OR length(residual)<15 THEN RAISE EXCEPTION 'S22G_DIRECT_CONTRACT %',lid; END IF;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,1,'PARCIAL',diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente 2026-11-25 01:19 Lima'),direct_hash,'GPT / Claude S22-G independiente')
 ON CONFLICT (legacy_id,nucleo_codigo,version_nucleo) DO UPDATE SET estado_cobertura=EXCLUDED.estado_cobertura, diferencias=EXCLUDED.diferencias, evidencia=EXCLUDED.evidencia, hash_paquete=EXCLUDED.hash_paquete, revisado_por=EXCLUDED.revisado_por;
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S22G_SOURCE_MISSING %',lid; END IF;
 SELECT count(DISTINCT legacy_id) INTO after_replaced FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='REEMPLAZADA';
 IF (SELECT count(*) FROM lf_ops.reglas)=586 AND (links<>10 OR after_replaced<>before_replaced+1) THEN RAISE EXCEPTION 'S22G_COVERAGE_READBACK_FAIL links=% before=% after=%',links,before_replaced,after_replaced; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM lf_ops.reglas x) IS DISTINCT FROM b_leg OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones x) IS DISTINCT FROM b_dep OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.lf_global_config x) IS DISTINCT FROM b_cfg THEN RAISE EXCEPTION 'S22G_POST_COVERAGE_INVARIANT_FAIL'; END IF;
 RAISE NOTICE 'S22G_PASS 2 JUICIOS 2 AUTO 10 VECTORES links=% replaced=% DPIG03=0',links,after_replaced;
END $s22$;
COMMIT;
