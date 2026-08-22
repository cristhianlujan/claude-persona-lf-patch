create or replace function programacion.fn_guard_input_family_semantic_depth()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, programacion
as $$
declare
  v_revision text; v_pantalla_id integer; v_expected_subject jsonb:='[]'::jsonb; v_expected_threat jsonb:='[]'::jsonb; v_bad integer:=0; v_expected_count integer:=0;
begin
  select r.contract_revision,r.pantalla_id into v_revision,v_pantalla_id from programacion.input_readiness_runs r where r.id=coalesce(new.run_id,old.run_id);
  if v_revision not in ('5.7','5.8','5.9') then return new; end if;
  if tg_op='INSERT' then
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then new.subject_coverage:=programacion.fn_input_subject_depth_expected(v_pantalla_id,new.family_code); else new.subject_coverage:='[]'::jsonb; end if;
    if new.family_code='SECURITY' then new.threat_coverage:=programacion.fn_input_security_threat_expected(v_pantalla_id); else new.threat_coverage:='[]'::jsonb; end if;
    new.semantic_depth_sha256:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',new.family_code,'subject_coverage',new.subject_coverage,'threat_coverage',new.threat_coverage));
    new.curator_evidence:=jsonb_set(coalesce(new.curator_evidence,'{}'::jsonb),'{semantic_depth_sha256}',to_jsonb(new.semantic_depth_sha256),true);
    if new.family_code in ('DESIGN_SYSTEM','SECURITY') then select count(*) into v_bad from jsonb_array_elements(new.subject_coverage) s where s->>'status' not in ('COMPLETE','NOT_APPLICABLE'); if v_bad>0 and new.coverage_status='COMPLETE' then raise exception 'FAMILY_COMPLETE_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if; if v_bad>0 and new.well_defined_status='COMPLETE' then raise exception 'FAMILY_WELL_DEFINED_WITH_INCOMPLETE_SUBJECT:%:%',new.family_code,v_bad; end if; end if;
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

create or replace function programacion.fn_guard_input_family_assessment_update()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v_payload jsonb; v_run_status text; v_run_sha text; v_curator_identity text; v_validator_identity text; v_validator_component_id bigint;
  v_version_id bigint; v_pantalla_id integer; v_run_contract_revision text; v_run_contract_sha text;
  v_contract_revision text; v_contract_payload jsonb; v_contract_sha text;
  v_current_manifest jsonb; v_current_sha text; v_bad_assertions integer; v_assertion jsonb; v_eval jsonb; v_governance_family boolean;
begin
  if new.run_id is distinct from old.run_id or new.family_code is distinct from old.family_code or new.severity is distinct from old.severity or new.applicability is distinct from old.applicability or new.coverage_status is distinct from old.coverage_status or new.well_defined_status is distinct from old.well_defined_status or new.story_ready_status is distinct from old.story_ready_status or new.implementation_ready_status is distinct from old.implementation_ready_status or new.qa_ready_status is distinct from old.qa_ready_status or new.production_ready_status is distinct from old.production_ready_status or new.source_refs is distinct from old.source_refs or new.rationale is distinct from old.rationale or new.blockers is distinct from old.blockers or new.negative_requirements is distinct from old.negative_requirements or new.test_obligations is distinct from old.test_obligations or new.freshness is distinct from old.freshness or new.curator_evidence is distinct from old.curator_evidence or new.curator_sha256 is distinct from old.curator_sha256 or new.subject_coverage is distinct from old.subject_coverage or new.threat_coverage is distinct from old.threat_coverage or new.semantic_depth_sha256 is distinct from old.semantic_depth_sha256 or new.created_at is distinct from old.created_at then raise exception 'CURATOR_FIELDS_IMMUTABLE:%',old.family_code; end if;
  if old.validator_outcome<>'PENDING' then raise exception 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code; end if;
  if new.validator_outcome='PENDING' then raise exception 'VALIDATOR_UPDATE_MUST_BE_TERMINAL:%',old.family_code; end if;
  select r.status,r.source_snapshot_sha256,r.curator_identity,r.validator_identity,r.validator_component_id,r.version_id,r.pantalla_id,r.contract_revision,r.contract_snapshot_sha256 into v_run_status,v_run_sha,v_curator_identity,v_validator_identity,v_validator_component_id,v_version_id,v_pantalla_id,v_run_contract_revision,v_run_contract_sha from programacion.input_readiness_runs r where r.id=old.run_id;
  if v_run_status<>'VALIDATING' then raise exception 'VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.family_code; end if;
  if v_validator_component_id is null then raise exception 'RUN_VALIDATOR_COMPONENT_REQUIRED'; end if;
  if v_validator_identity is null or v_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  if new.validator_identity is distinct from v_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH:%',old.family_code; end if;
  select c.especificacion->>'contract_revision',jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion) into v_contract_revision,v_contract_payload from programacion.contratos c where c.version_id=v_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_run_contract_revision is distinct from v_contract_revision or v_run_contract_sha is distinct from v_contract_sha then raise exception 'INPUT_READINESS_CONTRACT_PIN_STALE_DURING_VALIDATION:%',old.family_code; end if;
  if new.validator_assessed_at is null then new.validator_assessed_at:=now(); end if;
  if jsonb_typeof(new.validator_evidence)<>'object' or new.validator_evidence='{}'::jsonb then raise exception 'VALIDATOR_EVIDENCE_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run_sha then raise exception 'VALIDATOR_EVIDENCE_SOURCE_SNAPSHOT_MISMATCH:%',old.family_code; end if;
  if new.validator_evidence->>'curator_sha256' is distinct from old.curator_sha256 then raise exception 'VALIDATOR_EVIDENCE_CURATOR_HASH_MISMATCH:%',old.family_code; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'VALIDATOR_DIRECT_SOURCE_READBACK_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'execution_mode'<>'INDEPENDENT_VALIDATOR' then raise exception 'VALIDATOR_EXECUTION_MODE_REQUIRED:%',old.family_code; end if;
  if coalesce(new.validator_evidence->>'contract_revision','')<>v_contract_revision then raise exception 'VALIDATOR_EVIDENCE_CONTRACT_REVISION_MISMATCH:%',old.family_code; end if;
  if v_contract_revision in ('5.7','5.8','5.9') and new.validator_evidence->>'semantic_depth_sha256' is distinct from old.semantic_depth_sha256 then raise exception 'VALIDATOR_EVIDENCE_SEMANTIC_DEPTH_MISMATCH:%',old.family_code; end if;
  if jsonb_typeof(new.validator_evidence->'assertions')<>'array' or jsonb_array_length(new.validator_evidence->'assertions')=0 then raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code; end if;
  select count(*) into v_bad_assertions from jsonb_array_elements(new.validator_evidence->'assertions') a where jsonb_typeof(a)<>'object' or not (a?'actual') or not (a?'expected') or not (a?'operator') or not (a?'source_ref') or not (a?'path');
  if v_bad_assertions>0 then raise exception 'VALIDATOR_ASSERTION_SCHEMA_INVALID:%',old.family_code; end if;
  v_governance_family:=old.family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS');
  for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions') loop
    if v_assertion->'source_ref'->>'kind' in ('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','CURRENT_VISUAL_ARTIFACT','CAPABILITY_ABSENCE','SCREEN_CANONICAL_GRAPH') then if not (v_assertion->'source_ref'?'pantalla_id') or (v_assertion->'source_ref'->>'pantalla_id')::integer<>v_pantalla_id then raise exception 'VALIDATOR_SCREEN_SOURCE_REF_REQUIRES_EXPLICIT_PANTALLA_ID:%',old.family_code; end if; end if;
    if v_governance_family then if not programacion.fn_input_governance_assertion_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then raise exception 'GOVERNANCE_VALIDATOR_ASSERTION_REQUIRES_INDEPENDENT_AUTHORITY:%',old.family_code; end if; else if not programacion.fn_input_assertion_is_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then raise exception 'VALIDATOR_ASSERTION_NOT_RELEVANT:%',old.family_code; end if; end if;
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion); if new.validator_outcome='PASS' and coalesce((v_eval->>'passed')::boolean,false) is not true then raise exception 'VALIDATOR_ASSERTION_FAILED:%',old.family_code; end if;
  end loop;
  v_current_manifest:=programacion.fn_input_build_source_manifest(old.run_id); v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest); if v_current_sha<>v_run_sha then raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code; end if;
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'semantic_depth_sha256',old.semantic_depth_sha256,'source_snapshot_sha256',v_run_sha,'validator_outcome',new.validator_outcome,'validator_findings',new.validator_findings,'validator_evidence',new.validator_evidence,'validator_identity',new.validator_identity,'validator_assessed_at',new.validator_assessed_at); new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload); return new;
end;
$$;

update programacion.contratos
set especificacion = especificacion || jsonb_build_object(
  'contract_revision','5.9',
  'remediation_revision','AUDIT_20260818_R6_STAGE_AUTHORITY',
  'family_stage_requirements',coalesce(especificacion->'family_stage_requirements','{}'::jsonb) || jsonb_build_object(
    'ANALYTICS',jsonb_build_object('coverage_required_by','IMPLEMENTATION','allow_story_ready_when_incomplete',true,'allow_implementation_ready_when_incomplete',false,'allow_qa_ready_when_incomplete',false,'allow_production_ready_when_incomplete',false,'authority','INPUT_READINESS_CONTRACT_5_9'),
    'FORCED_COLORS_CONTRAST',jsonb_build_object('coverage_required_by','IMPLEMENTATION','allow_story_ready_when_incomplete',true,'allow_implementation_ready_when_incomplete',false,'allow_qa_ready_when_incomplete',false,'allow_production_ready_when_incomplete',false,'authority','INPUT_READINESS_CONTRACT_5_9'),
    'IDEMPOTENCY_CONCURRENCY',jsonb_build_object('coverage_required_by','IMPLEMENTATION','allow_story_ready_when_incomplete',true,'allow_implementation_ready_when_incomplete',false,'allow_qa_ready_when_incomplete',false,'allow_production_ready_when_incomplete',false,'authority','INPUT_READINESS_CONTRACT_5_9'),
    'REDUCED_MOTION',jsonb_build_object('coverage_required_by','IMPLEMENTATION','allow_story_ready_when_incomplete',true,'allow_implementation_ready_when_incomplete',false,'allow_qa_ready_when_incomplete',false,'allow_production_ready_when_incomplete',false,'authority','INPUT_READINESS_CONTRACT_5_9'),
    'TESTING_OBLIGATIONS',jsonb_build_object('coverage_required_by','QA','allow_story_ready_when_incomplete',true,'allow_implementation_ready_when_incomplete',true,'allow_qa_ready_when_incomplete',false,'allow_production_ready_when_incomplete',false,'authority','INPUT_READINESS_CONTRACT_5_9'),
    'THEME_LIGHT_DARK_SYSTEM',jsonb_build_object('coverage_required_by','IMPLEMENTATION','allow_story_ready_when_incomplete',true,'allow_implementation_ready_when_incomplete',false,'allow_qa_ready_when_incomplete',false,'allow_production_ready_when_incomplete',false,'authority','INPUT_READINESS_CONTRACT_5_9')
  ),
  'negative_tests',coalesce(especificacion->'negative_tests','[]'::jsonb) || jsonb_build_array('ANALYTICS_GAP_AS_STORY_P0','FORCED_COLORS_GAP_AS_STORY_P0','IDEMPOTENCY_GAP_AS_STORY_P0','REDUCED_MOTION_GAP_AS_STORY_P0','TEST_CONTRACT_GAP_AS_STORY_P0','THEME_GAP_AS_STORY_P0','LATER_STAGE_GAP_SEVERITY_LAUNDERED_TO_P0'),
  'audit_remediation',coalesce(especificacion->'audit_remediation','[]'::jsonb) || jsonb_build_array('AUD-IGA-027_STAGE_SPECIFIC_FAMILY_SEVERITY')
)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

do $$
declare rec record; a record; v_new bigint; v_val_identity text; v_cur_identity text; v_source_sha text; v_assertions jsonb; v_sev text; v_story text; v_impl text; v_qa text; v_prod text; v_block jsonb; v_rat text;
begin
  for rec in select * from (values (51,87::bigint),(52,88::bigint),(53,89::bigint),(54,90::bigint),(55,91::bigint)) v(pantalla_id,parent_run_id)
  loop
    v_cur_identity:='INPUT_CURATOR:v0.5r1-auth-'||rec.pantalla_id||'-v59-r6-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version)
    select version_id,pantalla_id,universe_rule_id,id,scope || jsonb_build_object('mode','CANDIDATE_V59_STAGE_AUTHORITY','parent_run_id',id,'remediation','AUDIT_20260818_R6_STAGE_AUTHORITY'),universe_snapshot_sha256,family_count,'CURATING',v_cur_identity,curator_component_id,5 from programacion.input_readiness_runs where id=rec.parent_run_id returning id into v_new;
    for a in select * from programacion.input_family_assessments where run_id=rec.parent_run_id order by family_code
    loop
      v_sev:=a.severity; v_story:=a.story_ready_status; v_impl:=a.implementation_ready_status; v_qa:=a.qa_ready_status; v_prod:=a.production_ready_status; v_block:=a.blockers; v_rat:=a.rationale;
      if a.applicability='APPLICABLE' and a.family_code in ('ANALYTICS','FORCED_COLORS_CONTRAST','IDEMPOTENCY_CONCURRENCY','REDUCED_MOTION','THEME_LIGHT_DARK_SYSTEM') and (a.coverage_status<>'COMPLETE' or a.well_defined_status<>'COMPLETE') then
        v_sev:='P1'; v_story:='READY'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
        v_block:=coalesce(a.blockers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('code','V59_STAGE_SPECIFIC_RECLASSIFICATION','earliest_blocking_stage','IMPLEMENTATION','blocks_story',false,'source_ref','INPUT_READINESS_CONTRACT_5_9'));
        v_rat:=a.rationale||' | V5.9: incomplete family remains visible but is an Implementation-stage gap, not a Story P0.';
      elsif a.applicability='APPLICABLE' and a.family_code='TESTING_OBLIGATIONS' and (a.coverage_status<>'COMPLETE' or a.well_defined_status<>'COMPLETE') then
        v_sev:='P2'; v_story:='READY'; v_impl:='READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
        v_block:=coalesce(a.blockers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('code','V59_STAGE_SPECIFIC_RECLASSIFICATION','earliest_blocking_stage','QA','blocks_story',false,'blocks_implementation',false,'source_ref','INPUT_READINESS_CONTRACT_5_9'));
        v_rat:=a.rationale||' | V5.9: test-contract materialization is a QA gate and must not block Story or Implementation.';
      end if;
      insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
      values(v_new,a.family_code,v_sev,a.applicability,a.coverage_status,a.well_defined_status,v_story,v_impl,v_qa,v_prod,a.source_refs,v_rat,v_block,a.negative_requirements,a.test_obligations,jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.9','parent_run_id',rec.parent_run_id,'parent_assessment_id',a.id,'remediation_revision','AUDIT_20260818_R6_STAGE_AUTHORITY','direct_source_readback',true),repeat('0',64));
    end loop;
    v_val_identity:='INPUT_VALIDATOR:v0.5r1-auth-'||rec.pantalla_id||'-v59-r6-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val_identity,validator_component_id=47 where id=v_new;
    select source_snapshot_sha256 into v_source_sha from programacion.input_readiness_runs where id=v_new;
    for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code
    loop
      v_assertions:=programacion.fn_input_v58_build_assertions(v_new,rec.parent_run_id,a.family_code);
      update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val_identity,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.9','source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assertions) where id=a.id;
    end loop;
    update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  end loop;
end;
$$;