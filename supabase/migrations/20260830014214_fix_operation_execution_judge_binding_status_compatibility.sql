create or replace view public.v_lf_operation_execution_checklist as
select
  e.execution_id,
  e.operation_code,
  e.target_type,
  e.target_code,
  e.target_repo,
  e.target_path,
  s.step_order,
  s.step_id,
  s.required,
  s.evidence_required,
  coalesce(es.status, 'MISSING'::text) as execution_step_status,
  es.evidence_ref,
  es.evidence_payload,
  case
    when s.required = true and es.status is null then 'FAIL_MISSING_REQUIRED_STEP'::text
    when s.required = true and not (
      es.status = any (array['PASS'::text, 'NO_APLICA_CON_MOTIVO'::text])
      or (b.status = 'ACTIVE_ENFORCEMENT' and es.status = b.clean_result_value)
    ) then 'FAIL_STEP_NOT_PASS'::text
    when s.required = false and es.status is null then 'OPTIONAL_NOT_RECORDED'::text
    else 'OK'::text
  end as checklist_result
from public.lf_operation_execution e
join public.lf_operation_steps s
  on s.operation_code = e.operation_code
 and s.active = true
left join public.lf_operation_execution_steps es
  on es.execution_id = e.execution_id
 and es.step_order = s.step_order
 and es.step_id = s.step_id
left join public.lf_operation_step_judge_bindings b
  on b.operation_code = e.operation_code
 and b.step_order = s.step_order
 and b.step_id = s.step_id
 and b.status = 'ACTIVE_ENFORCEMENT';

create or replace view public.v_lf_operation_execution_judge as
select
  c.execution_id,
  c.operation_code,
  c.target_type,
  c.target_code,
  count(*) filter (where c.required = true) as required_steps,
  count(*) filter (where c.required = true and c.checklist_result = 'OK') as required_steps_pass,
  count(*) filter (where c.checklist_result like 'FAIL%') as fail_count,
  count(*) filter (
    where c.execution_step_status = 'BLOCKED'
       or (b.blocked_result_value is not null and c.execution_step_status = b.blocked_result_value)
  ) as blocked_count,
  case
    when count(*) filter (
      where c.execution_step_status = 'BLOCKED'
         or (b.blocked_result_value is not null and c.execution_step_status = b.blocked_result_value)
    ) > 0 then 'BLOCKED'::text
    when count(*) filter (where c.checklist_result like 'FAIL%') > 0 then 'FAIL'::text
    else 'PASS'::text
  end as judge_result
from public.v_lf_operation_execution_checklist c
left join public.lf_operation_step_judge_bindings b
  on b.operation_code = c.operation_code
 and b.step_order = c.step_order
 and b.step_id = c.step_id
 and b.status = 'ACTIVE_ENFORCEMENT'
group by c.execution_id, c.operation_code, c.target_type, c.target_code;