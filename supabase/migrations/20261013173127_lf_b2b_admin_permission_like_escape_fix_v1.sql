-- LF_B2B_ADMIN_PERMISSION_LIKE_ESCAPE_FIX_V1
-- Forward fix for 20261008033605_b2b_admin_lf_all_permissions_v1.
-- When that migration was applied, the backslashes were lost in transport, so the live
-- trigger function compares permission_code LIKE 'B2B_%' ESCAPE '' (the "_" is a wildcard,
-- so e.g. 'B2BX...' would also be treated as B2B). The intended pattern is a literal
-- underscore: LIKE 'B2B\_%' ESCAPE '\'.
-- Data impact verified read-only on 2026-10-13: 0 rows in lf_ops.permisos match the wildcard
-- but not the literal pattern; this patch only removes the latent defect.
-- Scope: lf_ops.sync_b2b_admin_lf_permission_v1() body only. No data writes.

do $patch$
declare
  v_def text;
  v_old text := $old$like 'B2B_%' escape ''$old$;
  v_new text := $new$like 'B2B\_%' escape '\'$new$;
begin
  select pg_get_functiondef('lf_ops.sync_b2b_admin_lf_permission_v1()'::regprocedure) into v_def;
  if position(v_old in v_def) = 0 then
    raise exception 'LF_B2B_LIKE_ESCAPE_FIX_SOURCE_DRIFT';
  end if;
  -- "not like" occurrences contain "like ..." as a substring, so one replace covers both.
  v_def := replace(v_def, v_old, v_new);
  execute v_def;
end;
$patch$;

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef('lf_ops.sync_b2b_admin_lf_permission_v1()'::regprocedure) into v_def;
  if position($bad$escape ''$bad$ in v_def) > 0 then
    raise exception 'LF_B2B_LIKE_ESCAPE_FIX_VERIFY_FAILED_OLD_PATTERN_PRESENT';
  end if;
  if position($good$like 'B2B\_%' escape '\'$good$ in v_def) = 0 then
    raise exception 'LF_B2B_LIKE_ESCAPE_FIX_VERIFY_FAILED_NEW_PATTERN_MISSING';
  end if;
  if not ('B2B_ADMIN' like $p$B2B\_%$p$ escape $e$\$e$) then
    raise exception 'LF_B2B_LIKE_ESCAPE_FIX_POSITIVE_FAILED';
  end if;
  if 'B2BXADMIN' like $p$B2B\_%$p$ escape $e$\$e$ then
    raise exception 'LF_B2B_LIKE_ESCAPE_FIX_NEGATIVE_FAILED';
  end if;
end;
$verify$;
