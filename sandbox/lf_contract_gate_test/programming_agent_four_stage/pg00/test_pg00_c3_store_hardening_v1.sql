-- PostgreSQL 17 regression: execute after schema in disposable database only.
-- Do not disable trigger in governed environments.
DO $$
DECLARE v text;
BEGIN
 SELECT relrowsecurity::text INTO v FROM pg_class WHERE oid='transversal.lf_programming_std_catalog_release_v1'::regclass;
 IF v <> 'true' THEN RAISE EXCEPTION 'RLS_NOT_ENABLED'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='transversal.lf_programming_std_catalog_release_v1'::regclass AND NOT tgisinternal) <> 3 THEN
   RAISE EXCEPTION 'EXPECTED_THREE_BLOCKING_TRIGGERS';
 END IF;
 BEGIN
  EXECUTE 'TRUNCATE transversal.lf_programming_std_catalog_release_v1';
  RAISE EXCEPTION 'TRUNCATE_NOT_BLOCKED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'PG00_C3_APPEND_ONLY' THEN RAISE; END IF;
 END;
 BEGIN
  EXECUTE 'INSERT INTO transversal.lf_programming_std_catalog_release_v1 DEFAULT VALUES';
  RAISE EXCEPTION 'INSERT_NOT_BLOCKED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'PG00_C3_UNTRUSTED_INSERT_FORBIDDEN' THEN RAISE; END IF;
 END;
 IF has_table_privilege('PUBLIC','transversal.lf_programming_std_catalog_release_v1','SELECT')
    OR has_table_privilege('PUBLIC','transversal.lf_programming_std_catalog_release_v1','INSERT') THEN
    RAISE EXCEPTION 'PUBLIC_TABLE_PERMISSION_LEAK';
 END IF;
 RAISE NOTICE 'PG00_C3_STORE_HARDENING_PASS RLS, TRIGGERS, TRUNCATE, INSERT, PUBLIC_ACL';
END $$;
