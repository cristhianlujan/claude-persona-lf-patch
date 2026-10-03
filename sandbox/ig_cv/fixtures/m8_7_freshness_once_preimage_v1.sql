-- M8.7 N-9 rollback-only prelude.
-- The live database is already the exact preimage expected by the candidate migration.
-- This fixture only proves that exact preimage before the judge applies the candidate.

DO $m87_preimage$
DECLARE
  v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure))
    INTO v_md5;

  IF v_md5 <> '697055d6762447ee802a4fad067ded51' THEN
    RAISE EXCEPTION 'M8_7_N9_PREIMAGE_MISMATCH expected=697055d6762447ee802a4fad067ded51 actual=%', v_md5;
  END IF;
END $m87_preimage$;
