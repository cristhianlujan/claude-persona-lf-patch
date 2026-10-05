begin;

-- One-time bootstrap using the legacy role switch. After this migration the
-- engineering executor can perform normal DML on relations already protected
-- by the v3 governance guard without SET ROLE choreography.
grant lf_governance_owner_v3 to postgres
  with admin false, inherit false, set true
  granted by postgres;
set local role lf_governance_owner_v3;

do $grant_acl$
declare
  r record;
begin
  for r in
    select n.nspname as schema_name, c.relname as relation_name
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where t.tgfoid='private.fn_guard_governed_relation_v3()'::regprocedure
      and not t.tgisinternal
    order by n.nspname,c.relname
  loop
    execute format(
      'grant select, insert, update, delete on table %I.%I to postgres',
      r.schema_name,r.relation_name
    );
  end loop;
end
$grant_acl$;

reset role;
revoke lf_governance_owner_v3 from postgres granted by postgres;

do $verify$
declare
  v_missing integer;
  v_membership_restored boolean;
begin
  select count(*) into v_missing
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  where t.tgfoid='private.fn_guard_governed_relation_v3()'::regprocedure
    and not t.tgisinternal
    and not (
      has_table_privilege('postgres',c.oid,'SELECT')
      and has_table_privilege('postgres',c.oid,'INSERT')
      and has_table_privilege('postgres',c.oid,'UPDATE')
      and has_table_privilege('postgres',c.oid,'DELETE')
    );

  if v_missing<>0 then
    raise exception 'BLOCK_GOVERNED_WRITER_ACL_MISSING count=%',v_missing;
  end if;

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
end
$verify$;

commit;
