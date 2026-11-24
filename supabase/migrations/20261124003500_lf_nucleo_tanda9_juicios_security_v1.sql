-- Tanda 9 SECURITY: registro de cinco juicios independientes, verificacion contra el paquete vivo.
-- No altera IG, lectores, legadas ni aplicaciones.
BEGIN;
DO $tanda9$
DECLARE p jsonb; cd text; hp text; hv text; e jsonb; j jsonb; promo jsonb; prev_eval record;
        before_legacy jsonb; before_apps jsonb; before_deprec jsonb;
        n integer:=0; auto_n integer:=0; manual_n integer:=0; blocked_n integer:=0;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY id) INTO before_legacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,nodo) INTO before_apps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) INTO before_deprec FROM lf_ops.nucleo_deprecaciones r;
 IF (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='VIGENTE')<>58
    OR (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='CANDIDATA')<>6
    OR (SELECT count(*) FROM lf_ops.reglas) NOT IN (215,586)
    OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
 THEN RAISE EXCEPTION 'TANDA9_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"S1-C02","version":1,"eval_id":281,"hash_paquete_atestado":"1535f54e467d476278334b374fd759e29354c08627fde3c3959ce4db8ead4075","pruebas_atestadas":8,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.9,"observacion":"Consulta de datos del backend en contexto de validación no identifica la entidad consultada."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.95,"observacion":"Consulta es amplia; descripción aclara que no certifica protección contra inyección."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"validacion_servidor representa contexto, no violación; el texto describe los tres hechos."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S1-C03","version":1,"eval_id":282,"hash_paquete_atestado":"3c9d2e951c6f35f282a95b3fc3386dfd492c7896f171deb085b8797f9d47e691","pruebas_atestadas":8,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Relacionada con S1-C04 y M4-C03; esta gobierna autenticación interna webhook n8n al despachar OTP."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Autenticación verificada en backend antes de emitir el hecho."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S1-C04","version":1,"eval_id":283,"hash_paquete_atestado":"65489644230835df5a6f081ea12cf8fea740ba5d8f016f0c98c0a08624aafc4b","pruebas_atestadas":8,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.95,"observacion":"Firma y tiempo agrupados en un hecho."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.95,"observacion":"Relacionada con S1-C03."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"La descripción cita ventana de lf_global_config y condición recibe resultado agregado calculado en backend."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S1-C05","version":1,"eval_id":284,"hash_paquete_atestado":"da93f6533d5e21477f52b5b2e975bd8d49ff3513d34f471ae47673fa0e511315","pruebas_atestadas":8,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.9,"observacion":"Cuatro causas agrupadas en un hecho."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.85,"observacion":"Cooldown y reenvíos agotados solapan M4-B04 y M4-B06; agrega sesión inexistente y OTP verificado; no duplicar cobertura legada."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.9,"observacion":"Hecho agregado oculta cuatro causas y el texto lo declara."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"S1-C06","version":1,"eval_id":285,"hash_paquete_atestado":"e626d4d72e9ed5ea1e4647312e04e1addf18e7e2630b0b0bc696ba4f1d1d14e7","pruebas_atestadas":8,"veredicto":"PASS","juez":"Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.95,"observacion":"Tres validaciones agrupadas en un hecho."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"AUTH/ERROR_RESPONSE_MINIMUM_MS es calculado en backend."},"COH_EFECTO":{"puntaje":1}}}]'::jsonb) LOOP
   cd:=p->>'codigo';
   SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v WHERE v.regla=cd AND v.version=1 AND v.estado='CANDIDATA';
   IF hv IS NULL THEN RAISE EXCEPTION 'TANDA9_VERSION_NOT_CANDIDATE %',cd; END IF;
   IF (SELECT count(*) FROM lf_ops.nucleo_regla_pruebas WHERE regla=cd AND version=1)<>8
   THEN RAISE EXCEPTION 'TANDA9_TEST_COUNT_MISMATCH %',cd; END IF;
   SELECT id,hash_paquete,decision INTO prev_eval FROM lf_ops.nucleo_evaluaciones
     WHERE regla=cd AND version=1 ORDER BY id DESC LIMIT 1;
   IF ((SELECT count(*) FROM lf_ops.reglas)=586 AND prev_eval.id IS DISTINCT FROM (p->>'eval_id')::bigint)
      OR prev_eval.hash_paquete IS DISTINCT FROM p->>'hash_paquete_atestado'
   THEN RAISE EXCEPTION 'TANDA9_EVALUATION_DRIFT %',cd; END IF;
   hp:=lf_ops.nucleo_hash_paquete_v1(cd,1);
   IF hp IS DISTINCT FROM p->>'hash_paquete_atestado'
   THEN RAISE EXCEPTION 'TANDA9_PACKAGE_HASH_MISMATCH % want=% got=%',cd,p->>'hash_paquete_atestado',hp; END IF;
   j:=jsonb_build_object('regla',cd,'hash_evaluado',hp,'veredicto','PASS',
     'puntajes',p->'puntajes','juez',p->>'juez','modo','INDEPENDIENTE',
     'revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda9_v1.json#'||cd);
   BEGIN
     PERFORM lf_ops.nucleo_juicio_registrar_v1(j||jsonb_build_object('hash_evaluado',repeat('0',64)));
     RAISE EXCEPTION 'TANDA9_BAD_HASH_ACCEPTED %',cd;
   EXCEPTION WHEN OTHERS THEN
     IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
   END;
   PERFORM lf_ops.nucleo_juicio_registrar_v1(j);
   e:=lf_ops.nucleo_regla_evaluar_v1(cd,true);
   IF e->>'decision'='AUTO' THEN
     promo:=lf_ops.nucleo_regla_promover_v1(cd);
     IF promo->>'resultado'<>'PROMOVIDA_AUTO' THEN RAISE EXCEPTION 'TANDA9_PROMOTION_FAILED % %',cd,promo; END IF;
     auto_n:=auto_n+1;
   ELSIF e->>'decision'='MANUAL' THEN manual_n:=manual_n+1;
   ELSE blocked_n:=blocked_n+1;
   END IF;
   n:=n+1;
   RAISE NOTICE 'TANDA9_RESULT %',jsonb_build_object('regla',cd,'hash_paquete',hp,'decision',e->>'decision','promocion',COALESCE(promo->>'resultado','NO_AUTO'));
   promo:=NULL;
 END LOOP;
 IF n<>5 OR n<>auto_n+manual_n+blocked_n
    OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r) IS DISTINCT FROM before_legacy
    OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM before_apps
    OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM before_deprec
 THEN RAISE EXCEPTION 'TANDA9_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'TANDA9_PASS judged=% auto=% manual=% blocked=% legacy_unchanged=true',n,auto_n,manual_n,blocked_n;
END $tanda9$;
COMMIT;
