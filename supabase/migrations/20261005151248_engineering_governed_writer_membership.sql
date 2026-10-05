begin;

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

do $verify$
begin
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
