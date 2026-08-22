do $do$
declare
  v_oid oid;
  v_def text;
  v_old text := $old$  elsif p_family_code='BROWSER_PLATFORM' and p_pantalla_id in (51,52,53,54,56) then$old$;
  v_new_block text := $new$  elsif p_family_code='DESIGN_SYSTEM'
        and v_kind='SCREEN_CANONICAL_GRAPH'
        and v->'path'=jsonb_build_array('observed','canonical_contract','visual','design_bindings','summary','element_inventory_count') then
    v:=v || jsonb_build_object(
      'operator','EQ',
      'expected',coalesce((programacion.fn_input_screen_canonical_graph(p_pantalla_id,19)#>>'{canonical_contract,visual,design_bindings,summary,element_inventory_count}')::integer,0)
    );

  elsif p_family_code='BROWSER_PLATFORM' and p_pantalla_id in (51,52,53,54,56) then$new$;
  v_new text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_v58_assertion_template'
    and pg_get_function_identity_arguments(p.oid)='p_pantalla_id integer, p_family_code text, p_assertion jsonb';
  if v_oid is null then raise exception 'DESIGN_RECURATION_TEMPLATE_FUNCTION_NOT_FOUND'; end if;
  v_def:=pg_get_functiondef(v_oid);
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 then
    raise exception 'DESIGN_RECURATION_EXPECTED_ONE_INSERTION_POINT';
  end if;
  v_new:=replace(v_def,v_old,v_new_block);
  if v_new=v_def then raise exception 'DESIGN_RECURATION_TEMPLATE_NOT_CHANGED'; end if;
  execute v_new;
end
$do$;

revoke all on function programacion.fn_input_v58_assertion_template(integer,text,jsonb) from public;
grant execute on function programacion.fn_input_v58_assertion_template(integer,text,jsonb) to postgres;