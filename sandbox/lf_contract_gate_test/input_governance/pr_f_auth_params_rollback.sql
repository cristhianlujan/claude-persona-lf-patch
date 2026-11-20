-- Real PostgreSQL 17 temporary service test for PR-F.
-- Fixture derives the unmodified CREATE TABLE / RLS DDL from PR-D.
\set ON_ERROR_STOP on
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
@@SOURCE_TABLE_DDL@@
INSERT INTO public.lf_global_config
 (scope,config_key,config_value,value_type,value_status,description,valid_from,created_at)
VALUES ('PAGOS','NIUBIZ_EMAIL_GENERICO','niubiz-generico@lf-ficticio.invalid',
        'EMAIL','FICTICIO','PR-D fixture',TIMESTAMPTZ '2026-11-18 06:21:51.534969+00',
        TIMESTAMPTZ '2026-11-18 06:21:51.534969+00');

CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas (id bigint PRIMARY KEY,codigo text UNIQUE NOT NULL,estado text NOT NULL,valor_config jsonb NOT NULL);
INSERT INTO lf_ops.reglas VALUES
 (437,'B2B-RULE-AUTH-018','VIGENTE','{"fixture":"auth018","p":"before"}'),
 (438,'B2B-RULE-AUTH-019','VIGENTE','{"fixture":"auth019","p":"before"}'),
 (439,'B2B-RULE-AUTH-020','VIGENTE','{"fixture":"auth020","hold_hours":48,"human_approval_count_required":2}');

DO $p$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.lf_global_config;
 IF n<>1 OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')<>0
 THEN RAISE EXCEPTION 'PR_F_PREIMAGE_CONFIG_DRIFT'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')<>3
 THEN RAISE EXCEPTION 'PR_F_PREIMAGE_RULE_FIXTURE_DRIFT'; END IF;
 RAISE NOTICE 'PR_F_PREIMAGE_PASS global_rows=1 auth_rows=0 fixture_auth_rules=3';
END;
$p$;

BEGIN;
@@PR_F_MIGRATION_SQL@@

DO $assert$
DECLARE n int; invalid_count int; v_rls boolean; v_forced boolean; np int;
 r text; privilege text; expected jsonb;
BEGIN
 expected:=jsonb_build_object(
 'MFA_DEVICE_IDLE_DAYS','30','MFA_PASSWORD_AGE_MONTHS','3','TEMP_KEY_TTL_HOURS','24',
 'LOGIN_LOCKOUT_ATTEMPTS_1','5','LOGIN_LOCKOUT_MINUTES_1','15',
 'LOGIN_LOCKOUT_ATTEMPTS_2','3','LOGIN_LOCKOUT_MINUTES_2','60',
 'LOGIN_LOCKOUT_ATTEMPTS_3','3','LOGIN_LOCKOUT_MINUTES_3','1440');
 SELECT count(*) INTO n FROM public.lf_global_config WHERE scope='AUTH';
 IF n<>9 OR (SELECT count(*) FROM public.lf_global_config)<>10
 THEN RAISE EXCEPTION 'PR_F_CARDINALITY_INVALID'; END IF;
 SELECT count(*) INTO invalid_count FROM public.lf_global_config
 WHERE scope='AUTH' AND (
   (NOT expected ? config_key)
   OR expected->>config_key IS DISTINCT FROM config_value
   OR value_type IS DISTINCT FROM 'INTEGER'
   OR value_status IS DISTINCT FROM 'REAL'
   OR description IS NULL OR length(btrim(description))<=20
   OR config_value !~ '^[0-9]+$' OR valid_from IS DISTINCT FROM now()
   OR created_at IS DISTINCT FROM now());
 IF invalid_count<>0 OR (SELECT count(*) FROM jsonb_object_keys(expected))<>9
 THEN RAISE EXCEPTION 'PR_F_AUTH_VALUES_BAD invalid_count=%',invalid_count; END IF;
 SELECT count(*) INTO n FROM (
  SELECT config_key FROM public.lf_global_config WHERE scope='AUTH'
  GROUP BY config_key HAVING count(*)<>1 OR count(*) FILTER(WHERE value_status='REAL')<>1
 ) t;
 IF n<>0 THEN RAISE EXCEPTION 'PR_F_REAL_ONE_PER_KEY_VIOLATED'; END IF;

 SELECT relrowsecurity,relforcerowsecurity INTO v_rls,v_forced
 FROM pg_class WHERE oid='public.lf_global_config'::regclass;
 SELECT count(*) INTO np FROM pg_policies WHERE schemaname='public' AND tablename='lf_global_config';
 IF NOT v_rls OR NOT v_forced OR np<>0 THEN
  RAISE EXCEPTION 'PR_F_RLS_BAD'; END IF;
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  FOREACH privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
   IF has_table_privilege(r,'public.lf_global_config',privilege)
   THEN RAISE EXCEPTION 'PR_F_ROLE_EXPOSED % %',r,privilege; END IF;
  END LOOP;
 END LOOP;
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.lf_global_config'::regclass
  AND contype='u' AND pg_get_constraintdef(oid)='UNIQUE (scope, config_key, valid_from)')
 THEN RAISE EXCEPTION 'PR_F_UNIQUE_MISSING'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_global_config WHERE scope='PAGOS'
  AND config_key='NIUBIZ_EMAIL_GENERICO' AND value_status='FICTICIO'
  AND config_value='niubiz-generico@lf-ficticio.invalid'
  AND valid_from=TIMESTAMPTZ '2026-11-18 06:21:51.534969+00'
  AND created_at=TIMESTAMPTZ '2026-11-18 06:21:51.534969+00')
 THEN RAISE EXCEPTION 'PR_F_PRIOR_PAGOS_ROW_MUTATED'; END IF;

 BEGIN
  INSERT INTO public.lf_global_config
   (scope,config_key,config_value,value_type,value_status,description,valid_from)
  SELECT scope,config_key,config_value,value_type,value_status,description,valid_from
  FROM public.lf_global_config WHERE scope='AUTH' AND config_key='TEMP_KEY_TTL_HOURS';
  RAISE EXCEPTION 'PR_F_DUPLICATE_UNEXPECTEDLY_ALLOWED';
 EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PR_F_UNIQUE_REJECTED_PASS';
 END;
 BEGIN
  INSERT INTO public.lf_global_config
   (scope,config_key,config_value,value_type,value_status)
  VALUES ('AUTH','PR_F_INVALID_STATUS','1','INTEGER','SYNTHETIC');
  RAISE EXCEPTION 'PR_F_STATUS_UNEXPECTEDLY_ALLOWED';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PR_F_BAD_STATUS_REJECTED_PASS';
 END;
 BEGIN
  INSERT INTO public.lf_global_config
   (scope,config_key,config_value,value_type,value_status)
  VALUES ('AUTH','PR_F_INVALID_TYPE','1','NUMBER','REAL');
  RAISE EXCEPTION 'PR_F_TYPE_UNEXPECTEDLY_ALLOWED';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PR_F_BAD_TYPE_REJECTED_PASS';
 END;
 IF (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')<>9
 THEN RAISE EXCEPTION 'PR_F_NEGATIVE_TEST_SPILLOVER'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE' AND
  ((codigo='B2B-RULE-AUTH-018' AND valor_config='{"fixture":"auth018","p":"before"}'::jsonb)
  OR (codigo='B2B-RULE-AUTH-019' AND valor_config='{"fixture":"auth019","p":"before"}'::jsonb)
  OR (codigo='B2B-RULE-AUTH-020' AND valor_config='{"fixture":"auth020","hold_hours":48,"human_approval_count_required":2}'::jsonb)))<>3
 THEN RAISE EXCEPTION 'PR_F_AUTH_FIXTURE_RULES_MUTATED'; END IF;
 RAISE NOTICE 'PR_F_IN_TRANSACTION_PASS auth_rows=9 real_by_key=1 rls=ON forced=ON policies=0 roles_denied=14 fixture_rules_unchanged=3';
END;
$assert$;

ROLLBACK;

DO $after$
DECLARE n int; v_rls boolean; v_forced boolean;
BEGIN
 SELECT count(*) INTO n FROM public.lf_global_config;
 IF n<>1 OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')<>0
 THEN RAISE EXCEPTION 'PR_F_POST_ROLLBACK_NOT_RESTORED'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')<>3
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-020'
 AND (valor_config->>'hold_hours')='48' AND (valor_config->>'human_approval_count_required')='2')<>1
 THEN RAISE EXCEPTION 'PR_F_POST_ROLLBACK_RULE_FIXTURE_CHANGED'; END IF;
 SELECT relrowsecurity,relforcerowsecurity INTO v_rls,v_forced
 FROM pg_class WHERE oid='public.lf_global_config'::regclass;
 IF NOT v_rls OR NOT v_forced THEN RAISE EXCEPTION 'PR_F_POST_ROLLBACK_RLS_CHANGED'; END IF;
 RAISE NOTICE 'PR_F_REAL_POST_ROLLBACK_PASS global_rows=1 auth_rows=0 fixture_rules=3 rls_unchanged=true';
END;
$after$;
