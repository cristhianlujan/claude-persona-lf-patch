-- SALY: solo configuracion inicial aprobada de onboarding. Sin dependencia LF/Overall.
-- Fuente: documento 12_Homologacion_Parametros_Onboarding_SALY.md (1xauDwGTB6epKv2jlOU6ckQoKHbk7sk3u).
-- Excluye valores sin definir, lista exacta de caracteres, proveedores, bindings y reglas.
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
COMMIT;
