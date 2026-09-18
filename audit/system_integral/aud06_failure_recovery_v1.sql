-- AUD-6 Failure & Recovery v1
-- Read-only, freeze-bound to main dafe10a6a730d63bc59ce036360f214cd6fd8d96
with
ip as (
  select *, started_at >= timestamptz '2026-09-11 02:54:54+00' post_reliability
  from public.lf_operation_execution
  where status='IN_PROGRESS'
),
step_counts as (
  select execution_id,count(*) step_rows
  from public.lf_operation_execution_steps group by execution_id
),
required_steps as (
  select s.operation_code,s.step_id,s.step_order,coalesce(s.execution_order,s.step_order) ord,b.clean_result_value
  from public.lf_operation_steps s
  left join public.lf_operation_step_judge_bindings b
    on b.operation_code=s.operation_code and b.step_id=s.step_id and b.step_order=s.step_order
   and b.status='ACTIVE_ENFORCEMENT'
  where s.active=true and s.required=true
),
step_state as (
  select ip.execution_id,ip.operation_code,rs.step_id,rs.step_order,rs.ord,rs.clean_result_value,
         es.status observed_status,
         case when es.step_id is null then 'MISSING'
              when rs.clean_result_value is null then 'NO_ACTIVE_BINDING'
              when es.status is distinct from rs.clean_result_value then 'NOT_CLEAN'
              else 'CLEAN' end step_state
  from ip join required_steps rs using(operation_code)
  left join public.lf_operation_execution_steps es
    on es.execution_id=ip.execution_id and es.step_order=rs.step_order and es.step_id=rs.step_id
),
first_bad as (
  select distinct on (execution_id)
    execution_id,operation_code,step_id,step_order,ord,step_state,observed_status,clean_result_value
  from step_state where step_state<>'CLEAN'
  order by execution_id,ord,step_order
),
all_clean_open as (
  select ip.execution_id,ip.operation_code
  from ip left join first_bad using(execution_id)
  where first_bad.execution_id is null
),
op_shape as (
  select operation_code,
         count(*) filter(where active) active_steps,
         bool_or(active and step_id='report_output') has_report_output
  from public.lf_operation_steps group by operation_code
),
writers as (
  select s.execution_id,
         count(distinct coalesce(s.updated_by_execution_id,s.created_by_execution_id,'<NULL>')) effective_writers
  from public.lf_operation_execution_steps s join ip using(execution_id)
  group by s.execution_id
),
funcs as (
  select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity,
         pg_get_functiondef(p.oid) def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','private','programacion') and p.prokind='f'
),
reserve_callers as (
  select identity,def,
         def ilike '%fn_lf_operation_acquire_lease_v1%' has_acquire,
         def ilike '%fn_lf_operation_checkpoint_v1%' has_checkpoint,
         def ilike '%fn_lf_operation_release_lease_v1%' has_release
  from funcs
  where def ilike '%fn_lf_operation_reserve_execution_v1%'
),
reaper_jobs as (
  select jobid from cron.job
  where command ilike '%lf_operation_execution%'
     or command ilike '%lease%'
     or command ilike '%reaper%'
     or command ilike '%resume%'
),
effect as (
  select g.*,e.status execution_status
  from public.lf_operation_effect_guard g
  left join public.lf_operation_execution e using(execution_id)
),
rollback_functions as (
  select identity from funcs where lower(identity) like '%rollback%'
),
rollback_latest as (
  select distinct on (r.suite_code,r.test_code) r.*
  from public.lf_test_runs r
  join public.lf_test_suite_cases c using(suite_code,test_code)
  where c.test_type='ROLLBACK_CANARY'
  order by r.suite_code,r.test_code,coalesce(r.completed_at,r.started_at,r.created_at) desc
)
select jsonb_build_object(
 'freeze',jsonb_build_object('main_sha','dafe10a6a730d63bc59ce036360f214cd6fd8d96','schema_fp','56c2af889d3f6a4781b1ac74ba7da5bb'),
 'first_bad_hop',jsonb_build_object(
   'in_progress',(select count(*) from ip),
   'resolved',(select count(*) from first_bad),
   'missing',(select count(*) from first_bad where step_state='MISSING'),
   'not_clean',(select count(*) from first_bad where step_state='NOT_CLEAN'),
   'no_active_binding',(select count(*) from first_bad where step_state='NO_ACTIVE_BINDING'),
   'all_required_clean_but_open',(select count(*) from all_clean_open),
   'never_started_steps',(select count(*) from ip left join step_counts using(execution_id) where coalesce(step_rows,0)=0)
 ),
 'checkpoint_resume',jsonb_build_object(
   'checkpoint_zero',(select count(*) from ip where checkpoint_seq=0),
   'checkpoint_positive',(select count(*) from ip where checkpoint_seq>0),
   'inprogress_handoff_marker',(select count(*) from ip where lower(manifest::text) like '%handoff%' or lower(checkpoint_payload::text) like '%handoff%'),
   'inprogress_resume_marker',(select count(*) from ip where lower(manifest::text) like '%resume%' or lower(checkpoint_payload::text) like '%resume%'),
   'cron_reaper_resume_jobs',(select count(*) from reaper_jobs)
 ),
 'idempotency_retry',jsonb_build_object(
   'post_reliability_in_progress',(select count(*) from ip where post_reliability),
   'post_idempotency_present',(select count(*) from ip where post_reliability and nullif(btrim(idempotency_key),'') is not null),
   'post_request_sha_present',(select count(*) from ip where post_reliability and request_sha256 ~ '^[0-9a-f]{64}$'),
   'reserve_callers',(select count(*) from reserve_callers),
   'reserve_callers_with_acquire',(select count(*) from reserve_callers where has_acquire),
   'reserve_callers_with_checkpoint',(select count(*) from reserve_callers where has_checkpoint),
   'reserve_callers_with_release',(select count(*) from reserve_callers where has_release),
   'reserve_callers_full_chain',(select count(*) from reserve_callers where has_acquire and has_checkpoint and has_release)
 ),
 'concurrency_multiwriter',jsonb_build_object(
   'post_never_lease',(select count(*) from ip where post_reliability and lease_fence=0),
   'post_lease_used',(select count(*) from ip where post_reliability and lease_fence>0),
   'stepful_without_lease_ever',(select count(*) from writers w join ip using(execution_id) where ip.lease_fence=0),
   'post_stepful_without_lease',(select count(*) from writers w join ip using(execution_id) where ip.post_reliability and ip.lease_fence=0),
   'multiple_step_writers',(select count(*) from writers where effective_writers>1),
   'core_recorder_checks_lease',position('lease_fence' in lower((select def from funcs where identity like 'public.lf_record_operation_step_core_v1(%' limit 1)))>0
 ),
 'closure_blocker',jsonb_build_object(
   'registered_operations',(select count(*) from public.lf_operation_registry),
   'operations_with_report_output',(select count(*) from op_shape where has_report_output),
   'operations_without_report_output',(select count(*) from op_shape where not has_report_output),
   'inprogress_on_ops_without_report_output',(select count(*) from ip join op_shape using(operation_code) where not has_report_output),
   'all_required_clean_but_open',(select count(*) from all_clean_open)
 ),
 'handoff_context',jsonb_build_object(
   'inprogress_with_checkpoint',(select count(*) from ip where checkpoint_seq>0),
   'inprogress_without_checkpoint',(select count(*) from ip where checkpoint_seq=0),
   'all_execution_manifest_handoff_mentions',(select count(*) from public.lf_operation_execution where lower(manifest::text) like '%handoff%'),
   'all_execution_checkpoint_handoff_mentions',(select count(*) from public.lf_operation_execution where lower(checkpoint_payload::text) like '%handoff%')
 ),
 'rollback_effects',jsonb_build_object(
   'effect_guard_rows',(select count(*) from effect),
   'effect_reserved_unresolved',(select count(*) from effect where state='RESERVED' and resolved_at is null),
   'effect_rows_on_inprogress',(select count(*) from effect where execution_status='IN_PROGRESS'),
   'rollback_named_functions',(select count(*) from rollback_functions),
   'rollback_test_cases',(select count(*) from public.lf_test_suite_cases where test_type='ROLLBACK_CANARY'),
   'rollback_latest_runs',(select count(*) from rollback_latest),
   'rollback_latest_pass',(select count(*) from rollback_latest where status in ('PASS','PASSED'))
 )
) aud06_failure_recovery;
