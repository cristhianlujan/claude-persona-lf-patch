-- LF puente de cobertura por INTENCION: REEMPLAZADA cuenta; PARCIAL no cuenta.
-- Preserva legadas, IG, lectores, versiones y deprecaciones.
BEGIN;
DO $baseline$ BEGIN
 IF (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada)<>6
 OR (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada WHERE equivalencia='EQUIVALENCIA_TOTAL')<>1
 OR (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada WHERE equivalencia='PARCIAL')<>5
 OR (SELECT count(*) FROM lf_ops.reglas) NOT IN (215,586)
 OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE regla IN ('S1-C01','S1-C02','S1-C03','S1-C04','S1-C05','S1-C06') AND version=1 AND estado='PUBLICADA')<>6
 THEN RAISE EXCEPTION 'COBERTURA_V2_BASELINE_DRIFT'; END IF;
END $baseline$;
ALTER TABLE lf_ops.lf_nucleo_cobertura_legada
 DROP CONSTRAINT lf_nucleo_cobertura_legada_equivalencia_check;
ALTER TABLE lf_ops.lf_nucleo_cobertura_legada
 RENAME COLUMN equivalencia TO estado_cobertura;
ALTER TABLE lf_ops.lf_nucleo_cobertura_legada
 ADD COLUMN diferencias text NOT NULL DEFAULT '';
-- Se conservan las fuentes originales en evidencia. Diferencias no son residuales:
-- un residual solo persiste cuando queda parte de la intención sin cubrir.
UPDATE lf_ops.lf_nucleo_cobertura_legada c SET
 estado_cobertura=CASE WHEN c.legacy_id IN (22,124,126) THEN 'REEMPLAZADA' ELSE 'PARCIAL' END,
 diferencias=CASE c.legacy_id
 WHEN 22 THEN 'La regla del núcleo bloquea el intento de persistencia sin hash en producción; no regula lecturas ni demuestra el binding físico. Sandbox/prototipo permanece fuera del bloqueo.'
 WHEN 25 THEN 'La nueva regla se acota a consultas backend en contexto de validación; la legada exige validación de formato previa para todos los campos consultados. La prevención de inyección no está acreditada.'
 WHEN 124 THEN 'La nueva regla bloquea despacho OTP si la autenticación interna es inválida sin imponer tipo de header API key/Bearer ni respuesta HTTP 401. Diferencia operativa de contrato HTTP, no de intención de impedir despachos no autorizados.'
 WHEN 125 THEN 'La nueva regla verifica HMAC y ventana temporal al aceptar peticiones; no impone generación e inclusión de firma, timestamp y secreto compartido en cada petición ni rechazo silencioso.'
 WHEN 126 THEN 'La nueva regla usa inelegibilidad agregada calculada por backend y bloquea el despacho; la legada enumera session_id, otp_verified, reenvíos, cooldown y la consulta Supabase previa a Meta Cloud API. El binding y las fuentes físicas siguen sin certificarse.'
 WHEN 130 THEN 'La nueva regla exige un tiempo mínimo; la legada además exige independencia temporal del punto donde se detectó el error, mitigación no demostrada por el umbral mínimo.'
 END,
 evidencia=CASE WHEN c.legacy_id IN (22,124,126)
 THEN jsonb_set(jsonb_set(c.evidencia,'{residual}','""'::jsonb,true),'{alcance}','"INTENCION_CUBIERTA_SIN_CERTIFICAR_RUNTIME"'::jsonb,true)
 ELSE c.evidencia END,
 revisado_por='GPT-6 contraste intencion V2 autorizado 2026-11-23',
 fecha=now()
WHERE c.legacy_id IN (22,25,124,125,126,130);
ALTER TABLE lf_ops.lf_nucleo_cobertura_legada
 ADD CONSTRAINT lf_nucleo_cobertura_legada_estado_cobertura_check
 CHECK (estado_cobertura IN ('REEMPLAZADA','PARCIAL')),
 ADD CONSTRAINT lf_nucleo_cobertura_legada_diferencias_check
 CHECK (length(diferencias)<=4000);
CREATE OR REPLACE FUNCTION lf_ops.lf_cobertura_legada_guard_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog','lf_ops' AS $guard$
DECLARE estado text; vigente text; hash_actual text; residual text;
BEGIN
 SELECT v.estado,r.estado INTO estado,vigente FROM nucleo_regla_versiones v
 JOIN nucleo_reglas r ON r.codigo=v.regla
 WHERE v.regla=NEW.nucleo_codigo AND v.version=NEW.version_nucleo;
 IF estado IS DISTINCT FROM 'PUBLICADA' OR vigente IS DISTINCT FROM 'VIGENTE'
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LF_COBERTURA_REGLA_NO_PUBLICADA'; END IF;
 hash_actual:=nucleo_hash_paquete_v1(NEW.nucleo_codigo,NEW.version_nucleo);
 IF hash_actual IS DISTINCT FROM NEW.hash_paquete
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LF_COBERTURA_HASH_PAQUETE_INVALIDO'; END IF;
 IF length(btrim(coalesce(NEW.evidencia->>'fuente','')))<8
    OR length(btrim(coalesce(NEW.evidencia->>'contraste','')))<30
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LF_COBERTURA_EVIDENCIA_INSUFICIENTE'; END IF;
 residual:=btrim(coalesce(NEW.evidencia->>'residual',''));
 IF NEW.estado_cobertura='PARCIAL' AND length(residual)<15
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LF_COBERTURA_RESIDUAL_REQUERIDO'; END IF;
 IF NEW.estado_cobertura='REEMPLAZADA' AND residual<>''
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LF_COBERTURA_RESIDUAL_NO_CUBIERTO'; END IF;
 IF length(btrim(coalesce(NEW.diferencias,'')))>4000
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LF_COBERTURA_DIFERENCIAS_EXCESIVAS'; END IF;
 RETURN NEW;
END $guard$;
-- Negativos bajo SAVEPOINT; ninguna prueba se conserva.
SAVEPOINT cobertura_v2_probe;
DO $probe$
DECLARE ok boolean; n integer;
BEGIN
 SELECT count(DISTINCT c.legacy_id) INTO n FROM lf_ops.lf_nucleo_cobertura_legada c
 JOIN lf_ops.nucleo_regla_versiones v ON v.regla=c.nucleo_codigo AND v.version=c.version_nucleo
 WHERE c.estado_cobertura='REEMPLAZADA' AND v.estado='PUBLICADA';
 IF n<>3 THEN RAISE EXCEPTION 'COBERTURA_V2_TOTAL_INCORRECTO %',n; END IF;
 ok:=false;
 BEGIN
   UPDATE lf_ops.lf_nucleo_cobertura_legada
    SET estado_cobertura='REEMPLAZADA'
   WHERE legacy_id=25;
 EXCEPTION WHEN check_violation THEN ok:=SQLERRM='LF_COBERTURA_RESIDUAL_NO_CUBIERTO'; END;
 IF NOT ok THEN RAISE EXCEPTION 'COBERTURA_V2_PARTIAL_WRONGLY_COUNTED'; END IF;
 ok:=false;
 BEGIN
   UPDATE lf_ops.lf_nucleo_cobertura_legada
   SET hash_paquete=repeat('0',64) WHERE legacy_id=22;
 EXCEPTION WHEN check_violation THEN ok:=SQLERRM='LF_COBERTURA_HASH_PAQUETE_INVALIDO'; END;
 IF NOT ok THEN RAISE EXCEPTION 'COBERTURA_V2_BAD_HASH_ACCEPTED'; END IF;
 ok:=false;
 BEGIN
   UPDATE lf_ops.lf_nucleo_cobertura_legada
    SET evidencia=jsonb_set(evidencia,'{residual}','""'::jsonb)
   WHERE legacy_id=25;
 EXCEPTION WHEN check_violation THEN ok:=SQLERRM='LF_COBERTURA_RESIDUAL_REQUERIDO'; END;
 IF NOT ok THEN RAISE EXCEPTION 'COBERTURA_V2_MISSING_RESIDUAL_ACCEPTED'; END IF;
 RAISE NOTICE 'COBERTURA_V2_NEGATIVOS_PASS partial_hash_residual';
END $probe$;
ROLLBACK TO SAVEPOINT cobertura_v2_probe;
DO $final$
DECLARE n int;
BEGIN
 SELECT count(DISTINCT c.legacy_id) INTO n FROM lf_ops.lf_nucleo_cobertura_legada c
 JOIN lf_ops.nucleo_regla_versiones v ON v.regla=c.nucleo_codigo AND v.version=c.version_nucleo
 WHERE c.estado_cobertura='REEMPLAZADA' AND v.estado='PUBLICADA';
 IF n<>3
 OR (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada WHERE estado_cobertura='PARCIAL')<>3
 OR (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada WHERE length(btrim(diferencias))<15)<>0
 OR (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada)<>6
 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
 THEN RAISE EXCEPTION 'COBERTURA_V2_FINAL_INVARIANT'; END IF;
 RAISE NOTICE 'COBERTURA_V2_PASS reemplazadas=3 parciales=3 delta_reemplazadas=2 legacy_unchanged';
END $final$;
COMMIT;
