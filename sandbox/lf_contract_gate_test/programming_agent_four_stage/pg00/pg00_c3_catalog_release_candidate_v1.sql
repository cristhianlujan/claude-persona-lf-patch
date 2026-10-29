-- PG-00_C3 publication candidate ONLY, deliberately outside supabase/migrations.
-- Requires source-frozen CHG, PASE, Train, independent readback, and PG00 owner review.
BEGIN;
CREATE TABLE IF NOT EXISTS transversal.lf_programming_std_catalog_release_v1 (
  release_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  catalog_version text NOT NULL UNIQUE,
  source_repo text NOT NULL,
  source_commit_sha text NOT NULL CHECK (source_commit_sha ~ '^[0-9a-f]{40}$'),
  source_path text NOT NULL CHECK (source_path = 'standards/catalog.json'),
  catalog_json jsonb NOT NULL,
  source_file_sha256 text NOT NULL CHECK (source_file_sha256 ~ '^[0-9a-f]{64}
  train_execution_ref text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT catalog_jsonb_sha_matches_jsonb CHECK (
    catalog_jsonb_sha256 = encode(extensions.digest(convert_to(catalog_json::text,'UTF8'),'sha256'),'hex')),
  CONSTRAINT catalog_release_version_matches CHECK (
    catalog_json->>'catalog_version'=catalog_version),
  CONSTRAINT catalog_release_schema_matches CHECK (
    catalog_json->>'schema_version'='LF_STANDARDS_CATALOG_V1'),
  CONSTRAINT catalog_release_not_draft CHECK (
    catalog_json->>'status' <> 'BORRADOR_EN_REPO_DE_CALIFICACION')
);
-- No GRANT to API roles and no writes by the runtime.
CREATE OR REPLACE FUNCTION transversal.fn_lf_programming_std_catalog_readback_v1(p_version text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','transversal','extensions'
AS $$
  SELECT coalesce((
    SELECT jsonb_build_object(
      'found',true,'catalog_version',catalog_version,'source_repo',source_repo,
      'source_commit_sha',source_commit_sha,'source_path',source_path,
      'source_file_sha256',source_file_sha256,
      'catalog_jsonb_sha256',catalog_jsonb_sha256,
      'recomputed_jsonb_sha256',encode(extensions.digest(convert_to(catalog_json::text,'UTF8'),'sha256'),'hex'),
      'release_id',release_id,'catalog',catalog_json,
      'status','DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK'
    )
    FROM transversal.lf_programming_std_catalog_release_v1
    WHERE catalog_version=p_version
  ),jsonb_build_object('found',false,'reason','PG00_C3_RELEASE_NOT_FOUND'))
$$;
-- source_file_sha256 is SHA-256 of original repo bytes; distinct from PostgreSQL jsonb::text SHA.
-- No direct migration apply. No authenticated GitHub exact-head readback exists here.
ROLLBACK; -- safety: this illustrative DDL never persists when executed as a script.
),
  catalog_jsonb_sha256 text NOT NULL CHECK (catalog_jsonb_sha256 ~ '^[0-9a-f]{64}
  train_execution_ref text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT catalog_sha_matches_jsonb CHECK (
    catalog_sha256 = encode(extensions.digest(convert_to(catalog_json::text,'UTF8'),'sha256'),'hex')),
  CONSTRAINT catalog_release_version_matches CHECK (
    catalog_json->>'catalog_version'=catalog_version),
  CONSTRAINT catalog_release_schema_matches CHECK (
    catalog_json->>'schema_version'='LF_STANDARDS_CATALOG_V1'),
  CONSTRAINT catalog_release_not_draft CHECK (
    catalog_json->>'status' <> 'BORRADOR_EN_REPO_DE_CALIFICACION')
);
-- No GRANT to API roles and no writes by the runtime.
CREATE OR REPLACE FUNCTION transversal.fn_lf_programming_std_catalog_readback_v1(p_version text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','transversal','extensions'
AS $$
  SELECT coalesce((
    SELECT jsonb_build_object(
      'found',true,'catalog_version',catalog_version,'source_repo',source_repo,
      'source_commit_sha',source_commit_sha,'source_path',source_path,
      'catalog_sha256',catalog_sha256,
      'recomputed_jsonb_sha256',encode(extensions.digest(convert_to(catalog_json::text,'UTF8'),'sha256'),'hex'),
      'release_id',release_id,'catalog',catalog_json,
      'status','DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK'
    )
    FROM transversal.lf_programming_std_catalog_release_v1
    WHERE catalog_version=p_version
  ),jsonb_build_object('found',false,'reason','PG00_C3_RELEASE_NOT_FOUND'))
$$;
-- No direct migration apply. No authenticated GitHub exact-head readback exists here.
ROLLBACK; -- safety: this illustrative DDL never persists when executed as a script.
),
  train_execution_ref text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT catalog_sha_matches_jsonb CHECK (
    catalog_sha256 = encode(extensions.digest(convert_to(catalog_json::text,'UTF8'),'sha256'),'hex')),
  CONSTRAINT catalog_release_version_matches CHECK (
    catalog_json->>'catalog_version'=catalog_version),
  CONSTRAINT catalog_release_schema_matches CHECK (
    catalog_json->>'schema_version'='LF_STANDARDS_CATALOG_V1'),
  CONSTRAINT catalog_release_not_draft CHECK (
    catalog_json->>'status' <> 'BORRADOR_EN_REPO_DE_CALIFICACION')
);
-- No GRANT to API roles and no writes by the runtime.
CREATE OR REPLACE FUNCTION transversal.fn_lf_programming_std_catalog_readback_v1(p_version text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','transversal','extensions'
AS $$
  SELECT coalesce((
    SELECT jsonb_build_object(
      'found',true,'catalog_version',catalog_version,'source_repo',source_repo,
      'source_commit_sha',source_commit_sha,'source_path',source_path,
      'catalog_sha256',catalog_sha256,
      'recomputed_jsonb_sha256',encode(extensions.digest(convert_to(catalog_json::text,'UTF8'),'sha256'),'hex'),
      'release_id',release_id,'catalog',catalog_json,
      'status','DB_RECORD_ONLY_UNTIL_INDEPENDENT_SOURCE_READBACK'
    )
    FROM transversal.lf_programming_std_catalog_release_v1
    WHERE catalog_version=p_version
  ),jsonb_build_object('found',false,'reason','PG00_C3_RELEASE_NOT_FOUND'))
$$;
-- No direct migration apply. No authenticated GitHub exact-head readback exists here.
ROLLBACK; -- safety: this illustrative DDL never persists when executed as a script.
