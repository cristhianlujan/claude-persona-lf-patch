update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{action_specs_v1,RUN_CAMPAIGN}',
  (unit_metadata#>'{action_specs_v1,RUN_CAMPAIGN}')
  || jsonb_build_object(
    'status','READY',
    'precision','REAL_VALIDATOR_T1_T10_CAMPAIGN_V2',
    'handler_requirement',jsonb_build_object(
      'status','READY',
      'handler','REAL_VALIDATOR_T1_T10_ROLLBACK_CAMPAIGN',
      'entrypoint','programacion.fn_engineering_ig_validator_mutation_campaign_v1(integer)',
      'execution_mode','ROLLBACK_ONLY_REAL_VALIDATOR',
      'fixture_selection','CALLER_SELECTED_ELIGIBLE_COMPLETED_SCREEN',
      'last_verified_candidate_screen',50,
      'rollback_required',true,
      'synthetic_pass','FORBIDDEN',
      't10_independent_baseline_required',true
    ),
    'campaign_result_contract',jsonb_build_object(
      'actual_execution',true,
      'synthetic_pass',false,
      'known_mutations_total',10,
      'known_mutations_detected',10,
      't10_detected',true,
      't10_false_consensus_pass',false,
      'durable_residue',false,
      'classifier_restored',true,
      'semantic_authority_bound',true
    ),
    'verification_queries',jsonb_build_array(
      'select programacion.fn_engineering_ig_validator_mutation_campaign_v1(50) as result'
    ),
    'test_execution_contract',
      coalesce(unit_metadata#>'{action_specs_v1,RUN_CAMPAIGN,test_execution_contract}','{}'::jsonb)
      || jsonb_build_object(
        'mode','REAL_VALIDATOR_ROLLBACK_CAMPAIGN',
        'test_code','ENG_M4_9_RUN_CAMPAIGN',
        'test_path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m4_9/run_campaign.py',
        'campaign_entrypoint','programacion.fn_engineering_ig_validator_mutation_campaign_v1(integer)',
        'known_mutations_total',10,
        't10_mode','CORRELATED_CURATOR_RESOLVER_FALSE_CONSENSUS',
        'synthetic_pass','FORBIDDEN',
        'rollback_required',true,
        'semantic_authority','REAL_INPUT_GOVERNANCE_VALIDATOR'
      )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.9';

do $$
declare b jsonb;
begin
  b:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.9');
  if b#>>'{action_spec,status}'<>'READY'
     or b#>>'{execution_packet,status}'<>'READY'
     or b#>>'{action_spec,handler_requirement,status}'<>'READY'
     or b#>>'{action_spec,handler_requirement,entrypoint}' is distinct from
        'programacion.fn_engineering_ig_validator_mutation_campaign_v1(integer)'
  then
    raise exception 'M49_REAL_CAMPAIGN_CONTRACT_POSTCHECK_FAILED';
  end if;
end
$$;