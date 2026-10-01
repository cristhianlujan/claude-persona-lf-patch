-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L2 · T-INVAL / PAULO-029
-- A BLOCKED successor must not invalidate the last completed predecessor.
-- Keep the existing latch and change only the terminal-success condition.

do $migration$
declare
  v_def text;
  v_new text;
begin
  v_def := pg_get_functiondef('programacion.fn_input_latch_predecessor_invalidation()'::regprocedure);
  if md5(v_def) <> 'b97da8a5ad88eef23cb915d3362cf5aa' then
    raise exception 'T_INVAL_LATCH_BASELINE_DRIFT:%', md5(v_def);
  end if;

  v_new := replace(
    v_def,
    'new.status in (''COMPLETED'',''BLOCKED'')',
    'new.status=''COMPLETED'''
  );
  if v_new = v_def then
    raise exception 'T_INVAL_LATCH_ANCHOR_NOT_FOUND';
  end if;

  execute v_new;
end;
$migration$;

comment on function programacion.fn_input_latch_predecessor_invalidation() is
  'T-INVAL: predecessor invalidation is latched only when a successor reaches COMPLETED; BLOCKED successors preserve the prior current run.';
