do $do$
declare
  v_oid oid;
  v_def text;
  v_old text := $old$  elsif p_pantalla_id=56 and p_family_code='PROFILES' then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),
      'path',jsonb_build_array('observed','rules'),
      'operator','CONTAINS',
      'expected','[{"rule":{"codigo":"B2B-RULE-AUTH-029","valor_config":{"operational_authorization_before_completion":"DENY","recovery_context_scope":"PASSWORD_UPDATE_ONLY","client_context_promotion":"DENY"}}}]'::jsonb
    );$old$;
  v_new_block text := $new$  elsif p_pantalla_id=56 and p_family_code='PROFILES' then
    v:=jsonb_build_object(
      'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),
      'path',jsonb_build_array('observed','canonical_contract','profiles'),
      'operator','ARRAY_LENGTH_EQ',
      'expected',0
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
  if strpos(v_def,v_old)=0 then raise exception 'AUD039_PROFILES_BLOCK_NOT_FOUND'; end if;
  v_new:=replace(v_def,v_old,v_new_block);
  if v_new=v_def then raise exception 'AUD039_PROFILES_BLOCK_NOT_CHANGED'; end if;
  execute v_new;
end
$do$;