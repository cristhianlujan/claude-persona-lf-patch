-- Source-first reconciliation for CREACION_CARD_LF boundary.
-- Aligns deployed step contracts with the already-canonical Git/runtime order.
-- Exact github_write/github_readback mini-judges remain a separate governed blocker:
-- this migration deliberately does NOT fabricate judge authority or provenance.
-- No runtime/production/automatic impact.

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
    where operation_code='CREACION_CARD_LF' and step_id='pre_write_execution_binding_gate'
      and contract_code='CONTRACT_CREACION_CARD_LF_PRE_WRITE_EXECUTION_BINDING_GATE_V1'
      and mini_judge_code='MINI_JUDGE_CREACION_CARD_LF_PRE_WRITE_EXECUTION_BINDING_GATE_V1'
      and blocking_code='BLOCKED_PRE_WRITE_EXECUTION_BINDING_GATE_NOT_CLEAN'
  ) then raise exception 'CARD_PREWRITE_CONTRACT_BASELINE_MISMATCH'; end if;

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

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='CREACION_CARD_LF' and step_id='evidence_log'
      and contract_code='CONTRACT_CREACION_CARD_LF_EVIDENCE_LOG_V1'
      and mini_judge_code='MINI_JUDGE_CREACION_CARD_LF_EVIDENCE_LOG_V1'
      and blocking_code='BLOCKED_EVIDENCE_LOG_NOT_CLEAN'
  ) then raise exception 'CARD_EVIDENCE_LOG_CONTRACT_BASELINE_MISMATCH'; end if;

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

  if exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='CREACION_CARD_LF'
      and step_id in ('pre_write_execution_binding_gate','github_write','github_readback','evidence_log')
      and (step_order,step_id) not in (
        (24,'pre_write_execution_binding_gate'),
        (25,'github_write'),
        (26,'github_readback'),
        (27,'evidence_log')
      )
  ) then raise exception 'CARD_CONTRACT_BOUNDARY_ORDER_RECONCILIATION_FAILED'; end if;
end;
$migration$;
