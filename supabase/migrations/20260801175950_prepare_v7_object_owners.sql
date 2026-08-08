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

-- The migration executor must retain effective owner authority after objects are
-- transferred, including REFERENCES, DML, trigger and ALTER operations. INHERIT is
-- enabled only for this atomic migration chain; the final V7 migration revokes both
-- memberships before COMMIT, restoring the restricted post-migration state.
grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;

commit;
