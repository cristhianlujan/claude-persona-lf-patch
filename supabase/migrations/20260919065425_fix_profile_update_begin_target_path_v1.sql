-- FIX_PROFILE_UPDATE_BEGIN_TARGET_PATH_V1
-- ACTUALIZACION_PERFIL_LF may target a canonical profile file such as
-- profiles/<slug>/contracts/runtime_binding.json. Permit dots in a bounded
-- profiles/** path while keeping traversal/backslash/colon blocked.

do $patch$
declare
  v_def text;
  v_old text := $old$if p_target_path !~ '^profiles/[a-z0-9][a-z0-9_/-]*$'$old$;
  v_new text := $new$if p_target_path !~ '^profiles/[a-z0-9][a-z0-9_./-]*$'$new$;
begin
  select pg_get_functiondef(
    'public.lf_profile_update_begin_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure
  ) into v_def;

  if position(v_old in v_def)=0 then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_TARGET_PATH_PATCH_SOURCE_DRIFT';
  end if;

  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end;
$patch$;

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'public.lf_profile_update_begin_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure
  ) into v_def;
  if position($needle$^profiles/[a-z0-9][a-z0-9_./-]*$$needle$ in v_def)=0 then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_TARGET_PATH_PATCH_VERIFY_FAILED';
  end if;
end;
$verify$;
