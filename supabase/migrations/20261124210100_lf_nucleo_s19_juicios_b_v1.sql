-- S19B: independent Claude attestation; exact package hash; only AUTO; no legacy mutation.
BEGIN;
DO $s19b$
DECLARE p jsonb; e record; h text; val jsonb; ans jsonb; cd text; n int:=0; pub int:=0; links int:=0; b_leg jsonb; b_dep jsonb; lid int; residual text; diff text; old_desc text; new_desc text;
BEGIN
 SELECT jsonb_agg(to_jsonb(t) ORDER BY id) INTO b_leg FROM lf_ops.reglas t;
 SELECT jsonb_agg(to_jsonb(t) ORDER BY regla,version) INTO b_dep FROM lf_ops.nucleo_deprecaciones t;
 FOR p IN SELECT value FROM jsonb_array_elements($pack$[{"codigo":"S19-C01","version":1,"eval_id":1174,"hash_version_atestado":"7848bd1aa07a31231401ab8d2e8030e3177eebe1aca83223e88fdb216ed9e9bd","hash_paquete_atestado":"19467d62d047e29ae6f9ea0b332c5f7eeeaed453641e875920f5bb00a3f2954e","veredicto":"PASS","juez":"Claude independiente 2026-11-24 15:50 Lima","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}},"legada_id":46,"familia":"UI_MESSAGES","diferencias":"Contraste funcional: BLOQUEAR mensaje de error visible fuera del onboarding que exponga códigos técnicos, referencias a base de datos, términos internos o mensajes crudos del sistema. Preservar mensajes de negocio autorizados no sensibles y precedencia anti-enumeración. Onboarding conserva S18-C01. Conserva mensajes de negocio autorizados y anti-enumeración; complemento S18-C01. ","residual":"","complementa":"S18-C01"}]$pack$::jsonb) LOOP
 cd:=p->>'codigo'; lid:=(p->>'legada_id')::int;
 SELECT id,regla,version,hash_paquete INTO e FROM lf_ops.nucleo_evaluaciones WHERE regla=cd AND version=(p->>'version')::int ORDER BY id DESC LIMIT 1;
 IF ((SELECT count(*) FROM lf_ops.reglas)=586 AND e.id IS DISTINCT FROM (p->>'eval_id')::bigint) OR e.hash_paquete IS DISTINCT FROM p->>'hash_paquete_atestado' OR (SELECT count(*) FROM lf_ops.nucleo_regla_pruebas WHERE regla=cd AND version=e.version)<>8 OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=e.version AND estado='CANDIDATA' AND hash=p->>'hash_version_atestado') THEN RAISE EXCEPTION 'S19B_ATTESTATION_DRIFT %',cd; END IF;
 h:=lf_ops.nucleo_hash_paquete_v1(cd,e.version);
 IF h IS DISTINCT FROM e.hash_paquete THEN RAISE EXCEPTION 'S19B_HASH_DRIFT %',cd; END IF;
 val:=jsonb_build_object('regla',cd,'hash_evaluado',h,'veredicto',p->>'veredicto','puntajes',p->'puntajes','juez',p->>'juez','modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,'evidencia_ref','sandbox/lf_contract_gate_test/nucleo_ci/nucleo_s19_juicios_b_v1.json#'||cd);
 BEGIN
 PERFORM lf_ops.nucleo_juicio_registrar_v1(val||jsonb_build_object('hash_evaluado',repeat('0',64)));
 RAISE EXCEPTION 'S19B_NEGATIVE_HASH_ACCEPTED %',cd;
 EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF; END;
 PERFORM lf_ops.nucleo_juicio_registrar_v1(val);
 ans:=lf_ops.nucleo_regla_evaluar_v1(cd,true);
 IF ans->>'decision'<>'AUTO' THEN RAISE EXCEPTION 'S19B_NOT_AUTO % %',cd,ans; END IF;
 ans:=lf_ops.nucleo_regla_promover_v1(cd);
 IF ans->>'resultado'<>'PROMOVIDA_AUTO' OR NOT EXISTS(SELECT 1 FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=e.version AND estado='PUBLICADA') THEN RAISE EXCEPTION 'S19B_PROMOTION_FAIL % %',cd,ans; END IF;
 pub:=pub+1;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id=lid) THEN
 IF EXISTS(SELECT 1 FROM lf_ops.lf_nucleo_cobertura_legada WHERE legacy_id=lid AND estado_cobertura='REEMPLAZADA') THEN RAISE EXCEPTION 'S19B_COVERAGE_DRIFT %',lid; END IF;
 IF p->>'complementa' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM lf_ops.lf_nucleo_cobertura_legada c JOIN lf_ops.nucleo_regla_versiones v ON v.regla=c.nucleo_codigo AND v.version=c.version_nucleo WHERE c.legacy_id=lid AND c.nucleo_codigo=p->>'complementa' AND c.estado_cobertura='PARCIAL' AND v.estado='PUBLICADA') THEN RAISE EXCEPTION 'S19B_COMPLEMENT_DRIFT %',lid; END IF;
 SELECT descripcion INTO old_desc FROM lf_ops.reglas WHERE id=lid;
 SELECT descripcion INTO new_desc FROM lf_ops.nucleo_regla_versiones WHERE regla=cd AND version=e.version;
 residual:=coalesce(p->>'residual',''); diff:=p->>'diferencias'||CASE WHEN residual<>'' THEN ' Residual: '||residual ELSE '' END;
 INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,estado_cobertura,diferencias,evidencia,hash_paquete,revisado_por)
 VALUES(lid,cd,e.version,CASE WHEN residual='' THEN 'REEMPLAZADA' ELSE 'PARCIAL' END,diff,jsonb_build_object('fuente','lf_ops.reglas/'||lid,'contraste','LEGADA: '||old_desc||' NUCLEO: '||new_desc||' DIFERENCIA: '||diff,'residual',residual,'juicio','Claude independiente S19B 2026-11-24 15:50','limite_aceptacion','Cobertura funcional; binding runtime no certificado'),h,'GPT / Claude S19B independiente');
 links:=links+1;
 ELSIF (SELECT count(*) FROM lf_ops.reglas)=586 THEN RAISE EXCEPTION 'S19B_SOURCE_MISSING %',lid; END IF;
 n:=n+1;
 END LOOP;
 IF n<>1 OR pub<>1 OR ((SELECT count(*) FROM lf_ops.reglas)=586 AND links<>1) OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY id) FROM lf_ops.reglas t) IS DISTINCT FROM b_leg OR (SELECT jsonb_agg(to_jsonb(t) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones t) IS DISTINCT FROM b_dep THEN RAISE EXCEPTION 'S19B_READBACK_FAIL n=% pub=% links=%',n,pub,links; END IF;
 IF jsonb_array_length(lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS')->'nativas') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'S19B_DPIG03_FAIL'; END IF;
 RAISE NOTICE 'S19B_PASS 1 JUICIOS 1 AUTO links=% DPIG03=0',links;
END $s19b$;
COMMIT;
