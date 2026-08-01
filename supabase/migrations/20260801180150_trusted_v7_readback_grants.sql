-- Explicit read/test execution for the trusted PostgreSQL root.
-- No table access or operational API writer permission is granted here.

begin;

set local role lf_writer_verifier_v7;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to postgres;
reset role;

set local role lf_governance_owner_v3;
grant execute on function private.fn_reconciliation_nonce_v7_valid(bigint)
  to postgres;
grant execute on function private.fn_gate_nonce_v7_valid(bigint)
  to postgres;
reset role;

commit;
