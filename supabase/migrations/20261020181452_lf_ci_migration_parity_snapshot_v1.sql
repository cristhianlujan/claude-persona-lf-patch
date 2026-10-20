-- PASE/POST-PASE X16 step 2: read-only snapshot for MIGRATION_SOURCE_PARITY.
--
-- The focal parity runner today sends 5 separate SQL statements as the
-- `postgres` user (write credential). The CI read-only role lf_ci_readonly
-- cannot read supabase_migrations.schema_migrations nor
-- public.lf_operation_effect_guard (RLS without a policy), so it cannot run them.
--
-- This SECURITY DEFINER function returns, in ONE call, exactly the five result
-- sets the focal runner reads, with the same expressions:
--   post_cutover     : version, name, 'sha256:' || canonical comment-stripped hash (context versions)
--   statement_counts : version, statement cardinality                               (managed versions)
--   grandfathered    : count, sha256 of (cutover, baseline_end]
--   legacy           : count, sha256 of [legacy_start, legacy_end]
--   owners           : 15 MIGRATION_OWNER_CURRENTNESS columns                       (context versions)
-- EXECUTE only for lf_ci_readonly and service_role; no table or schema grants.
-- Same pattern as lf_ci_control_system_qualification_readback_v1 (#2956).
-- Owner decision 2026-10-20: CI uses read-only credentials only.
DO $pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lf_ci_readonly') THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_PRECONDITION_ROLE_MISSING:lf_ci_readonly';
  END IF;
  IF to_regclass('supabase_migrations.schema_migrations') IS NULL
     OR to_regclass('public.lf_operation_effect_guard') IS NULL
     OR to_regclass('public.lf_operation_execution') IS NULL THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_PRECONDITION_SOURCE_MISSING';
  END IF;
  IF to_regprocedure('extensions.digest(bytea,text)') IS NULL THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_PRECONDITION_DIGEST_MISSING';
  END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_ci_migration_parity_snapshot_v1(
  p_context_versions text[],
  p_managed_versions text[],
  p_cutover text,
  p_baseline_end text,
  p_legacy_start text,
  p_legacy_end text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_post jsonb;
  v_counts jsonb;
  v_grand jsonb;
  v_legacy jsonb;
  v_owners jsonb;
BEGIN
  IF p_context_versions IS NULL OR p_managed_versions IS NULL
     OR cardinality(p_context_versions) > 200 OR cardinality(p_managed_versions) > 200 THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_VERSIONS_INVALID';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(p_context_versions || p_managed_versions) v WHERE v IS NULL OR v !~ '^[0-9]{14}$') THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_VERSION_LITERAL';
  END IF;
  IF coalesce(p_cutover, '') !~ '^[0-9]{14}$' OR coalesce(p_baseline_end, '') !~ '^[0-9]{14}$'
     OR coalesce(p_legacy_start, '') !~ '^[0-9]{14}$' OR coalesce(p_legacy_end, '') !~ '^[0-9]{14}$' THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_RANGE_LITERAL';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_array(r.version, r.name, r.hash) ORDER BY r.version), '[]'::jsonb)
    INTO v_post
  FROM (
    SELECT sm.version,
           coalesce(sm.name, '') AS name,
           'sha256:' || (
             SELECT encode(extensions.digest(convert_to(regexp_replace(coalesce(string_agg(line, E'\n' ORDER BY ord), ''), E'\n+$', ''), 'UTF8'), 'sha256'), 'hex')
             FROM regexp_split_to_table(replace(replace(coalesce(array_to_string(sm.statements, E'\n'), ''), E'\r\n', E'\n'), E'\r', E'\n'), E'\n') WITH ORDINALITY AS x(line, ord)
             WHERE line !~ '^[[:space:]]*--'
           ) AS hash
    FROM supabase_migrations.schema_migrations sm
    WHERE sm.version = ANY (p_context_versions)
  ) r;

  SELECT coalesce(jsonb_agg(jsonb_build_array(sm.version, coalesce(cardinality(sm.statements), 0)::text) ORDER BY sm.version), '[]'::jsonb)
    INTO v_counts
  FROM supabase_migrations.schema_migrations sm
  WHERE sm.version = ANY (p_managed_versions);

  WITH x AS (
    SELECT sm.version, coalesce(sm.name, '') AS name, array_to_string(sm.statements, E'\n') AS sql_text
    FROM supabase_migrations.schema_migrations sm
    WHERE sm.version > p_cutover AND sm.version <= p_baseline_end
  )
  SELECT jsonb_build_array(
           count(*)::text,
           encode(extensions.digest(convert_to(coalesce(string_agg(version || E'\n' || name || E'\n' || sql_text, E'\n--MIGRATION--\n' ORDER BY version), ''), 'UTF8'), 'sha256'), 'hex'))
    INTO v_grand
  FROM x;

  SELECT jsonb_build_array(
           count(*)::text,
           encode(extensions.digest(convert_to(string_agg(sm.version || E'\n' || coalesce(sm.name, '') || E'\n' || array_to_string(sm.statements, E'\n--STATEMENT--\n'), E'\n--MIGRATION--\n' ORDER BY sm.version), 'UTF8'), 'sha256'), 'hex'))
    INTO v_legacy
  FROM supabase_migrations.schema_migrations sm
  WHERE sm.version BETWEEN p_legacy_start AND p_legacy_end;

  SELECT coalesce(jsonb_agg(row_json ORDER BY ord), '[]'::jsonb)
    INTO v_owners
  FROM (
    SELECT jsonb_build_array(
             g.execution_id, e.status, e.operation_code,
             coalesce(g.receipt->>'repository', ''), coalesce(g.receipt->>'target_path', ''),
             coalesce(g.receipt->>'migration_version', ''), coalesce(g.receipt->>'migration_name', ''),
             coalesce(g.receipt->>'pr_number', ''), coalesce(g.receipt->>'pr_head_sha', ''),
             coalesce(g.receipt->>'source_blob', ''), coalesce(g.receipt->>'write_readback', ''),
             coalesce(g.receipt->>'currentness_result', ''), coalesce(g.receipt->>'ddl_replayed', ''),
             encode(convert_to(coalesce(array_to_string(m.statements, chr(10)), ''), 'UTF8'), 'hex'),
             coalesce(cardinality(m.statements), 0)::text
           ) AS row_json,
           row_number() OVER (ORDER BY g.resolved_at DESC NULLS LAST, g.execution_id) AS ord
    FROM public.lf_operation_effect_guard g
    JOIN public.lf_operation_execution e USING (execution_id)
    JOIN supabase_migrations.schema_migrations m
      ON m.version = g.receipt->>'migration_version' AND m.name = g.receipt->>'migration_name'
    WHERE g.effect_scope LIKE 'MIGRATION_OWNER_CURRENTNESS:%'
      AND g.state = 'SUCCEEDED'
      AND g.receipt->>'schema_version' = 'lf-migration-owner-currentness/v1'
      AND g.receipt->>'migration_version' = ANY (p_context_versions)
  ) o;

  RETURN jsonb_build_object(
    'schema_version', 'lf-ci-migration-parity-snapshot/v1',
    'post_cutover', v_post,
    'statement_counts', v_counts,
    'grandfathered', v_grand,
    'legacy', v_legacy,
    'owners', v_owners
  );
END
$fn$;

COMMENT ON FUNCTION public.lf_ci_migration_parity_snapshot_v1(text[], text[], text, text, text, text) IS
  'CI read-only single-call snapshot for MIGRATION_SOURCE_PARITY (lf_ci_readonly). '
  'Same expressions as the focal runner SQL; read-only; no table grants.';

REVOKE ALL ON FUNCTION public.lf_ci_migration_parity_snapshot_v1(text[], text[], text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_ci_migration_parity_snapshot_v1(text[], text[], text, text, text, text)
  TO lf_ci_readonly, service_role;

DO $post$
DECLARE
  v_fn regprocedure := to_regprocedure('public.lf_ci_migration_parity_snapshot_v1(text[],text[],text,text,text,text)');
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_POSTCHECK_MISSING';
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_fn) THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_POSTCHECK_NOT_DEFINER';
  END IF;
  IF (SELECT p.provolatile FROM pg_proc p WHERE p.oid = v_fn) <> 's' THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_POSTCHECK_NOT_STABLE';
  END IF;
  IF NOT coalesce((SELECT 'search_path=""' = ANY (p.proconfig) FROM pg_proc p WHERE p.oid = v_fn), false) THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_POSTCHECK_SEARCH_PATH';
  END IF;
  IF NOT has_function_privilege('lf_ci_readonly', v_fn, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_POSTCHECK_EXECUTE_MISSING';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE')
     OR has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_POSTCHECK_PUBLIC_EXECUTE';
  END IF;
  IF has_table_privilege('lf_ci_readonly', 'public.lf_operation_effect_guard', 'SELECT')
     OR (has_schema_privilege('lf_ci_readonly', 'supabase_migrations', 'USAGE')
         AND has_table_privilege('lf_ci_readonly', 'supabase_migrations.schema_migrations', 'SELECT')) THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_POSTCHECK_TABLE_ACCESS_WIDENED';
  END IF;
END
$post$;
