-- Forward-only owner context for the quarantine cutover.
-- 180005 is already an immutable applied history point in the sandbox and correctly
-- removed schema CREATE. 180100 creates a new private relation and transfers it to
-- lf_governance_owner_v3, which PostgreSQL requires to have CREATE on the containing
-- schema at ownership-transfer time. 180150 removes this temporary CREATE again.

begin;

grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_governance_owner_v3;

commit;
