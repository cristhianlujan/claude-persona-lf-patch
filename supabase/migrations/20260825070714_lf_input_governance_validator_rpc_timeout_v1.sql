-- INPUT_GOVERNANCE_AGENT 5.12
-- Scoped remediation for REC_001 validator runtime.
-- Do not change role/global statement_timeout; only the governed validator RPC wrapper.
ALTER FUNCTION programacion.fn_input_governance_validator_validate_v1(bigint, text)
  SET statement_timeout TO '30s';
