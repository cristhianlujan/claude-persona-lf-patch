-- Temporary schema context required for V7 verifier/governance-owned objects.
-- CREATE is removed immediately after the ownership migration; USAGE remains.

begin;

grant usage, create on schema private to lf_writer_verifier_v7;
grant usage, create on schema private to lf_governance_owner_v3;

commit;
