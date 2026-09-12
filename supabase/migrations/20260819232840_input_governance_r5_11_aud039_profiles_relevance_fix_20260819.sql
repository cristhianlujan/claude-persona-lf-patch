do $do$
declare
  v_oid oid;
  v_def text;
  v_new text;
  v_old text := $q$jsonb_build_object('kind','SCREEN_RULE_SET','pantalla_id',56)$q$;
  v_good text := $q$jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56)$q$;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_v58_assertion_template'
    and pg_get_function_identity_arguments(p.oid)='p_pantalla_id integer, p_family_code text, p_assertion jsonb';
  if v_oid is null then raise exception 'AUD039_TEMPLATE_FUNCTION_NOT_FOUND'; end if;
  v_def:=pg_get_functiondef(v_oid);
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 then
    raise exception 'AUD039_EXPECTED_EXACTLY_ONE_TARGET';
  end if;
  v_new:=replace(v_def,v_old,v_good);
  execute v_new;
end
$do$;