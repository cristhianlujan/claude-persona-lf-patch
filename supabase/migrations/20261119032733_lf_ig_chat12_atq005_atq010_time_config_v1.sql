-- IG Chat12 | Familia A | prerequisites REG_ATQ_005 and REG_ATQ_010.
-- Source-bound: numerical controls remain identical until separate governed
-- Product Director -> Step70 -> Owner V2 CORRECT_VIGENTE/FUNCTIONAL RUNs.
-- No direct modifications to rules or policies.
BEGIN;
DO $chat12_pre$
BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas
     WHERE codigo='REG_ATQ_005' AND estado='VIGENTE'
       AND valor_config->>'ventana_validez_segundos'='30'
       AND valor_config->>'algoritmo'='HMAC-SHA256')<>1
    OR (SELECT count(*) FROM lf_ops.reglas
     WHERE codigo='REG_ATQ_010' AND estado='VIGENTE'
       AND valor_config->>'tiempo_minimo_respuesta_ms'='200')<>1
    OR EXISTS(SELECT 1 FROM public.lf_global_config
      WHERE scope='AUTH'
        AND config_key IN ('OTP_HMAC_TIMESTAMP_WINDOW_SECONDS',
                           'ERROR_RESPONSE_MINIMUM_MS'))
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ005_010_PREIMAGE_OR_KEY_DRIFT'; END IF;
END $chat12_pre$;
SAVEPOINT ig_chat12_time_proof;
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
VALUES
('AUTH','OTP_HMAC_TIMESTAMP_WINDOW_SECONDS','30','INTEGER','REAL',
 'Ventana vigente de validez temporal de firma de peticiones OTP; preserva HMAC y verificaciones del webhook.'),
('AUTH','ERROR_RESPONSE_MINIMUM_MS','200','INTEGER','REAL',
 'Tiempo minimo vigente de respuesta de error para prevenir filtraciones por timing; aplica a validacion de identidad, telefono y OTP.');
DO $chat12_probe$
BEGIN
 IF public.lf_auth_config_integer_v1('OTP_HMAC_TIMESTAMP_WINDOW_SECONDS')<>30
    OR public.lf_auth_config_integer_v1('ERROR_RESPONSE_MINIMUM_MS')<>200
 THEN RAISE EXCEPTION 'IG_CHAT12_TIME_CONFIG_PROBE_FAILED'; END IF;
END $chat12_probe$;
ROLLBACK TO SAVEPOINT ig_chat12_time_proof;
RELEASE SAVEPOINT ig_chat12_time_proof;
DO $chat12_rollback_readback$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_global_config
      WHERE scope='AUTH'
        AND config_key IN ('OTP_HMAC_TIMESTAMP_WINDOW_SECONDS',
                           'ERROR_RESPONSE_MINIMUM_MS'))
 THEN RAISE EXCEPTION 'IG_CHAT12_TIME_CONFIG_ROLLBACK_NOT_CLEAN'; END IF;
END $chat12_rollback_readback$;
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
VALUES
('AUTH','OTP_HMAC_TIMESTAMP_WINDOW_SECONDS','30','INTEGER','REAL',
 'Ventana vigente de validez temporal de firma de peticiones OTP; preserva HMAC y verificaciones del webhook.'),
('AUTH','ERROR_RESPONSE_MINIMUM_MS','200','INTEGER','REAL',
 'Tiempo minimo vigente de respuesta de error para prevenir filtraciones por timing; aplica a validacion de identidad, telefono y OTP.');
DO $chat12_post$
BEGIN
 IF (SELECT count(*) FROM public.lf_global_config
      WHERE scope='AUTH'
        AND config_key IN ('OTP_HMAC_TIMESTAMP_WINDOW_SECONDS','ERROR_RESPONSE_MINIMUM_MS')
        AND value_type='INTEGER' AND value_status='REAL')<>2
   OR public.lf_auth_config_integer_v1('OTP_HMAC_TIMESTAMP_WINDOW_SECONDS')<>30
   OR public.lf_auth_config_integer_v1('ERROR_RESPONSE_MINIMUM_MS')<>200
   OR (SELECT valor_config->>'ventana_validez_segundos' FROM lf_ops.reglas
     WHERE codigo='REG_ATQ_005' AND estado='VIGENTE')<>'30'
   OR (SELECT valor_config->>'tiempo_minimo_respuesta_ms' FROM lf_ops.reglas
     WHERE codigo='REG_ATQ_010' AND estado='VIGENTE')<>'200'
 THEN RAISE EXCEPTION 'IG_CHAT12_TIME_CONFIG_POSTIMAGE_MISMATCH'; END IF;
 RAISE NOTICE 'IG_CHAT12_CONFIG_TWO_PASS; RULES_UNCHANGED; V2_PENDING';
END $chat12_post$;
COMMIT;
