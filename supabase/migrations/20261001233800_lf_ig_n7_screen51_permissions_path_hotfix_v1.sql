-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · N-7 / PAULO-172 closure hotfix
-- Fix a stale assertion path for screen 51 PERMISSIONS.
-- The canonical graph exposes effective governed permissions in profile_permissions;
-- the expected permission codes remain unchanged.

do $hotfix$
declare
  v_def text := pg_get_functiondef('programacion.fn_input_v58_assertion_template(integer,text,jsonb)'::regprocedure);
  v_new text;
begin
  if md5(v_def) <> '3778739c813dc6031f5ba316a0dfdc92' then
    raise exception 'IG_N7_SCREEN51_PERMISSIONS_TEMPLATE_BASELINE_DRIFT:%', md5(v_def);
  end if;

  v_new := replace(
    v_def,
    $old$  elsif p_pantalla_id=51 and p_family_code='PERMISSIONS' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"permission":{"permission_code":"B2B_USER_UPDATE"}},{"permission":{"permission_code":"B2B_AUTH_FACTOR_RESET"}}]'::jsonb);
$old$,
    $new$  elsif p_pantalla_id=51 and p_family_code='PERMISSIONS' then
    v:=v || jsonb_build_object('path',jsonb_build_array('observed','profile_permissions'),'operator','CONTAINS','expected','[{"permission":{"permission_code":"B2B_USER_UPDATE"}},{"permission":{"permission_code":"B2B_AUTH_FACTOR_RESET"}}]'::jsonb);
$new$
  );

  if v_new = v_def then
    raise exception 'IG_N7_SCREEN51_PERMISSIONS_TEMPLATE_ANCHOR_NOT_FOUND';
  end if;

  execute v_new;
end;
$hotfix$;

comment on function programacion.fn_input_v58_assertion_template(integer,text,jsonb) is
  'N-7 closure hotfix: screen 51 PERMISSIONS binds the existing expected permission codes to canonical graph profile_permissions instead of the stale screen_permissions path.';
