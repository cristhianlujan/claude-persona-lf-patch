\set ON_ERROR_STOP on
-- Runs AFTER test_srcr_n1n2_source_first_ledger_20261030.sql in isolated DB.
-- STUBS ONLY: prove that the actual recorder calls the exact source function
-- before recording output_validate. No claim of live evidence or real core.
create or replace function public.lf_profile_execution_trust_validation_v2(
 p_execution_id text,p_step_id text,p_evidence_payload jsonb
) returns jsonb language sql as $$select '{"valid":true}'::jsonb$$;
create or replace function public.lf_record_operation_step_core_v1(
 p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,
 p_actor_execution_id text,p_operation_code text,p_target_type text,
 p_contract_state text,p_judge_state text,p_binding_state text,
 p_trust jsonb,p_bool boolean,p_caller text
) returns jsonb language plpgsql as $core$
begin
 insert into public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
 values(p_execution_id,p_step_id,'STEP_PASS_WITH_EVIDENCE',p_evidence_payload)
 on conflict(execution_id,step_id)
 do update set status=excluded.status,evidence_payload=excluded.evidence_payload;
 return jsonb_build_object('valid',true,'step_id',p_step_id);
end
$core$;

\ir SRCR_N1N2_RECORDER_EXTRACTED_TEST_ONLY.sql

do $test$
declare
  r jsonb;
  n integer;
begin
  -- First fixture's failure test mutated owner; restore to exact previous state.
  update public.lf_activos set owner_name=null where codigo_activo='ACT-0058';
  update public.lf_operation_execution
     set manifest='{"srcr_n1n2_ledger_gate":"SOURCE_FIRST_V1","evidence_ledger_execution_id":"EXEC-LEDGER"}'::jsonb
   where execution_id='EXEC-SRCR';
  r:=public.lf_record_profile_execution_step_v1(
   'EXEC-SRCR','output_validate','test://step60',
   '{"output_contract_result":"PASS","deterministic_validation":"PASS"}'::jsonb,
   'EXEC-TEST-ACTOR'
  );
  if r->>'valid' is distinct from 'true' then raise exception 'TEST_RECORDER_NO_PASS'; end if;
  select count(*) into n from private.lf_evidence_ledger_v1;
  if n<>2 then raise exception 'TEST_RECORDER_DUPLICATED_OR_FAILED_LEDGER:%',n; end if;
  if not exists(select 1 from public.lf_operation_execution_steps
    where execution_id='EXEC-SRCR' and step_id='output_validate'
      and status='STEP_PASS_WITH_EVIDENCE') then
    raise exception 'TEST_RECORDER_FAILED_TO_RECORD_STEP60';
  end if;
  update public.lf_operation_execution
    set manifest='{"srcr_n1n2_ledger_gate":"SOURCE_FIRST_V1","evidence_ledger_execution_id":"EXEC-FAKE"}'::jsonb
    where execution_id='EXEC-SRCR';
  begin
    perform public.lf_record_profile_execution_step_v1(
      'EXEC-SRCR','output_validate','test://step60','{}'::jsonb,'EXEC-TEST-ACTOR');
    raise exception 'TEST_EXPECTED_INVALID_ACTOR_BLOCK';
  exception when others then
    if SQLERRM<>'BLOCK_SRCR_LEDGER_ACTOR_NOT_BOUND_TO_PRODUCER' then raise; end if;
  end;
  update public.lf_operation_execution set manifest='{}'::jsonb
     where execution_id='EXEC-SRCR';
  update public.lf_activos set owner_name='TEST_SOURCE_DRIFT' where codigo_activo='ACT-0058';
  r:=public.lf_record_profile_execution_step_v1(
    'EXEC-SRCR','output_validate','test://legacy','{}'::jsonb,'EXEC-TEST-ACTOR');
  if r->>'valid' is distinct from 'true' or
      (select count(*) from private.lf_evidence_ledger_v1)<>2 then
     raise exception 'TEST_LEGACY_EXECUTION_REGRESSION';
  end if;
  raise notice 'PASS_SRCR_PROFILE_RECORDER_WIRING 4/4 (stubs; NOT LIVE)';
end
$test$;
