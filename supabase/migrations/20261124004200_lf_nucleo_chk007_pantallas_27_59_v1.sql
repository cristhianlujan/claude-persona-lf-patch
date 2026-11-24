-- REG_CHK_007 v3: restringir SOLO_AQUI a confirmacion (27) y seleccion de pago (59).
-- Prueba PG17: mutacion negativa de pantalla legal, prueba positiva, rollback real de savepoint y commit gobernado.
BEGIN;
DO $pre$
DECLARE h text;
BEGIN
 IF (SELECT count(*) FROM lf_ops.nucleo_aplicaciones WHERE regla='REG_CHK_007' AND nodo='CLIENTE' AND modo='HEREDA')<>1
    OR (SELECT count(*) FROM lf_ops.nucleo_aplicaciones WHERE regla='REG_CHK_007')<>1
    OR (SELECT estado FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_007' AND version=3)<>'CANDIDATA'
    OR (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo='REG_CHK_007')<>'CANDIDATA'
    OR NOT EXISTS (SELECT 1 FROM lf_ops.nucleo_juicios WHERE regla='REG_CHK_007' AND version=3 AND veredicto='PASS' AND modo='INDEPENDIENTE')
 THEN RAISE EXCEPTION 'CHK007_SCOPE_BASELINE_DRIFT'; END IF;
 h:=lf_ops.nucleo_hash_paquete_v1('REG_CHK_007',3);
 IF h IS DISTINCT FROM '3f173fcf905cff20835c73d83fb5b22a4c9aaed2cd3ee6d7930e1a98e1b44ea2'
 THEN RAISE EXCEPTION 'CHK007_SCOPE_HASH_MISMATCH %',h; END IF;
 IF (SELECT count(*) FROM lf_ops.nucleo_nodos WHERE (pantalla_id=27 AND codigo='PANTALLA-27') OR (pantalla_id=59 AND codigo='PANTALLA-59'))<>2
    OR (SELECT codigo FROM lf_ops.pantallas WHERE id=36)<>'PANT_LIBRO_RECLAMACIONES'
 THEN RAISE EXCEPTION 'CHK007_SCOPE_SCREEN_DRIFT'; END IF;
END $pre$;
-- Negativo: vincular indebidamente la pantalla 36 DEBE aparecer en lectura nativa.
SAVEPOINT chk007_wrong_scope;
DELETE FROM lf_ops.nucleo_aplicaciones WHERE regla='REG_CHK_007';
INSERT INTO lf_ops.nucleo_aplicaciones(regla,nodo,modo)
VALUES('REG_CHK_007','PANTALLA-27','SOLO_AQUI'),
      ('REG_CHK_007','PANTALLA-59','SOLO_AQUI'),
      ('REG_CHK_007','PANTALLA-36','SOLO_AQUI');
DO $negative$
DECLARE p jsonb; a jsonb;
BEGIN
 p:=lf_ops.nucleo_regla_promover_v1('REG_CHK_007');
 IF p->>'resultado'<>'PROMOVIDA_AUTO' THEN RAISE EXCEPTION 'CHK007_SCOPE_NEGATIVE_PROMOTION_FAILED %',p; END IF;
 a:=lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS');
 IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(a->'nativas') n WHERE n->'version'->>'regla'='REG_CHK_007')
 THEN RAISE EXCEPTION 'CHK007_SCOPE_NEGATIVE_NOT_DETECTED %',a; END IF;
 RAISE NOTICE 'CHK007_SCOPE_NEGATIVE_DETECTED legal_screen_36_native=true';
END $negative$;
ROLLBACK TO SAVEPOINT chk007_wrong_scope;
-- Positivo: dos pantallas correctas, legal libre, sin cambiar version/pruebas.
SAVEPOINT chk007_correct_scope;
DELETE FROM lf_ops.nucleo_aplicaciones WHERE regla='REG_CHK_007';
INSERT INTO lf_ops.nucleo_aplicaciones(regla,nodo,modo)
VALUES('REG_CHK_007','PANTALLA-27','SOLO_AQUI'),('REG_CHK_007','PANTALLA-59','SOLO_AQUI');
DO $positive$
DECLARE p jsonb; a jsonb; sid int;
BEGIN
 p:=lf_ops.nucleo_regla_promover_v1('REG_CHK_007');
 IF p->>'resultado'<>'PROMOVIDA_AUTO' THEN RAISE EXCEPTION 'CHK007_SCOPE_POSITIVE_PROMOTION_FAILED %',p; END IF;
 FOR sid IN SELECT unnest(ARRAY[27,59]) LOOP
  a:=lf_ops.lf_nucleo_lectura_transicion_v1(sid,'INPUT_GOVERNANCE','DIRECTAS');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(a->'nativas') n WHERE n->'version'->>'regla'='REG_CHK_007')
  THEN RAISE EXCEPTION 'CHK007_SCOPE_NATIVE_MISSING % %',sid,a; END IF;
 END LOOP;
 a:=lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS');
 IF COALESCE(jsonb_array_length(a->'nativas'),0)<>0 THEN RAISE EXCEPTION 'CHK007_SCOPE_LEGAL_CONTAMINATION %',a; END IF;
 RAISE NOTICE 'CHK007_SCOPE_POSITIVE_PASS screens_27_59_native screen_36_empty';
END $positive$;
ROLLBACK TO SAVEPOINT chk007_correct_scope;
DO $rollback$
BEGIN
 IF (SELECT estado FROM lf_ops.nucleo_reglas WHERE codigo='REG_CHK_007')<>'CANDIDATA'
   OR (SELECT count(*) FROM lf_ops.nucleo_aplicaciones WHERE regla='REG_CHK_007' AND nodo='CLIENTE')<>1
 THEN RAISE EXCEPTION 'CHK007_SCOPE_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'CHK007_SCOPE_ROLLBACK_PASS candidate_and_original_scope_restored';
END $rollback$;
-- Escritura persistente exclusivamente por el Train.
DELETE FROM lf_ops.nucleo_aplicaciones WHERE regla='REG_CHK_007';
INSERT INTO lf_ops.nucleo_aplicaciones(regla,nodo,modo)
VALUES('REG_CHK_007','PANTALLA-27','SOLO_AQUI'),('REG_CHK_007','PANTALLA-59','SOLO_AQUI');
DO $final$
DECLARE p jsonb; a jsonb; sid int;
BEGIN
 p:=lf_ops.nucleo_regla_promover_v1('REG_CHK_007');
 IF p->>'resultado'<>'PROMOVIDA_AUTO' THEN RAISE EXCEPTION 'CHK007_SCOPE_COMMIT_FAILED %',p; END IF;
 FOR sid IN SELECT unnest(ARRAY[27,59]) LOOP
  a:=lf_ops.lf_nucleo_lectura_transicion_v1(sid,'INPUT_GOVERNANCE','DIRECTAS');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(a->'nativas') n WHERE n->'version'->>'regla'='REG_CHK_007') THEN RAISE EXCEPTION 'CHK007_SCOPE_FINAL_NATIVE_MISSING %',sid; END IF;
 END LOOP;
 a:=lf_ops.lf_nucleo_lectura_transicion_v1(36,'INPUT_GOVERNANCE','DIRECTAS');
 IF COALESCE(jsonb_array_length(a->'nativas'),0)<>0
    OR (SELECT count(*) FROM lf_ops.nucleo_aplicaciones WHERE regla='REG_CHK_007')<>2
    OR (SELECT estado FROM lf_ops.nucleo_regla_versiones WHERE regla='REG_CHK_007' AND version=3)<>'PUBLICADA'
    OR (SELECT count(*) FROM lf_ops.nucleo_regla_pruebas WHERE regla='REG_CHK_007' AND version=3)<>11
    OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
 THEN RAISE EXCEPTION 'CHK007_SCOPE_FINAL_INVARIANT'; END IF;
 RAISE NOTICE 'CHK007_SCOPE_COMMIT_PASS published_v3 screens_27_59 legal_36_zero';
END $final$;
COMMIT;
