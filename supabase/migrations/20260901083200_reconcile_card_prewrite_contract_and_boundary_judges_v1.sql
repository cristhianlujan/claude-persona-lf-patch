-- Source-first reconciliation for CREACION_CARD_LF boundary.
-- Aligns deployed step contracts with the already-canonical Git/runtime order
-- and materializes only the two exact mini-judges deterministically implied by
-- their existing active step contracts. No runtime/production/automatic impact.

do $migration$
declare
  v_bad integer;
begin
  select count(*) into v_bad
  from public.lf_operation_steps
  where operation_code='CREACION_CARD_LF'
    and (step_id,step_order) not in (
      ('pre_write_execution_binding_gate',24),
      ('github_write',25),
      ('github_readback',26),
      ('evidence_log',27)
    )
    and step_id in ('pre_write_execution_binding_gate','github_write','github_readback','evidence_log');
  if v_bad<>0 then
    raise exception 'CARD_RUNTIME_BOUNDARY_ORDER_NOT_CANONICAL';
  end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='CREACION_CARD_LF' and step_id='github_write'
      and contract_code='CONTRACT_CREACION_CARD_LF_GITHUB_WRITE_V1'
      and mini_judge_code='MINI_JUDGE_CREACION_CARD_LF_GITHUB_WRITE_V1'
      and blocking_code='BLOCKED_GITHUB_WRITE_NOT_CLEAN'
  ) then raise exception 'CARD_GITHUB_WRITE_CONTRACT_BASELINE_MISMATCH'; end if;

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='CREACION_CARD_LF' and step_id='github_readback'
      and contract_code='CONTRACT_CREACION_CARD_LF_GITHUB_READBACK_V1'
      and mini_judge_code='MINI_JUDGE_CREACION_CARD_LF_GITHUB_READBACK_V1'
      and blocking_code='BLOCKED_GITHUB_READBACK_NOT_CLEAN'
  ) then raise exception 'CARD_GITHUB_READBACK_CONTRACT_BASELINE_MISMATCH'; end if;

  update public.lf_operation_step_contracts
  set step_order = case step_id
      when 'pre_write_execution_binding_gate' then 24
      when 'github_write' then 25
      when 'github_readback' then 26
      when 'evidence_log' then 27
    end,
    execution_order = case step_id
      when 'pre_write_execution_binding_gate' then 24
      when 'github_write' then 25
      when 'github_readback' then 26
      when 'evidence_log' then 27
    end,
    updated_at=now()
  where operation_code='CREACION_CARD_LF'
    and step_id in ('pre_write_execution_binding_gate','github_write','github_readback','evidence_log');

  insert into public.lf_operation_judges(
    operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
    created_at,updated_at,created_by_execution_id,updated_by_execution_id
  ) values
  ('CREACION_CARD_LF','MINI_JUDGE_CREACION_CARD_LF_GITHUB_WRITE_V1',
   'supabase://public/lf_operation_step_contracts/CREACION_CARD_LF/github_write',
   'CONTRACT_CREACION_CARD_LF_GITHUB_WRITE_V1',
   '{"pass_condition_met":true,"step_contract_present":true,"generic_payload_rejected":true,"required_evidence_keys_present":true}'::jsonb,
   '{"scope_bypass":true,"generic_payload":true,"step_contract_missing":true,"required_evidence_missing":true,"invented_source_or_destination":true}'::jsonb,
   '{"pass":"STEP_CLEAN_PASS","return":"RETURN_TO_WORKER_FOR_SELF_REPAIR","blocked":"BLOCKED_GITHUB_WRITE_NOT_CLEAN"}'::jsonb,
   'ACTIVE_ENFORCEMENT',now(),now(),'MIG-20260901083200-CARD-BOUNDARY','MIG-20260901083200-CARD-BOUNDARY'),
  ('CREACION_CARD_LF','MINI_JUDGE_CREACION_CARD_LF_GITHUB_READBACK_V1',
   'supabase://public/lf_operation_step_contracts/CREACION_CARD_LF/github_readback',
   'CONTRACT_CREACION_CARD_LF_GITHUB_READBACK_V1',
   '{"pass_condition_met":true,"step_contract_present":true,"generic_payload_rejected":true,"required_evidence_keys_present":true}'::jsonb,
   '{"scope_bypass":true,"generic_payload":true,"step_contract_missing":true,"required_evidence_missing":true,"invented_source_or_destination":true}'::jsonb,
   '{"pass":"STEP_CLEAN_PASS","return":"RETURN_TO_WORKER_FOR_SELF_REPAIR","blocked":"BLOCKED_GITHUB_READBACK_NOT_CLEAN"}'::jsonb,
   'ACTIVE_ENFORCEMENT',now(),now(),'MIG-20260901083200-CARD-BOUNDARY','MIG-20260901083200-CARD-BOUNDARY')
  on conflict (operation_code,judge_code) do update set
    judge_path=excluded.judge_path,
    judge_sha=excluded.judge_sha,
    pass_if=excluded.pass_if,
    fail_if=excluded.fail_if,
    result_values=excluded.result_values,
    status=excluded.status,
    updated_at=now(),
    updated_by_execution_id=excluded.updated_by_execution_id;

  insert into public.lf_operation_step_judge_bindings(
    operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,
    return_result_value,required_evidence_keys,status,created_at,updated_at,
    created_by_execution_id,updated_by_execution_id
  )
  select c.operation_code,c.step_order,c.step_id,c.mini_judge_code,
         'STEP_CLEAN_PASS',c.blocking_code,'RETURN_TO_WORKER_FOR_SELF_REPAIR',
         c.required_evidence_keys,'ACTIVE_ENFORCEMENT',now(),now(),
         'MIG-20260901083200-CARD-BOUNDARY','MIG-20260901083200-CARD-BOUNDARY'
  from public.lf_operation_step_contracts c
  where c.operation_code='CREACION_CARD_LF'
    and c.step_id in ('github_write','github_readback')
  on conflict (operation_code,step_order,step_id) do update set
    judge_code=excluded.judge_code,
    clean_result_value=excluded.clean_result_value,
    blocked_result_value=excluded.blocked_result_value,
    return_result_value=excluded.return_result_value,
    required_evidence_keys=excluded.required_evidence_keys,
    status=excluded.status,
    updated_at=now(),
    updated_by_execution_id=excluded.updated_by_execution_id;
end;
$migration$;
