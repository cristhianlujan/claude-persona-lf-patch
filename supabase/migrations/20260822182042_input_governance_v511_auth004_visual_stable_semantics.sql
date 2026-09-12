do $do$
declare
  v_oid oid;
  v_def text;
  v_old text := $old$  elsif p_pantalla_id in (52,53,56) and p_family_code='VISUAL_EVIDENCE' then$old$;
  v_new_block text := $new$  elsif p_pantalla_id=54 and p_family_code='VISUAL_EVIDENCE' then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',54),
      'path',jsonb_build_array('observed'),
      'operator','CONTAINS',
      'expected',jsonb_build_array(
        jsonb_build_object('artifact',jsonb_build_object('pantalla_id',54,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-004-DESKTOP-LIGHT'))),
        jsonb_build_object('artifact',jsonb_build_object('pantalla_id',54,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-004-TABLET-LIGHT'))),
        jsonb_build_object('artifact',jsonb_build_object('pantalla_id',54,'is_current',true,'status','CANDIDATO_VISUAL','storage_provider','GOOGLE_DRIVE','storage_metadata',jsonb_build_object('variant_code','B2B-AUTH-004-MOBILE-LIGHT')))
      )
    );

  elsif p_pantalla_id in (52,53,56) and p_family_code='VISUAL_EVIDENCE' then$new$;
  v_new text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_v58_assertion_template'
    and pg_get_function_identity_arguments(p.oid)='p_pantalla_id integer, p_family_code text, p_assertion jsonb';
  if v_oid is null then raise exception 'AUTH004_VISUAL_TEMPLATE_FUNCTION_NOT_FOUND'; end if;
  v_def:=pg_get_functiondef(v_oid);
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old) <> 1 then
    raise exception 'AUTH004_VISUAL_EXPECTED_ONE_INSERTION_POINT';
  end if;
  v_new:=replace(v_def,v_old,v_new_block);
  if v_new=v_def then raise exception 'AUTH004_VISUAL_TEMPLATE_NOT_CHANGED'; end if;
  execute v_new;
end
$do$;

revoke all on function programacion.fn_input_v58_assertion_template(integer,text,jsonb) from public;
grant execute on function programacion.fn_input_v58_assertion_template(integer,text,jsonb) to postgres;