-- Keep authored negative tests bound to the CURRENT canonical IG exit criterion.
-- Scope correction: removes stale POST_PASE/SADM wording from M5.10/M6.13
-- negative-test semantic authority without changing the test purpose.

do $preflight$
declare
  v_count int;
begin
  select count(*) into v_count
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and unit_code in ('M5.10','M6.13')
    and unit_metadata#>>'{action_specs_v1,NEGATIVE_OPEN_UNIT,test_execution_contract,semantic_authority}'
        ='CANONICAL_PLAN_EXIT_CRITERION';
  if v_count<>2 then
    raise exception 'IG_CLOSURE_NEGATIVE_SCOPE_SYNC_PREFLIGHT_FAILED:%',v_count;
  end if;
end
$preflight$;

update programacion.engineering_plan_units pu
set unit_metadata=jsonb_set(
  pu.unit_metadata,
  '{action_specs_v1,NEGATIVE_OPEN_UNIT,test_execution_contract,canonical_exit_criterion}',
  to_jsonb(pu.exit_criterion),
  false
)
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code in ('M5.10','M6.13');

update public.lf_error_knowledge
set validacion =
  'PASS when M5.10 and M6.13 POST_PASE transversal activation is DECLARED_ONLY, their exit criteria contain no active FINAL_EVIDENCE/CLOSURE_GATE requirement, FINAL_EVIDENCE_SADM is NOT_APPLICABLE while the external workstream is disabled, and each NEGATIVE_OPEN_UNIT test contract is bound to the current IG exit criterion rather than stale POST_PASE wording.',
    ultima_vez=now(),
    updated_at=now()
where codigo='IG-CROSS-WORKSTREAM-POST-PASE-BLEED-001';

do $selftest$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and unit_code in ('M5.10','M6.13')
    and unit_metadata#>>'{action_specs_v1,NEGATIVE_OPEN_UNIT,test_execution_contract,canonical_exit_criterion}'
        is distinct from exit_criterion;
  if v_bad<>0 then
    raise exception 'IG_CLOSURE_NEGATIVE_SCOPE_SYNC_SELFTEST_FAILED:%',v_bad;
  end if;
end
$selftest$;
