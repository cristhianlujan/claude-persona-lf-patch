-- Remove every temporary privilege used by the idempotency replacement migration.

begin;

revoke create on schema public from lf_governance_owner_v3;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

commit;
