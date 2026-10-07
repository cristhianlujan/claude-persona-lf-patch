-- M4.6 CROSS_FAMILY_CASES V1
-- Exact detector unit harness. 10 cases = positive + negative for each of 5
-- existing semantic-coherence rules. All fixtures are transaction-local.
-- No ASSURANCE_EVALUATOR activation. No persistent Input Governance mutation.

begin;

create temp table _m46_fixture
(like programacion.input_family_assessments including all)
on commit drop;

create trigger trg_m46_semantic_detector
before update on _m46_fixture
for each row
execute function programacion.fn_guard_input_validator_semantic_coherence_v512();

create temp table _m46_results(
  test_code text primary key,
  family_code text not null,
  polarity text not null,
  passed boolean not null,
  observed text not null
) on commit drop;

do $m46$
declare
  v_cur jsonb;
  v_run bigint;
  v_parent bigint;
  v_source_sha text;
  v_contract_revision text;
  v_family text;
  v_polarity text;
  v_test_code text;
  v_expected_error text;
  v_err text;
  v_assertions jsonb;
  v_assertion_sha text;
  v_logical jsonb;
  v_physical jsonb;
  v_validator_identity text:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M46CASES01';
  a programacion.input_family_assessments%rowtype;
begin
  v_cur:=programacion.fn_input_governance_curator_rebind_v1(
    54,'MANUAL',
    'INPUT_CURATOR:EDGE:input-governance-curator-v1:M46CASES01',
    true
  );
  v_run:=(v_cur->>'run_id')::bigint;

  if v_run is null then
    raise exception 'M46_FRESH_SUCCESSOR_NOT_CREATED:%',v_cur;
  end if;

  select supersedes_run_id,source_snapshot_sha256,contract_revision
    into v_parent,v_source_sha,v_contract_revision
  from programacion.input_readiness_runs where id=v_run;

  for v_family,v_expected_error in
    select * from (values
      ('REDUCED_MOTION','V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH'),
      ('FORCED_COLORS_CONTRAST','V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH'),
      ('THEME_LIGHT_DARK_SYSTEM','V512_VALIDATOR_THEME_SEMANTICS_MISMATCH'),
      ('ACCESSIBILITY','V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE'),
      ('MFA_OTP_SSO','V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE')
    ) x(family_code,expected_error)
  loop
    select * into a
    from programacion.input_family_assessments
    where run_id=v_run and family_code=v_family;

    v_assertions:=programacion.fn_input_v58_build_assertions(v_run,v_parent,v_family);
    v_assertion_sha:=programacion.fn_v09_sha256_jsonb(v_assertions);

    insert into programacion.input_validator_assertion_sets_v1(assertion_set_sha256,assertions)
    values(v_assertion_sha,v_assertions)
    on conflict (assertion_set_sha256) do nothing;

    v_logical:=jsonb_build_object(
      'component_id',(select min(id) from programacion.componentes
                      where version_id=19 and componente_codigo='INPUT_VALIDATOR'),
      'execution_id',gen_random_uuid()::text,
      'validated_curator_execution_id',a.curator_evidence->>'execution_id',
      'execution_mode','INDEPENDENT_VALIDATOR',
      'runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
      'direct_source_readback',true,
      'contract_revision',v_contract_revision,
      'source_snapshot_sha256',v_source_sha,
      'curator_sha256',a.curator_sha256,
      'semantic_depth_sha256',a.semantic_depth_sha256,
      'assertions',v_assertions
    );
    v_physical:=(v_logical-'assertions')
      || jsonb_build_object('assertion_set_sha256',v_assertion_sha);

    foreach v_polarity in array array['POSITIVE','NEGATIVE']
    loop
      truncate _m46_fixture;
      v_test_code:='M46_'||
        case v_polarity when 'POSITIVE' then 'POS' else 'NEG' end||
        '_'||v_family;

      insert into _m46_fixture(
        id,run_id,family_code,severity,applicability,coverage_status,well_defined_status,
        story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
        source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,
        curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,
        validator_identity,validator_sha256,validator_assessed_at,created_at,
        subject_coverage,threat_coverage,semantic_depth_sha256
      )
      select
        a.id,a.run_id,a.family_code,a.severity,
        case when v_polarity='NEGATIVE' and v_family='MFA_OTP_SSO'
             then 'NOT_APPLICABLE' else a.applicability end,
        case
          when v_polarity='NEGATIVE' and v_family='MFA_OTP_SSO' then 'NOT_APPLICABLE'
          when v_polarity='NEGATIVE' then 'MISSING'
          else a.coverage_status
        end,
        case
          when v_polarity='NEGATIVE' and v_family='MFA_OTP_SSO' then 'NOT_APPLICABLE'
          when v_polarity='NEGATIVE' then 'MISSING'
          else a.well_defined_status
        end,
        case when v_polarity='NEGATIVE' and v_family='MFA_OTP_SSO' then 'NOT_APPLICABLE' else a.story_ready_status end,
        case when v_polarity='NEGATIVE' and v_family='MFA_OTP_SSO' then 'NOT_APPLICABLE' else a.implementation_ready_status end,
        case when v_polarity='NEGATIVE' and v_family='MFA_OTP_SSO' then 'NOT_APPLICABLE' else a.qa_ready_status end,
        case when v_polarity='NEGATIVE' and v_family='MFA_OTP_SSO' then 'NOT_APPLICABLE' else a.production_ready_status end,
        a.source_refs,a.rationale,
        case when v_polarity='NEGATIVE' then '[]'::jsonb else a.blockers end,
        a.negative_requirements,a.test_obligations,a.freshness,
        a.curator_evidence,a.curator_sha256,
        'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,a.created_at,
        a.subject_coverage,a.threat_coverage,a.semantic_depth_sha256;

      begin
        update _m46_fixture
           set validator_outcome='PASS',
               validator_findings='[]'::jsonb,
               validator_evidence=v_physical,
               validator_identity=v_validator_identity,
               validator_sha256=programacion.fn_v09_sha256_jsonb(
                 jsonb_build_object(
                   'family_code',v_family,
                   'polarity',v_polarity,
                   'evidence',v_physical
                 )
               ),
               validator_assessed_at=clock_timestamp()
         where family_code=v_family;

        if v_polarity='POSITIVE' then
          insert into _m46_results values(
            v_test_code,v_family,v_polarity,true,'PASS_ACCEPTED_BY_DETECTOR'
          );
        else
          insert into _m46_results values(
            v_test_code,v_family,v_polarity,false,'UNEXPECTED_PASS'
          );
        end if;
      exception when others then
        v_err:=sqlerrm;
        if v_polarity='NEGATIVE' and (
             position(v_expected_error in v_err)>0
             or (v_family='MFA_OTP_SSO'
                 and position('V512_VALIDATOR_NA_WITHOUT_POSITIVE_EXCLUSION' in v_err)>0)
           ) then
          insert into _m46_results values(
            v_test_code,v_family,v_polarity,true,v_err
          );
        else
          insert into _m46_results values(
            v_test_code,v_family,v_polarity,false,v_err
          );
        end if;
      end;
    end loop;
  end loop;
end;
$m46$;

select jsonb_build_object(
  'schema_version','M46_CROSS_FAMILY_DETECTOR_TEST_RUN_V1',
  'actual_execution',true,
  'synthetic_pass',false,
  'transaction_policy','ROLLBACK_ALL_FIXTURES',
  'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
  'case_count',count(*),
  'pass_count',count(*) filter(where passed),
  'failure_count',count(*) filter(where not passed),
  'positive_passed',count(*) filter(where polarity='POSITIVE' and passed),
  'negative_detected',count(*) filter(where polarity='NEGATIVE' and passed),
  'results',jsonb_agg(
    jsonb_build_object(
      'test_code',test_code,
      'status',case when passed then 'PASS' else 'FAIL' end,
      'actual_output',jsonb_build_object(
        'family_code',family_code,
        'polarity',polarity,
        'observed',observed
      ),
      'evidence_payload',jsonb_build_object(
        'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
        'base_screen_id',54,
        'fresh_assertions',true,
        'rollback_fixture',true,
        'observed',observed
      ),
      'assertion_code',test_code||'_ASSERT'
    )
    order by test_code
  )
) as test_run
from _m46_results;

rollback;
