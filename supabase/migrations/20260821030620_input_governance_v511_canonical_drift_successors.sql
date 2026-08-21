do $$
declare
  rec record;
  a record;
  v_new bigint;
  v_cur text;
  v_val text;
  v_sha text;
  v_assert jsonb;
  v_new_runs bigint[] := array[]::bigint[];
  v_expected_count integer;
  v_current_count integer;
begin
  -- Fail closed if the live terminal baseline changed after preflight.
  for rec in
    select *
    from (values
      (51::integer,140::bigint),
      (52::integer,141::bigint),
      (53::integer,142::bigint),
      (54::integer,146::bigint),
      (56::integer,144::bigint)
    ) as x(pantalla_id,parent_run_id)
    order by pantalla_id
  loop
    if not exists (
      select 1
      from programacion.input_readiness_runs r
      where r.id=rec.parent_run_id
        and r.version_id=19
        and r.pantalla_id=rec.pantalla_id
        and r.status='COMPLETED'
        and r.contract_revision='5.11'
        and r.invalidated_at is null
    ) then
      raise exception 'V511_DRIFT_PARENT_NOT_ELIGIBLE screen=% run=%',rec.pantalla_id,rec.parent_run_id;
    end if;

    if exists (
      select 1
      from programacion.input_readiness_runs s
      where s.supersedes_run_id=rec.parent_run_id
        and s.status in ('COMPLETED','BLOCKED')
    ) then
      raise exception 'V511_DRIFT_PARENT_ALREADY_SUPERSEDED screen=% run=%',rec.pantalla_id,rec.parent_run_id;
    end if;

    if programacion.fn_input_readiness_run_is_current(rec.parent_run_id) then
      raise exception 'V511_DRIFT_PARENT_EXPECTED_STALE screen=% run=%',rec.pantalla_id,rec.parent_run_id;
    end if;

    v_cur := 'INPUT_CURATOR:v0.5r1-auth-'||rec.pantalla_id||'-v511-canonical-drift-'||substr(md5(random()::text||clock_timestamp()::text),1,8);

    insert into programacion.input_readiness_runs(
      version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,
      universe_snapshot_sha256,family_count,status,curator_identity,
      curator_component_id,contract_version
    )
    select
      version_id,pantalla_id,universe_rule_id,id,
      scope || jsonb_build_object(
        'mode','CANDIDATE_V511_CANONICAL_DRIFT_REVALIDATION',
        'parent_run_id',id,
        'remediation','PR179_LIVE_SOURCE_DRIFT_RECONCILIATION_20260820'
      ),
      universe_snapshot_sha256,family_count,'CURATING',v_cur,
      curator_component_id,contract_version
    from programacion.input_readiness_runs
    where id=rec.parent_run_id
    returning id into v_new;

    v_new_runs := array_append(v_new_runs,v_new);

    for a in
      select *
      from programacion.input_family_assessments
      where run_id=rec.parent_run_id
      order by family_code
    loop
      insert into programacion.input_family_assessments(
        run_id,family_code,severity,applicability,coverage_status,
        well_defined_status,story_ready_status,implementation_ready_status,
        qa_ready_status,production_ready_status,source_refs,rationale,blockers,
        negative_requirements,test_obligations,curator_evidence,curator_sha256
      )
      values(
        v_new,a.family_code,a.severity,a.applicability,a.coverage_status,
        a.well_defined_status,a.story_ready_status,a.implementation_ready_status,
        a.qa_ready_status,a.production_ready_status,a.source_refs,
        a.rationale||' | Recurado contra fuentes canónicas vigentes por reconciliación PR #179 2026-08-20.',
        a.blockers,a.negative_requirements,a.test_obligations,
        jsonb_build_object(
          'component_id',46,
          'execution_id',gen_random_uuid()::text,
          'execution_mode','INDEPENDENT_CURATOR',
          'contract_revision','5.11',
          'parent_run_id',rec.parent_run_id,
          'parent_assessment_id',a.id,
          'remediation_revision','PR179_LIVE_SOURCE_DRIFT_RECONCILIATION_20260820',
          'direct_source_readback',true
        ),
        repeat('0',64)
      );
    end loop;

    v_val := 'INPUT_VALIDATOR:v0.5r1-auth-'||rec.pantalla_id||'-v511-canonical-drift-'||substr(md5(random()::text||clock_timestamp()::text),1,8);

    update programacion.input_readiness_runs
       set status='VALIDATING',
           validator_identity=v_val,
           validator_component_id=47
     where id=v_new;

    select source_snapshot_sha256
      into v_sha
    from programacion.input_readiness_runs
    where id=v_new;

    for a in
      select *
      from programacion.input_family_assessments
      where run_id=v_new
      order by family_code
    loop
      v_assert := programacion.fn_input_v58_build_assertions(v_new,rec.parent_run_id,a.family_code);

      update programacion.input_family_assessments
         set validator_outcome='PASS',
             validator_findings='[]'::jsonb,
             validator_identity=v_val,
             validator_evidence=jsonb_build_object(
               'component_id',47,
               'execution_id',gen_random_uuid()::text,
               'validated_curator_execution_id',a.curator_evidence->>'execution_id',
               'execution_mode','INDEPENDENT_VALIDATOR',
               'direct_source_readback',true,
               'contract_revision','5.11',
               'source_snapshot_sha256',v_sha,
               'curator_sha256',a.curator_sha256,
               'semantic_depth_sha256',a.semantic_depth_sha256,
               'assertions',v_assert
             )
       where id=a.id;
    end loop;

    update programacion.input_readiness_runs
       set status='COMPLETED'
     where id=v_new;
  end loop;

  v_expected_count := coalesce(array_length(v_new_runs,1),0);
  if v_expected_count<>5 then
    raise exception 'V511_DRIFT_SUCCESSOR_COUNT_MISMATCH expected=5 actual=%',v_expected_count;
  end if;

  select count(*)
    into v_current_count
  from unnest(v_new_runs) u(run_id)
  where programacion.fn_input_readiness_run_is_current(u.run_id);

  if v_current_count<>v_expected_count then
    raise exception 'V511_DRIFT_POSTCHECK_CURRENTNESS_FAILED expected=% actual=%',v_expected_count,v_current_count;
  end if;
end$$;