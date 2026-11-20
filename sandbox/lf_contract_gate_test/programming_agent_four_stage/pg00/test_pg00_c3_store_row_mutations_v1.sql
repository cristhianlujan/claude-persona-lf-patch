-- DANGEROUS FIXTURE ONLY: run in disposable PostgreSQL, NEVER on Supabase.
-- Temporary trigger bypass exists solely to seed a controlled row.
BEGIN;
ALTER TABLE transversal.lf_programming_std_catalog_release_v1
  DISABLE TRIGGER lf_programming_std_catalog_block_insert_v1;
WITH payload AS (
 SELECT jsonb_build_object('schema_version','LF_STANDARDS_CATALOG_V1',
  'catalog_version','0.7.0','status','APROBADO',
  'rules',jsonb_build_array(jsonb_build_object('id','STD-TEST-01','status','APROBADO'))) AS j
)
INSERT INTO transversal.lf_programming_std_catalog_release_v1 (
 catalog_version,source_repo,source_path,source_commit_sha,source_file_sha256,
 catalog_json,catalog_jsonb_sha256,catalog_migration_version)
SELECT '0.7.0','paulozterra/lf-programming-sandbox','standards/catalog.json',
 repeat('a',40),repeat('b',64),j,
 encode(pg_catalog.sha256(convert_to(j::text,'UTF8')),'hex'),'20261030143000'
FROM payload;
ALTER TABLE transversal.lf_programming_std_catalog_release_v1
  ENABLE TRIGGER lf_programming_std_catalog_block_insert_v1;

DO $check$
BEGIN
 IF (SELECT count(*) FROM transversal.lf_programming_std_catalog_release_v1) <> 1 THEN
  RAISE EXCEPTION 'FIXTURE_INSERT_MISSING';
 END IF;
 BEGIN
  UPDATE transversal.lf_programming_std_catalog_release_v1 SET catalog_version='0.0.1';
  RAISE EXCEPTION 'UPDATE_WAS_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'PG00_C3_APPEND_ONLY' THEN RAISE; END IF;
 END;
 BEGIN
  DELETE FROM transversal.lf_programming_std_catalog_release_v1;
  RAISE EXCEPTION 'DELETE_WAS_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'PG00_C3_APPEND_ONLY' THEN RAISE; END IF;
 END;
 BEGIN
  TRUNCATE transversal.lf_programming_std_catalog_release_v1;
  RAISE EXCEPTION 'TRUNCATE_WAS_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'PG00_C3_APPEND_ONLY' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM transversal.lf_programming_std_catalog_release_v1) <> 1 THEN
  RAISE EXCEPTION 'ROW_ALTERED';
 END IF;
 RAISE NOTICE 'PG00_C3_MUTATION_GUARDS_PASS UPDATE DELETE TRUNCATE, seed_preserved=1';
END $check$;
ROLLBACK;
