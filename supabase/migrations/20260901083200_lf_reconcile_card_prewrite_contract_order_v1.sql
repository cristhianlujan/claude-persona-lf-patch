-- Source-first reconciliation for CREACION_CARD_LF boundary.
-- Aligns deployed operation steps + step contracts with the already-canonical Git order.
-- Exact github_write/github_readback mini-judges remain a separate governed blocker:
-- this migration deliberately does NOT fabricate judge authority.
-- No runtime enablement, production promotion, automatic impact, or retroactive receipt.

-- Governed execution provenance is created first, with the required active policy snapshot
-- captured before any later execution status transition.
insert into public.lf_operation_execution (
  execution_id,
  operation_code,
  target_type,
  target_code,
  target_repo,
  target_path,
  status,
  manifest
) values (
  'GOV-CARD-PREWRITE-RECONCILE-20260901',
  'CREACION_CARD_LF',
  'GOVERNANCE_METADATA_RECONCILIATION',
  'CREACION_CARD_LF',
  'cristhianlujan/claude-persona-lf-patch',
  'supabase/migrations/20260901083200_lf_reconcile_card_prewrite_contract_order_v1.sql',
  'IN_PROGRESS',
  jsonb_build_object(
    'issue', 352,
    'source_first', true,
    'source_main_sha', 'b6b7067e2fdbec9239556711dab2c96ef1a821e4',
    'canonical_procedure_path', 'gobernanza/procedimientos/creacion_card_lf_steps_validation.yaml',
    'canonical_procedure_blob_sha', '29e147df8640831f205df8ee69c84da9649ba5ff',
    'scope', 'SANDBOX_GOVERNANCE_METADATA_ONLY',
    'no_production', true,
    'no_runtime_enablement', true,
    'no_retroactive_receipt', true,
    'operation_policy_snapshots', jsonb_build_array(
      jsonb_build_object(
        'policy_role', 'OPERATION_LIFECYCLE',
        'policy_code', 'POL-LF-OPERATION-LIFECYCLE',
        'policy_version', 'v1.0',
        'policy_sha', '973b5a0ad26433095066ff06b53c3043f38fef51d04e9482c458e178f20920e8',
        'effective_at', '2026-08-29T20:48:43.667538+00:00'
      )
    )
  )
);

do $migration$
declare
  v_bad integer;
  v_missing_judge_bindings integer;
begin
  -- Fail closed if current runtime step identity/order has drifted from the canonical source.
  select count(*) into v_bad
  from public.lf_operation_steps
  where operation_code='CREACION_CARD_LF'
    and step_id in (
      'partial_scope_guard',
      'pre_write_execution_binding_gate',
      'github_write',
      'github_readback',
      'evidence_log'
    )
    and (step_id,step_order) not in (
      ('partial_scope_guard',23),
      ('pre_write_execution_binding_gate',24),
      ('github_write',25),
      ('github_readback',26),
      ('evidence_log',27)
    );
  if v_bad<>0 then
    raise exception 'CARD_RUNTIME_BOUNDARY_ORDER_NOT_CANONICAL';
  end if;

  if (
    select count(*) from public.lf_operation_steps
    where operation_code='CREACION_CARD_LF'
      and step_id in (
        'partial_scope_guard',
        'pre_write_execution_binding_gate',
        'github_write',
        'github_readback',
        'evidence_log'
      )
  ) <> 5 then
    raise exception 'CARD_RUNTIME_BOUNDARY_STEP_SET_INCOMPLETE';
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

  if not exists (
    select 1 from public.lf_operation_step_contracts
    where operation_code='CREACION_CARD_LF' and step_id='partial_scope_guard'
      and contract_code='CONTRACT_CREACION_CARD_LF_PARTIAL_SCOPE_GUARD_V1'
      and mini_judge_code='MINI_JUDGE_CREACION_CARD_LF_PARTIAL_SCOPE_GUARD_V1'
      and blocking_code='BLOCKED_PARTIAL_SCOPE_GUARD_NOT_CLEAN'
  ) then raise exception 'CARD_PARTIAL_SCOPE_GUARD_CONTRACT_BASELINE_MISMATCH'; end if;

  -- Preserve fail-closed separation: missing exact write/readback judge bindings are observed,
  -- not fabricated by this migration.
  select count(*) into v_missing_judge_bindings
  from (values
    ('github_write','MINI_JUDGE_CREACION_CARD_LF_GITHUB_WRITE_V1'),
    ('github_readback','MINI_JUDGE_CREACION_CARD_LF_GITHUB_READBACK_V1')
  ) as expected(step_id,judge_code)
  where not exists (
    select 1
    from public.lf_operation_step_judge_bindings b
    where b.operation_code='CREACION_CARD_LF'
      and b.step_id=expected.step_id
      and b.judge_code=expected.judge_code
  );

  update public.lf_operation_steps
  set execution_order = case step_id
      when 'partial_scope_guard' then 23
      when 'pre_write_execution_binding_gate' then 24
      when 'github_write' then 25
      when 'github_readback' then 26
      when 'evidence_log' then 27
    end,
    source_path = 'gobernanza/procedimientos/creacion_card_lf_steps_validation.yaml',
    source_sha = '29e147df8640831f205df8ee69c84da9649ba5ff',
    updated_by_execution_id = 'GOV-CARD-PREWRITE-RECONCILE-20260901',
    updated_at = now()
  where operation_code='CREACION_CARD_LF'
    and step_id in (
      'partial_scope_guard',
      'pre_write_execution_binding_gate',
      'github_write',
      'github_readback',
      'evidence_log'
    );

  update public.lf_operation_step_contracts
  set step_order = case step_id
      when 'partial_scope_guard' then 23
      when 'pre_write_execution_binding_gate' then 24
      when 'github_write' then 25
      when 'github_readback' then 26
      when 'evidence_log' then 27
    end,
    execution_order = case step_id
      when 'partial_scope_guard' then 23
      when 'pre_write_execution_binding_gate' then 24
      when 'github_write' then 25
      when 'github_readback' then 26
      when 'evidence_log' then 27
    end,
    updated_by_execution_id = 'GOV-CARD-PREWRITE-RECONCILE-20260901',
    updated_at=now()
  where operation_code='CREACION_CARD_LF'
    and step_id in (
      'partial_scope_guard',
      'pre_write_execution_binding_gate',
      'github_write',
      'github_readback',
      'evidence_log'
    );

  select count(*) into v_bad
  from public.lf_operation_steps s
  join public.lf_operation_step_contracts c
    on c.operation_code=s.operation_code and c.step_id=s.step_id
  where s.operation_code='CREACION_CARD_LF'
    and s.step_id in (
      'partial_scope_guard',
      'pre_write_execution_binding_gate',
      'github_write',
      'github_readback',
      'evidence_log'
    )
    and (
      s.step_order is distinct from s.execution_order
      or s.step_order is distinct from c.step_order
      or s.execution_order is distinct from c.execution_order
      or s.source_path is distinct from 'gobernanza/procedimientos/creacion_card_lf_steps_validation.yaml'
      or s.source_sha is distinct from '29e147df8640831f205df8ee69c84da9649ba5ff'
      or s.updated_by_execution_id is distinct from 'GOV-CARD-PREWRITE-RECONCILE-20260901'
      or c.updated_by_execution_id is distinct from 'GOV-CARD-PREWRITE-RECONCILE-20260901'
    );
  if v_bad<>0 then
    raise exception 'CARD_PREWRITE_RUNTIME_CONTRACT_RECONCILIATION_FAILED';
  end if;

  if not exists (
    select 1 from public.lf_operation_steps p
    join public.lf_operation_steps w on w.operation_code=p.operation_code
    where p.operation_code='CREACION_CARD_LF'
      and p.step_id='pre_write_execution_binding_gate'
      and w.step_id='github_write'
      and p.execution_order < w.execution_order
  ) then
    raise exception 'CARD_PREWRITE_TEMPORAL_GUARD_FAILED';
  end if;

  update public.lf_operation_execution
  set manifest = manifest || jsonb_build_object(
        'reconciled_step_count', 5,
        'missing_exact_write_readback_judge_bindings', v_missing_judge_bindings,
        'judge_binding_scope', 'OBSERVED_ONLY_NO_FABRICATION'
      ),
      updated_by_execution_id='GOV-CARD-PREWRITE-RECONCILE-20260901',
      updated_at=now()
  where execution_id='GOV-CARD-PREWRITE-RECONCILE-20260901'
    and status='IN_PROGRESS';
end;
$migration$;

-- Status transition happens only after the immutable policy snapshot was captured in manifest.
update public.lf_operation_execution
set status='COMPLETED',
    completed_at=now(),
    updated_by_execution_id='GOV-CARD-PREWRITE-RECONCILE-20260901',
    updated_at=now()
where execution_id='GOV-CARD-PREWRITE-RECONCILE-20260901'
  and status='IN_PROGRESS';
