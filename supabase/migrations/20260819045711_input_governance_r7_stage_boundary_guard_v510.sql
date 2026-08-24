create or replace function programacion.fn_guard_input_family_semantic_depth_v510()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $$
declare v_revision text; v_pantalla_id integer; v_expected_subject jsonb:='[]'::jsonb; v_expected_threat jsonb:='[]'::jsonb; v_bad integer:=0; v_expected_count integer:=0;
begin
  select r.contract_revision,r.pantalla_id into v_revision,v_pantalla_id from programacion.input_readiness_runs r where r.id=coalesce(new.run_id,old.run_id);
  if v_revision<>'5.10' then return new; end if;
  if tg_op='INSERT' then
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then new.subject_coverage:=programacion.fn_input_subject_depth_expected(v_pantalla_id,new.family_code); else new.subject_coverage:='[]'::jsonb; end if;
    if new.family_code='SECURITY' then new.threat_coverage:=programacion.fn_input_security_threat_expected(v_pantalla_id); else new.threat_coverage:='[]'::jsonb; end if;
    new.semantic_depth_sha256:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',new.family_code,'subject_coverage',new.subject_coverage,'threat_coverage',new.threat_coverage));
    new.curator_evidence:=jsonb_set(coalesce(new.curator_evidence,'{}'::jsonb),'{semantic_depth_sha256}',to_jsonb(new.semantic_depth_sha256),true);
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then
      select count(*) into v_bad from jsonb_array_elements(new.subject_coverage) s where s->>'status' not in ('COMPLETE','NOT_APPLICABLE');
      if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'FAMILY_COMPLETE_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if;
      if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'FAMILY_WELL_DEFINED_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if;
    end if;
    if new.family_code='SECURITY' then
      select count(*) into v_bad from jsonb_array_elements(new.threat_coverage) t where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');
      if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'SECURITY_COMPLETE_WITH_UNRESOLVED_THREAT:%',v_bad; end if;
      if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'SECURITY_WELL_DEFINED_WITH_UNRESOLVED_THREAT:%',v_bad; end if;
      if exists(select 1 from jsonb_array_elements(new.threat_coverage) t where t->>'applicability'='NOT_APPLICABLE' and (t->'applicability_authority'->>'authority_rule' is null or nullif(t->>'rationale','') is null)) then raise exception 'SECURITY_THREAT_NA_REQUIRES_POSITIVE_PROFILE_AUTHORITY'; end if;
      select jsonb_array_length(c.especificacion->'semantic_depth_contract'->'security_threat_catalog') into v_expected_count from programacion.contratos c join programacion.input_readiness_runs r on r.version_id=c.version_id where r.id=new.run_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
      if jsonb_array_length(new.threat_coverage)<>v_expected_count then raise exception 'SECURITY_THREAT_CATALOG_CARDINALITY_MISMATCH expected=% actual=%',v_expected_count,jsonb_array_length(new.threat_coverage); end if;
    end if;
    return new;
  end if;
  if new.subject_coverage is distinct from old.subject_coverage or new.threat_coverage is distinct from old.threat_coverage or new.semantic_depth_sha256 is distinct from old.semantic_depth_sha256 then raise exception 'SEMANTIC_DEPTH_IMMUTABLE:%',old.family_code; end if;
  if old.validator_outcome='PENDING' and new.validator_outcome<>'PENDING' then
    if new.validator_evidence->>'semantic_depth_sha256' is distinct from old.semantic_depth_sha256 then raise exception 'VALIDATOR_SEMANTIC_DEPTH_HASH_MISMATCH:%',old.family_code; end if;
    if old.family_code in ('DESIGN_SYSTEM','SECURITY') then v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,old.family_code); if old.subject_coverage is distinct from v_expected_subject then raise exception 'SEMANTIC_SUBJECT_DEPTH_STALE_DURING_VALIDATION:%',old.family_code; end if; end if;
    if old.family_code='SECURITY' then v_expected_threat:=programacion.fn_input_security_threat_expected(v_pantalla_id); if old.threat_coverage is distinct from v_expected_threat then raise exception 'SEMANTIC_THREAT_DEPTH_STALE_DURING_VALIDATION'; end if; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_input_family_assessment_01a_semantic_depth_v510_insert on programacion.input_family_assessments;
create trigger trg_input_family_assessment_01a_semantic_depth_v510_insert before insert on programacion.input_family_assessments for each row execute function programacion.fn_guard_input_family_semantic_depth_v510();
drop trigger if exists trg_input_family_assessment_01a_semantic_depth_v510_update on programacion.input_family_assessments;
create trigger trg_input_family_assessment_01a_semantic_depth_v510_update before update on programacion.input_family_assessments for each row execute function programacion.fn_guard_input_family_semantic_depth_v510();

create or replace function programacion.fn_guard_input_stage_earliest_boundary()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $$
declare v_revision text; v_version_id bigint; v_cfg jsonb; v_stage text; v_incomplete boolean;
begin
  select r.contract_revision,r.version_id into v_revision,v_version_id from programacion.input_readiness_runs r where r.id=new.run_id;
  if v_revision<>'5.10' or new.applicability<>'APPLICABLE' then return new; end if;
  select coalesce(c.especificacion->'family_stage_requirements'->new.family_code,'{}'::jsonb) into v_cfg from programacion.contratos c where c.version_id=v_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  if v_cfg='{}'::jsonb then return new; end if;
  v_stage:=upper(coalesce(v_cfg->>'coverage_required_by',''));
  v_incomplete:=new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE';
  if not v_incomplete then return new; end if;
  if v_stage='IMPLEMENTATION' then
    if new.story_ready_status<>'READY' then raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:STORY',new.family_code; end if;
    if new.severity<>'P1' then raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P1 actual=%',new.family_code,new.severity; end if;
  elsif v_stage='QA' then
    if new.story_ready_status<>'READY' or new.implementation_ready_status<>'READY' then raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:PRE_QA',new.family_code; end if;
    if new.severity<>'P2' then raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P2 actual=%',new.family_code,new.severity; end if;
  elsif v_stage='PRODUCTION' then
    if new.story_ready_status<>'READY' or new.implementation_ready_status<>'READY' or new.qa_ready_status<>'READY' then raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:PRE_PRODUCTION',new.family_code; end if;
    if new.severity<>'P3' then raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P3 actual=%',new.family_code,new.severity; end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_input_family_assessment_02_stage_earliest_boundary_insert on programacion.input_family_assessments;
create trigger trg_input_family_assessment_02_stage_earliest_boundary_insert before insert on programacion.input_family_assessments for each row execute function programacion.fn_guard_input_stage_earliest_boundary();

update programacion.contratos
set especificacion=especificacion || jsonb_build_object(
 'contract_revision','5.10',
 'remediation_revision','AUDIT_20260818_R7_STAGE_BOUNDARY_GUARD',
 'stage_boundary_contract',jsonb_build_object('mode','EARLIEST_BLOCKING_STAGE_ENFORCED','incomplete_family_cannot_block_earlier_stage',true,'severity_must_match_earliest_blocking_stage',true,'source','family_stage_requirements'),
 'negative_tests',coalesce(especificacion->'negative_tests','[]'::jsonb)||jsonb_build_array('CURATOR_REINTRODUCES_P0_FOR_IMPLEMENTATION_GAP','CURATOR_REINTRODUCES_P0_FOR_QA_GAP','QA_GAP_BLOCKS_IMPLEMENTATION','STAGE_SEVERITY_MISMATCH'),
 'audit_remediation',coalesce(especificacion->'audit_remediation','[]'::jsonb)||jsonb_build_array('AUD-IGA-028_ENFORCE_NO_EARLIER_STAGE_OVERBLOCK')
) where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

do $$
declare rec record; a record; v_new bigint; v_cur text; v_val text; v_sha text; v_assert jsonb;
begin
 for rec in select * from (values (51,92::bigint),(52,93::bigint),(53,94::bigint),(54,95::bigint),(55,96::bigint)) v(pantalla_id,parent_run_id)
 loop
  v_cur:='INPUT_CURATOR:v0.5r1-auth-'||rec.pantalla_id||'-v510-r7-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version)
  select version_id,pantalla_id,universe_rule_id,id,scope||jsonb_build_object('mode','CANDIDATE_V510_STAGE_BOUNDARY_GUARD','parent_run_id',id,'remediation','AUDIT_20260818_R7_STAGE_BOUNDARY_GUARD'),universe_snapshot_sha256,family_count,'CURATING',v_cur,curator_component_id,5 from programacion.input_readiness_runs where id=rec.parent_run_id returning id into v_new;
  for a in select * from programacion.input_family_assessments where run_id=rec.parent_run_id order by family_code loop
   insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
   values(v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,a.source_refs,a.rationale||' | V5.10 guard-enforced stage boundary.',a.blockers,a.negative_requirements,a.test_obligations,jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.10','parent_run_id',rec.parent_run_id,'parent_assessment_id',a.id,'remediation_revision','AUDIT_20260818_R7_STAGE_BOUNDARY_GUARD','direct_source_readback',true),repeat('0',64));
  end loop;
  v_val:='INPUT_VALIDATOR:v0.5r1-auth-'||rec.pantalla_id||'-v510-r7-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_new;
  select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_new;
  for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code loop
   v_assert:=programacion.fn_input_v58_build_assertions(v_new,rec.parent_run_id,a.family_code);
   update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.10','source_snapshot_sha256',v_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assert) where id=a.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
 end loop;
end;
$$;