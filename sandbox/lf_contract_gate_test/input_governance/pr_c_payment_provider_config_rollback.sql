-- PR-C REAL PostgreSQL 17 BEGIN/ROLLBACK, sandbox-only isolated database.
-- No remote credentials, no production test writes, no permanent changes.
\set ON_ERROR_STOP on
DO $pre$
BEGIN
  IF to_regclass('public.payment_provider_config') IS NOT NULL
  THEN RAISE EXCEPTION 'PR_C_UNEXPECTED_PREEXISTING_TABLE'; END IF;
  RAISE NOTICE 'PR_C_EMPTY_PREIMAGE_PASS';
END;
$pre$;

\echo PR_C_BEGIN
BEGIN;
@@MIGRATION_SQL@@

DO $readback$
DECLARE
  actual_columns text[];
  expected_columns text[]:=ARRAY[
    'provider:text:NO','config_key:text:NO','config_value:text:NO',
    'value_status:text:NO','valid_from:timestamptz:NO',
    'created_at:timestamptz:NO'
  ];
  n integer;
  enabled boolean;
  forced boolean;
  pol_n integer;
  role_name text;
  perm text;
BEGIN
  SELECT array_agg(column_name||':'||udt_name||':'||is_nullable ORDER BY ordinal_position)
  INTO actual_columns FROM information_schema.columns
  WHERE table_schema='public' AND table_name='payment_provider_config';
  IF actual_columns IS DISTINCT FROM expected_columns THEN
    RAISE EXCEPTION 'PR_C_COLUMN_SCHEMA_DRIFT actual=%', actual_columns; END IF;

  SELECT c.relrowsecurity,c.relforcerowsecurity INTO enabled,forced
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='payment_provider_config';
  IF NOT COALESCE(enabled,false) OR NOT COALESCE(forced,false)
    THEN RAISE EXCEPTION 'PR_C_RLS_NOT_FORCED'; END IF;

  SELECT count(*) INTO pol_n FROM pg_policies
  WHERE schemaname='public' AND tablename='payment_provider_config';
  IF pol_n<>0 THEN RAISE EXCEPTION 'PR_C_UNEXPECTED_RLS_POLICIES %',pol_n; END IF;

  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOREACH perm IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE',
      'TRUNCATE','REFERENCES','TRIGGER'] LOOP
      IF has_table_privilege(role_name,'public.payment_provider_config',perm)
      THEN RAISE EXCEPTION 'PR_C_ROLE_EXPOSED role=% privilege=%',role_name,perm;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT EXISTS(
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.payment_provider_config'::regclass
      AND contype='u' AND conname='payment_provider_config_unique_version'
      AND pg_get_constraintdef(oid)='UNIQUE (provider, config_key, valid_from)'
  ) THEN RAISE EXCEPTION 'PR_C_UNIQUE_MISSING'; END IF;

  SELECT count(*) INTO n FROM public.payment_provider_config;
  IF n<>1 OR NOT EXISTS (
    SELECT 1 FROM public.payment_provider_config
    WHERE provider='NIUBIZ' AND config_key='NIUBIZ_EMAIL_GENERICO'
      AND config_value='niubiz-generico@lf-ficticio.invalid'
      AND value_status='FICTICIO'
      AND valid_from IS NOT NULL AND created_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'PR_C_EXACTLY_ONE_FAKE_ROW_FAILED count=%',n;
  END IF;

  BEGIN
    INSERT INTO public.payment_provider_config(provider,config_key,config_value,
      value_status,valid_from)
    SELECT provider,config_key,config_value,value_status,valid_from
    FROM public.payment_provider_config;
    RAISE EXCEPTION 'PR_C_DUPLICATE_UNEXPECTEDLY_ALLOWED';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PR_C_DUPLICATE_REJECTED_PASS';
  END;

  BEGIN
    INSERT INTO public.payment_provider_config(provider,config_key,config_value,
      value_status,valid_from)
    VALUES ('NIUBIZ','NIUBIZ_EMAIL_GENERICO','fake@invalid.invalid','PRODUCTION',
            now() + interval '1 day');
    RAISE EXCEPTION 'PR_C_STATUS_UNEXPECTEDLY_ALLOWED';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PR_C_STATUS_ENUM_REJECTED_PASS';
  END;

  IF (SELECT count(*) FROM public.payment_provider_config)<>1
  THEN RAISE EXCEPTION 'PR_C_NEGATIVE_TEST_ROWS_PERSISTED'; END IF;
  RAISE NOTICE 'PR_C_IN_TRANSACTION_PASS columns=6 rls=ON forced=ON policies=0 roles_denied=2 row=1 status=FICTICIO';
END;
$readback$;

\echo PR_C_ROLLBACK
ROLLBACK;

DO $post$
BEGIN
  IF to_regclass('public.payment_provider_config') IS NOT NULL
  THEN RAISE EXCEPTION 'PR_C_ROLLBACK_DID_NOT_REMOVE_TABLE'; END IF;
  RAISE NOTICE 'PR_C_REAL_POST_ROLLBACK_PASS table_absent=true';
END;
$post$;
