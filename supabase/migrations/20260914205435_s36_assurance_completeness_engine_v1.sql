-- S36 WP06 — dynamic assurance completeness engine.
-- Source-first migration. Reuses canonical LF test stores; creates no parallel matrix/store.

create or replace function public.lf_s36_operation_assurance_coverage_v1()
returns table(
  operation_code text,
  lifecycle_state_code text,
  assurance_obligation text,
  required_binding_count bigint,
  executable_suite_count bigint,
  active_case_count bigint,
  observed_run_count bigint,
  coverage_state text,
  coverage_reason text
)
language sql
stable
set search_path to 'pg_catalog','public'
as $function$
with operation_universe as (
  select r.operation_code, r.lifecycle_state_code,
         case when r.lifecycle_state_code='OP_OPERATIONAL' then 'REQUIRED'
              else 'DISCOVERED' end as assurance_obligation
  from public.lf_operation_registry r
  where r.lifecycle_state_code in ('OP_OPERATIONAL','OP_CANDIDATE')
), binding_rollup as (
  select u.operation_code,
         count(b.binding_code) filter (
           where b.status='ACTIVE'
             and b.required is true
             and b.effective_from <= clock_timestamp()
             and public.lf_test_requirement_applies_v1(b.binding_code,'OPERATION',u.operation_code)
         ) as required_binding_count,
         count(distinct b.suite_code) filter (
           where b.status='ACTIVE'
             and b.required is true
             and b.effective_from <= clock_timestamp()
             and public.lf_test_requirement_applies_v1(b.binding_code,'OPERATION',u.operation_code)
             and exists (
               select 1 from public.lf_test_suites s
               where s.suite_code=b.suite_code and s.status in ('CANDIDATO','ACTIVE')
             )
         ) as executable_suite_count
  from operation_universe u
  left join public.lf_test_requirement_bindings b
    on b.subject_type='OPERATION'
   and b.subject_code=u.operation_code
  group by u.operation_code
), case_rollup as (
  select u.operation_code,
         count(c.test_code) filter (where c.status='CANDIDATO') as active_case_count
  from operation_universe u
  left join public.lf_test_requirement_bindings b
    on b.subject_type='OPERATION'
   and b.subject_code=u.operation_code
   and b.status='ACTIVE'
   and b.required is true
   and b.effective_from <= clock_timestamp()
   and public.lf_test_requirement_applies_v1(b.binding_code,'OPERATION',u.operation_code)
  left join public.lf_test_suite_cases c on c.suite_code=b.suite_code
  group by u.operation_code
), run_rollup as (
  select u.operation_code, count(tr.test_run_id) as observed_run_count
  from operation_universe u
  left join public.lf_test_runs tr on tr.operation_code=u.operation_code
  group by u.operation_code
)
select u.operation_code,
       u.lifecycle_state_code,
       u.assurance_obligation,
       coalesce(b.required_binding_count,0),
       coalesce(b.executable_suite_count,0),
       coalesce(c.active_case_count,0),
       coalesce(rr.observed_run_count,0),
       case
         when u.assurance_obligation='DISCOVERED' and coalesce(b.required_binding_count,0)=0 then 'DISCOVERED'
         when coalesce(b.required_binding_count,0)=0 and coalesce(rr.observed_run_count,0)>0 then 'EVIDENCE_UNMAPPED'
         when coalesce(b.required_binding_count,0)=0 then 'NOT_COVERED'
         when coalesce(b.executable_suite_count,0) < coalesce(b.required_binding_count,0) then 'BLOCK'
         when coalesce(c.active_case_count,0)=0 then 'BLOCK'
         else 'COVERED'
       end as coverage_state,
       case
         when u.assurance_obligation='DISCOVERED' and coalesce(b.required_binding_count,0)=0 then 'CANDIDATE_VISIBLE_PENDING_ASSURANCE'
         when coalesce(b.required_binding_count,0)=0 and coalesce(rr.observed_run_count,0)>0 then 'RUN_EVIDENCE_EXISTS_WITHOUT_REQUIRED_BINDING'
         when coalesce(b.required_binding_count,0)=0 then 'REQUIRED_OPERATION_HAS_NO_ASSURANCE_BINDING'
         when coalesce(b.executable_suite_count,0) < coalesce(b.required_binding_count,0) then 'REQUIRED_BINDING_SUITE_NOT_EXECUTABLE'
         when coalesce(c.active_case_count,0)=0 then 'REQUIRED_BINDING_HAS_NO_ACTIVE_CASES'
         else 'REQUIRED_ASSURANCE_BINDING_PRESENT'
       end as coverage_reason
from operation_universe u
left join binding_rollup b using(operation_code)
left join case_rollup c using(operation_code)
left join run_rollup rr using(operation_code)
order by case when u.assurance_obligation='REQUIRED' then 0 else 1 end, u.operation_code;
$function$;

create or replace function public.lf_s36_assurance_completeness_v1(p_fail_on_gap boolean default false)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public'
as $function$
declare
  v_required int;
  v_covered int;
  v_not_covered int;
  v_unmapped int;
  v_blocked int;
  v_discovered int;
  v_result jsonb;
begin
  select
    count(*) filter (where assurance_obligation='REQUIRED'),
    count(*) filter (where assurance_obligation='REQUIRED' and coverage_state='COVERED'),
    count(*) filter (where assurance_obligation='REQUIRED' and coverage_state='NOT_COVERED'),
    count(*) filter (where assurance_obligation='REQUIRED' and coverage_state='EVIDENCE_UNMAPPED'),
    count(*) filter (where assurance_obligation='REQUIRED' and coverage_state='BLOCK'),
    count(*) filter (where assurance_obligation='DISCOVERED')
  into v_required,v_covered,v_not_covered,v_unmapped,v_blocked,v_discovered
  from public.lf_s36_operation_assurance_coverage_v1();

  v_result:=jsonb_build_object(
    'contract_version','S36_ASSURANCE_COMPLETENESS_V1',
    'matrix_policy','ONE_LF_TEST_MATRIX_ONLY',
    'operational_required',v_required,
    'covered',v_covered,
    'not_covered',v_not_covered,
    'evidence_unmapped',v_unmapped,
    'blocked',v_blocked,
    'candidate_discovered',v_discovered,
    'completeness_state',case when v_not_covered=0 and v_unmapped=0 and v_blocked=0 then 'PASS' else 'BLOCKED' end,
    'pass_rate_policy','PASS_RATE_NEVER_IMPLIES_COMPLETENESS',
    'source_stores',jsonb_build_array('lf_operation_registry','lf_test_requirement_bindings','lf_test_suites','lf_test_suite_cases','lf_test_runs')
  );

  if p_fail_on_gap and (v_not_covered>0 or v_unmapped>0 or v_blocked>0) then
    raise exception 'LF_S36_ASSURANCE_COMPLETENESS_BLOCKED:%',v_result::text;
  end if;
  return v_result;
end;
$function$;

comment on function public.lf_s36_operation_assurance_coverage_v1() is
'S36 WP06 dynamic operation assurance universe. Reuses canonical LF stores; no parallel matrix. Operational operations are required; candidate operations remain visible as DISCOVERED.';

comment on function public.lf_s36_assurance_completeness_v1(boolean) is
'S36 WP06 completeness gate. Required NOT_COVERED, EVIDENCE_UNMAPPED or BLOCK states fail closed when p_fail_on_gap=true; pass rate alone never implies completeness.';
