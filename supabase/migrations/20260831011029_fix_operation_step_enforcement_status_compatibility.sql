create or replace view public.v_lf_operation_step_contracts
with (security_invoker = true)
as
select
  operation_code,
  step_id,
  step_order,
  execution_order,
  contract_code,
  purpose,
  input_required,
  resolver_ref,
  output_payload,
  pass_condition,
  block_condition,
  blocking_code,
  mini_judge_code,
  required_evidence_keys,
  next_if_pass,
  next_if_blocked,
  status,
  notes,
  created_at,
  updated_at
from public.lf_operation_step_contracts
where status = any (array['ACTIVE'::text, 'ACTIVO'::text, 'ACTIVE_ENFORCEMENT'::text]);

create or replace view public.v_lf_operation_step_contract_judge_coverage
with (security_invoker = true)
as
select
  s.operation_code,
  s.execution_order,
  s.step_order,
  s.step_id,
  s.required,
  s.evidence_required,
  c.contract_code,
  c.purpose,
  c.resolver_ref,
  c.blocking_code,
  c.mini_judge_code,
  count(b.judge_code) filter (where b.status = any (array['ACTIVE'::text, 'ACTIVE_ENFORCEMENT'::text])) as active_judge_bindings,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'judge_code', b.judge_code,
        'clean_result_value', b.clean_result_value,
        'blocked_result_value', b.blocked_result_value,
        'required_evidence_keys', b.required_evidence_keys,
        'status', b.status
      ) order by b.judge_code
    ) filter (where b.judge_code is not null and b.status = any (array['ACTIVE'::text, 'ACTIVE_ENFORCEMENT'::text])),
    '[]'::jsonb
  ) as judges
from public.v_lf_operation_steps s
left join public.v_lf_operation_step_contracts c
  on c.operation_code = s.operation_code
 and c.step_id = s.step_id
left join public.lf_operation_step_judge_bindings b
  on b.operation_code = s.operation_code
 and b.step_order = s.step_order
 and b.step_id = s.step_id
 and b.status = any (array['ACTIVE'::text, 'ACTIVE_ENFORCEMENT'::text])
where s.active = true
group by
  s.operation_code,
  s.execution_order,
  s.step_order,
  s.step_id,
  s.required,
  s.evidence_required,
  c.contract_code,
  c.purpose,
  c.resolver_ref,
  c.blocking_code,
  c.mini_judge_code;