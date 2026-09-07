\set ON_ERROR_STOP on

begin;
\ir OP24_WORKING_CONTEXT_BUDGET_GATE_V1.sql

insert into private.lf_context_budget_events_v2(
  id, execution_id, estimated_tokens, context_status, source, recommendation, recorded_at, evidence_event_id
) overriding system value values
(99024001,'OP24-WC-GREEN',800,'GREEN','OP24_SANDBOX_CANARY',null,clock_timestamp(),null),
(99024002,'OP24-WC-RED',100,'RED','OP24_SANDBOX_CANARY',null,clock_timestamp(),null),
(99024003,'OP24-WC-YELLOW',100,'YELLOW','OP24_SANDBOX_CANARY',null,clock_timestamp(),null),
(99024004,'OP24-WC-UNKNOWN',100,'UNKNOWN','OP24_SANDBOX_CANARY',null,clock_timestamp(),null),
(99024005,'OP24-WC-STALE',100,'GREEN','OP24_SANDBOX_CANARY',null,clock_timestamp() - interval '2 hours',null),
(99024006,'OP24-WC-OVER',1200,'GREEN','OP24_SANDBOX_CANARY',null,clock_timestamp(),null),
(99024007,'OP24-WC-FUTURE',100,'GREEN','OP24_SANDBOX_CANARY',null,clock_timestamp() + interval '10 minutes',null),
(99024008,'OP24-WC-LATEST',100,'GREEN','OP24_SANDBOX_CANARY',null,clock_timestamp() - interval '1 minute',null),
(99024009,'OP24-WC-LATEST',100,'RED','OP24_SANDBOX_CANARY',null,clock_timestamp(),null);

do $test$
declare
  r jsonb;
begin
  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-GREEN',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,false) is not true or r->>'reason' <> 'BUDGET_GREEN_WITHIN_LIMIT' then
    raise exception 'EXPECTED_GREEN_ALLOW:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-MISSING',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,true) is not false or r->>'reason' <> 'BUDGET_NOT_OBSERVED' then
    raise exception 'EXPECTED_MISSING_BLOCK:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-RED',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,true) is not false or r->>'reason' <> 'BUDGET_STATUS_RED' then
    raise exception 'EXPECTED_RED_BLOCK:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-YELLOW',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,true) is not false or r->>'reason' <> 'BUDGET_STATUS_YELLOW' then
    raise exception 'EXPECTED_YELLOW_BLOCK:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-UNKNOWN',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,true) is not false or r->>'reason' <> 'BUDGET_STATUS_UNKNOWN' then
    raise exception 'EXPECTED_UNKNOWN_BLOCK:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-STALE',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,true) is not false or r->>'reason' <> 'BUDGET_STALE' then
    raise exception 'EXPECTED_STALE_BLOCK:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-OVER',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,true) is not false or r->>'reason' <> 'BUDGET_OVER_LIMIT' then
    raise exception 'EXPECTED_OVER_BLOCK:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-FUTURE',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,true) is not false or r->>'reason' <> 'BUDGET_EVENT_FROM_FUTURE' then
    raise exception 'EXPECTED_FUTURE_BLOCK:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-LATEST',1000,interval '1 hour');
  if coalesce((r->>'authorized')::boolean,true) is not false or r->>'reason' <> 'BUDGET_STATUS_RED' then
    raise exception 'EXPECTED_LATEST_EVENT_WINS:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('',1000,interval '1 hour');
  if r->>'reason' <> 'EXECUTION_ID_REQUIRED' then
    raise exception 'EXPECTED_EXECUTION_REQUIRED:%',r;
  end if;

  r := private.sbx_fn_lf_working_context_budget_gate_v1('OP24-WC-GREEN',-1,interval '1 hour');
  if r->>'reason' <> 'VALID_BUDGET_LIMIT_REQUIRED' then
    raise exception 'EXPECTED_LIMIT_REQUIRED:%',r;
  end if;
end
$test$;

rollback;

do $post$
begin
  if to_regprocedure('private.sbx_fn_lf_working_context_budget_gate_v1(text,bigint,interval)') is not null then
    raise exception 'BUDGET_GATE_FUNCTION_RESIDUE';
  end if;
  if exists(select 1 from private.lf_context_budget_events_v2 where id between 99024001 and 99024009) then
    raise exception 'BUDGET_GATE_EVENT_RESIDUE';
  end if;
end
$post$;
