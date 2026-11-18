-- PR-D REAL PostgreSQL 17 BEGIN/ROLLBACK: PR-C fixture pre-exists.
-- The PR-C source fixture executes BEFORE BEGIN in isolated temporary PostgreSQL.
-- The PR-D migration executes INSIDE BEGIN. No remote database is used.
\set ON_ERROR_STOP on
@@PRC_SOURCE_SQL@@

DO $pre$
DECLARE v_count integer;
BEGIN
  IF to_regclass('public.payment_provider_config') IS NULL OR
     to_regclass('public.lf_global_config') IS NOT NULL
  THEN RAISE EXCEPTION 'PR_D_PREIMAGE_TABLES_DRIFT'; END IF;
  SELECT count(*) INTO v_count FROM public.payment_provider_config;
  IF v_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.payment_provider_config
    WHERE provider='NIUBIZ' AND config_key='NIUBIZ_EMAIL_GENERICO'
    AND config_value='niubiz-generico@lf-ficticio.invalid'
    AND value_status='FICTICIO'
  ) THEN RAISE EXCEPTION 'PR_D_PREIMAGE_SOURCE_DRIFT'; END IF;
  RAISE NOTICE 'PR_D_PREIMAGE_PASS old_rows=1 new_absent=true';
END;
$pre$;

\echo PR_D_BEGIN
BEGIN;
@@PRD_MIGRATION_SQL@@

DO $readback$
DECLARE
  actual_columns text[];
  expected_columns text[]:=ARRAY[
    'scope:text:NO','config_key:text:NO','config_value:text:NO',
    'value_type:text:NO','value_status:text:NO','description:text:YES',
    'valid_from:timestamptz:NO','created_at:timestamptz:NO'
  ];
  n bigint;
  enabled boolean;
  forced boolean;
  policies integer;
  role_name text;
  permission text;
BEGIN
  SELECT array_agg(column_name||':'||udt_name||':'||is_nullable ORDER BY ordinal_position)
  INTO actual_columns FROM information_schema.columns
  WHERE table_schema='public' AND table_name='lf_global_config';
  IF actual_columns IS DISTINCT FROM expected_columns THEN
    RAISE EXCEPTION 'PR_D_COLUMNS_INVALID actual=%',actual_columns; END IF;

  SELECT c.relrowsecurity,c.relforcerowsecurity INTO enabled,forced
  FROM pg_class c WHERE c.oid='public.lf_global_config'::regclass;
  IF NOT COALESCE(enabled,false) OR NOT COALESCE(forced,false)
    THEN RAISE EXCEPTION 'PR_D_RLS_INVALID'; END IF;
  SELECT count(*) INTO policies FROM pg_policies
  WHERE schemaname='public' AND tablename='lf_global_config';
  IF policies <> 0 THEN RAISE EXCEPTION 'PR_D_RLS_POLICIES=%',policies; END IF;

  FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOREACH permission IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE',
       'TRUNCATE','REFERENCES','TRIGGER'] LOOP
      IF has_table_privilege(role_name,'public.lf_global_config',permission)
      THEN RAISE EXCEPTION 'PR_D_CLIENT_ROLE_EXPOSED % %',role_name,permission;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.lf_global_config'::regclass
      AND conname='lf_global_config_unique_version' AND contype='u'
      AND pg_get_constraintdef(oid)='UNIQUE (scope, config_key, valid_from)'
  ) THEN RAISE EXCEPTION 'PR_D_UNIQUE_CONSTRAINT_MISSING'; END IF;

  SELECT count(*) INTO n FROM public.lf_global_config;
  IF n<>1 OR NOT EXISTS (
    SELECT 1 FROM public.lf_global_config
    WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_GENERICO'
      AND config_value='niubiz-generico@lf-ficticio.invalid'
      AND value_type='EMAIL' AND value_status='FICTICIO'
      AND description='Correo generico enviado a Niubiz cuando el correo del cliente empieza con numero (R-PAY-040/041)'
      AND valid_from IS NOT NULL AND created_at IS NOT NULL
  ) OR (SELECT count(*) FROM public.lf_global_config WHERE value_status='REAL')<>0
  THEN RAISE EXCEPTION 'PR_D_WRONG_COPIED_ROW_OR_REAL_COUNT count=%',n; END IF;

  IF to_regclass('public.payment_provider_config') IS NOT NULL
  THEN RAISE EXCEPTION 'PR_D_OLD_TABLE_NOT_DROPPED'; END IF;

  BEGIN
    INSERT INTO public.lf_global_config (
      scope,config_key,config_value,value_type,value_status,
      description,valid_from,created_at)
    SELECT scope,config_key,config_value,value_type,value_status,
      description,valid_from,created_at
    FROM public.lf_global_config;
    RAISE EXCEPTION 'PR_D_DUPLICATE_UNEXPECTEDLY_ALLOWED';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PR_D_DUPLICATE_DENIED_PASS';
  END;

  BEGIN
    INSERT INTO public.lf_global_config
      (scope,config_key,config_value,value_type,value_status)
    VALUES('PR_D_TEST','INVALID_STATUS','test','TEXT','INVALID_STATUS');
    RAISE EXCEPTION 'PR_D_BAD_STATUS_UNEXPECTEDLY_ALLOWED';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PR_D_BAD_STATUS_DENIED_PASS';
  END;

  BEGIN
    INSERT INTO public.lf_global_config
      (scope,config_key,config_value,value_type,value_status)
    VALUES('PR_D_TEST','INVALID_TYPE','test','XML','FICTICIO');
    RAISE EXCEPTION 'PR_D_BAD_TYPE_UNEXPECTEDLY_ALLOWED';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PR_D_BAD_TYPE_DENIED_PASS';
  END;

  IF (SELECT count(*) FROM public.lf_global_config)<>1
  THEN RAISE EXCEPTION 'PR_D_NEGATIVE_TEST_SIDE_EFFECT'; END IF;
  RAISE NOTICE 'PR_D_IN_TRANSACTION_PASS columns=8 rls=ON forced=ON policies=0 client_roles_denied=2 migrated_rows=1 real=0 source_absent=true';
END;
$readback$;

\echo PR_D_ROLLBACK
ROLLBACK;

DO $post$
DECLARE v_count bigint;
BEGIN
  IF to_regclass('public.lf_global_config') IS NOT NULL
  THEN RAISE EXCEPTION 'PR_D_ROLLBACK_DESTINATION_PERSISTED'; END IF;
  IF to_regclass('public.payment_provider_config') IS NULL
  THEN RAISE EXCEPTION 'PR_D_ROLLBACK_SOURCE_NOT_RESTORED'; END IF;
  SELECT count(*) INTO v_count FROM public.payment_provider_config;
  IF v_count<>1 OR NOT EXISTS (
     SELECT 1 FROM public.payment_provider_config
     WHERE provider='NIUBIZ' AND config_key='NIUBIZ_EMAIL_GENERICO'
       AND config_value='niubiz-generico@lf-ficticio.invalid'
       AND value_status='FICTICIO'
  ) THEN RAISE EXCEPTION 'PR_D_ROLLBACK_SOURCE_ROW_DRIFT'; END IF;
  RAISE NOTICE 'PR_D_REAL_POST_ROLLBACK_PASS dest_absent=true source_restored=true source_rows=1';
END;
$post$;
