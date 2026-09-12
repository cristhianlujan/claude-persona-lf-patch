-- Mirrors the proven RTE-008 validator remediation pattern.
-- PostgREST invokes the public wrapper, so the timeout exception belongs there.
-- Do not change role/global statement_timeout.
ALTER FUNCTION public.fn_input_governance_curator_materialize_v1(integer, text, text)
  SET statement_timeout TO '30s';

ALTER FUNCTION programacion.fn_input_governance_curator_materialize_v1(integer, text, text, boolean)
  RESET statement_timeout;
