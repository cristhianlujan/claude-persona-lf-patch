-- M8.7 / PAULO-025
-- Reuse the dispatch freshness receipt when the selected current run is the same run.
-- This removes the duplicate fn_input_freshness_delta call on the normal reuse path
-- while preserving a fail-safe fallback if selection ever resolves to a different run.

DO $m87$
DECLARE
  v_def text;
  v_after text;
  v_old constant text := $$  v_fresh:=programacion.fn_input_freshness_delta(v_run); v_summary:=v_fresh->'summary';$$;
  v_new constant text := $$  if v_run = v_latest_completed then
    v_fresh:=v_dispatch_fresh;
  else
    v_fresh:=programacion.fn_input_freshness_delta(v_run);
  end if;
  v_summary:=v_fresh->'summary';$$;
BEGIN
  SELECT pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    INTO v_def;

  IF md5(v_def) <> '697055d6762447ee802a4fad067ded51' THEN
    RAISE EXCEPTION 'M8_7_PREIMAGE_MISMATCH expected=697055d6762447ee802a4fad067ded51 actual=%', md5(v_def);
  END IF;

  IF strpos(v_def, v_old) = 0 THEN
    RAISE EXCEPTION 'M8_7_TARGET_BLOCK_NOT_FOUND';
  END IF;

  v_def := replace(v_def, v_old, v_new);
  EXECUTE v_def;

  SELECT pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    INTO v_after;

  IF strpos(v_after, 'if v_run = v_latest_completed then') = 0
     OR strpos(v_after, 'v_fresh:=v_dispatch_fresh;') = 0 THEN
    RAISE EXCEPTION 'M8_7_POSTIMAGE_REUSE_BLOCK_MISSING';
  END IF;

  IF md5(v_after) = '697055d6762447ee802a4fad067ded51' THEN
    RAISE EXCEPTION 'M8_7_POSTIMAGE_UNCHANGED';
  END IF;
END $m87$;
