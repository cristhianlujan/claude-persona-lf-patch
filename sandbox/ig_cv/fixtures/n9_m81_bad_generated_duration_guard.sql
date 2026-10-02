-- N-9 / M8.1 negative probe candidate.
-- Reintroduce only the historical generated-duration guard defect inside the
-- judge transaction. The outer judge ROLLBACK restores the live definition.
do $$
declare
  v_def text;
  v_bad text;
  v_occurrences integer;
begin
  v_def := pg_get_functiondef('programacion.fn_guard_input_readiness_run()'::regprocedure);
  v_occurrences :=
    (length(v_def) - length(replace(v_def, '-''curator_duration_ms''-''validator_duration_ms''', '')))
    / length('-''curator_duration_ms''-''validator_duration_ms''');

  if v_occurrences <> 2 then
    raise exception 'N9_M81_NEGATIVE_FIXTURE_EXPECTED_2_HOTFIX_OCCURRENCES_GOT:%', v_occurrences;
  end if;

  v_bad := replace(
    v_def,
    '-''curator_duration_ms''-''validator_duration_ms''',
    ''
  );

  execute v_bad;
end
$$;
