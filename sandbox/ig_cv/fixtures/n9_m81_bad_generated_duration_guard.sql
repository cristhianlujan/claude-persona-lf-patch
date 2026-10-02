-- N-9 / M8.1 negative probe candidate.
-- Build a valid terminal predecessor with the current guard, make only that
-- screen source stale inside the judge transaction, then reintroduce the
-- historical generated-duration guard defect. The outer judge transaction
-- restores every change.
do $$
declare
  v_dispatch jsonb;
  v_curator jsonb;
  v_validator jsonb;
  v_run_id bigint;
  v_status text;
  v_rows integer;
  v_def text;
  v_curator_def text;
  v_occurrences integer;
  v_freshness jsonb;
  i integer;
begin
  -- Seed a valid predecessor while the fixed guard is still active.
  v_dispatch := programacion.fn_input_governance_execute(4, 'STORY_CREATOR');
  if coalesce(v_dispatch->>'status','') <> 'CURATOR_RUNTIME_REQUIRED' then
    raise exception 'N9_M81_SEED_DISPATCH_UNEXPECTED:%', v_dispatch->>'status';
  end if;

  v_curator := programacion.fn_input_governance_curator_materialize_v1(
    4,
    'STORY_CREATOR',
    'INPUT_CURATOR:EDGE:input-governance-curator-v1:n9-m81-seed',
    true
  );
  if coalesce(v_curator->>'status','') <> 'VALIDATOR_RUNTIME_REQUIRED' then
    raise exception 'N9_M81_SEED_CURATOR_UNEXPECTED:%', v_curator->>'status';
  end if;

  v_run_id := coalesce((v_curator->>'run_id')::bigint, (v_curator->>'latest_run_id')::bigint);
  if v_run_id is null then
    raise exception 'N9_M81_SEED_RUN_ID_MISSING';
  end if;

  for i in 1..8 loop
    v_validator := programacion.fn_input_governance_validator_validate_v1(
      v_run_id,
      'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:n9-m81-seed'
    );
    v_status := coalesce(v_validator->>'status','');
    exit when v_status in ('COMPLETED','NOOP_COMPLETED');
  end loop;

  if v_status <> 'COMPLETED' then
    raise exception 'N9_M81_SEED_VALIDATOR_UNEXPECTED:%', v_status;
  end if;

  -- Make that predecessor stale while preserving the same semantic screen.
  update lf_ops.pantallas
     set descripcion = coalesce(descripcion, '') || ' '
   where id = 4;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'N9_M81_SEED_EXPECTED_ONE_SCREEN_ROW_GOT:%', v_rows;
  end if;

  v_freshness := programacion.fn_input_freshness_delta(v_run_id);
  if coalesce(v_freshness->>'run_state','') <> 'STALE' then
    raise exception 'N9_M81_SEED_EXPECTED_STALE_GOT:%', v_freshness->>'run_state';
  end if;

  -- Isolation shim for the N-9 v1 harness only. The harness currently calls
  -- curator_materialize with p_force_selftest=true; that routes to the known
  -- rebind path covered by INPUT-GOV-REBIND-CLASSIFIER-FINGERPRINT-001 and can
  -- mask M8.1 before the terminal-successor guard is exercised. Within this
  -- rollback-only candidate transaction, force the same function to evaluate
  -- its normal runtime stale-source branch instead. No production/runtime
  -- authority is changed and the outer judge rollback restores the definition.
  v_curator_def := pg_get_functiondef(
    'programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure
  );
  if strpos(v_curator_def, 'if not p_force_selftest') = 0 then
    raise exception 'N9_M81_CURATOR_ISOLATION_PATTERN_MISSING';
  end if;
  execute replace(v_curator_def, 'if not p_force_selftest', 'if true');

  -- Reintroduce exactly the M8.1 generated-column guard regression.
  v_def := pg_get_functiondef('programacion.fn_guard_input_readiness_run()'::regprocedure);
  v_occurrences :=
    (length(v_def) - length(replace(v_def, '-''curator_duration_ms''-''validator_duration_ms''', '')))
    / length('-''curator_duration_ms''-''validator_duration_ms''');

  if v_occurrences <> 2 then
    raise exception 'N9_M81_NEGATIVE_FIXTURE_EXPECTED_2_HOTFIX_OCCURRENCES_GOT:%', v_occurrences;
  end if;

  v_def := replace(
    v_def,
    '-''curator_duration_ms''-''validator_duration_ms''',
    ''
  );
  execute v_def;
end
$$;
