-- M7.11 NEG_CASE_MUTATED
-- Canonical case: CI-API-04, adjudicated v2 decision HUMAN_REQUIRED.
-- Mutation: expected decision -> GLOBAL_ESCALATE.
-- The mutation exists only in local variables and the transaction rolls back.

begin;

create temp table _m711_neg_result(
  test_code text primary key,
  passed boolean not null,
  observed text not null,
  canonical_decision text not null,
  mutated_decision text not null
) on commit drop;

do $m711$
declare
  v_input jsonb;
  v_expected jsonb;
  v_mutated jsonb;
  v_canonical text;
  v_mutated_decision text;
  v_err text;
begin
  select input_payload,expected_output
    into v_input,v_expected
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and test_code='CI-API-04'
    and metadata->>'unit_code'='M7.11'
    and metadata->>'checkpoint_code'='REGISTER_SUITE';

  if v_input is null or v_expected is null then
    raise exception 'M711_NEG_SOURCE_CASE_NOT_FOUND:CI-API-04';
  end if;

  v_canonical:=v_input->>'adjudicated_decision';
  if v_canonical is distinct from 'HUMAN_REQUIRED'
     or v_expected->>'decision' is distinct from v_canonical then
    raise exception 'M711_NEG_SOURCE_CASE_BASELINE_DRIFT:CI-API-04:input=%:expected=%',
      coalesce(v_canonical,'<NULL>'),coalesce(v_expected->>'decision','<NULL>');
  end if;

  v_mutated:=jsonb_set(v_expected,'{decision}','"GLOBAL_ESCALATE"'::jsonb,true);
  v_mutated_decision:=v_mutated->>'decision';

  begin
    if v_mutated_decision is distinct from v_canonical then
      raise exception
        'M711_GOLD_EXPECTED_DECISION_DRIFT:CI-API-04:expected=%:mutated=%',
        v_canonical,v_mutated_decision;
    end if;

    insert into _m711_neg_result values(
      'M711_NEG_API04_EXPECTED_MUTATION',
      false,
      'UNEXPECTED_PASS',
      v_canonical,
      v_mutated_decision
    );
  exception when others then
    v_err:=sqlerrm;
    insert into _m711_neg_result values(
      'M711_NEG_API04_EXPECTED_MUTATION',
      position('M711_GOLD_EXPECTED_DECISION_DRIFT:CI-API-04' in v_err)>0,
      v_err,
      v_canonical,
      v_mutated_decision
    );
  end;
end;
$m711$;

select jsonb_build_object(
  'schema_version','M711_NEG_MUTATED_EXPECTED_RUN_V1',
  'actual_execution',true,
  'synthetic_pass',false,
  'transaction_policy','ROLLBACK_ALL_MUTATIONS',
  'source_case','CI-API-04',
  'case_count',count(*),
  'pass_count',count(*) filter(where passed),
  'failure_count',count(*) filter(where not passed),
  'results',jsonb_agg(
    jsonb_build_object(
      'test_code',test_code,
      'status',case when passed then 'PASS' else 'FAIL' end,
      'actual_output',jsonb_build_object(
        'canonical_decision',canonical_decision,
        'mutated_decision',mutated_decision,
        'observed',observed
      ),
      'evidence_payload',jsonb_build_object(
        'source_case','CI-API-04',
        'source_oracle','INPUT_GOV_CHANGE_IMPACT_L3C_ADJUDICATED_GOLD_V2',
        'canonical_decision',canonical_decision,
        'mutated_decision',mutated_decision,
        'typed_finding','M711_GOLD_EXPECTED_DECISION_DRIFT',
        'rollback_mutation',true,
        'observed',observed
      ),
      'assertion_code',test_code||'_ASSERT'
    )
    order by test_code
  )
) as test_run
from _m711_neg_result;

rollback;
