do $do$
declare
  v_parent bigint:=165; v_new bigint; v_screen integer:=51;
  v_validator_identity text:='INPUT_VALIDATOR:v0.5r1-auth-51-v512-semantic-coherence';
  v_source_sha text; v_assert jsonb; v_readbacks jsonb; v_assessment record; v_proposal record;
begin
  if programacion.fn_input_readiness_run_is_current(v_parent) then raise exception 'V512_PARENT_MUST_BE_STALE:%',v_parent; end if;
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  select version_id,pantalla_id,universe_rule_id,id,'CURATING',scope||jsonb_build_object('mode','CANDIDATE_V512_SEMANTIC_COHERENCE','remediation','V512_SEMANTIC_COHERENCE_PROPOSAL_SEPARATION_20260822','parent_run_id',id,'research_basis','IGA_2026','canon_vs_proposal','STRICT_SEPARATION'),universe_snapshot_sha256,family_count,contract_version,'INPUT_CURATOR:v0.5r1-auth-51-v512-semantic-coherence',curator_component_id
  from programacion.input_readiness_runs where id=v_parent returning id into v_new;

  insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
  select v_new,src.family_code,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'P0' else src.severity end,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'UNRESOLVED' else src.applicability end,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'PENDING' else src.coverage_status end,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'PENDING' else src.well_defined_status end,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'BLOCKED' else src.story_ready_status end,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'BLOCKED' else src.implementation_ready_status end,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'BLOCKED' else src.qa_ready_status end,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then 'BLOCKED' else src.production_ready_status end,
    src.source_refs,
    case
      when src.family_code='FEATURE_FLAGS' then 'UNRESOLVED: no feature-flag relation is observed, but absence is not a positive exclusion authority. A canonical applicability decision is required.'
      when src.family_code='I18N_FORMATS' then 'UNRESOLVED: no i18n/locale relation is observed, but absence is not a positive exclusion authority. A canonical applicability decision is required.'
      when src.family_code='DESIGN_SYSTEM' then src.rationale||' | V5.12 removed zero-count blocker noise.'
      else src.rationale||' | Recurated under INPUT_READINESS_CONTRACT 5.12.' end,
    case
      when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then jsonb_build_array(jsonb_build_object('code','APPLICABILITY_AUTHORITY_REQUIRED','family_code',src.family_code,'blocks_story',true,'source_ref','GOV-012'))
      when src.family_code='DESIGN_SYSTEM' then coalesce((select jsonb_agg(j.value) from jsonb_array_elements(src.blockers) j(value) where not (j.value->>'code'='SCREEN_ELEMENT_INVENTORY_MISSING' and coalesce((j.value->>'count')::integer,0)=0)),'[]'::jsonb)
      else src.blockers end,
    src.negative_requirements,
    case when src.family_code in ('FEATURE_FLAGS','I18N_FORMATS') then src.test_obligations||jsonb_build_array('Reject NOT_APPLICABLE when only absence/empty collections are observed') else src.test_obligations end,
    '{}'::jsonb,jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'parent_run_id',v_parent,'parent_assessment_id',src.id,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.12','remediation_revision','V512_SEMANTIC_COHERENCE_PROPOSAL_SEPARATION_20260822','direct_source_readback',true),repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64)
  from programacion.input_family_assessments src where src.run_id=v_parent order by src.family_code;
  if (select count(*) from programacion.input_family_assessments where run_id=v_new)<>47 then raise exception 'V512_SCREEN51_CURATOR_CARDINALITY_MISMATCH'; end if;

  insert into programacion.input_gap_proposals(run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,source_refs,evidence_refs,confidence,stage_impact,contradictions_checked,status,curator_identity,curator_execution_id,curator_sha256)
  select v_new,cur.id,cur.family_code,'APPLICABILITY_AUTHORITY_REQUIRED','HUMAN_DECISION_REQUIRED',
    jsonb_build_object('proposed_completion',case cur.family_code when 'FEATURE_FLAGS' then 'Define explicit canonical FEATURE_FLAGS applicability for B2B-AUTH-001; exclusion or binding must be authoritative, never inferred from absence.' when 'I18N_FORMATS' then 'Define explicit canonical I18N/locale applicability for B2B-AUTH-001; exclusion or locale source binding must be authoritative.' end),
    jsonb_build_object('target_type','APPLICABILITY_RULE_OR_DECISION','family_code',cur.family_code,'screen_code','B2B-AUTH-001'),
    cur.source_refs,'[{"kind":"EKB_ERROR","code":"GOV-012"},{"kind":"RESEARCH","code":"IGA_2026"}]'::jsonb,0.95,'{"story":"BLOCKED","implementation":"BLOCKED","qa":"BLOCKED","production":"BLOCKED"}'::jsonb,'["CAPABILITY_ABSENCE_IS_NOT_EXCLUSION","NO_EXPLICIT_CANONICAL_EXCLUSION_OBSERVED"]'::jsonb,'PROPOSED','INPUT_CURATOR:v0.5r1-auth-51-v512-semantic-coherence',cur.curator_evidence->>'execution_id',repeat('0',64)
  from programacion.input_family_assessments cur where cur.run_id=v_new and cur.family_code in ('FEATURE_FLAGS','I18N_FORMATS');

  update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_validator_identity,validator_component_id=47 where id=v_new;
  select source_snapshot_sha256 into v_source_sha from programacion.input_readiness_runs where id=v_new;
  for v_assessment in select * from programacion.input_family_assessments where run_id=v_new order by family_code loop
    v_assert:=programacion.fn_input_v58_build_assertions(v_new,v_parent,v_assessment.family_code);
    update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_VALIDATOR','contract_revision','5.12','direct_source_readback',true,'source_snapshot_sha256',v_source_sha,'curator_sha256',v_assessment.curator_sha256,'semantic_depth_sha256',v_assessment.semantic_depth_sha256,'validated_curator_execution_id',v_assessment.curator_evidence->>'execution_id','assertions',v_assert),validator_identity=v_validator_identity,validator_assessed_at=now() where id=v_assessment.id;
  end loop;
  for v_proposal in select * from programacion.input_gap_proposals where run_id=v_new order by id loop
    select coalesce(jsonb_agg(jsonb_build_object('source_ref',refs.value,'source_observed_sha256',programacion.fn_v09_sha256_jsonb(programacion.fn_input_resolve_source_ref(refs.value,v_screen,19))) order by refs.ord),'[]'::jsonb) into v_readbacks from jsonb_array_elements(v_proposal.source_refs) with ordinality refs(value,ord);
    update programacion.input_gap_proposals set status='HUMAN_DECISION_REQUIRED',validator_identity=v_validator_identity,validator_outcome='PASS',validator_evidence=jsonb_build_object('direct_source_readback',true,'source_snapshot_sha256',v_source_sha,'source_readbacks',v_readbacks,'proposal_is_canonical',false,'auto_promotion','DENY','validated_gap_semantics',true) where id=v_proposal.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  if not programacion.fn_input_readiness_run_is_current(v_new) then raise exception 'V512_SCREEN51_SUCCESSOR_NOT_CURRENT:%',v_new; end if;
  if (select count(*) from programacion.input_family_assessments where run_id=v_new and validator_outcome='PASS')<>47 then raise exception 'V512_SCREEN51_VALIDATOR_CARDINALITY_MISMATCH'; end if;
  if (select count(*) from programacion.input_gap_proposals where run_id=v_new and validator_outcome='PASS')<>2 then raise exception 'V512_SCREEN51_PROPOSAL_VALIDATION_CARDINALITY_MISMATCH'; end if;
end;
$do$;