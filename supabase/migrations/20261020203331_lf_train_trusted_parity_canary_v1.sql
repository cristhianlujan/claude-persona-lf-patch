-- Canary for the Train's trusted read-only parity step (#2968).
-- Effect: only refreshes the COMMENT of the parity snapshot function; no data,
-- grants or behaviour change. Its purpose is to exercise, end to end, the new
-- pre-apply credential guard and the post-apply parity that runs trusted main
-- code against this candidate as Git data with lf_ci_readonly.
DO $pre$
BEGIN
  IF to_regprocedure('public.lf_ci_migration_parity_snapshot_v1(text[],text[],text,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'LF_TRAIN_PARITY_CANARY_PRECONDITION_SNAPSHOT_MISSING';
  END IF;
END
$pre$;

COMMENT ON FUNCTION public.lf_ci_migration_parity_snapshot_v1(text[], text[], text, text, text, text) IS
  'CI read-only single-call snapshot for MIGRATION_SOURCE_PARITY (lf_ci_readonly and the Merge Train trusted parity step). '
  'Same expressions as the focal runner SQL; read-only; no table grants.';
