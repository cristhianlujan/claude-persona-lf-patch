-- AUD-5 Test & Assurance runner v1
-- Read-only, freeze-bound: main dafe10a6a730d63bc59ce036360f214cd6fd8d96
-- Measures traceability and evidence; absence of a binding is not equated to absence of source-level tests.
with
claims as (
 select * from public.lf_assurance_claim_catalog
),
obligations as (
 select *,
   nullif(btrim(coalesce(positive_test_ref,'')),'') is not null has_positive_ref,
   nullif(btrim(coalesce(negative_test_ref,'')),'') is not null has_negative_ref,
   nullif(btrim(coalesce(adversarial_test_ref,'')),'') is not null has_adversarial_ref
 from public.lf_assurance_obligation_catalog
),
claim_cov as (
 select c.claim_code,c.version,count(o.obligation_code) obligation_count
 from claims c left join obligations o on o.claim_code=c.claim_code and o.claim_version=c.version
 group by c.claim_code,c.version
),
claim_eval as (
 select c.claim_code,c.version,count(e.evaluation_id) eval_count,
        count(*) filter(where e.result in ('PASS','PASSED','PASS_CLOSED')) pass_count
 from claims c left join public.lf_assurance_evaluations e
   on e.claim_code=c.claim_code and e.claim_version=c.version
 group by c.claim_code,c.version
),
obl_eval as (
 select o.obligation_code,o.claim_code,o.claim_version,o.required,
        count(e.evaluation_id) eval_count,
        count(*) filter(where e.result in ('PASS','PASSED','PASS_CLOSED')) pass_count
 from obligations o left join public.lf_assurance_evaluations e
   on e.claim_code=o.claim_code and e.claim_version=o.claim_version and e.obligation_code=o.obligation_code
 group by o.obligation_code,o.claim_code,o.claim_version,o.required
),
cases as (
 select c.*,
   (c.expected_output is not null and c.expected_output<>'{}'::jsonb) has_expected,
   (c.prohibited_output is not null and c.prohibited_output<>'{}'::jsonb) has_prohibited,
   (c.preconditions is not null and c.preconditions<>'[]'::jsonb and c.preconditions<>'{}'::jsonb) has_preconditions
 from public.lf_test_suite_cases c
),
runs as (
 select r.*,
   case when r.commit_sha is null or btrim(r.commit_sha)='' then 'MISSING'
        when r.commit_sha ~ '^[0-9a-f]{40}$' then 'SHA40'
        else 'INVALID' end sha_state
 from public.lf_test_runs r
),
latest as (
 select distinct on (suite_code,test_code) *
 from runs
 order by suite_code,test_code,coalesce(completed_at,started_at,created_at) desc
),
case_currentness as (
 select c.suite_code,c.test_code,c.test_type,c.has_expected,c.has_prohibited,c.has_preconditions,
        l.test_run_id,l.status run_status,l.commit_sha,l.sha_state
 from cases c left join latest l using(suite_code,test_code)
),
active_contracts as (
 select * from public.lf_operation_step_contracts
 where status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO','COMPLETE')
),
transitions as (
 select operation_code,step_id,'PASS' branch,nullif(btrim(next_if_pass),'') target from active_contracts
 union all
 select operation_code,step_id,'BLOCKED' branch,nullif(btrim(next_if_blocked),'') target from active_contracts
),
transition_class as (
 select t.*,
   exists(select 1 from active_contracts a where a.operation_code=t.operation_code and a.step_id=t.target) exact_step_target,
   coalesce(t.target,'') ~ '^(NEXT_|RETURN_|STOP|BLOCK|FAILED_|HITL_|READBACK_|RETRY|CLOSE|REPORT|END)' pseudo_target
 from transitions t where t.target is not null
),
gpt_runtime as (
 select *,
   (execution_sql is not null and btrim(execution_sql)<>'') has_execution_sql,
   (input_required is not null and input_required<>'{}'::jsonb and input_required<>'[]'::jsonb) has_input_contract,
   (output_payload is not null and output_payload<>'{}'::jsonb and output_payload<>'[]'::jsonb) has_output_contract,
   (required_evidence_keys is not null and required_evidence_keys<>'{}'::jsonb and required_evidence_keys<>'[]'::jsonb) has_evidence_contract,
   (pass_condition is not null and pass_condition<>'{}'::jsonb and pass_condition<>'[]'::jsonb) has_pass_condition,
   (block_condition is not null and block_condition<>'{}'::jsonb and block_condition<>'[]'::jsonb) has_block_condition
 from active_contracts
 where resolver_ref like 'GPT_RUNTIME%'
),
gpt_behavior as (
 select *,
 case
  when has_execution_sql then 'DETERMINISTIC_EXECUTOR_PRESENT'
  when has_input_contract and has_output_contract and has_evidence_contract and has_pass_condition then 'CONTRACT_BOUND_NO_DETERMINISTIC_EXECUTOR'
  else 'PARTIAL_BEHAVIOR_CONTRACT_NO_EXECUTOR'
 end behavior_class
 from gpt_runtime
),
op_bindings as (
 select distinct subject_code operation_code
 from public.lf_test_requirement_bindings
 where status='ACTIVE' and subject_type='OPERATION' and required
),
ops as (select operation_code,status from public.lf_operation_registry),
gate_currentness as (
 select * from public.lf_operation_gate_check_results
)
select jsonb_build_object(
 'freeze',jsonb_build_object('main_sha','dafe10a6a730d63bc59ce036360f214cd6fd8d96','schema_fp','56c2af889d3f6a4781b1ac74ba7da5bb'),
 'claim_universe',jsonb_build_object(
   'claims_total',(select count(*) from claims),
   'claims_without_obligation',(select count(*) from claim_cov where obligation_count=0),
   'obligations_total',(select count(*) from obligations),
   'required_obligations',(select count(*) from obligations where required),
   'required_missing_positive_ref',(select count(*) from obligations where required and not has_positive_ref),
   'required_missing_negative_ref',(select count(*) from obligations where required and not has_negative_ref),
   'required_missing_adversarial_ref',(select count(*) from obligations where required and not has_adversarial_ref),
   'subject_bindings',(select count(*) from public.lf_assurance_subject_bindings),
   'claims_with_evaluation',(select count(*) from claim_eval where eval_count>0),
   'claims_without_evaluation',(select count(*) from claim_eval where eval_count=0),
   'claims_with_pass',(select count(*) from claim_eval where pass_count>0),
   'required_obligations_with_evaluation',(select count(*) from obl_eval where required and eval_count>0),
   'required_obligations_without_evaluation',(select count(*) from obl_eval where required and eval_count=0),
   'required_obligations_with_pass',(select count(*) from obl_eval where required and pass_count>0)
 ),
 'preconditions_predecessors',jsonb_build_object(
   'test_cases_total',(select count(*) from cases),
   'test_cases_with_preconditions',(select count(*) from cases where has_preconditions),
   'test_cases_without_preconditions',(select count(*) from cases where not has_preconditions),
   'active_step_contracts',(select count(*) from active_contracts),
   'transition_edges',(select count(*) from transition_class),
   'exact_step_edges',(select count(*) from transition_class where exact_step_target),
   'pseudo_token_edges',(select count(*) from transition_class where not exact_step_target and pseudo_target),
   'unresolved_nonpseudo_edges',(select count(*) from transition_class where not exact_step_target and not pseudo_target)
 ),
 'test_traceability',jsonb_build_object(
   'test_runs_total',(select count(*) from runs),
   'runs_with_nonempty_contract_codes',(select count(*) from runs where contract_codes is not null and cardinality(contract_codes)>0),
   'operations_total',(select count(*) from ops),
   'operations_with_required_test_binding',(select count(*) from ops join op_bindings using(operation_code)),
   'operations_without_required_test_binding',(select count(*) from ops left join op_bindings using(operation_code) where op_bindings.operation_code is null),
   'active_required_test_bindings',(select count(*) from public.lf_test_requirement_bindings where status='ACTIVE' and required),
   'active_required_exact_revision_bindings',(select count(*) from public.lf_test_requirement_bindings where status='ACTIVE' and required and currentness_mode='EXACT_REVISION')
 ),
 'positive_negative_adversarial',jsonb_build_object(
   'case_types',coalesce((select jsonb_object_agg(coalesce(test_type,'NULL'),n) from (select test_type,count(*) n from cases group by test_type)x),'{}'::jsonb),
   'negative_adversarial_cases',(select count(*) from case_currentness where test_type in ('ADVERSARIAL','NEGATIVE_CANARY','MUTATION','STRESS','ROLLBACK_CANARY')),
   'negative_adversarial_without_latest_run',(select count(*) from case_currentness where test_type in ('ADVERSARIAL','NEGATIVE_CANARY','MUTATION','STRESS','ROLLBACK_CANARY') and test_run_id is null),
   'cases_with_expected_oracle',(select count(*) from cases where has_expected),
   'cases_with_prohibited_oracle',(select count(*) from cases where has_prohibited),
   'weak_oracle_candidates',(select count(*) from cases where not has_expected and not has_prohibited)
 ),
 'evidence_currentness',jsonb_build_object(
   'cases_without_latest_run',(select count(*) from case_currentness where test_run_id is null),
   'latest_with_sha40',(select count(*) from case_currentness where sha_state='SHA40'),
   'latest_missing_sha',(select count(*) from case_currentness where test_run_id is not null and sha_state='MISSING'),
   'latest_invalid_sha',(select count(*) from case_currentness where sha_state='INVALID'),
   'latest_exact_freeze',(select count(*) from case_currentness where commit_sha='dafe10a6a730d63bc59ce036360f214cd6fd8d96'),
   'negative_adversarial_latest_exact_freeze',(select count(*) from case_currentness where test_type in ('ADVERSARIAL','NEGATIVE_CANARY','MUTATION','STRESS','ROLLBACK_CANARY') and commit_sha='dafe10a6a730d63bc59ce036360f214cd6fd8d96'),
   'gate_results_total',(select count(*) from gate_currentness),
   'gate_results_with_sha40',(select count(*) from gate_currentness where source_commit ~ '^[0-9a-f]{40}$'),
   'gate_results_exact_freeze',(select count(*) from gate_currentness where source_commit='dafe10a6a730d63bc59ce036360f214cd6fd8d96')
 ),
 'gpt_runtime_behavior',jsonb_build_object(
   'population',(select count(*) from gpt_behavior),
   'deterministic_executor_present',(select count(*) from gpt_behavior where behavior_class='DETERMINISTIC_EXECUTOR_PRESENT'),
   'contract_bound_no_deterministic_executor',(select count(*) from gpt_behavior where behavior_class='CONTRACT_BOUND_NO_DETERMINISTIC_EXECUTOR'),
   'partial_behavior_contract_no_executor',(select count(*) from gpt_behavior where behavior_class='PARTIAL_BEHAVIOR_CONTRACT_NO_EXECUTOR'),
   'with_input_contract',(select count(*) from gpt_behavior where has_input_contract),
   'with_output_contract',(select count(*) from gpt_behavior where has_output_contract),
   'with_required_evidence',(select count(*) from gpt_behavior where has_evidence_contract)
 )
) as aud05_test_assurance;
