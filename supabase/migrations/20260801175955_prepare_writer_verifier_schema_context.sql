-- Temporary schema context required for V7 verifier/governance-owned objects.
-- CREATE is removed immediately after the ownership migration; USAGE remains only
-- where the runtime owner requires it.

begin;

grant usage, create on schema private to lf_writer_verifier_v7;
grant usage, create on schema private to lf_governance_owner_v3;

-- PostgreSQL requires the new owner to have CREATE on the containing schema before
-- ownership of public V7 writer functions can be transferred.
grant usage, create on schema public to lf_governance_owner_v3;

commit;
