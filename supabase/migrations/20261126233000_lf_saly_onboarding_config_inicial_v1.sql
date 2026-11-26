-- SALY: solo configuracion inicial aprobada de onboarding. Sin dependencia LF/Overall.
-- Fuente: documento 12_Homologacion_Parametros_Onboarding_SALY.md (1xauDwGTB6epKv2jlOU6ckQoKHbk7sk3u).
-- Excluye valores sin definir, lista exacta de caracteres, proveedores, binding runtime y reglas.
-- No DDL, grants, cambios de otros modulos ni habilitacion de runtime.
BEGIN;
DO $seed$
DECLARE
 p record;
 n integer := 0;
BEGIN
 FOR p IN SELECT * FROM (VALUES
    ('AUTH', 'OTP_LENGTH', '6', 'Longitud del codigo OTP en digitos. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'OTP_EXPIRATION_MINUTES', '5', 'Vigencia del codigo OTP en minutos. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'OTP_MAX_ATTEMPTS', '5', 'Maximo de intentos por codigo. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'OTP_MAX_RESENDS', '3', 'Maximo de reenvios. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'OTP_RESEND_WAIT_SECONDS', '45', 'Espera ordinaria entre reenvios en segundos. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'OTP_COOLDOWN_SECONDS', '120', 'Pausa temporal por agotamiento del codigo en segundos. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'PASSWORD_MIN_LENGTH', '8', 'Longitud minima de contrasena. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'PASSWORD_MIN_UPPERCASE', '1', 'Minimo de letras mayusculas. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'PASSWORD_MIN_LOWERCASE', '1', 'Minimo de letras minusculas. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'PASSWORD_MIN_NUMBERS', '1', 'Minimo de numeros. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('AUTH', 'PASSWORD_MIN_SPECIAL', '1', 'Minimo de caracteres especiales permitidos; lista pendiente. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('BIOMETRIA', 'MAX_MATCH_ATTEMPTS', '5', 'Maximo de comparaciones biometricas fallidas confirmadas; no incluye fallas tecnicas. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('VALIDACION', 'CE_MIN_LENGTH', '9', 'Longitud minima de carne de extranjeria. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('VALIDACION', 'CE_MAX_LENGTH', '12', 'Longitud maxima de carne de extranjeria. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('VALIDACION', 'PASSPORT_MIN_LENGTH', '5', 'Longitud minima de pasaporte. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('VALIDACION', 'PASSPORT_MAX_LENGTH', '20', 'Longitud maxima de pasaporte. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.'),
    ('VALIDACION', 'EMAIL_MAX_LENGTH', '100', 'Longitud maxima del correo B2C. Fuente: conformidad del dueno, onboarding 26/11/2026; documento 12. Configuracion inicial, no activacion de runtime.')
 ) AS v(scope, config_key, config_value, description)
 LOOP
   IF EXISTS (
     SELECT 1 FROM saly.config_global g
     WHERE g.scope = p.scope AND g.config_key = p.config_key
   ) THEN
     RAISE EXCEPTION 'SALY_ONB_CONFIG_ALREADY_PRESENT: %.%', p.scope, p.config_key;
   END IF;
   INSERT INTO saly.config_global(scope, config_key, config_value, value_type, value_status, description)
   VALUES(p.scope, p.config_key, p.config_value, 'INTEGER', 'REAL', p.description);
   IF (SELECT count(*) FROM saly.config_global g WHERE g.scope=p.scope AND g.config_key=p.config_key AND g.config_value=p.config_value AND g.value_type='INTEGER' AND g.value_status='REAL') <> 1 THEN
     RAISE EXCEPTION 'SALY_ONB_CONFIG_READBACK_FAILED: %.%', p.scope, p.config_key;
   END IF;
   n := n + 1;
 END LOOP;
 IF n <> 17 THEN RAISE EXCEPTION 'SALY_ONB_CONFIG_COUNT_MISMATCH'; END IF;
 RAISE NOTICE 'SALY_ONB_CONFIG_INITIAL_VALUES %', n;
END $seed$;
-- Asociaciones al vocabulario de ONBOARDING, aprobacion de alcance 26/11/2026.
-- Hechos logicos de diseno, NO binding runtime. No se definen rangos no aprobados.
DO $bindings$
DECLARE p record; n integer:=0;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM saly.nucleo_familias WHERE codigo='ONBOARDING') THEN
  RAISE EXCEPTION 'SALY_ONB_BINDING_FAMILY_MISSING';
 END IF;
 FOR p IN SELECT * FROM (VALUES
    ('AUTH', 'OTP_LENGTH', 'otp_longitud_ingresada', 'cantidad', 'Longitud del OTP recibido en la verificacion del canal.'),
    ('AUTH', 'OTP_EXPIRATION_MINUTES', 'otp_edad_minutos', 'minutos', 'Edad del desafio OTP desde su emision autorizada.'),
    ('AUTH', 'OTP_MAX_ATTEMPTS', 'otp_intentos_fallidos', 'veces', 'Cantidad de intentos fallidos confirmados del desafio OTP.'),
    ('AUTH', 'OTP_MAX_RESENDS', 'otp_reenvios_confirmados', 'veces', 'Cantidad de reenvios confirmados del desafio OTP.'),
    ('AUTH', 'OTP_RESEND_WAIT_SECONDS', 'otp_segundos_desde_envio', 'segundos', 'Tiempo transcurrido desde el envio ordinario de OTP.'),
    ('AUTH', 'OTP_COOLDOWN_SECONDS', 'otp_segundos_desde_agotamiento', 'segundos', 'Tiempo transcurrido desde el agotamiento confirmado del desafio.'),
    ('AUTH', 'PASSWORD_MIN_LENGTH', 'pwd_longitud', 'cantidad', 'Longitud de la contrasena ingresada; solo conteo, no secreto.'),
    ('AUTH', 'PASSWORD_MIN_UPPERCASE', 'pwd_mayusculas', 'cantidad', 'Cantidad de letras mayusculas de la contrasena.'),
    ('AUTH', 'PASSWORD_MIN_LOWERCASE', 'pwd_minusculas', 'cantidad', 'Cantidad de letras minusculas de la contrasena.'),
    ('AUTH', 'PASSWORD_MIN_NUMBERS', 'pwd_numeros', 'cantidad', 'Cantidad de numeros de la contrasena.'),
    ('AUTH', 'PASSWORD_MIN_SPECIAL', 'pwd_especiales_permitidos', 'cantidad', 'Cantidad de caracteres especiales autorizados por politica SALY; lista pendiente.'),
    ('BIOMETRIA', 'MAX_MATCH_ATTEMPTS', 'bio_match_fallidos_confirmados', 'veces', 'Cantidad de comparaciones biometricas fallidas confirmadas; excluye calidad y fallas tecnicas.'),
    ('VALIDACION', 'CE_MIN_LENGTH', 'ce_longitud_min_evaluada', 'cantidad', 'Longitud de documento CE para evaluar limite inferior.'),
    ('VALIDACION', 'CE_MAX_LENGTH', 'ce_longitud_max_evaluada', 'cantidad', 'Longitud de documento CE para evaluar limite superior.'),
    ('VALIDACION', 'PASSPORT_MIN_LENGTH', 'pasaporte_longitud_min_evaluada', 'cantidad', 'Longitud de pasaporte para evaluar limite inferior.'),
    ('VALIDACION', 'PASSPORT_MAX_LENGTH', 'pasaporte_longitud_max_evaluada', 'cantidad', 'Longitud de pasaporte para evaluar limite superior.'),
    ('VALIDACION', 'EMAIL_MAX_LENGTH', 'correo_longitud', 'cantidad', 'Longitud del correo B2C para evaluar limite superior.')
 ) AS v(scope,config_key,hecho,unidad,descripcion)
 LOOP
  IF EXISTS(SELECT 1 FROM saly.nucleo_hechos h WHERE h.codigo=p.hecho)
   OR EXISTS(SELECT 1 FROM saly.nucleo_parametros q WHERE q.scope=p.scope AND q.config_key=p.config_key) THEN
   RAISE EXCEPTION 'SALY_ONB_BINDING_COLLISION %.%',p.scope,p.config_key;
  END IF;
  INSERT INTO saly.nucleo_hechos(codigo,tipo_dato,unidad,descripcion)
  VALUES(p.hecho,'integer',p.unidad,p.descripcion || ' Hecho logico propuesto; binding runtime pendiente.');
  INSERT INTO saly.nucleo_familia_vocabulario(familia,hecho,origen)
  VALUES('ONBOARDING',p.hecho,'CURADO');
  INSERT INTO saly.nucleo_parametros(scope,config_key,hecho,minimo,maximo,dueno)
  VALUES(p.scope,p.config_key,p.hecho,NULL,NULL,'PRODUCTO');
  IF NOT EXISTS(SELECT 1 FROM saly.nucleo_parametros q
    JOIN saly.nucleo_hechos h ON h.codigo=q.hecho
    JOIN saly.nucleo_familia_vocabulario v ON v.hecho=h.codigo AND v.familia='ONBOARDING'
    WHERE q.scope=p.scope AND q.config_key=p.config_key AND h.codigo=p.hecho
    AND h.tipo_dato='integer' AND h.unidad=p.unidad AND q.minimo IS NULL AND q.maximo IS NULL
    AND h.tabla_ref IS NULL AND h.columna_ref IS NULL AND h.campo_id IS NULL) THEN
   RAISE EXCEPTION 'SALY_ONB_BINDING_READBACK %.%',p.scope,p.config_key;
  END IF;
  n:=n+1;
 END LOOP;
 IF n<>17 THEN RAISE EXCEPTION 'SALY_ONB_BINDING_COUNT %',n; END IF;
 RAISE NOTICE 'SALY_ONB_CONFIG_BINDINGS %',n;
END $bindings$;
COMMIT;
