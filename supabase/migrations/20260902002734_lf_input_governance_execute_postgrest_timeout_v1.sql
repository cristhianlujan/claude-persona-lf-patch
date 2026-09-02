-- RTE-008 recurrence: PostgREST applies the caller role statement_timeout before the
-- internal programacion.* delegate can govern the request. The exception therefore
-- belongs on the exact public RPC entrypoint consumed by the Edge orchestrator.
--
-- Scope: timeout configuration only. No readiness semantics, gates, product data,
-- permissions, production authorization, or downstream authorization are changed.

do $$
begin
  if to_regprocedure('public.fn_input_governance_execute(integer,text)') is null then
    raise exception 'PUBLIC_INPUT_GOVERNANCE_EXECUTE_RPC_NOT_FOUND';
  end if;
end
$$;

alter function public.fn_input_governance_execute(integer, text)
  set statement_timeout = '30s';
