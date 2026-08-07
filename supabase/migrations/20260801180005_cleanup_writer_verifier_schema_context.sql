begin;
revoke create on schema private from lf_writer_verifier_v7;
revoke create on schema private from lf_governance_owner_v3;
revoke create on schema public from lf_governance_owner_v3;
commit;
