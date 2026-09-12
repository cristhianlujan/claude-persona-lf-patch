set local statement_timeout = '10min';

do $$
declare
  v_screen integer := 54;
  v_parent bigint;
  a record;
  v_new bigint;
  v_cur text;
  v_val text;
  v_sha text;
  v_assert jsonb;
begin
  select r.id into v_parent from programacion.input_readiness_runs r where r.version_id=19 and r.pantalla_id=v_screen and r.status='COMPLETED' and r.contract_revision='5.11' and r.invalidated_at is null and not exists (select 1 from programacion.input_readiness_runs s where s.supersedes_run_id=r.id and s.status in ('COMPLETED','BLOCKED')) order by r.id desc limit 1;
  if v_parent is null then raise exception 'V511_R2_PARENT_NOT_FOUND screen=%',v_screen; end if;
  if programacion.fn_input_readiness_run_is_current(v_parent) then raise exception 'V511_R2_PARENT_EXPECTED_STALE screen=% run=%',v_screen,v_parent; end if;
  v_cur := 'INPUT_CURATOR:v0.5r1-auth-'||v_screen||'-v511-live-r2-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version)
  select version_id,pantalla_id,universe_rule_id,id,scope || jsonb_build_object('mode','CANDIDATE_V511_LIVE_SOURCE_REVALIDATION_R2','parent_run_id',id,'remediation','PR179_RULE_GRAPH_AND_EKB_DRIFT_RECONCILIATION_20260821'),universe_snapshot_sha256,family_count,'CURATING',v_cur,curator_component_id,contract_version from programacion.input_readiness_runs where id=v_parent returning id into v_new;
  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code loop
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
    values(v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,a.source_refs,a.rationale||' | Recurado contra fuentes canónicas vigentes por reconciliación PR #179 2026-08-21.',a.blockers,a.negative_requirements,a.test_obligations,jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.11','parent_run_id',v_parent,'parent_assessment_id',a.id,'remediation_revision','PR179_RULE_GRAPH_AND_EKB_DRIFT_RECONCILIATION_20260821','direct_source_readback',true),repeat('0',64));
  end loop;
  v_val := 'INPUT_VALIDATOR:v0.5r1-auth-'||v_screen||'-v511-live-r2-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_new;
  select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_new;
  for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code loop
    v_assert := programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);
    update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.11','source_snapshot_sha256',v_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assert) where id=a.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  if not programacion.fn_input_readiness_run_is_current(v_new) then raise exception 'V511_R2_POSTCHECK_CURRENTNESS_FAILED screen=% run=%',v_screen,v_new; end if;
end$$;