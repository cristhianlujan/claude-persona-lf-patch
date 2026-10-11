-- Execute with BEGIN; [exact migration Git source]; [this file]; ROLLBACK.
-- All writes are synthetic/transactional. No authoritative source registered.
DO $check_catalog_acl$
BEGIN
 IF pg_catalog.has_table_privilege('authenticated','public.lf_activos','INSERT')
  OR pg_catalog.has_table_privilege('anon','public.lf_activos','INSERT')
  OR pg_catalog.has_table_privilege('authenticated','public.lf_activos','TRUNCATE')
  OR pg_catalog.has_table_privilege('anon','public.lf_activos','TRUNCATE')
  OR pg_catalog.has_table_privilege('authenticated','public.lf_activos','TRIGGER')
  OR pg_catalog.has_table_privilege('anon','public.lf_activos','TRIGGER')
  OR pg_catalog.has_table_privilege('authenticated','public.lf_activos','REFERENCES')
  OR pg_catalog.has_table_privilege('anon','public.lf_activos','REFERENCES')
 THEN RAISE EXCEPTION 'FAIL_UNTRUSTED_CATALOG_WRITE_PRIVILEGE'; END IF;
 IF NOT pg_catalog.has_table_privilege('authenticated','public.lf_activos','SELECT')
  OR NOT pg_catalog.has_table_privilege('service_role','public.lf_activos','INSERT')
  OR NOT pg_catalog.has_table_privilege('service_role','public.lf_activos','UPDATE')
  OR NOT pg_catalog.has_table_privilege('postgres','public.lf_activos','INSERT')
 THEN RAISE EXCEPTION 'FAIL_EXISTING_AUTHORIZED_PATH_REGRESSION'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.lf_activos'::regclass
   AND polname='lf_activos_authenticated_insert') THEN
   RAISE EXCEPTION 'FAIL_CLIENT_INSERT_POLICY_REMAINS'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_policy WHERE polrelid='public.lf_activos'::regclass
   AND polname='lf_activos_authenticated_select') THEN
   RAISE EXCEPTION 'FAIL_CLIENT_SELECT_POLICY_REMOVED'; END IF;
END $check_catalog_acl$;

-- A real SQL attempted insertion must now fail, not just a summary Boolean.
SET LOCAL ROLE authenticated;
DO $check_client_insert$
BEGIN
 BEGIN
  INSERT INTO public.lf_activos (
    codigo_activo,nombre_canonico,tipo_activo,estado_documental,estado_operativo,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,metadata,created_by_execution_id)
  VALUES ('LF_UNTRUSTED_BINDING_PROBE_NO_PERSIST','ROLLBACK_ONLY_SOURCE','DB_TABLE',
   'VIGENTE','READ_ONLY','LEGACY_REQUIRED_FIELD','LEGACY_REQUIRED_FIELD',
   'LEGACY_REQUIRED_FIELD',-1,
   '00000000-0000-4000-8000-000000000099',
   '{"canonical_source_ref":"db://lf_ops.cargas_lotes","admission_status":"VIGENTE"}'::jsonb,
   'EXEC-LF-AUTHORITY-ROLLBACK-ONLY');
  RAISE EXCEPTION 'FAIL_UNTRUSTED_CATALOG_INSERT_SUCCEEDED';
 EXCEPTION WHEN insufficient_privilege THEN
   NULL;
 END;
END $check_client_insert$;
RESET ROLE;

-- A server-side asset writer must remain functional. Entire fixture is rolled back.
SET LOCAL ROLE service_role;
INSERT INTO public.lf_activos (
  codigo_activo,nombre_canonico,tipo_activo,estado_documental,estado_operativo,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
  migration_batch_id,metadata,created_by_execution_id)
VALUES ('LF_SERVER_ASSET_WRITE_PROBE_NO_PERSIST','ROLLBACK_ONLY_METADATA','CONTRACT',
 'CANDIDATO','READ_ONLY','LEGACY_REQUIRED_FIELD','LEGACY_REQUIRED_FIELD',
 'LEGACY_REQUIRED_FIELD',-1,'00000000-0000-4000-8000-000000000098',
 '{"sandbox_rollback_only":true}'::jsonb,'EXEC-LF-AUTHORITY-ROLLBACK-ONLY');
DO $check_server_insert$
BEGIN
 IF (SELECT count(*) FROM public.lf_activos
  WHERE codigo_activo='LF_SERVER_ASSET_WRITE_PROBE_NO_PERSIST')<>1 THEN
  RAISE EXCEPTION 'FAIL_GOVERNED_SERVER_ASSET_WRITES'; END IF;
END $check_server_insert$;
RESET ROLE;
SELECT 'PASS' AS authority_acl_result,
 (SELECT count(*) FROM public.lf_activos WHERE codigo_activo='LF_SERVER_ASSET_WRITE_PROBE_NO_PERSIST') AS reversible_server_asset_fixture,
 (SELECT count(*) FROM public.lf_activos WHERE codigo_activo='LF_UNTRUSTED_BINDING_PROBE_NO_PERSIST') AS untrusted_insert_rows;
