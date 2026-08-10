begin;

grant lf_governance_owner_v3 to postgres
  with admin false, inherit false, set true
  granted by postgres;
grant create on schema public to lf_governance_owner_v3;

set local role lf_governance_owner_v3;

do $patch$
declare
  def text;
  old_guard text := $$x.value not in ('ARTIFACT_SHA256_MISMATCH','BRANCH_PROTECTION_NOT_VERIFIED')$$;
  new_guard text := $$x.value not in ('ARTIFACT_SHA256_MISMATCH','ARTIFACT_NOT_EXERCISED_BY_WORKFLOW','BRANCH_PROTECTION_NOT_VERIFIED')$$;
begin
  select pg_get_functiondef('public.sync_lf_artifact_content_from_repository_v3(bigint,bigint,text,text)'::regprocedure)
    into def;

  if position(old_guard in def)=0 then
    raise exception 'repository sync v3 eligibility anchor missing';
  end if;

  def:=replace(def,old_guard,new_guard);
  execute def;
end;
$patch$;

reset role;
revoke create on schema public from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

do $assertions$
declare
  def text;
  owner_name text;
begin
  select pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner)
    into def,owner_name
  from pg_proc p
  where p.oid='public.sync_lf_artifact_content_from_repository_v3(bigint,bigint,text,text)'::regprocedure;

  if position($$x.value not in ('ARTIFACT_SHA256_MISMATCH','ARTIFACT_NOT_EXERCISED_BY_WORKFLOW','BRANCH_PROTECTION_NOT_VERIFIED')$$ in def)=0 then
    raise exception 'repository sync v3 corrected eligibility guard missing';
  end if;
  if position($$x.value='ARTIFACT_SHA256_MISMATCH'$$ in def)=0 then
    raise exception 'repository sync v3 no longer requires SHA mismatch';
  end if;
  if owner_name<>'lf_governance_owner_v3' then
    raise exception 'repository sync v3 owner changed unexpectedly: %',owner_name;
  end if;
  if not has_function_privilege('service_role','public.sync_lf_artifact_content_from_repository_v3(bigint,bigint,text,text)','EXECUTE') then
    raise exception 'repository sync v3 service_role execute grant missing';
  end if;
  if has_schema_privilege('lf_governance_owner_v3','public','CREATE') then
    raise exception 'temporary public schema CREATE privilege was not revoked';
  end if;
  if exists (
    select 1
    from pg_auth_members m
    join pg_roles r on r.oid=m.roleid
    join pg_roles member on member.oid=m.member
    where r.rolname='lf_governance_owner_v3'
      and member.rolname='postgres'
      and pg_get_userbyid(m.grantor)='postgres'
  ) then
    raise exception 'temporary postgres governance-owner membership was not revoked';
  end if;
end;
$assertions$;

commit;
