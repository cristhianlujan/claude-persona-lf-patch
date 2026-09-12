-- PR93: distinguish Supabase-managed administrative metadata from runtime access.
-- The trusted postgres administrator may retain non-inheritable/non-settable
-- memberships created by Supabase. Runtime roles must not inherit or SET the LF
-- owner roles. pg_net ACLs are platform-managed; Data API exposure is measured at
-- callable wrappers in exposed API schemas and the hosted PostgREST schema list is
-- verified by the required GitHub gate.

create or replace function private.fn_governance_role_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    (
      select count(*)=2
      from pg_catalog.pg_roles r
      where r.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
    )
    and not exists (
      select 1
      from pg_catalog.pg_roles r
      where r.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
        and (r.rolcanlogin or r.rolinherit or r.rolbypassrls)
    )
    and not exists (
      select 1
      from pg_catalog.pg_auth_members m
      join pg_catalog.pg_roles member_role on member_role.oid=m.member
      join pg_catalog.pg_roles granted_role on granted_role.oid=m.roleid
      where granted_role.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
        and (
          member_role.rolname <> 'postgres'
          or m.inherit_option
          or m.set_option
        )
    )
    and not exists (
      select 1
      from pg_catalog.pg_auth_members m
      join pg_catalog.pg_roles member_role on member_role.oid=m.member
      where member_role.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
    );
$function$;

alter function private.fn_governance_role_separation_v7_valid() owner to postgres;
revoke all on function private.fn_governance_role_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_governance_role_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_net_api_exposure_v7_count()
returns bigint
language sql
stable
security definer
set search_path to ''
as $function$
  select count(*)
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','graphql_public')
    and p.prokind='f'
    and (
      pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      or pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
      or pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE')
    )
    and (
      p.prosrc ~* E'\\mnet\\s*\\.'
      or p.prosrc ~* E'\\mfn_dispatch_architecture_outbox_v4\\M'
      or coalesce(pg_catalog.array_to_string(p.proconfig,','),'')
           ~* E'search_path=.*\\mnet\\M'
    );
$function$;

alter function private.fn_net_api_exposure_v7_count() owner to postgres;
revoke all on function private.fn_net_api_exposure_v7_count()
  from public,anon,authenticated;
grant execute on function private.fn_net_api_exposure_v7_count()
  to postgres,service_role,lf_governance_owner_v3;
