begin;

-- One-time bootstrap through the legacy role switch. Temporary privileges are
-- removed before commit; future governed relation writes no longer need them.
grant lf_governance_owner_v3 to postgres
  with admin false, inherit false, set true
  granted by postgres;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

create or replace function private.fn_guard_governed_relation_v3()
returns trigger
language plpgsql
set search_path to 'pg_catalog'
as $$
begin
  if not pg_has_role(current_user, 'lf_governance_owner_v3', 'MEMBER') then
    raise exception using
      errcode='42501',
      message=format('governed relation %I.%I only accepts writes through an authorized v3 writer', tg_table_schema, tg_table_name);
  end if;

  if tg_argv[0]='APPEND_ONLY' and tg_op in ('UPDATE','DELETE') then
    raise exception using
      errcode='55000',
      message=format('%I.%I is append-only',tg_table_schema,tg_table_name);
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

comment on function private.fn_guard_governed_relation_v3() is
'Governed relation guard v3. Authorized writer is any role that is a member of lf_governance_owner_v3. This preserves relation guards while avoiding temporary GRANT/SET ROLE/REVOKE choreography for the engineering executor.';

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

do $verify$
declare
  v_membership_restored boolean;
begin
  select count(*)=1
         and bool_and(pg_get_userbyid(am.grantor)='supabase_admin'
                      and am.admin_option
                      and not am.inherit_option
                      and not am.set_option)
    into v_membership_restored
  from pg_auth_members am
  join pg_roles granted on granted.oid=am.roleid
  join pg_roles member on member.oid=am.member
  where granted.rolname='lf_governance_owner_v3'
    and member.rolname='postgres';

  if not coalesce(v_membership_restored,false) then
    raise exception 'BLOCK_GOVERNED_WRITER_MEMBERSHIP_NOT_RESTORED';
  end if;

  if has_schema_privilege('lf_governance_owner_v3','private','CREATE') then
    raise exception 'BLOCK_GOVERNED_WRITER_SCHEMA_CREATE_NOT_RESTORED';
  end if;

  if not pg_has_role('postgres','lf_governance_owner_v3','MEMBER') then
    raise exception 'BLOCK_GOVERNED_WRITER_POSTGRES_NOT_MEMBER';
  end if;

  if pg_has_role('anon','lf_governance_owner_v3','MEMBER')
     or pg_has_role('authenticated','lf_governance_owner_v3','MEMBER')
     or pg_has_role('service_role','lf_governance_owner_v3','MEMBER') then
    raise exception 'BLOCK_GOVERNED_WRITER_PUBLIC_OR_SERVICE_ROLE_MEMBER';
  end if;
end
$verify$;

commit;
