-- N-9 / M8.1 negative probe prelude.
-- Force the current ONB_004 readiness run stale without persistent effects.
-- The outer IG_RUNTIME_CANDIDATE_JUDGE transaction always rolls this back.
do $$
declare
  v_rows integer;
begin
  update lf_ops.pantallas
     set descripcion = coalesce(descripcion, '') || ' '
   where id = 57;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'N9_M81_PRELUDE_EXPECTED_ONE_SCREEN_ROW_GOT:%', v_rows;
  end if;
end
$$;
