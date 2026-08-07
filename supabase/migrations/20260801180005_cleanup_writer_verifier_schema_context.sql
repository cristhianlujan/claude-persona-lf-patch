-- Remove temporary CREATE while preserving schema USAGE for verifier-owned functions.

begin;

revoke create on schema private from lf_writer_verifier_v7;

commit;
