-- PG-00_C3 V2 CANDIDATE. Disposable PostgreSQL only; no production authority.
BEGIN;
CREATE TABLE transversal.lf_programming_std_catalog_release_v2 (
 release_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 catalog_version text NOT NULL UNIQUE,
 source_repo text NOT NULL,
 source_commit_sha text NOT NULL CHECK(source_commit_sha ~ '^[0-9a-f]{40}$'),
 source_path text NOT NULL CHECK(source_path='standards/catalog.json'),
 catalog_json jsonb NOT NULL,
 source_file_sha256 text NOT NULL CHECK(source_file_sha256 ~ '^[0-9a-f]{64}$'),
 catalog_jsonb_sha256 text NOT NULL CHECK(catalog_jsonb_sha256 ~ '^[0-9a-f]{64}$'),
 train_execution_ref text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT catalog_jsonb_sha_matches_jsonb CHECK (catalog_jsonb_sha256=encode(extensions.digest(convert_to(catalog_json::text,'UTF8'),'sha256'),'hex')),
 CONSTRAINT catalog_version_match CHECK(catalog_json->>'catalog_version'=catalog_version),
 CONSTRAINT catalog_schema_match CHECK(catalog_json->>'schema_version'='LF_STANDARDS_CATALOG_V1'),
 CONSTRAINT catalog_not_draft CHECK(catalog_json->>'status'<>'BORRADOR_EN_REPO_DE_CALIFICACION')
);
CREATE FUNCTION transversal.fn_lf_programming_std_catalog_guard_v2()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','transversal' AS $guard$
DECLARE newest text; newparts int[]; oldparts int[];
BEGIN
 IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'PG00_C3_APPEND_ONLY'; END IF;
 IF NEW.catalog_version !~ '^[0-9]+[.][0-9]+[.][0-9]+$' THEN RAISE EXCEPTION 'PG00_C3_INVALID_VERSION'; END IF;
 SELECT catalog_version INTO newest FROM transversal.lf_programming_std_catalog_release_v2
 ORDER BY split_part(catalog_version,'.',1)::int DESC, split_part(catalog_version,'.',2)::int DESC, split_part(catalog_version,'.',3)::int DESC LIMIT 1;
 IF newest IS NOT NULL THEN
  newparts:=string_to_array(NEW.catalog_version,'.')::int[];
  oldparts:=string_to_array(newest,'.')::int[];
  IF newparts <= oldparts THEN RAISE EXCEPTION 'PG00_C3_DOWNGRADE_OR_REPLAY'; END IF;
 END IF;
 RETURN NEW;
END
$guard$;
CREATE TRIGGER trg_std_catalog_insert_v2 BEFORE INSERT ON transversal.lf_programming_std_catalog_release_v2
FOR EACH ROW EXECUTE FUNCTION transversal.fn_lf_programming_std_catalog_guard_v2();
CREATE TRIGGER trg_std_catalog_immutable_v2 BEFORE UPDATE OR DELETE ON transversal.lf_programming_std_catalog_release_v2
FOR EACH ROW EXECUTE FUNCTION transversal.fn_lf_programming_std_catalog_guard_v2();
CREATE FUNCTION transversal.fn_lf_programming_std_catalog_readback_v2(p_version text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','transversal','extensions' AS $fn$
SELECT coalesce((
 SELECT jsonb_build_object('found',true,'catalog_version',catalog_version,
 'source_repo',source_repo,'source_commit_sha',source_commit_sha,
 'source_file_sha256',source_file_sha256,'catalog_jsonb_sha256',catalog_jsonb_sha256,
 'recomputed_jsonb_sha256',encode(extensions.digest(convert_to(catalog_json::text,'UTF8'),'sha256'),'hex'),
 'status','DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK')
 FROM transversal.lf_programming_std_catalog_release_v2 WHERE catalog_version=p_version
),jsonb_build_object('found',false,'reason','PG00_C3_RELEASE_NOT_FOUND'))
$fn$;
ROLLBACK;
