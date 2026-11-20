-- PG-00_C3: schema only. No catalog release rows, no authority, no PG-01 grants.
-- Governed application only through PASE/Merge Train.
BEGIN;
CREATE TABLE transversal.lf_programming_std_catalog_release_v1 (
 release_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 catalog_version text NOT NULL UNIQUE CHECK (catalog_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
 source_repo text NOT NULL CHECK (source_repo = 'paulozterra/lf-programming-sandbox'),
 source_path text NOT NULL CHECK (source_path = 'standards/catalog.json'),
 source_commit_sha text NOT NULL CHECK (source_commit_sha ~ '^[0-9a-f]{40}$'),
 source_file_sha256 text NOT NULL CHECK (source_file_sha256 ~ '^[0-9a-f]{64}$'),
 catalog_json jsonb NOT NULL,
 catalog_jsonb_sha256 text NOT NULL CHECK (catalog_jsonb_sha256 ~ '^[0-9a-f]{64}$'),
 catalog_migration_version text NOT NULL CHECK (catalog_migration_version ~ '^[0-9]{14}$'),
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT catalog_c3_jsonb_digest_matches CHECK (
  catalog_jsonb_sha256 = encode(pg_catalog.sha256(pg_catalog.convert_to(catalog_json::text,'UTF8')),'hex')),
 CONSTRAINT catalog_c3_version_matches CHECK (catalog_json->>'catalog_version'=catalog_version),
 CONSTRAINT catalog_c3_schema_matches CHECK (catalog_json->>'schema_version'='LF_STANDARDS_CATALOG_V1'),
 CONSTRAINT catalog_c3_status_whitelist CHECK (coalesce(catalog_json->>'status','') IN ('APROBADO','VALIDAR_CON_LEGAL')),
 CONSTRAINT catalog_c3_rules_whitelist CHECK (jsonb_typeof(catalog_json->'rules')='array' AND jsonb_array_length(catalog_json->'rules')>0 AND NOT jsonb_path_exists(catalog_json,'$.rules[*] ? (!exists(@.status) || (@.status != "APROBADO" && @.status != "VALIDAR_CON_LEGAL"))'))
);
ALTER TABLE transversal.lf_programming_std_catalog_release_v1 ENABLE ROW LEVEL SECURITY;
-- Staging-only schema: no release writer exists. Even an owner INSERT cannot establish provenance.
CREATE FUNCTION transversal.fn_lf_programming_std_catalog_block_insert_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path='pg_catalog' AS $fn$
BEGIN
 RAISE EXCEPTION 'PG00_C3_UNTRUSTED_INSERT_FORBIDDEN';
END $fn$;
CREATE TRIGGER lf_programming_std_catalog_block_insert_v1
BEFORE INSERT ON transversal.lf_programming_std_catalog_release_v1
FOR EACH ROW EXECUTE FUNCTION transversal.fn_lf_programming_std_catalog_block_insert_v1();
CREATE FUNCTION transversal.fn_lf_programming_std_catalog_no_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path='pg_catalog' AS $fn$
BEGIN
 RAISE EXCEPTION 'PG00_C3_APPEND_ONLY';
END $fn$;
CREATE TRIGGER lf_programming_std_catalog_no_update_delete_v1
BEFORE UPDATE OR DELETE ON transversal.lf_programming_std_catalog_release_v1
FOR EACH ROW EXECUTE FUNCTION transversal.fn_lf_programming_std_catalog_no_mutation_v1();
CREATE TRIGGER lf_programming_std_catalog_no_truncate_v1
BEFORE TRUNCATE ON transversal.lf_programming_std_catalog_release_v1
FOR EACH STATEMENT EXECUTE FUNCTION transversal.fn_lf_programming_std_catalog_no_mutation_v1();
CREATE FUNCTION transversal.fn_lf_programming_std_catalog_metadata_v1(p_version text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path='pg_catalog','transversal' AS $fn$
 SELECT coalesce(
  (SELECT jsonb_build_object(
    'found',true,'catalog_version',catalog_version,'source_repo',source_repo,
    'source_commit_sha',source_commit_sha,'source_file_sha256',source_file_sha256,
    'catalog_jsonb_sha256',catalog_jsonb_sha256,
    'catalog_migration_version',catalog_migration_version,
    'status','DB_RECORD_ONLY_TRAIN_AND_SOURCE_CHECK_REQUIRED')
   FROM transversal.lf_programming_std_catalog_release_v1
   WHERE catalog_version=p_version),
  jsonb_build_object('found',false,'reason','PG00_C3_RELEASE_NOT_FOUND'))
$fn$;
REVOKE ALL ON transversal.lf_programming_std_catalog_release_v1 FROM PUBLIC;
REVOKE ALL ON FUNCTION transversal.fn_lf_programming_std_catalog_metadata_v1(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION transversal.fn_lf_programming_std_catalog_no_mutation_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION transversal.fn_lf_programming_std_catalog_block_insert_v1() FROM PUBLIC;
-- No INSERT, no catalog data, no read grants to runtime roles, no release authorization.
COMMIT;
