-- Remove every temporary privilege used by the idempotency replacement migration.
-- Then prepare the verifier-owner context required by the following key-rotation
-- migration, which alters the verifier-owned nonce relation and verifier-owned
-- consume function. The later canonicalization migration revokes this membership.

begin;

revoke create on schema public from lf_governance_owner_v3;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;

commit;
