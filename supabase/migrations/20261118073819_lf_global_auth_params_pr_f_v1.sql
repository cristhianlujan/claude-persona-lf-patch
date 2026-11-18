-- PR-F | Nine independently sourced AUTH configuration values, no rule/policy DML.
-- Only public.lf_global_config is touched, through an authorized migration Train.
-- REAL is an owner-defined parameter value, NOT proof the consumer is production-ready.
DO $pre$
DECLARE
  v_existing integer;
  v_rls boolean;
  v_force boolean;
  v_policies integer;
BEGIN
  IF to_regclass('public.lf_global_config') IS NULL THEN
    RAISE EXCEPTION 'PR_F_GLOBAL_CONFIG_MISSING';
  END IF;
  SELECT relrowsecurity,relforcerowsecurity INTO v_rls,v_force
    FROM pg_class WHERE oid='public.lf_global_config'::regclass;
  SELECT count(*) INTO v_policies
    FROM pg_policies WHERE schemaname='public' AND tablename='lf_global_config';
  IF NOT v_rls OR NOT v_force OR v_policies<>0 THEN
    RAISE EXCEPTION 'PR_F_EXISTING_RLS_DRIFT';
  END IF;
  IF has_table_privilege('anon','public.lf_global_config','SELECT')
     OR has_table_privilege('authenticated','public.lf_global_config','SELECT')
     OR has_table_privilege('anon','public.lf_global_config','INSERT')
     OR has_table_privilege('authenticated','public.lf_global_config','INSERT')
  THEN RAISE EXCEPTION 'PR_F_EXISTING_CLIENT_PRIVILEGE_DRIFT'; END IF;
  SELECT count(*) INTO v_existing FROM public.lf_global_config
  WHERE scope='AUTH' AND config_key IN (
    'MFA_DEVICE_IDLE_DAYS','MFA_PASSWORD_AGE_MONTHS','TEMP_KEY_TTL_HOURS',
    'LOGIN_LOCKOUT_ATTEMPTS_1','LOGIN_LOCKOUT_MINUTES_1',
    'LOGIN_LOCKOUT_ATTEMPTS_2','LOGIN_LOCKOUT_MINUTES_2',
    'LOGIN_LOCKOUT_ATTEMPTS_3','LOGIN_LOCKOUT_MINUTES_3'
  );
  IF v_existing<>0 THEN
    RAISE EXCEPTION 'PR_F_AUTH_PARAMETER_PREEXISTENCE:%',v_existing;
  END IF;
END;
$pre$;

INSERT INTO public.lf_global_config
  (scope,config_key,config_value,value_type,value_status,description,valid_from)
VALUES
  ('AUTH','MFA_DEVICE_IDLE_DAYS','30','INTEGER','REAL',
    'Dias sin uso del dispositivo reconocido que obligan a OTP por correo en el siguiente inicio de sesion B2B.',now()),
  ('AUTH','MFA_PASSWORD_AGE_MONTHS','3','INTEGER','REAL',
    'Meses transcurridos desde el ultimo cambio de contrasena que activan MFA condicional para perfiles B2B 1 a 6.',now()),
  ('AUTH','TEMP_KEY_TTL_HOURS','24','INTEGER','REAL',
    'Horas de vigencia de una clave temporal de un solo uso emitida tras recuperacion asistida; no permite sesion operativa antes de definir clave nueva.',now()),
  ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_1','5','INTEGER','REAL',
    'Cantidad de fallos adicionales de contrasena hasta el primer bloqueo; sujeto, ventana y reinicio siguen pendientes de definicion.',now()),
  ('AUTH','LOGIN_LOCKOUT_MINUTES_1','15','INTEGER','REAL',
    'Duracion en minutos del primer bloqueo tras el primer tramo de fallos de contrasena.',now()),
  ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_2','3','INTEGER','REAL',
    'Fallos adicionales de contrasena para el segundo bloqueo tras el primer tramo; sujeto, ventana y reinicio pendientes.',now()),
  ('AUTH','LOGIN_LOCKOUT_MINUTES_2','60','INTEGER','REAL',
    'Duracion en minutos del segundo bloqueo de contrasena tras el segundo tramo.',now()),
  ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_3','3','INTEGER','REAL',
    'Fallos adicionales de contrasena para el tercer bloqueo; sujeto, ventana y reinicio pendientes.',now()),
  ('AUTH','LOGIN_LOCKOUT_MINUTES_3','1440','INTEGER','REAL',
    'Duracion en minutos del tercer bloqueo de contrasena tras el tercer tramo.',now());

DO $after$
DECLARE
  v_expected int:=9;
  v_found int;
  v_bad int;
BEGIN
  WITH wanted(k,v) AS (
    VALUES
      ('MFA_DEVICE_IDLE_DAYS','30'),('MFA_PASSWORD_AGE_MONTHS','3'),
      ('TEMP_KEY_TTL_HOURS','24'),('LOGIN_LOCKOUT_ATTEMPTS_1','5'),
      ('LOGIN_LOCKOUT_MINUTES_1','15'),('LOGIN_LOCKOUT_ATTEMPTS_2','3'),
      ('LOGIN_LOCKOUT_MINUTES_2','60'),('LOGIN_LOCKOUT_ATTEMPTS_3','3'),
      ('LOGIN_LOCKOUT_MINUTES_3','1440')
  )
  SELECT count(*),count(*) FILTER (WHERE NOT
     (g.scope='AUTH'
       AND g.config_value=w.v
       AND g.value_type='INTEGER'
       AND g.value_status='REAL'
       AND g.description IS NOT NULL
       AND length(btrim(g.description))>20
       AND g.valid_from=now()
       AND g.created_at=now()
       AND g.config_value ~ '^[0-9]+$'
       AND g.config_value::numeric>0))
  INTO v_found,v_bad
  FROM wanted w LEFT JOIN public.lf_global_config g
    ON g.scope='AUTH' AND g.config_key=w.k;
  IF v_found<>v_expected OR v_bad<>0 THEN
    RAISE EXCEPTION 'PR_F_POST_INSERT_READBACK_FAILED found=% bad=%',v_found,v_bad;
  END IF;
  IF (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')<>9
    THEN RAISE EXCEPTION 'PR_F_AUTH_TOTAL_NOT_NINE'; END IF;
  IF (SELECT count(*) FROM public.lf_global_config
       WHERE scope='AUTH' AND value_status='REAL')<>9
    THEN RAISE EXCEPTION 'PR_F_AUTH_REAL_COUNT_NOT_NINE'; END IF;
END;
$after$;
