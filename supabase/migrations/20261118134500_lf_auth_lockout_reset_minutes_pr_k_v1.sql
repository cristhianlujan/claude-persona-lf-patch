-- PR-K: parameter ONLY, source-bound owner IG 13:40; four rules DOCUMENT ONLY.
-- No direct rule DML or fabricated CREACION_REGLA_LF runs.
-- SQL atomic: BEGIN/COMMIT; Train applies exact source, PG17 tests use BEGIN/ROLLBACK.
BEGIN;
DO $pr_k$
DECLARE
  v_before_md5 text;
  v_after_old_md5 text;
  v_rules_md5 text;
  v_rules_after_md5 text;
  v_auth18 text;
  v_auth19 text;
  v_auth20 text;
  v_rls boolean;
  v_force boolean;
  v_policies int;
  v_row public.lf_global_config%ROWTYPE;
BEGIN
  IF to_regclass('public.lf_global_config') IS NULL
    OR to_regclass('lf_ops.reglas') IS NULL
  THEN RAISE EXCEPTION 'PR_K_MISSING_CANONICAL_TABLE'; END IF;
  SELECT relrowsecurity,relforcerowsecurity INTO v_rls,v_force
  FROM pg_class WHERE oid='public.lf_global_config'::regclass;
  SELECT count(*) INTO v_policies FROM pg_policies
  WHERE schemaname='public' AND tablename='lf_global_config';
  IF NOT v_rls OR NOT v_force OR v_policies<>0
    OR has_table_privilege('anon','public.lf_global_config','SELECT')
    OR has_table_privilege('authenticated','public.lf_global_config','SELECT')
    OR has_table_privilege('anon','public.lf_global_config','INSERT')
    OR has_table_privilege('authenticated','public.lf_global_config','INSERT')
  THEN RAISE EXCEPTION 'PR_K_GLOBAL_CONFIG_RLS_OR_PRIVILEGE_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_global_config) <> 10
     OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH') <> 9
     OR EXISTS (SELECT 1 FROM public.lf_global_config
                WHERE scope='AUTH' AND config_key='LOGIN_LOCKOUT_RESET_MINUTES')
  THEN RAISE EXCEPTION 'PR_K_GLOBAL_CONFIG_PREIMAGE_10_9_MISSING_OR_DUPLICATE'; END IF;

  IF EXISTS(
      WITH wanted(k,val) AS (VALUES
      ('MFA_DEVICE_IDLE_DAYS','30'),('MFA_PASSWORD_AGE_MONTHS','3'),
      ('TEMP_KEY_TTL_HOURS','24'),('LOGIN_LOCKOUT_ATTEMPTS_1','5'),
      ('LOGIN_LOCKOUT_ATTEMPTS_2','3'),('LOGIN_LOCKOUT_ATTEMPTS_3','3'),
      ('LOGIN_LOCKOUT_MINUTES_1','15'),('LOGIN_LOCKOUT_MINUTES_2','60'),
      ('LOGIN_LOCKOUT_MINUTES_3','1440'))
      SELECT 1 FROM wanted w
      LEFT JOIN public.lf_global_config g ON g.scope='AUTH' AND g.config_key=w.k
      WHERE g.config_value IS DISTINCT FROM w.val
         OR g.value_type IS DISTINCT FROM 'INTEGER'
         OR g.value_status IS DISTINCT FROM 'REAL'
  ) THEN RAISE EXCEPTION 'PR_K_PREEXISTING_AUTH_PARAMETER_DRIFT'; END IF;

  IF (SELECT count(*) FROM lf_ops.reglas)<>579
    OR EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo IN (
      'PROP-B2B-AUTH-MFA-CONDITIONAL-001',
      'PROP-B2B-AUTH-TRUSTED-DEVICE-C-001',
      'PROP-B2B-AUTH-INTICO-SMS-CONTINGENCY-001',
      'PROP-B2B-AUTH-PASSWORD-LOCKOUT-TIERS-001'
    ))
  THEN RAISE EXCEPTION 'PR_K_RULE_PREIMAGE_OR_PROPOSAL_PREEXISTENCE_DRIFT'; END IF;

  SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.scope,g.config_key)::text,'[]'))
     INTO v_before_md5 FROM public.lf_global_config g;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
     INTO v_rules_md5 FROM lf_ops.reglas r;
  SELECT md5((to_jsonb(r)-'updated_at')::text) INTO v_auth18
     FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-018';
  SELECT md5((to_jsonb(r)-'updated_at')::text) INTO v_auth19
     FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-019';
  SELECT md5((to_jsonb(r)-'updated_at')::text) INTO v_auth20
     FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-020';
  IF v_auth18 IS NULL OR v_auth19 IS NULL OR v_auth20 IS NULL
  THEN RAISE EXCEPTION 'PR_K_AUTH018_019_020_SOURCE_MISSING'; END IF;

  INSERT INTO public.lf_global_config
   (scope,config_key,config_value,value_type,value_status,description,valid_from)
  VALUES(
    'AUTH','LOGIN_LOCKOUT_RESET_MINUTES','1440','INTEGER','REAL',
    'Contador de fallos de contrasena por usuario. Se reinicia a los 1440 minutos desde el ultimo bloqueo de ese usuario; el ultimo bloqueo es el ancla del plazo, no IP ni dispositivo. Valor de configuracion, no evidencia de QA ni autorizacion de produccion.',
    now()
  ) RETURNING * INTO v_row;

  IF v_row.scope IS DISTINCT FROM 'AUTH'
     OR v_row.config_key IS DISTINCT FROM 'LOGIN_LOCKOUT_RESET_MINUTES'
     OR v_row.config_value IS DISTINCT FROM '1440'
     OR v_row.value_type IS DISTINCT FROM 'INTEGER'
     OR v_row.value_status IS DISTINCT FROM 'REAL'
     OR v_row.valid_from IS DISTINCT FROM now()
     OR v_row.created_at IS DISTINCT FROM now()
  THEN RAISE EXCEPTION 'PR_K_LOCKOUT_RESET_1440_POSTIMAGE_INVALID'; END IF;
  IF (SELECT count(*) FROM public.lf_global_config)<>11
     OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')<>10
     OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH'
       AND config_key='LOGIN_LOCKOUT_RESET_MINUTES')<>1
  THEN RAISE EXCEPTION 'PR_K_GLOBAL_CONFIG_READBACK_COUNT_MISMATCH'; END IF;

  SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.scope,g.config_key)::text,'[]'))
     INTO v_after_old_md5 FROM public.lf_global_config g
  WHERE NOT (g.scope='AUTH' AND g.config_key='LOGIN_LOCKOUT_RESET_MINUTES');
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
     INTO v_rules_after_md5 FROM lf_ops.reglas r;

  IF v_after_old_md5 IS DISTINCT FROM v_before_md5
    OR v_rules_after_md5 IS DISTINCT FROM v_rules_md5
    OR (SELECT count(*) FROM lf_ops.reglas)<>579
    OR (SELECT md5((to_jsonb(r)-'updated_at')::text) FROM lf_ops.reglas r
        WHERE codigo='B2B-RULE-AUTH-018') IS DISTINCT FROM v_auth18
    OR (SELECT md5((to_jsonb(r)-'updated_at')::text) FROM lf_ops.reglas r
        WHERE codigo='B2B-RULE-AUTH-019') IS DISTINCT FROM v_auth19
    OR (SELECT md5((to_jsonb(r)-'updated_at')::text) FROM lf_ops.reglas r
        WHERE codigo='B2B-RULE-AUTH-020') IS DISTINCT FROM v_auth20
  THEN RAISE EXCEPTION 'PR_K_UNAUTHORIZED_RULE_OR_EXISTING_CONFIG_DELTA'; END IF;
  RAISE NOTICE 'PR_K_LOCKOUT_RESET_PASS rows_before=10 rows_after=11 rules=579 auth=9_to_10 value=1440 scope=USER_LAST_LOCKOUT';
END $pr_k$;
COMMIT;
