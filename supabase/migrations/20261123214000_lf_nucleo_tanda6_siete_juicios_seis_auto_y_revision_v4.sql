-- Tanda 6: seis PASS, una DEVOLVER veredictos PASS de juez externo. Hash versión != hash paquete (pruebas).
-- Fuente: sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda6_v1.json
BEGIN;
DO $pilot$
DECLARE p jsonb; code text; ver int; hv text; hp text; got_tests int; jr jsonb; ev jsonb; promoted jsonb; res text;
 oldlegacy jsonb; oldcore jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldchecks jsonb; oldekb bigint;
 n int:=0; auto_count int:=0; manual_count int:=0; blocked_count int:=0; new_published int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldcore FROM lf_ops.nucleo_reglas r
  WHERE r.codigo NOT IN ('REG_CHK_005','REG_CHK_006','REG_CHK_008','REG_CHK_013','REG_TEC_009','REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001','REG_CHK_004');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r
  WHERE r.regla NOT IN ('REG_CHK_005','REG_CHK_006','REG_CHK_008','REG_CHK_013','REG_TEC_009','REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001','REG_CHK_004');
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldchecks FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007';
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 RAISE NOTICE 'TANDA6_PREFLIGHT legacy_rows=% publicadas=%', (SELECT count(*) FROM lf_ops.reglas),(SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA');
 IF (SELECT count(*) FROM lf_ops.reglas)<1 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
   OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>50
   OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla IN ('REG_CHK_005','REG_CHK_006','REG_CHK_008','REG_CHK_013','REG_TEC_009','REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001','REG_CHK_004')
     AND modo='INDEPENDIENTE' AND veredicto='PASS')<>0
 THEN RAISE EXCEPTION 'TANDA6_BASELINE_DRIFT'; END IF;
 FOR p IN SELECT value FROM jsonb_array_elements('[{"codigo":"REG_CHK_005","version":3,"hash_version_atestado":"1ea603883cbb61b508970e9c666cd76e7aca388074a702679b05f92183452485","hash_paquete_atestado":"2ebe570ccd338b6c692ab01ba3776c75d43bb76e7d0921fd1166435181c1f158","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.9,"observacion":"La condición no lleva un hecho de pantalla CHECKOUT_PAGO_EXITOSO y depende del binding de pantalla."},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Se propone integrarla con REG_CLIENT_PAYMENT_SUCCESS_VIEW_001 y no la sustituye."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Que no genera acciones post-pago no lo evalúa la condición."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"REG_CHK_006","version":1,"hash_version_atestado":"6dc916352b9b47be786492c7207f4085a911465912c6ea426f373e008a40b4f3","hash_paquete_atestado":"881bef4a5ee9d5c172a52373f0515eb660c79b5e7b95a59f366c80ba7655e33f","pruebas_atestadas":3,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.95,"observacion":"Faltan pruebas con ambas comisiones ocultas a la vez y con ambos tipos NONE; los hechos usan nombres físicos de columnas, que existen."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":1},"COH_EFECTO":{"puntaje":1}}},{"codigo":"REG_CHK_008","version":3,"hash_version_atestado":"ca9efd53f6fff4ba015fe38fa10691534119f16e826f5d868b7c6fe1839bd9fe","hash_paquete_atestado":"5eb6a59911377f64c10eecb606b68233e79c6355feacc7b798717201970556fa","pruebas_atestadas":5,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.95,"observacion":"En BACKEND y para cada deuda figura en el texto y no en la condición."},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Consolidación pendiente con REG_CLIENT_NO_DEBT_LETTER_STATUS_001 y relación con M3-C03 publicada, distinto efecto (PERMITIR vs BLOQUEAR)."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Que el frontend no exige solicitud manual no lo evalúa la condición."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"REG_CHK_013","version":3,"hash_version_atestado":"76a22f4a1bff6b9ef7e9e71b694d452aa860c3a2b58d8c986b90d74031067baa","hash_paquete_atestado":"d9f0ed3dea6f3c93670927ee7420699b89bad012a230465ac169d1645a7af0bf","pruebas_atestadas":5,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Consolidación pendiente con REG_CLIENT_CHECKOUT_AUTODEBIT_CONSENT_CONTEXT_001."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"Timestamp, contexto del medio y versión del cronograma colapsan en un hecho de evidencia vinculada."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"REG_TEC_009","version":3,"hash_version_atestado":"1a3521d15598ce9b280be5ce195231a98ae9cd239de9c4920a0aae7ebc1ddee3","hash_paquete_atestado":"de3112dfc263c403c4a711a9473487799430497d0b19f73dc8aa2224cc7cc0ab","pruebas_atestadas":6,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.9,"observacion":"Descripción larga con cautelas de runtime."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.85,"observacion":"Coincidencia de usuario, idempotency_key y request_sha256 y operation_number asociado se agrupan en hechos; el binding real no está acreditado."},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.85,"observacion":"En el borde exacto la condición da false pero la reconciliación aparte no la evalúa; el texto declara que ese criterio conservador no está validado contra runtime, y así debe quedar registrado en la EKB como pendiente de Paulo."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001","version":3,"hash_version_atestado":"9b29a98281a346f5dae334d9e68b770c0efd18cc82e9cccd56f410b6d7011dd0","hash_paquete_atestado":"be6efba5af2d9bdfc6f10200225b7e9f6a25f7c9b1a79502e3875360b21feb17","pruebas_atestadas":4,"veredicto":"PASS","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":1},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":0.95,"observacion":"Sin hecho de pantalla CHECKOUT_ESTADO_YAPE_QR."},"SEM_NO_DUPLICA":{"puntaje":0.9,"observacion":"Solapa con REG_CHK_005 en evidencia autoritativa de pago."},"SEM_NO_CONTRADICE":{"puntaje":1},"COH_TEXTO_CONDICION":{"puntaje":0.95,"observacion":"El CTA Ya escaneé y la expiración no los evalúa la condición."},"COH_EFECTO":{"puntaje":1}}},{"codigo":"REG_CHK_004","version":3,"hash_version_atestado":"78f6bc40616d4d26b81f25a0144e26f84cad3530d673cc380e1ae9236a4ddee5","hash_paquete_atestado":"8249771509939cf055b58cd0a99d2ac61d5ffd853a152eb2df2247ce2eef735f","pruebas_atestadas":8,"veredicto":"DEVOLVER","juez":"Claude Sonnet 5.5 Anthropic, juicio independiente declarado por Claude","modo":"INDEPENDIENTE","revisor_es_productor":false,"llamadas_modelo":1,"puntajes":{"CAL_CLARIDAD":{"puntaje":0.9,"observacion":"La redacción de la descripción es ambigua acerca de las condiciones concurrentes de desbloqueo de reintento."},"CAL_ACCIONABLE":{"puntaje":1},"CAL_ALCANCE":{"puntaje":1},"SEM_NO_DUPLICA":{"puntaje":1},"SEM_NO_CONTRADICE":{"puntaje":0.7,"observacion":"La descripción presenta outcome seguro, permiso explícito y reserva/quote vigente como alternativas, mientras título, condición y pruebas exigen las tres concurrentemente. Prueba 4 bloquea PAYMENT_NOT_SUBMITTED sin permiso pese a quote vigente; prueba 3 bloquea DECLINED_CONFIRMED con permiso si quote no vigente."},"COH_TEXTO_CONDICION":{"puntaje":0.6,"observacion":"La condición bloquea si falta cualquiera de las tres validaciones, pero la descripción usa ''o'' e induce a interpretar cualquiera de las tres como suficiente; requiere un ''y'' expreso y coocurrencia."},"COH_EFECTO":{"puntaje":1}}}]'::jsonb) LOOP
  code:=p->>'codigo'; ver:=(p->>'version')::integer;
  SELECT v.hash INTO hv FROM lf_ops.nucleo_regla_versiones v
    WHERE v.regla=code AND v.version=ver AND v.estado='CANDIDATA';
  IF hv IS DISTINCT FROM p->>'hash_version_atestado' THEN
   RAISE EXCEPTION 'TANDA6_VERSION_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_version_atestado',hv;
  END IF;
  SELECT count(*) INTO got_tests FROM lf_ops.nucleo_regla_pruebas
    WHERE regla=code AND version=ver;
  IF got_tests IS DISTINCT FROM (p->>'pruebas_atestadas')::integer THEN
   RAISE EXCEPTION 'TANDA6_TEST_COUNT_MISMATCH code=% want=% got=%',code,p->>'pruebas_atestadas',got_tests;
  END IF;
  hp:=lf_ops.nucleo_hash_paquete_v1(code,ver);
  IF hp IS DISTINCT FROM p->>'hash_paquete_atestado' THEN
   RAISE EXCEPTION 'TANDA6_PACKAGE_HASH_MISMATCH code=% want=% got=%',code,p->>'hash_paquete_atestado',hp;
  END IF;
  jr:=jsonb_build_object('regla',code,'hash_evaluado',hp,'veredicto',p->>'veredicto','puntajes',p->'puntajes',
     'juez','Claude Sonnet 5.5 (Anthropic) — revisión independiente atestada por Claude',
     'modo','INDEPENDIENTE','revisor_es_productor',false,'llamadas_modelo',1,
     'evidencia_ref','https://github.com/cristhianlujan/claude-persona-lf-patch/blob/main/sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda6_v1.json#'||code);
  -- Negativo: hash alterado jamás puede admitirse.
  BEGIN
   PERFORM lf_ops.nucleo_juicio_registrar_v1(jr||jsonb_build_object('hash_evaluado',repeat('0',64)));
   RAISE EXCEPTION 'TANDA6_BAD_HASH_ACCEPTED %',code;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'NUCLEO_JUICIO_HASH_DISTINTO:%' THEN RAISE; END IF;
  END;
  PERFORM lf_ops.nucleo_juicio_registrar_v1(jr);
  ev:=lf_ops.nucleo_regla_evaluar_v1(code,true);
  res:=ev->>'decision'; promoted:=NULL;
  IF res='AUTO' AND p->>'veredicto'='DEVOLVER' THEN RAISE EXCEPTION 'TANDA6_DEVOLVER_WAS_AUTO %',code; END IF;
  IF res='AUTO' THEN
   promoted:=lf_ops.nucleo_regla_promover_v1(code);
   IF promoted->>'resultado'<>'PROMOVIDA_AUTO' THEN
     RAISE EXCEPTION 'TANDA6_AUTO_PROMOTION_FAILED % %',code,promoted;
   END IF;
   auto_count:=auto_count+1;
  ELSIF res='MANUAL' THEN manual_count:=manual_count+1;
  ELSE blocked_count:=blocked_count+1; END IF;
  RAISE NOTICE 'TANDA6_RESULT %',jsonb_build_object('regla',code,'version',ver,
    'hash_version',hv,'hash_paquete',hp,'decision',res,'nota',ev->'nota',
    'motivos',ev->'motivos','promocion',COALESCE(promoted->>'resultado','NO_PROMOVIDA'));
  n:=n+1;
 END LOOP;
 IF auto_count<>6 OR blocked_count<>1 OR manual_count<>0 THEN RAISE EXCEPTION 'TANDA6_DECISION_COUNTS_AUTO_%_BLOCK_%_MANUAL_%',auto_count,blocked_count,manual_count; END IF;


 
 -- Contrato y evidencia de DEVOLVER v3 antes de versionar.
 IF (SELECT veredicto FROM lf_ops.nucleo_juicios WHERE regla='REG_CHK_004' AND version=3 ORDER BY id DESC LIMIT 1)<>'DEVOLVER'
   OR (SELECT decision FROM lf_ops.nucleo_evaluaciones WHERE regla='REG_CHK_004' AND version=3 ORDER BY id DESC LIMIT 1)<>'DEVUELTA'
 THEN RAISE EXCEPTION 'TANDA6_DEVOLVER_NOT_RECORDED'; END IF;
 DECLARE
  p4 jsonb; outcome4 jsonb; old_v lf_ops.nucleo_regla_versiones%ROWTYPE;
  v4_hash text; v4_package text; old_proofs jsonb; new_proofs jsonb; result4 jsonb;
 BEGIN
  SELECT * INTO old_v FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_004' AND version=3 AND estado='CANDIDATA';
  IF old_v.hash IS DISTINCT FROM '78f6bc40616d4d26b81f25a0144e26f84cad3530d673cc380e1ae9236a4ddee5' THEN
    RAISE EXCEPTION 'TANDA6_V3_CHANGED_BEFORE_REVISION'; END IF;
  SELECT jsonb_agg(jsonb_build_object('casuistica',t.casuistica,'entrada',t.entrada,'esperado',t.esperado) ORDER BY t.n)
    INTO old_proofs FROM lf_ops.nucleo_regla_pruebas t WHERE t.regla='REG_CHK_004' AND t.version=3;
  IF jsonb_array_length(old_proofs)<>8 THEN RAISE EXCEPTION 'TANDA6_V3_PROOFS'; END IF;
  p4:=old_v.ficha || jsonb_build_object('tipo','REVISION','version_anterior',3,'hash_anterior',old_v.hash,
     'motivo_revision','Corregir solo redacción ambigua del reintento: las tres condiciones son concurrentes, sin alterar condición, efecto ni pruebas.',
     'descripcion','Un intento de checkout ya iniciado mantiene BLOQUEADO el reintento hasta que coexistan obligatoriamente las tres condiciones: (1) un outcome normalizado seguro del intento previo (PAYMENT_DECLINED_CONFIRMED, PAYMENT_NOT_SUBMITTED o PAYMENT_PROVIDER_UNAVAILABLE_BEFORE_SUBMIT), (2) permiso explícito del backend para reintentar la misma operación, y (3) reserva original de operación y quote vigente y válida. Ninguna de estas tres condiciones por sí sola ni en combinación parcial desbloquea el reintento. El backend debe comprobar user_id, quote_status=VALID, expires_at y referencia reservada antes de emitir los hechos. Un timeout ambiguo nunca autoriza segundo cobro. Antes del primer envío esta regla no bloquea el inicio.',
     'pruebas',old_proofs);
  -- Preflight de todos los controles oficiales sin escritura.
  outcome4:=lf_ops.nucleo_regla_proponer_v1(p4,false);
  IF outcome4->>'resultado'<>'EVALUADA_SIN_ESCRIBIR' THEN RAISE EXCEPTION 'TANDA6_V4_PREFLIGHT %',outcome4; END IF;
  result4:=lf_ops.nucleo_regla_proponer_v1(p4,true);
  IF result4->>'resultado'<>'CANDIDATA' OR (result4->>'version')::int<>4 THEN RAISE EXCEPTION 'TANDA6_V4_PROPOSAL %',result4; END IF;
  SELECT * INTO old_v FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_004' AND version=4;
  SELECT jsonb_agg(jsonb_build_object('casuistica',t.casuistica,'entrada',t.entrada,'esperado',t.esperado) ORDER BY t.n)
    INTO new_proofs FROM lf_ops.nucleo_regla_pruebas t WHERE t.regla='REG_CHK_004' AND t.version=4;
  IF old_v.descripcion IS DISTINCT FROM p4->>'descripcion'
   OR old_v.condicion IS DISTINCT FROM (SELECT condicion FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_004' AND version=3)
   OR old_v.efecto IS DISTINCT FROM (SELECT efecto FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_004' AND version=3)
   OR old_v.titulo IS DISTINCT FROM (SELECT titulo FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_004' AND version=3)
   OR old_v.autoridad IS DISTINCT FROM (SELECT autoridad FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_004' AND version=3)
   OR new_proofs IS DISTINCT FROM old_proofs
   OR (SELECT estado FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_004' AND version=3)<>'DESCARTADA'
   OR old_v.estado<>'CANDIDATA' THEN RAISE EXCEPTION 'TANDA6_V4_CONTENT_DRIFT'; END IF;
  v4_package:=lf_ops.nucleo_hash_paquete_v1('REG_CHK_004',4);
  outcome4:=lf_ops.nucleo_regla_evaluar_v1('REG_CHK_004',true);
  IF outcome4->>'decision'='AUTO' THEN RAISE EXCEPTION 'TANDA6_V4_AUTO_UNJUDGED'; END IF;
  RAISE NOTICE 'TANDA6_V4_RESULT %',jsonb_build_object('regla','REG_CHK_004','version',4,'hash_version',old_v.hash,
    'hash_paquete',v4_package,'nota',outcome4->'nota','decision',outcome4->'decision',
    'motivos',outcome4->'motivos','condicion_y_pruebas_sin_cambios',true,'promocion','NO_PROMOVIDA');
 END;

 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-TANDA6-7-JUICIOS-Y-REINTENTO-V4-20261123-001') THEN RAISE EXCEPTION 'TANDA6_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-TANDA6-7-JUICIOS-Y-REINTENTO-V4-20261123-001','NUCLEO_REGLAS','Tanda 6: seis PASS y una DEVOLVER + revisión v4',
  'REG_CHK_004 v3 DEVOLVER por disyunción semántica versus tres condiciones concurrentes; v4 solo aclara descripción y queda CANDIDATA. Seis PASS registrados y solo AUTO publicados.',
  'La descripción v3 presentaba requisitos como alternativas; el backend, las pruebas y la condición requieren todos. REG_TEC_009 borde de idempotencia pendiente de validación runtime de Paulo.',
  'NUCLEO_TANDA6_DEVOLUCION_VERSION_GOBERNADA',
  'No promover REG_CHK_004 v4 sin otro juicio independiente. Validar en Paulo comportamiento real del borde exacto AUTH/IDEMPOTENCY_KEY_VALIDITY_MINUTES=5 y bindings de usuario, clave, sha y operación.',
  'PG17 BEGIN ROLLBACK, hash alterado negativo por 7 reglas, 6 AUTO, v3 DEVUELTA, v4 CANDIDATA no promovida, 17 regresiones y lector IG 14/14.',
  'MEDIUM',1,now(),now(),'TANDA6-JUICIOS-20261123','ACTIVO','sandbox/lf_contract_gate_test/nucleo_ci/nucleo_juicios_independientes_tanda6_v1.json; docs/nucleo/LF_TANDA6_SIETE_JUICIOS_Y_REG_CHK_004_V4_20261123.md');
 IF n<>7 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r
   WHERE r.codigo NOT IN ('REG_CHK_005','REG_CHK_006','REG_CHK_008','REG_CHK_013','REG_TEC_009','REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001','REG_CHK_004')) IS DISTINCT FROM oldcore
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r
   WHERE r.regla NOT IN ('REG_CHK_005','REG_CHK_006','REG_CHK_008','REG_CHK_013','REG_TEC_009','REG_CLIENT_CHECKOUT_QR_CONFIRMATION_001','REG_CHK_004')) IS DISTINCT FROM oldversions
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
  OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r WHERE r.codigo='REG_CHK_007') IS DISTINCT FROM oldchecks
  OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE estado='PUBLICADA')<>50+auto_count
 THEN RAISE EXCEPTION 'TANDA6_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'TANDA6_PASS 7/7 judged; auto=% manual=% blocked=%; legadas sin drift; 0 deprecaciones',auto_count,manual_count,blocked_count;
END $pilot$;
COMMIT;
