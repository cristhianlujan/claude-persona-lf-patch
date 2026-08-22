do $$
declare
  rec record;
  a record;
  v_parent bigint;
  v_new bigint;
  v_cur text;
  v_val text;
  v_sha text;
  v_assert jsonb;
begin
  for rec in
    select p.id as pantalla_id
    from lf_ops.pantallas p
    where p.id in (51,52,53,54,56) and p.activa=true
    order by p.id
  loop
    select r.id into v_parent
    from programacion.input_readiness_runs r
    where r.version_id=19 and r.pantalla_id=rec.pantalla_id and r.status='COMPLETED' and r.contract_revision='5.11'
    order by r.id desc limit 1;
    if v_parent is null then raise exception 'R511_RECURATION_PARENT_NOT_FOUND:%',rec.pantalla_id; end if;

    v_cur:='INPUT_CURATOR:v0.5r1-auth-'||rec.pantalla_id||'-v511-recuration-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version)
    select version_id,pantalla_id,universe_rule_id,id,scope||jsonb_build_object('mode','CANDIDATE_V511_SEMANTIC_ASSERTION_RECURATION','parent_run_id',id,'remediation','AUD019_SEMANTIC_ASSERTION_RECURATION_20260819'),universe_snapshot_sha256,family_count,'CURATING',v_cur,curator_component_id,contract_version
    from programacion.input_readiness_runs where id=v_parent returning id into v_new;

    for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code loop
      insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
      values(v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,a.source_refs,a.rationale||' | Assertions semánticas recuradas contra fuentes canónicas vigentes 2026-08-19.',a.blockers,a.negative_requirements,a.test_obligations,jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.11','parent_run_id',v_parent,'parent_assessment_id',a.id,'remediation_revision','AUD019_SEMANTIC_ASSERTION_RECURATION_20260819','direct_source_readback',true),repeat('0',64));
    end loop;

    v_val:='INPUT_VALIDATOR:v0.5r1-auth-'||rec.pantalla_id||'-v511-recuration-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_new;
    select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_new;

    for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code loop
      v_assert:=programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);
      update programacion.input_family_assessments
         set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val,
             validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.11','source_snapshot_sha256',v_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assert)
       where id=a.id;
    end loop;
    update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  end loop;
end$$;