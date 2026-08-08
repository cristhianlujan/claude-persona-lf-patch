-- PR #93 · V7 runtime permission repair
-- The SECURITY DEFINER writer verifier calls extensions.digest/hmac.
-- It needs schema USAGE, never CREATE.
begin;

do $preflight$
begin
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7') then
    raise exception 'lf_writer_verifier_v7 is required';
  end if;
  if not exists (select 1 from pg_namespace where nspname='extensions') then
    raise exception 'extensions schema is required';
  end if;
end
$preflight$;

grant usage on schema extensions to lf_writer_verifier_v7;

do $assertions$
begin
  if not has_schema_privilege('lf_writer_verifier_v7','extensions','USAGE') then
    raise exception 'lf_writer_verifier_v7 requires USAGE on extensions';
  end if;
  if has_schema_privilege('lf_writer_verifier_v7','extensions','CREATE') then
    raise exception 'lf_writer_verifier_v7 must not have CREATE on extensions';
  end if;
  if not has_function_privilege('lf_writer_verifier_v7','extensions.digest(bytea,text)','EXECUTE') then
    raise exception 'lf_writer_verifier_v7 requires EXECUTE on extensions.digest';
  end if;
  if not has_function_privilege('lf_writer_verifier_v7','extensions.hmac(bytea,bytea,text)','EXECUTE') then
    raise exception 'lf_writer_verifier_v7 requires EXECUTE on extensions.hmac';
  end if;
end
$assertions$;

commit;
