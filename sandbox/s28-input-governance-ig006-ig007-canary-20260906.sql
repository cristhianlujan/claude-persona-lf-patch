-- Continuation of sandbox/s28-input-governance-ig006-ig007-candidate-20260906.sql
-- Same psql session and same transaction. This file ALWAYS ends in ROLLBACK.
\set ON_ERROR_STOP on
set local statement_timeout = '180s';

create temp table s28_ig006_007_results(
  screen_code text,
  pantalla_id integer,
  parent_run_id bigint,
  candidate_run_id bigint,
  curator_ms numeric,
  validator_total_ms numeric,
  validator_max_chunk_ms numeric,
  validator_calls integer,
  validator_pass_count integer,
  semantic_diff_count integer,
  missing_classifier_fingerprint_count integer,
  result text
) on commit drop;

do $canary$
declare
  r record;
  v_cur jsonb;
  v_val jsonb;
  v_run bigint;
  v_parent bigint;
  v_family_count integer;
  v_pass integer;
  v_missing_fp integer;
  v_diff integer;
  v_cur_ms numeric;
  v_val_total numeric;
  v_val_max numeric;
  v_chunk_ms numeric;
  v_calls integer;
  v_status text;
  v_curator_identity text;
  v_validator_identity text;
  t0 timestamptz;
  t1 timestamptz;
begin
  for r in
    select * from (values
      (43,'B2B-CARGA-001'),
      (5,'HOME_002')
    ) as x(pantalla_id,screen_code)
  loop
    select id into v_parent
    from programacion.input_readiness_runs
    where version_id=19 and pantalla_id=r.pantalla_id and status='COMPLETED'
    order by id desc limit 1;
    if v_parent is null then raise exception 'S28_IG_CANARY_PARENT_MISSING:%',r.screen_code; end if;

    v_curator_identity := 'INPUT_CURATOR:EDGE:input-governance-curator-v1:S28IG006_' || r.pantalla_id::text;
    v_validator_identity := 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:S28IG006_' || r.pantalla_id::text;

    t0:=clock_timestamp();
    v_cur:=programacion.fn_input_governance_curator_rebind_candidate_v1(
      r.pantalla_id,'MANUAL',v_curator_identity,true
    );
    t1:=clock_timestamp();
    v_cur_ms:=extract(epoch from (t1-t0))*1000;

    if v_cur->>'status'<>'VALIDATOR_RUNTIME_REQUIRED' then
      raise exception 'S28_IG_CURATOR_STATUS_FAIL:%:%',r.screen_code,v_cur;
    end if;
    v_run:=(v_cur->>'run_id')::bigint;
    v_family_count:=(v_cur->>'family_count')::integer;
    if v_family_count<>47 then raise exception 'S28_IG_CURATOR_CARDINALITY_FAIL:%:%',r.screen_code,v_family_count; end if;
    if v_cur_ms>=30000 then raise exception 'S28_IG_CURATOR_30S_GATE_FAIL:%:%ms',r.screen_code,round(v_cur_ms,3); end if;

    select count(*) into v_missing_fp
    from programacion.input_family_assessments
    where run_id=v_run
      and coalesce(curator_evidence->>'bootstrap_classifier_sha256','')='';
    if v_missing_fp<>0 then raise exception 'S28_IG_CLASSIFIER_FINGERPRINT_MISSING:%:%',r.screen_code,v_missing_fp; end if;

    select count(*) into v_diff
    from programacion.input_family_assessments c
    join programacion.input_family_assessments p
      on p.run_id=v_parent and p.family_code=c.family_code
    where c.run_id=v_run and jsonb_build_object(
      'severity',c.severity,
      'applicability',c.applicability,
      'coverage_status',c.coverage_status,
      'well_defined_status',c.well_defined_status,
      'story_ready_status',c.story_ready_status,
      'implementation_ready_status',c.implementation_ready_status,
      'qa_ready_status',c.qa_ready_status,
      'production_ready_status',c.production_ready_status,
      'source_refs',c.source_refs,
      'blockers',c.blockers,
      'negative_requirements',c.negative_requirements,
      'test_obligations',c.test_obligations,
      'subject_coverage',c.subject_coverage,
      'threat_coverage',c.threat_coverage,
      'semantic_depth_sha256',c.semantic_depth_sha256
    ) is distinct from jsonb_build_object(
      'severity',p.severity,
      'applicability',p.applicability,
      'coverage_status',p.coverage_status,
      'well_defined_status',p.well_defined_status,
      'story_ready_status',p.story_ready_status,
      'implementation_ready_status',p.implementation_ready_status,
      'qa_ready_status',p.qa_ready_status,
      'production_ready_status',p.production_ready_status,
      'source_refs',p.source_refs,
      'blockers',p.blockers,
      'negative_requirements',p.negative_requirements,
      'test_obligations',p.test_obligations,
      'subject_coverage',p.subject_coverage,
      'threat_coverage',p.threat_coverage,
      'semantic_depth_sha256',p.semantic_depth_sha256
    );
    if v_diff<>0 then raise exception 'S28_IG_SEMANTIC_COPY_DIFF:%:%',r.screen_code,v_diff; end if;

    v_val_total:=0;
    v_val_max:=0;
    v_calls:=0;
    v_status:=null;
    for i in 1..8 loop
      v_calls:=v_calls+1;
      t0:=clock_timestamp();
      v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,v_validator_identity);
      t1:=clock_timestamp();
      v_chunk_ms:=extract(epoch from (t1-t0))*1000;
      v_val_total:=v_val_total+v_chunk_ms;
      v_val_max:=greatest(v_val_max,v_chunk_ms);
      v_status:=v_val->>'status';
      if v_chunk_ms>=30000 then
        raise exception 'S28_IG_VALIDATOR_30S_CHUNK_GATE_FAIL:%:call=%:%ms',r.screen_code,v_calls,round(v_chunk_ms,3);
      end if;
      exit when v_status='COMPLETED';
      if v_status<>'VALIDATOR_CONTINUE_REQUIRED' then
        raise exception 'S28_IG_VALIDATOR_STATUS_FAIL:%:call=%:%',r.screen_code,v_calls,v_val;
      end if;
    end loop;
    if v_status<>'COMPLETED' then raise exception 'S28_IG_VALIDATOR_NOT_COMPLETED:%:%',r.screen_code,v_status; end if;

    select count(*) into v_pass
    from programacion.input_family_assessments
    where run_id=v_run
      and validator_outcome='PASS'
      and validator_identity=v_validator_identity;
    if v_pass<>47 then raise exception 'S28_IG_VALIDATOR_47_GATE_FAIL:%:%',r.screen_code,v_pass; end if;
    if v_validator_identity=v_curator_identity then raise exception 'S28_IG_VALIDATOR_INDEPENDENCE_FAIL:%',r.screen_code; end if;

    insert into s28_ig006_007_results values(
      r.screen_code,r.pantalla_id,v_parent,v_run,
      round(v_cur_ms,3),round(v_val_total,3),round(v_val_max,3),v_calls,v_pass,v_diff,v_missing_fp,'PASS'
    );
  end loop;
end;
$canary$;

select * from s28_ig006_007_results order by pantalla_id;
rollback;
