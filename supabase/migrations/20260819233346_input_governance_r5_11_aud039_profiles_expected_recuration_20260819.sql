do $do$
declare
  v_oid oid;
  v_def text;
  v_old text := $old$      'expected',0
    );$old$;
  v_new_block text := $new$      'expected',jsonb_array_length(programacion.fn_input_screen_canonical_graph(56,19)->'canonical_contract'->'profiles')
    );$new$;
  v_new text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_v58_assertion_template'
    and pg_get_function_identity_arguments(p.oid)='p_pantalla_id integer, p_family_code text, p_assertion jsonb';
  if v_oid is null then raise exception 'AUD039_TEMPLATE_FUNCTION_NOT_FOUND'; end if;
  v_def:=pg_get_functiondef(v_oid);
  if strpos(v_def,v_old)=0 then raise exception 'AUD039_EXPECTED_ZERO_BLOCK_NOT_FOUND'; end if;
  v_new:=replace(v_def,v_old,v_new_block);
  if v_new=v_def then raise exception 'AUD039_EXPECTED_BLOCK_NOT_CHANGED'; end if;
  execute v_new;
end
$do$;