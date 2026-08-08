do $$
begin
  if not exists (select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    create role lf_governance_owner_v3 nologin noinherit;
  end if;
end
$$;
grant lf_governance_owner_v3 to postgres;
grant usage, create on schema private, public to lf_governance_owner_v3;
