-- Remove schema context no longer needed after the initial writer ownership transfer.
-- Governance still needs CREATE on private for the immediately-following quarantine
-- migration to transfer its new private table to lf_governance_owner_v3. That last
-- temporary CREATE privilege is removed by 20260801180150_trusted_v7_readback_grants.sql.

begin;

revoke create on schema private from lf_writer_verifier_v7;
revoke create on schema public from lf_governance_owner_v3;

commit;
