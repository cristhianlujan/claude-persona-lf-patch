-- INPUT_GOVERNANCE_AGENT 5.12
-- Correct the scoped timeout target to the actual PostgREST RPC entrypoint.
-- PostgREST invokes public.fn_input_governance_validator_validate_v1; the
-- programacion function is an internal delegate and must not carry the RPC override.
ALTER FUNCTION public.fn_input_governance_validator_validate_v1(bigint, text)
  SET statement_timeout TO '30s';

ALTER FUNCTION programacion.fn_input_governance_validator_validate_v1(bigint, text)
  RESET statement_timeout;
