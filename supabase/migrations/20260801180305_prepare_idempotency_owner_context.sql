-- Temporary owner context for replacing governance-owned V7 writers.
-- These privileges are revoked by 20260801180320_cleanup_idempotency_owner_context.sql.

begin;

grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema public to lf_governance_owner_v3;
grant create on schema private to lf_governance_owner_v3;

commit;
