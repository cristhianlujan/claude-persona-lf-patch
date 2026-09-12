do $$
begin
  if to_regprocedure('public.fn_input_governance_execute(integer,text)') is null then
    raise exception 'PUBLIC_INPUT_GOVERNANCE_EXECUTE_RPC_NOT_FOUND';
  end if;
end
$$;

alter function public.fn_input_governance_execute(integer, text)
  set statement_timeout = '30s';