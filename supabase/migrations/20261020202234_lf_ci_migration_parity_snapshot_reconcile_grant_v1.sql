-- Let the Merge Train's existing read-only credential run the parity snapshot.
--
-- The Train job (environment lf-merge-train) already has LF_SUPABASE_RO_DATABASE_URL
-- for the role lf_reconcile_readonly (used by the RECONCILE_SOURCE_ONLY lane).
-- Granting EXECUTE on the read-only snapshot to that role lets the Train's
-- post-apply parity run trusted main code with a read-only credential instead of
-- LF_SUPABASE_DB_PASSWORD, without adding or copying any secret.
-- Only EXECUTE on this one SECURITY DEFINER read-only function; no table, schema
-- or other grant. lf_ci_readonly and service_role keep their EXECUTE.
DO $pre$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lf_reconcile_readonly') THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_GRANT_PRECONDITION_ROLE_MISSING:lf_reconcile_readonly';
  END IF;
  IF to_regprocedure('public.lf_ci_migration_parity_snapshot_v1(text[],text[],text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_GRANT_PRECONDITION_FUNCTION_MISSING';
  END IF;
  IF NOT (SELECT p.prosecdef FROM pg_proc p
          WHERE p.oid = to_regprocedure('public.lf_ci_migration_parity_snapshot_v1(text[],text[],text,text,text,text)')) THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_GRANT_PRECONDITION_NOT_DEFINER';
  END IF;
END
$pre$;

GRANT EXECUTE ON FUNCTION public.lf_ci_migration_parity_snapshot_v1(text[], text[], text, text, text, text)
  TO lf_reconcile_readonly;

DO $post$
DECLARE
  v_fn regprocedure := to_regprocedure('public.lf_ci_migration_parity_snapshot_v1(text[],text[],text,text,text,text)');
BEGIN
  IF NOT has_function_privilege('lf_reconcile_readonly', v_fn, 'EXECUTE')
     OR NOT has_function_privilege('lf_ci_readonly', v_fn, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_GRANT_POSTCHECK_EXECUTE_MISSING';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE')
     OR has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_GRANT_POSTCHECK_PUBLIC_EXECUTE';
  END IF;
  IF has_table_privilege('lf_reconcile_readonly', 'public.lf_operation_effect_guard', 'SELECT') THEN
    RAISE EXCEPTION 'LF_PARITY_SNAPSHOT_GRANT_POSTCHECK_TABLE_ACCESS_WIDENED';
  END IF;
END
$post$;
