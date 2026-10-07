-- M4.6 NEG_CONTRADICTION V1
-- True cross-family pair: MFA_OTP_SSO <-> SESSION on RECOVERY_OTP_VERIFY.
-- Contract authority: INPUT_READINESS_CONTRACT 5.13.1
-- semantic_depth_contract.recovery_otp_operational_session_creation = DENY.
-- All domain fixtures roll back.

begin;

create temp table _m46_xf_fixture
(like programacion.input_family_assessments including all)
on commit drop;

create trigger trg_m46_xf_semantic_detector
before update on _m46_xf_fixture
for each row
execute function programacion.fn_guard_input_validator_semantic_coherence_v512();

create temp table _m46_xf_results(
  test_code text primary key,
  passed boolean not null,
  observed text not null
) on commit drop;

do $m46$
declare
  v_cur jsonb;
  v_run bigint;
  v_mfa programacion.input_family_assessments%rowtype;
  v_session programacion.input_family_assessments%rowtype;
  v_err text;
begin
  v_cur:=programacion.fn_input_governance_curator_rebind_v1(
    56,
    'MANUAL',
    'INPUT_CURATOR:EDGE:input-governance-curator-v1:M46XFPAIR01',
    true
  );
  v_run:=(v_cur->>'run_id')::bigint;

  if v_run is null then
    raise exception 'M46_XF_FRESH_SUCCESSOR_NOT_CREATED:%',v_cur;
  end if;

  select * into v_mfa
  from programacion.input_family_assessments
  where run_id=v_run and family_code='MFA_OTP_SSO';

  select * into v_session
  from programacion.input_family_assessments
  where run_id=v_run and family_code='SESSION';

  if v_mfa.applicability<>'APPLICABLE'
     or v_session.applicability<>'NOT_APPLICABLE' then
    raise exception 'M46_XF_CANONICAL_PAIR_NOT_READY:mfa=% session=%',
      v_mfa.applicability,v_session.applicability;
  end if;

  -- Positive: canonical pair is coherent.
  truncate _m46_xf_fixture;
  insert into _m46_xf_fixture
  select * from programacion.input_family_assessments
  where run_id=v_run and family_code='MFA_OTP_SSO';

  update _m46_xf_fixture
     set validator_outcome='PASS',
         validator_identity='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M46XFPAIR01',
         validator_sha256=repeat('a',64),
         validator_assessed_at=clock_timestamp()
   where family_code='MFA_OTP_SSO';

  insert into _m46_xf_results values(
    'M46_XF_POS_RECOVERY_OTP_SESSION_DENY',
    true,
    'CANONICAL_PAIR_ACCEPTED:MFA_OTP_SSO=APPLICABLE,SESSION=NOT_APPLICABLE'
  );

  -- Negative: build a Curator-valid but semantically contradictory SESSION sibling.
  delete from programacion.input_family_assessments
  where run_id=v_run and family_code='SESSION';

  insert into programacion.input_family_assessments(
    id,run_id,family_code,severity,applicability,coverage_status,well_defined_status,
    story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
    source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,
    curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,
    validator_identity,validator_sha256,validator_assessed_at,created_at,
    subject_coverage,threat_coverage,semantic_depth_sha256
  ) values (
    v_session.id,v_session.run_id,v_session.family_code,
    'P1','APPLICABLE','PARTIAL','PARTIAL',
    'READY','NOT_READY','NOT_READY','NOT_READY',
    v_session.source_refs,
    'M4.6 rollback fixture: recovery OTP incorrectly creates operational SESSION applicability.',
    '[]'::jsonb,
    v_session.negative_requirements,v_session.test_obligations,v_session.freshness,
    v_session.curator_evidence,v_session.curator_sha256,
    'PENDING','[]'::jsonb,'{}'::jsonb,
    null,null,null,v_session.created_at,
    v_session.subject_coverage,v_session.threat_coverage,v_session.semantic_depth_sha256
  );

  truncate _m46_xf_fixture;
  insert into _m46_xf_fixture
  select * from programacion.input_family_assessments
  where run_id=v_run and family_code='MFA_OTP_SSO';

  begin
    update _m46_xf_fixture
       set validator_outcome='PASS',
           validator_identity='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M46XFPAIR01',
           validator_sha256=repeat('b',64),
           validator_assessed_at=clock_timestamp()
     where family_code='MFA_OTP_SSO';

    insert into _m46_xf_results values(
      'M46_XF_NEG_RECOVERY_OTP_SESSION_APPLICABLE',
      false,
      'UNEXPECTED_PASS'
    );
  exception when others then
    v_err:=sqlerrm;
    insert into _m46_xf_results values(
      'M46_XF_NEG_RECOVERY_OTP_SESSION_APPLICABLE',
      position('V5131_CROSS_FAMILY_RECOVERY_OTP_SESSION_CONTRADICTION' in v_err)>0,
      v_err
    );
  end;
end;
$m46$;

select jsonb_build_object(
  'schema_version','M46_TRUE_CROSS_FAMILY_PAIR_RUN_V1',
  'actual_execution',true,
  'synthetic_pass',false,
  'transaction_policy','ROLLBACK_ALL_FIXTURES',
  'pair',jsonb_build_array('MFA_OTP_SSO','SESSION'),
  'contract_rule','recovery_otp_operational_session_creation=DENY',
  'case_count',count(*),
  'pass_count',count(*) filter(where passed),
  'failure_count',count(*) filter(where not passed),
  'results',jsonb_agg(
    jsonb_build_object(
      'test_code',test_code,
      'status',case when passed then 'PASS' else 'FAIL' end,
      'actual_output',jsonb_build_object('observed',observed),
      'evidence_payload',jsonb_build_object(
        'pair',jsonb_build_array('MFA_OTP_SSO','SESSION'),
        'pantalla_id',56,
        'profile','RECOVERY_OTP_VERIFY',
        'authority_rule','B2B-RULE-AUTH-037',
        'contract_rule','recovery_otp_operational_session_creation=DENY',
        'rollback_fixture',true,
        'observed',observed
      ),
      'assertion_code',test_code||'_ASSERT'
    )
    order by test_code
  )
) as test_run
from _m46_xf_results;

rollback;
