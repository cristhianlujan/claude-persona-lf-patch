-- REG_CHK_007 v2, cambio de semántica autorizado: CANDIDATA, nunca promover.
-- Los hechos agregados son lógicos, sin binding físico ni permisos a IG.
BEGIN;
DO $batch$
DECLARE p jsonb; res jsonb; e jsonb; previous jsonb; checked jsonb; actual text; v2hash text;
 oldlegacy jsonb; oldother jsonb; oldversions jsonb; olddeprec jsonb; oldapps jsonb; oldekb bigint; ntests int;
BEGIN
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) INTO oldlegacy FROM lf_ops.reglas r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) INTO oldother FROM lf_ops.nucleo_reglas r WHERE r.codigo<>'REG_CHK_007';
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO oldversions FROM lf_ops.nucleo_regla_versiones r WHERE r.regla<>'REG_CHK_007';
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) INTO olddeprec FROM lf_ops.nucleo_deprecaciones r;
 SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) INTO oldapps FROM lf_ops.nucleo_aplicaciones r;
 SELECT count(*) INTO oldekb FROM public.lf_error_knowledge;
 IF (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='VIGENTE')<>57
 OR (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='CANDIDATA')<>1
 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
 OR (SELECT count(*) FROM lf_ops.nucleo_juicios WHERE regla='REG_CHK_007' AND modo='INDEPENDIENTE')<>0
 THEN RAISE EXCEPTION 'CHK007_BASELINE_DRIFT'; END IF;
 INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('chk007_intento_modificar_seleccion','boolean','ninguna','El usuario intenta modificar la selección de ofertas, no solamente leer el resumen o navegar Volver.');
 INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','chk007_intento_modificar_seleccion','CURADO');
 INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('chk007_violacion_seleccion_inmutable','boolean','ninguna','El intento de modificación viola la política contextual, no una simple visita a confirmación; requiere evidencia lógica de violación.');
 INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','chk007_violacion_seleccion_inmutable','CURADO');
 INSERT INTO lf_ops.nucleo_hechos(codigo,tipo_dato,unidad,descripcion) VALUES('chk007_pago_enviado_no_terminal_seguro','boolean','ninguna','El pago ya fue enviado y todavía no tiene outcome terminal seguro acreditado; incluye pago pendiente, supuesto pendiente de decisión de Cristhian.');
 INSERT INTO lf_ops.nucleo_familia_vocabulario(familia,hecho,origen) VALUES('PAYMENTS_CHECKOUT','chk007_pago_enviado_no_terminal_seguro','CURADO');
 p:='{"tipo":"REVISION","codigo":"REG_CHK_007","clave":"seleccion_inmutable_confirmacion","familia":"PAYMENTS_CHECKOUT","naturaleza":"CONDUCTA","clase":"PANTALLA","alcance":"CLIENTE","modo":"HEREDA","dueno":"PRODUCTO","titulo":"Bloqueo del intento de modificar la selección en confirmación o pago enviado sin outcome terminal seguro","descripcion":"BLOQUEAR únicamente un intento real de modificar la selección de ofertas cuando la modificación constituye una violación y se intenta directamente desde la pantalla de confirmación, que es de solo lectura, o tras enviar un pago cuyo outcome todavía no sea terminal seguro. Para cambiar antes de enviar el pago, el cliente debe usar Volver para regresar al paso de selección, ajustar ofertas y avanzar con un resumen nuevo; navegar Volver o consultar el resumen sin intentar modificar no se bloquea. El pago pendiente sigue bloqueando cambios hasta outcome terminal seguro como supuesto funcional pendiente de decisión de Cristhian. La regla no concede por sí misma permiso para editar tras un outcome terminal ni decide reintentos de pago. Los hechos son lógicos tipados sin binding runtime acreditado de Paulo.","condicion":{"op":"y","izq":{"op":"y","izq":{"op":"=","izq":{"hecho":"chk007_intento_modificar_seleccion"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"chk007_violacion_seleccion_inmutable"},"der":{"lit":true}}},"der":{"op":"o","izq":{"op":"=","izq":{"hecho":"checkout_en_confirmacion"},"der":{"lit":true}},"der":{"op":"=","izq":{"hecho":"chk007_pago_enviado_no_terminal_seguro"},"der":{"lit":true}}}},"efecto":"BLOQUEAR","autoridad":"LEG-TECNICO","impacto":"REVISAR","origen":{"tipo":"CHAT","ref":"Cristhian 2026-11-23 17:47 Lima; Claude traspaso Tanda7 REG_CHK_007","solicitante":"Cristhian Lujan"},"version_anterior":1,"hash_anterior":"e9744cd5013e09e0fa26faefc99094ed880daf7ac7afd7252d05a50614c39057","motivo_revision":"Evitar bloquear toda confirmación; bloquear solo modificación violatoria y contexto confirmado o pago enviado no terminal.","pruebas":[{"casuistica":"NO_SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":false,"chk007_violacion_seleccion_inmutable":false,"checkout_en_confirmacion":true,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":true,"checkout_en_confirmacion":true,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":false,"checkout_en_confirmacion":true,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":false,"chk007_violacion_seleccion_inmutable":false,"checkout_en_confirmacion":true,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":false,"checkout_en_confirmacion":false,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":false,"checkout_en_confirmacion":false,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":true,"checkout_en_confirmacion":false,"chk007_pago_enviado_no_terminal_seguro":true},"esperado":true},{"casuistica":"SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":true,"checkout_en_confirmacion":true,"chk007_pago_enviado_no_terminal_seguro":true},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":false,"chk007_violacion_seleccion_inmutable":false,"checkout_en_confirmacion":false,"chk007_pago_enviado_no_terminal_seguro":true},"esperado":false},{"casuistica":"NO_SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":false,"checkout_en_confirmacion":false,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":false},{"casuistica":"SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":true,"checkout_en_confirmacion":true,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":true},{"casuistica":"NO_SE_CUMPLE","entrada":{"chk007_intento_modificar_seleccion":true,"chk007_violacion_seleccion_inmutable":true,"checkout_en_confirmacion":false,"chk007_pago_enviado_no_terminal_seguro":false},"esperado":false}]}'::jsonb;
 res:=lf_ops.nucleo_regla_proponer_v1(p,false);
 IF res->>'resultado'<>'EVALUADA_SIN_ESCRIBIR' OR (res->>'bloqueantes')::int<>0 THEN RAISE EXCEPTION 'CHK007_PREFLIGHT %',res; END IF;
 res:=lf_ops.nucleo_regla_proponer_v1(p,true);
 IF res->>'resultado'<>'CANDIDATA' OR (res->>'version')::int<>2 THEN RAISE EXCEPTION 'CHK007_V2_NOT_CANDIDATE %',res; END IF;
 SELECT count(*) INTO ntests FROM lf_ops.nucleo_regla_pruebas WHERE regla='REG_CHK_007' AND version=2;
 IF ntests<>12 THEN RAISE EXCEPTION 'CHK007_TEST_COUNT %',ntests; END IF;
 -- Negativo por defecto v1: sin intento en confirmación no se debe bloquear.
 checked:=lf_ops.nucleo_eval_v1((SELECT condicion FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_007' AND version=2),
    '{"chk007_intento_modificar_seleccion":false,"chk007_violacion_seleccion_inmutable":false,"checkout_en_confirmacion":true,"chk007_pago_enviado_no_terminal_seguro":false}'::jsonb);
 IF checked IS DISTINCT FROM 'false'::jsonb THEN RAISE EXCEPTION 'CHK007_MUTANT_INTENT_MISSING_NOT_DETECTED'; END IF;
 previous:=lf_ops.nucleo_eval_v1((SELECT condicion FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_007' AND version=1),
    '{"checkout_en_confirmacion":true}'::jsonb);
 IF previous IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'CHK007_V1_DEFECT_NOT_REPRODUCED'; END IF;
 e:=lf_ops.nucleo_regla_evaluar_v1('REG_CHK_007',true);
 IF e->>'decision'='AUTO' THEN RAISE EXCEPTION 'CHK007_UNJUDGED_AUTO'; END IF;
 IF (SELECT estado FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_007' AND version=2)<>'CANDIDATA'
  OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo='REG_CHK_007')<>'CANDIDATA'
  OR (SELECT estado FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_007' AND version=1)<>'DESCARTADA'
 THEN RAISE EXCEPTION 'CHK007_LIFECYCLE_DRIFT'; END IF;
 v2hash:=lf_ops.nucleo_hash_paquete_v1('REG_CHK_007',2);
 RAISE NOTICE 'CHK007_V2_RESULT %',jsonb_build_object('regla','REG_CHK_007','version',2,'hash_version',(SELECT hash FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_007' AND version=2),'hash_paquete',v2hash,'nota',e->'nota','decision',e->>'decision','pruebas',ntests,'promocion','NO_PROMOVIDA');
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-NUCLEO-REG-CHK-007-V2-REVISION-PENDIENTE-20261123-001') THEN RAISE EXCEPTION 'CHK007_EKB_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia)
 VALUES('LF-NUCLEO-REG-CHK-007-V2-REVISION-PENDIENTE-20261123-001','NUCLEO_REGLAS','REG_CHK_007 v2 intento y violación','V1 bloqueaba toda confirmación sin hecho de intento. V2 solo bloquea intento de cambio violatorio en confirmación o pago enviado sin outcome terminal seguro; pendiente juicio independiente y supuesto de pago pendiente.','Condición anterior evaluaba pantalla y no acción de modificación.','NUCLEO_INTENTO_VIOLACION','Distinguir navegación, intento y violación; no declarar binding runtime; pago pendiente requiere decisión de Cristhian; no promocionar sin juicio.','PG17 12 pruebas, negativo v1, BEGIN ROLLBACK exacto, núcleo 17/17, lector IG 14/14.','MEDIUM',1,now(),now(),'REG-CHK-007-V2-20261123','ACTIVO','docs/nucleo/LF_REG_CHK_007_V2_SELECCION_INMUTABLE_20261123.md');
 IF (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM lf_ops.reglas r) IS DISTINCT FROM oldlegacy
 OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.codigo) FROM lf_ops.nucleo_reglas r WHERE r.codigo<>'REG_CHK_007') IS DISTINCT FROM oldother
 OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_regla_versiones r WHERE r.regla<>'REG_CHK_007') IS DISTINCT FROM oldversions
 OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.version) FROM lf_ops.nucleo_deprecaciones r) IS DISTINCT FROM olddeprec
 OR (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.regla,r.nodo) FROM lf_ops.nucleo_aplicaciones r) IS DISTINCT FROM oldapps
 OR (SELECT count(*) FROM public.lf_error_knowledge)<>oldekb+1
 OR (SELECT count(*) FROM lf_ops.nucleo_reglas WHERE estado='VIGENTE')<>57
 THEN RAISE EXCEPTION 'CHK007_UNAUTHORIZED_DRIFT'; END IF;
 RAISE NOTICE 'CHK007_V2_PASS candidate only; legacy/IG unchanged; no deprecation';
END $batch$;
COMMIT;
