-- Temporary role setup required for explicit PostgreSQL object ownership changes.
-- Every membership granted here is removed by later migrations in the same batch.

begin;

do $block$
begin
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7') then
    create role lf_writer_verifier_v7 nologin noinherit nobypassrls;
  end if;
end
$block$;

alter role lf_writer_verifier_v7 nologin noinherit nobypassrls;

-- PostgreSQL requires SET OPTION on a target owner role before ownership can be
-- transferred. INHERIT remains false and no operational privileges are inherited.
grant lf_writer_verifier_v7 to postgres
  with admin false, inherit false, set true
  granted by postgres;
grant lf_governance_owner_v3 to postgres
  with admin false, inherit false, set true
  granted by postgres;

commit;
