-- Puente N:M legadas -> version publicada del nucleo, evidencia funcional y residual sin lectores legacy.
BEGIN;
CREATE TABLE lf_ops.lf_nucleo_cobertura_legada (
 legacy_id integer NOT NULL REFERENCES lf_ops.reglas(id),
 nucleo_codigo text NOT NULL,
 version_nucleo integer NOT NULL CHECK (version_nucleo >= 1),
 equivalencia text NOT NULL CHECK (equivalencia IN ('EQUIVALENCIA_TOTAL','PARCIAL')),
 evidencia jsonb NOT NULL CHECK (jsonb_typeof(evidencia)='object'),
 hash_paquete text NOT NULL CHECK (hash_paquete ~ '^[0-9a-f]{64}$'),
 revisado_por text NOT NULL CHECK (length(btrim(revisado_por))>=3),
 fecha timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (legacy_id,nucleo_codigo,version_nucleo),
 FOREIGN KEY (nucleo_codigo,version_nucleo)
   REFERENCES lf_ops.nucleo_regla_versiones(regla,version)
);
REVOKE ALL ON lf_ops.lf_nucleo_cobertura_legada FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON lf_ops.lf_nucleo_cobertura_legada TO supabase_read_only_user;
CREATE FUNCTION lf_ops.lf_cobertura_legada_guard_v1() RETURNS trigger
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
 IF (NEW.equivalencia='PARCIAL' AND length(residual)<15)
    OR (NEW.equivalencia='EQUIVALENCIA_TOTAL' AND residual<>'')
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='LF_COBERTURA_RESIDUAL_INCONSISTENTE'; END IF;
 RETURN NEW;
END $guard$;
CREATE TRIGGER trg_lf_cobertura_legada_guard_v1
 BEFORE INSERT OR UPDATE ON lf_ops.lf_nucleo_cobertura_legada
 FOR EACH ROW EXECUTE FUNCTION lf_ops.lf_cobertura_legada_guard_v1();
DO $baseline$
BEGIN
 IF (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada)<>0
 OR (SELECT count(*) FROM lf_ops.reglas WHERE id IN (22,25,124,125,126,130))<>6
 OR (SELECT count(*) FROM lf_ops.nucleo_regla_versiones WHERE regla IN ('S1-C01','S1-C02','S1-C03','S1-C04','S1-C05','S1-C06') AND version=1 AND estado='PUBLICADA')<>6
 THEN RAISE EXCEPTION 'COBERTURA_BASELINE_INVALIDO'; END IF;
END $baseline$;
-- PG17 control: parcial sola no mueve métrica; total sí; negativos hash, residual y duplicado.
SAVEPOINT cobertura_probe;
INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,equivalencia,evidencia,hash_paquete,revisado_por)
VALUES(25,'S1-C02',1,'PARCIAL',
 jsonb_build_object('fuente','lf_ops.reglas/25 REG_SEG_007','contraste','Regla control parcial de formato antes de consultar el backend.','residual','Queda sin acreditar proteccion de inyeccion y todas las consultas.'),
 lf_ops.nucleo_hash_paquete_v1('S1-C02',1),'GPT-6 prueba gobernada');
DO $partial$
BEGIN
 IF (SELECT count(DISTINCT legacy_id) FROM lf_ops.lf_nucleo_cobertura_legada WHERE equivalencia='EQUIVALENCIA_TOTAL')<>0
 THEN RAISE EXCEPTION 'COBERTURA_PARCIAL_CONTADA_COMO_TOTAL'; END IF;
 RAISE NOTICE 'COBERTURA_PARTIAL_NOT_MIGRATED_PASS';
END $partial$;
INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,equivalencia,evidencia,hash_paquete,revisado_por)
VALUES(22,'S1-C01',1,'EQUIVALENCIA_TOTAL',
 jsonb_build_object('fuente','lf_ops.reglas/22 REG_SEG_004','contraste','La prohibicion de OTP en claro en produccion coincide con el bloqueo de persistencia sin hash.','residual',''),
 lf_ops.nucleo_hash_paquete_v1('S1-C01',1),'GPT-6 prueba gobernada');
DO $negative$
DECLARE ok boolean;
BEGIN
 IF (SELECT count(DISTINCT legacy_id) FROM lf_ops.lf_nucleo_cobertura_legada WHERE equivalencia='EQUIVALENCIA_TOTAL')<>1
 THEN RAISE EXCEPTION 'COBERTURA_TOTAL_NO_CONTADA'; END IF;
 ok:=false;
 BEGIN
  INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,equivalencia,evidencia,hash_paquete,revisado_por)
  VALUES(124,'S1-C03',1,'PARCIAL',jsonb_build_object('fuente','lf_ops.reglas/124 REG_ATQ_004','contraste','Prueba negativa de hash por version publicada y origen verificado.','residual','Faltan protocolo y codigo de respuesta.'),
  repeat('0',64),'GPT-6 prueba gobernada');
 EXCEPTION WHEN check_violation THEN ok:=SQLERRM='LF_COBERTURA_HASH_PAQUETE_INVALIDO'; END;
 IF NOT ok THEN RAISE EXCEPTION 'COBERTURA_BAD_HASH_ACCEPTED'; END IF;
 ok:=false;
 BEGIN
  INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,equivalencia,evidencia,hash_paquete,revisado_por)
  VALUES(130,'S1-C06',1,'PARCIAL',jsonb_build_object('fuente','lf_ops.reglas/130 REG_ATQ_010','contraste','Prueba negativa de cobertura con residual ausente y texto presente.','residual',''),
  lf_ops.nucleo_hash_paquete_v1('S1-C06',1),'GPT-6 prueba gobernada');
 EXCEPTION WHEN check_violation THEN ok:=SQLERRM='LF_COBERTURA_RESIDUAL_INCONSISTENTE'; END;
 IF NOT ok THEN RAISE EXCEPTION 'COBERTURA_NO_RESIDUAL_ACCEPTED'; END IF;
 ok:=false;
 BEGIN
  INSERT INTO lf_ops.lf_nucleo_cobertura_legada(legacy_id,nucleo_codigo,version_nucleo,equivalencia,evidencia,hash_paquete,revisado_por)
  VALUES(22,'S1-C01',1,'EQUIVALENCIA_TOTAL',jsonb_build_object('fuente','lf_ops.reglas/22 REG_SEG_004','contraste','Prueba negativa de clave duplicada en la misma version.','residual',''),
  lf_ops.nucleo_hash_paquete_v1('S1-C01',1),'GPT-6 prueba gobernada');
 EXCEPTION WHEN unique_violation THEN ok:=true; END;
 IF NOT ok THEN RAISE EXCEPTION 'COBERTURA_DUPLICATE_ACCEPTED'; END IF;
 RAISE NOTICE 'COBERTURA_NEGATIVE_PASS hash residual unique';
END $negative$;
ROLLBACK TO SAVEPOINT cobertura_probe;
DO $rollback$
BEGIN
 IF (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada)<>0
 THEN RAISE EXCEPTION 'COBERTURA_ROLLBACK_RESIDUE'; END IF;
 RAISE NOTICE 'COBERTURA_ROLLBACK_PASS empty';
END $rollback$;
-- Seis equivalencias revisadas contra texto original de lf_ops.reglas y condicion publicada.
INSERT INTO lf_ops.lf_nucleo_cobertura_legada
 (legacy_id,nucleo_codigo,version_nucleo,equivalencia,hash_paquete,evidencia,revisado_por)
SELECT (j->>'legacy_id')::integer,j->>'codigo',1,j->>'equivalencia',
 lf_ops.nucleo_hash_paquete_v1(j->>'codigo',1),j->'evidencia',
 'GPT-6 comparación funcional 2026-11-23'
FROM jsonb_array_elements('[{"legacy_id":22,"codigo":"S1-C01","equivalencia":"EQUIVALENCIA_TOTAL","evidencia":{"fuente":"lf_ops.reglas/22 REG_SEG_004","contraste":"El legado exige OTP almacenado como hash en producción y permite texto plano solo en sandbox/prototipo. S1-C01 bloquea el intento de persistir OTP sin hash en producción; no bloquea sandbox/prototipo. Equivalencia de obligación funcional, no prueba de binding runtime.","residual":"","alcance":"FUNCIONAL_SIN_BINDING_RUNTIME"}},{"legacy_id":25,"codigo":"S1-C02","equivalencia":"PARCIAL","evidencia":{"fuente":"lf_ops.reglas/25 REG_SEG_007","contraste":"S1-C02 bloquea consulta backend cuando el formato no está validado y el contexto está activo; coincide parcialmente con validación previa a consulta del legado.","residual":"No certifica prevención de inyección ni cobertura de todos los campos/consultas; no identifica entidad en hecho agregado.","alcance":"FUNCIONAL_PARCIAL"}},{"legacy_id":124,"codigo":"S1-C03","equivalencia":"PARCIAL","evidencia":{"fuente":"lf_ops.reglas/124 REG_ATQ_004","contraste":"S1-C03 bloquea despacho OTP por webhook n8n sin autenticación interna válida.","residual":"El legado exige header API key interna o Bearer token Supabase válido y rechazo HTTP 401; no están acreditados por la condición.","alcance":"FUNCIONAL_PARCIAL"}},{"legacy_id":125,"codigo":"S1-C04","equivalencia":"PARCIAL","evidencia":{"fuente":"lf_ops.reglas/125 REG_ATQ_005","contraste":"S1-C04 bloquea aceptar solicitud webhook OTP si el resultado agregado de firma HMAC o tiempo es inválido; el parámetro temporal se cita desde configuración.","residual":"No exige construir e incluir firma HMAC-SHA256 con secreto compartido configurable, timestamp en cada petición ni rechazo silencioso; cálculo backend sin binding.","alcance":"FUNCIONAL_PARCIAL"}},{"legacy_id":126,"codigo":"S1-C05","equivalencia":"PARCIAL","evidencia":{"fuente":"lf_ops.reglas/126 REG_ATQ_006","contraste":"S1-C05 bloquea despacho OTP cuando el backend marca inelegible la sesión OTP.","residual":"No comprueba individualmente existencia session_id, otp_verified=false, límite de reenvíos y cooldown ni la consulta Supabase antes de Meta Cloud API; solapa otras reglas ya publicadas.","alcance":"FUNCIONAL_PARCIAL"}},{"legacy_id":130,"codigo":"S1-C06","equivalencia":"PARCIAL","evidencia":{"fuente":"lf_ops.reglas/130 REG_ATQ_010","contraste":"S1-C06 bloquea respuesta de error de validación DNI/celular/OTP inferior al mínimo de AUTH/ERROR_RESPONSE_MINIMUM_MS.","residual":"Un piso de duración no demuestra tiempo de respuesta constante e independiente del momento de detección ni lectura runtime de configuración.","alcance":"FUNCIONAL_PARCIAL"}}]'::jsonb) j;
DO $final$
BEGIN
 IF (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada)<>6
 OR (SELECT count(DISTINCT legacy_id) FROM lf_ops.lf_nucleo_cobertura_legada WHERE equivalencia='EQUIVALENCIA_TOTAL')<>1
 OR (SELECT count(*) FROM lf_ops.lf_nucleo_cobertura_legada WHERE equivalencia='PARCIAL')<>5
 OR EXISTS (SELECT 1 FROM lf_ops.lf_nucleo_cobertura_legada c JOIN lf_ops.nucleo_regla_versiones v
    ON v.regla=c.nucleo_codigo AND v.version=c.version_nucleo WHERE v.estado<>'PUBLICADA')
 OR (SELECT count(*) FROM lf_ops.nucleo_deprecaciones)<>0
 THEN RAISE EXCEPTION 'COBERTURA_FINAL_INVARIANT'; END IF;
 RAISE NOTICE 'COBERTURA_FINAL_PASS six_links one_total_five_partial none_deprecated';
END $final$;
COMMIT;
