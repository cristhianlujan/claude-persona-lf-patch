-- Repair the two stale successor-currentness consumers of T-INVAL.
-- A BLOCKED successor is immutable and terminal, but it must NOT invalidate
-- the last COMPLETED predecessor; only a COMPLETED successor does.
-- Preserve terminal run validity, the run immutability guard, and old ledger rows.
DO $repair$
DECLARE v_func regprocedure;v_source text;v_fixed text;v_old text;v_new text;v_count int;
BEGIN
 FOR v_func,v_old,v_new IN
 SELECT
  'programacion.fn_input_run_source_currentness_v1(bigint)'::regprocedure,
  'n.status IN (''COMPLETED'',''BLOCKED'')',
  'n.status=''COMPLETED'''
 UNION ALL SELECT
  'programacion.fn_input_freshness_delta(bigint)'::regprocedure,
  'n.status in (''COMPLETED'',''BLOCKED'')',
  'n.status=''COMPLETED'''
 LOOP
  v_source:=pg_get_functiondef(v_func);
  v_count:=(length(v_source)-length(replace(v_source,v_old,'')))/length(v_old);
  IF v_count<>1 OR v_source NOT LIKE '%supersedes_run_id%' THEN
    RAISE EXCEPTION 'IG_TINVAL_CURRENTNESS_SOURCE_DRIFT:% occurrences:%',v_func,v_count;
  END IF;
  v_fixed:=replace(v_source,v_old,v_new);
  IF v_fixed=v_source THEN RAISE EXCEPTION 'IG_TINVAL_REPAIR_WAS_NOOP:%',v_func;END IF;
  EXECUTE v_fixed;
 END LOOP;
END;
$repair$;
DO $readback$
DECLARE v_first text;v_second text;v_latch text;
BEGIN
 v_first:=pg_get_functiondef('programacion.fn_input_run_source_currentness_v1(bigint)'::regprocedure);
 v_second:=pg_get_functiondef('programacion.fn_input_freshness_delta(bigint)'::regprocedure);
 v_latch:=pg_get_functiondef('programacion.fn_input_latch_predecessor_invalidation()'::regprocedure);
 IF v_first LIKE '%n.status IN (''COMPLETED'',''BLOCKED'')%'
    OR v_second LIKE '%n.status in (''COMPLETED'',''BLOCKED'')%'
    OR v_first NOT LIKE '%n.status=''COMPLETED''%'
    OR v_second NOT LIKE '%n.status=''COMPLETED''%'
    OR v_latch NOT LIKE '%new.status=''COMPLETED''%'
 THEN RAISE EXCEPTION 'IG_TINVAL_CURRENTNESS_LATCH_READBACK_FAILED';END IF;
END;
$readback$;