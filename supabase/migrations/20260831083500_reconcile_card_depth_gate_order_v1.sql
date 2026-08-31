begin;

create temp table _tmp_card_step_judge_bindings on commit drop as
select *
from public.lf_operation_step_judge_bindings
where operation_code = 'CREACION_CARD_LF'
  and step_order between 28 and 39;

delete from public.lf_operation_step_judge_bindings
where operation_code = 'CREACION_CARD_LF'
  and step_order between 28 and 39;

update public.lf_operation_steps
set step_order = -step_order,
    updated_at = now(),
    updated_by_execution_id = 'MIG-20260831083500-CARD-DEPTH-ORDER'
where operation_code = 'CREACION_CARD_LF'
  and step_order between 28 and 39;

update public.lf_operation_steps
set step_order = case step_id
    when 'step_depth_validation' then 28
    when 'pack_internal_depth_validation' then 29
    when 'examples_depth_validation' then 30
    when 'evals_depth_validation' then 31
    when 'judge_depth_validation' then 32
    when 'schema_depth_validation' then 33
    when 'output_modes_validation' then 34
    when 'blocking_overrides_validation' then 35
    when 'card_examples_depth_judge' then 36
    when 'contract_judge' then 37
    when 'close' then 38
    when 'report_output' then 39
  end,
  execution_order = case step_id
    when 'step_depth_validation' then 28
    when 'pack_internal_depth_validation' then 29
    when 'examples_depth_validation' then 30
    when 'evals_depth_validation' then 31
    when 'judge_depth_validation' then 32
    when 'schema_depth_validation' then 33
    when 'output_modes_validation' then 34
    when 'blocking_overrides_validation' then 35
    when 'card_examples_depth_judge' then 36
    when 'contract_judge' then 37
    when 'close' then 38
    when 'report_output' then 39
  end,
  source_path = 'gobernanza/procedimientos/creacion_card_lf_steps_validation.yaml',
  source_sha = '29e147df8640831f205df8ee69c84da9649ba5ff',
  updated_at = now(),
  updated_by_execution_id = 'MIG-20260831083500-CARD-DEPTH-ORDER'
where operation_code = 'CREACION_CARD_LF'
  and step_order between -39 and -28;

update public.lf_operation_step_contracts
set step_order = case step_id
    when 'step_depth_validation' then 28
    when 'pack_internal_depth_validation' then 29
    when 'examples_depth_validation' then 30
    when 'evals_depth_validation' then 31
    when 'judge_depth_validation' then 32
    when 'schema_depth_validation' then 33
    when 'output_modes_validation' then 34
    when 'blocking_overrides_validation' then 35
    when 'card_examples_depth_judge' then 36
    when 'contract_judge' then 37
    when 'close' then 38
    when 'report_output' then 39
  end,
  execution_order = case step_id
    when 'step_depth_validation' then 28
    when 'pack_internal_depth_validation' then 29
    when 'examples_depth_validation' then 30
    when 'evals_depth_validation' then 31
    when 'judge_depth_validation' then 32
    when 'schema_depth_validation' then 33
    when 'output_modes_validation' then 34
    when 'blocking_overrides_validation' then 35
    when 'card_examples_depth_judge' then 36
    when 'contract_judge' then 37
    when 'close' then 38
    when 'report_output' then 39
  end,
  updated_at = now(),
  updated_by_execution_id = 'MIG-20260831083500-CARD-DEPTH-ORDER'
where operation_code = 'CREACION_CARD_LF'
  and step_id in (
    'step_depth_validation','pack_internal_depth_validation','examples_depth_validation',
    'evals_depth_validation','judge_depth_validation','schema_depth_validation',
    'output_modes_validation','blocking_overrides_validation','card_examples_depth_judge',
    'contract_judge','close','report_output'
  );

insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,clean_result_value,
  blocked_result_value,return_result_value,required_evidence_keys,status,
  created_at,updated_at,created_by_execution_id,updated_by_execution_id
)
select operation_code,
  case step_id
    when 'step_depth_validation' then 28
    when 'pack_internal_depth_validation' then 29
    when 'examples_depth_validation' then 30
    when 'evals_depth_validation' then 31
    when 'judge_depth_validation' then 32
    when 'schema_depth_validation' then 33
    when 'output_modes_validation' then 34
    when 'blocking_overrides_validation' then 35
    when 'card_examples_depth_judge' then 36
    when 'contract_judge' then 37
    when 'close' then 38
    when 'report_output' then 39
  end,
  step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_at,now(),created_by_execution_id,
  'MIG-20260831083500-CARD-DEPTH-ORDER'
from _tmp_card_step_judge_bindings;

update public.lf_operation_judges
set pass_if = '["repo_matrix_read","contract_read","destination_validated","runtime_no_habilitado","automatic_impact_bloqueado","all_required_pre_judge_steps_pass","research_pack_pass","research_pack_evidence_strong","research_to_rules_matrix_present","decision_matrix_present","source_sha_present","contract_sha_present","judge_sha_present","github_write_done","github_readback_done","no_blocking_observations"]'::jsonb,
    fail_if = '["write_without_contract","wrong_repository","wrong_path","runtime_enabled","automatic_impact_enabled","no_readback","missing_execution_id","missing_required_pre_judge_step","missing_research_pack","weak_research_pack_evidence","missing_research_to_rules_matrix","missing_decision_matrix","assistant_freeform_decision","missing_source_sha","missing_contract_sha","missing_judge_sha","blocking_observations"]'::jsonb,
    judge_path = 'gobernanza/judges/judge_contrato_card_lf.yaml',
    judge_sha = '4bd77d42b4c2725c3970cd532793c12cdcc49667',
    updated_at = now(),
    updated_by_execution_id = 'MIG-20260831083500-CARD-DEPTH-ORDER'
where operation_code = 'CREACION_CARD_LF'
  and judge_code = 'JUDGE_CONTRATO_CARD_LF';

update public.lf_operation_registry
set version = 'v0.3',
    updated_at = now(),
    updated_by_execution_id = 'MIG-20260831083500-CARD-DEPTH-ORDER'
where operation_code = 'CREACION_CARD_LF';

commit;
