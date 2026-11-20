-- IG Chat12, familia A: TODAS las 20 variables numéricas faltantes
-- de las 22 reglas. Sin cambios de textos, políticas ni valor_config en este PR.
-- Datos fuente: SELECT real de lf_ops.reglas VIGENTE, lectura de configuracion
-- preexistente, version 1 del historial. Los números son VALORES de config,
-- nunca literales agregados a texto de regla.
BEGIN;
CREATE TEMP TABLE ig_chat12_family_a_config_source (
 config_key text PRIMARY KEY, config_value text NOT NULL, codigo text NOT NULL,
 source_field text NOT NULL, source_expected text NOT NULL
) ON COMMIT DROP;
INSERT INTO ig_chat12_family_a_config_source
(config_key,config_value,codigo,source_field,source_expected)
VALUES
  ('OTP_MAX_RESENDS','3','REG_ATQ_012','max_resends','3'),
  ('OTP_EXHAUSTION_COOLDOWN_SECONDS','120','REG_ATQ_012','cooldown_after_exhaustion_seconds','120'),
  ('OTP_ORDINARY_RESEND_TIMER_SECONDS','45','REG_RATE_005','cooldown_segundos','45'),
  ('OTP_RESEND_LIMIT_COOLDOWN_MINUTES','2','REG_RL_002','bloqueo_minutos','2'),
  ('PHONE_UPDATE_MAX_PER_SESSION','3','REG_RL_003','max_cambios','3'),
  ('ONBOARDING_UNVERIFIED_SESSION_EXPIRATION_MINUTES','30','REG_SES_001','expiracion_minutos','30'),
  ('IDEMPOTENCY_KEY_VALIDITY_MINUTES','5','REG_TEC_009','ventana_validez_minutos','5'),
  ('FAILED_PHONE_PER_DNI_LIMIT','3','REG_ATQ_017','max_celulares_por_dni_fallidos','3'),
  ('FAILED_PHONE_PER_DNI_WINDOW_HOURS','24','REG_ATQ_017','ventana_horas','24'),
  ('SESSION_ACCESS_TOKEN_TTL_SECONDS','3600','REG_ATQ_018','access_token_ttl_seconds','3600'),
  ('SESSION_IDLE_TIMEOUT_SECONDS','86400','REG_ATQ_018','idle_timeout_seconds','86400'),
  ('SESSION_ABSOLUTE_TIMEOUT_SECONDS','2592000','REG_ATQ_018','absolute_timeout_seconds','2592000'),
  ('JWT_DISTINCT_GEO_LIMIT','2','REG_ATQ_020','condicion','2_geos_distintas_en_10min'),
  ('JWT_GEO_WINDOW_MINUTES','10','REG_ATQ_020','condicion','2_geos_distintas_en_10min'),
  ('REGISTRATION_PER_IP_MAX_ATTEMPTS','5','REG_RATE_001','max_envios','5'),
  ('REGISTRATION_PER_IP_WINDOW_MINUTES','10','REG_RATE_001','ventana_minutos','10'),
  ('OTP_VALIDATION_PER_IP_MAX_ATTEMPTS','10','REG_RATE_002','max_intentos','10'),
  ('OTP_VALIDATION_PER_IP_WINDOW_MINUTES','10','REG_RATE_002','ventana_minutos','10'),
  ('ONBOARDING_PER_DNI_MAX_ATTEMPTS','3','REG_RATE_004','max_intentos','3'),
  ('ONBOARDING_PER_DNI_WINDOW_HOURS','24','REG_RATE_004','ventana_horas','24');
DO $pre$
BEGIN
 IF (SELECT count(*) FROM pg_temp.ig_chat12_family_a_config_source)<>20
 OR EXISTS (
  SELECT 1 FROM pg_temp.ig_chat12_family_a_config_source m
  LEFT JOIN lf_ops.reglas r ON r.codigo=m.codigo AND r.estado='VIGENTE'
  WHERE r.id IS NULL OR r.valor_config->>m.source_field IS DISTINCT FROM m.source_expected
 )
 OR EXISTS (
  SELECT 1 FROM public.lf_global_config g
  JOIN pg_temp.ig_chat12_family_a_config_source m
    ON g.scope='AUTH' AND g.config_key=m.config_key
 )
 OR NOT EXISTS(SELECT 1 FROM public.lf_global_config
   WHERE scope='AUTH' AND config_key='OTP_MAX_ATTEMPTS'
   AND config_value='5' AND value_type='INTEGER' AND value_status='REAL')
 OR (SELECT valor_config->>'max_cambios' FROM lf_ops.reglas WHERE codigo='REG_SEG_005')
  IS DISTINCT FROM '3'
 OR (SELECT valor_config->>'max_resends' FROM lf_ops.reglas WHERE codigo='REG_ATQ_012')
  IS DISTINCT FROM (SELECT valor_config->>'otp_resend_max' FROM lf_ops.reglas WHERE codigo='REG_SEG_002')
 OR (SELECT valor_config->>'cooldown_after_exhaustion_seconds' FROM lf_ops.reglas WHERE codigo='REG_ATQ_012')
  IS DISTINCT FROM (SELECT valor_config->>'cooldown_agotamiento_segundos' FROM lf_ops.reglas WHERE codigo='REG_RATE_005')
 OR (SELECT valor_config->>'cooldown_segundos' FROM lf_ops.reglas WHERE codigo='REG_RATE_005')
  IS DISTINCT FROM (SELECT valor_config->>'cooldown_segundos' FROM lf_ops.reglas WHERE codigo='REG_RL_001')
 THEN RAISE EXCEPTION 'IG_CHAT12_FAMILY_A_CONFIG_SOURCE_DRIFT'; END IF;
END $pre$;
SAVEPOINT ig_chat12_family_a_config_reversible;
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
SELECT 'AUTH',config_key,config_value,'INTEGER','REAL',
  'Familia A/IG: límite existente de '||codigo||', campo '||source_field||
  '; valor operativo conservado; no activa backend ni cambia reglas.'
FROM pg_temp.ig_chat12_family_a_config_source ORDER BY config_key;
DO $probe$
BEGIN
 IF (SELECT count(*) FROM public.lf_global_config g
    JOIN pg_temp.ig_chat12_family_a_config_source m
      ON g.scope='AUTH' AND g.config_key=m.config_key
    WHERE g.value_type='INTEGER' AND g.value_status='REAL'
      AND g.config_value=m.config_value
      AND public.lf_auth_config_integer_v1(m.config_key)=m.config_value::integer)<>20
 THEN RAISE EXCEPTION 'IG_CHAT12_FAMILY_A_CONFIG_REVERSIBLE_PROBE_FAILED'; END IF;
END $probe$;
ROLLBACK TO SAVEPOINT ig_chat12_family_a_config_reversible;
RELEASE SAVEPOINT ig_chat12_family_a_config_reversible;
DO $rollback_readback$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_global_config g
    JOIN pg_temp.ig_chat12_family_a_config_source m
      ON g.scope='AUTH' AND g.config_key=m.config_key)
 THEN RAISE EXCEPTION 'IG_CHAT12_FAMILY_A_REAL_ROLLBACK_FAILED'; END IF;
END $rollback_readback$;
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_type,value_status,description)
SELECT 'AUTH',config_key,config_value,'INTEGER','REAL',
  'Familia A/IG: límite existente de '||codigo||', campo '||source_field||
  '; valor operativo conservado; no activa backend ni cambia reglas.'
FROM pg_temp.ig_chat12_family_a_config_source ORDER BY config_key;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.lf_global_config g
    JOIN pg_temp.ig_chat12_family_a_config_source m
      ON g.scope='AUTH' AND g.config_key=m.config_key
    WHERE g.value_type='INTEGER' AND g.value_status='REAL'
      AND g.config_value=m.config_value
      AND public.lf_auth_config_integer_v1(m.config_key)=m.config_value::integer)<>20
 THEN RAISE EXCEPTION 'IG_CHAT12_FAMILY_A_CONFIG_INSERT_READBACK_FAILED'; END IF;
 RAISE NOTICE 'IG_CHAT12_FAMILY_A_CONFIG_20_OF_20_REAL; SAVEPOINT_ROLLBACK_PASS; RULES_UNCHANGED';
END $post$;
COMMIT;
