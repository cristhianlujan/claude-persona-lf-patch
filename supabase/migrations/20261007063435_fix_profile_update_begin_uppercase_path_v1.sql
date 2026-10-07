-- FIX_PROFILE_UPDATE_BEGIN_UPPERCASE_PATH_V1
-- ACTUALIZACION_PERFIL_LF must be able to bind canonical profile files such as
-- profiles/<slug>/SKILL.md. Align the DB path validator with the governed
-- Edge Function while keeping traversal, backslash and colon blocked.

do $patch$
declare
  v_def text;
  v_old text := $old$if p_target_path !~ '^profiles/[a-z0-9][a-z0-9_./-]*$'$old$;
  v_new text := $new$if p_target_path !~ '^profiles/[A-Za-z0-9][A-Za-z0-9_./-]*$'$new$;
begin
  select pg_get_functiondef(
    'public.lf_profile_update_begin_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure
  ) into v_def;

  if position(v_old in v_def)=0 then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_UPPERCASE_PATH_PATCH_SOURCE_DRIFT';
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

  if position($needle$^profiles/[A-Za-z0-9][A-Za-z0-9_./-]*$$needle$ in v_def)=0 then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_UPPERCASE_PATH_PATCH_VERIFY_FAILED';
  end if;

  if 'profiles/systemic_root_cause_repair_lf/SKILL.md' !~ '^profiles/[A-Za-z0-9][A-Za-z0-9_./-]*$' then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_UPPERCASE_PATH_POSITIVE_FAILED';
  end if;

  if 'profiles/systemic_root_cause_repair_lf/SKILL:md' ~ '^profiles/[A-Za-z0-9][A-Za-z0-9_./-]*$'
     or 'profiles/systemic_root_cause_repair_lf\SKILL.md' ~ '^profiles/[A-Za-z0-9][A-Za-z0-9_./-]*$'
     or position('..' in 'profiles/systemic_root_cause_repair_lf/../SKILL.md')=0 then
    raise exception 'LF_PROFILE_UPDATE_BEGIN_UPPERCASE_PATH_NEGATIVE_FAILED';
  end if;
end;
$verify$;
