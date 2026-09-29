-- Close failed Input Governance run 265 after cached/non-cached classifier mismatch.
-- The assessments are intentionally not rewritten. A fresh successor must be curated
-- after the cached classifier equivalence fix.

begin;

do $preflight$
declare
  v_status text;
  v_api record;
  v_normal jsonb;
  v_cached jsonb;
  v_graph jsonb;
begin
  select status into v_status
  from programacion.input_readiness_runs
  where id=265 and pantalla_id=51;

  if v_status<>'CURATING' then
    raise exception 'RUN265_RECOVERY_UNEXPECTED_STATUS:%',coalesce(v_status,'NULL');
  end if;

  select coverage_status,well_defined_status,implementation_ready_status
    into v_api
  from programacion.input_family_assessments
  where run_id=265 and family_code='API_DATA_CONTRACT';

  if v_api.coverage_status<>'PARTIAL'
     or v_api.implementation_ready_status<>'NOT_READY' then
    raise exception 'RUN265_API_SNAPSHOT_NOT_EXPECTED_OLD_CLASSIFIER:%',row_to_json(v_api);
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);
  v_normal:=programacion.fn_input_governance_bootstrap_classify_v2(
    51,'API_DATA_CONTRACT',19
  );
  v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(
    51,'API_DATA_CONTRACT',19,v_graph
  );

  if v_normal->>'classifier_sha256' is distinct from v_cached->>'classifier_sha256'
     or v_normal->>'coverage_status'<>'COMPLETE'
     or v_normal->>'implementation_ready_status'<>'NOT_READY'
     or v_normal->'blockers'->0->>'code'<>'API_EXECUTABLE_IDENTITY_BINDING_PENDING' then
    raise exception 'RUN265_RECOVERY_CLASSIFIER_NOT_STABLE normal=% cached=%',v_normal,v_cached;
  end if;
end;
$preflight$;

update programacion.input_readiness_runs
set status='BLOCKED',
    blocked_reason='VALIDATOR_CLASSIFIER_EQUIVALENCE_MISMATCH_API_DATA_CONTRACT_FIXED_BY_CACHED_CLASSIFIER_EQUIVALENCE_V1'
where id=265
  and pantalla_id=51
  and status='CURATING';

do $postconditions$
declare
  v_status text;
  v_reason text;
begin
  select status,blocked_reason
    into v_status,v_reason
  from programacion.input_readiness_runs
  where id=265;

  if v_status<>'BLOCKED'
     or v_reason<>'VALIDATOR_CLASSIFIER_EQUIVALENCE_MISMATCH_API_DATA_CONTRACT_FIXED_BY_CACHED_CLASSIFIER_EQUIVALENCE_V1' then
    raise exception 'RUN265_RECOVERY_POSTCONDITION_FAILED:%:%',v_status,v_reason;
  end if;
end;
$postconditions$;

commit;
