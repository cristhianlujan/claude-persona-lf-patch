do $do$
declare
  v_test_run bigint; v_parent bigint:=178; v_cur text:='INPUT_CURATOR:v0.5r1-v512-negative-suite'; v_val text:='INPUT_VALIDATOR:v0.5r1-v512-negative-suite';
  v_assessment_id bigint; v_proposal_id bigint; v_assert jsonb; v_sha text; v_sem text; v_cur_sha text; v_exec text;
  v_passed jsonb:='[]'::jsonb; v_rel boolean; v_def text;
begin
  begin
    insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
    select version_id,pantalla_id,universe_rule_id,'CURATING',scope||jsonb_build_object('mode','NEGATIVE_TEST_V512_18','ephemeral',true),universe_snapshot_sha256,family_count,contract_version,v_cur,curator_component_id
    from programacion.input_readiness_runs where id=v_parent returning id into v_test_run;

    begin
      insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
      select v_test_run,family_code,'P4','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE',source_refs,'negative test','[]','[]','[]',jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'contract_revision','5.12'),repeat('0',64)
      from programacion.input_family_assessments where run_id=v_parent and family_code='FEATURE_FLAGS';
      raise exception 'NEG_DID_NOT_REJECT_NA_CAPABILITY';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_NA_CAPABILITY' or sqlerrm not like 'V512_NOT_APPLICABLE_REQUIRES_EXPLICIT_SEMANTIC_EXCLUSION:%' then raise; end if;
      v_passed:=v_passed||'["NA_WITH_CAPABILITY_ABSENCE_PLUS_EMPTY_RULE_SET"]'::jsonb;
    end;

    begin
      insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
      select v_test_run,family_code,'P4','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE',source_refs,'negative test','[]','[]','[]',jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'contract_revision','5.12'),repeat('0',64)
      from programacion.input_family_assessments where run_id=v_parent and family_code='STATES';
      raise exception 'NEG_DID_NOT_REJECT_NA_STATE';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_NA_STATE' or sqlerrm not like 'V512_NOT_APPLICABLE_REQUIRES_EXPLICIT_SEMANTIC_EXCLUSION:%' then raise; end if;
      v_passed:=v_passed||'["NA_WITH_EMPTY_STATE_SET"]'::jsonb;
    end;

    begin
      insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
      select v_test_run,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,'positive control','[]','[]','[]',jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'contract_revision','5.12'),repeat('0',64)
      from programacion.input_family_assessments where run_id=v_parent and family_code='PERMISSIONS';
      raise exception 'NEG_EXPECTED_ACCEPT_PERMISSIONS';
    exception when others then
      if sqlerrm<>'NEG_EXPECTED_ACCEPT_PERMISSIONS' then raise; end if;
      v_passed:=v_passed||'["NA_WITH_EXPLICIT_AUTH_EXCLUSION_ACCEPTED"]'::jsonb;
    end;

    begin
      insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
      select v_test_run,family_code,'P4','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE','NOT_APPLICABLE',source_refs,'negative test','[]','[]','[]',jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'contract_revision','5.12'),repeat('0',64)
      from programacion.input_family_assessments where run_id=v_parent and family_code='MFA_OTP_SSO';
      raise exception 'NEG_DID_NOT_REJECT_OTP_NA';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_OTP_NA' or sqlerrm not like 'V512_NOT_APPLICABLE_REQUIRES_EXPLICIT_SEMANTIC_EXCLUSION:%' then raise; end if;
      v_passed:=v_passed||'["OTP_SOURCE_EXISTS_BUT_MFA_OTP_SSO_NA"]'::jsonb;
    end;

    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    select v_test_run,src.family_code,
      case when src.family_code='REDUCED_MOTION' then 'P1' else src.severity end,
      src.applicability,
      case when src.family_code='REDUCED_MOTION' then 'MISSING' else src.coverage_status end,
      case when src.family_code='REDUCED_MOTION' then 'MISSING' else src.well_defined_status end,
      src.story_ready_status,
      case when src.family_code='REDUCED_MOTION' then 'NOT_READY' else src.implementation_ready_status end,
      case when src.family_code='REDUCED_MOTION' then 'BLOCKED' else src.qa_ready_status end,
      case when src.family_code='REDUCED_MOTION' then 'BLOCKED' else src.production_ready_status end,
      case when src.family_code='PERMISSIONS' then coalesce((select jsonb_agg(e.value) from jsonb_array_elements(src.source_refs) e(value) where e.value->>'kind'<>'RULE'),'[]'::jsonb) else src.source_refs end,
      src.rationale,
      case when src.family_code='FORCED_COLORS_CONTRAST' then src.blockers||'[{"code":"FORCED_COLORS_REQUIREMENT_MISSING","source_ref":"NEGATIVE_SUITE"}]'::jsonb else src.blockers end,
      src.negative_requirements,src.test_obligations,'{}'::jsonb,
      jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'parent_run_id',v_parent,'parent_assessment_id',src.id,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.12','direct_source_readback',true),repeat('0',64),'PENDING','[]','{}',null,null,null,'[]','[]',repeat('0',64)
    from programacion.input_family_assessments src where src.run_id=v_parent order by src.family_code;
    if (select count(*) from programacion.input_family_assessments where run_id=v_test_run)<>47 then raise exception 'NEG_SUITE_CARDINALITY'; end if;

    select id into v_assessment_id from programacion.input_family_assessments where run_id=v_test_run and family_code='FEATURE_FLAGS';
    begin
      insert into programacion.input_gap_proposals(run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,source_refs,evidence_refs,status,curator_identity,curator_execution_id,curator_sha256)
      select v_test_run,id,'FEATURE_FLAGS','NEG_NO_EVIDENCE','RESEARCH_EVIDENCED_PROPOSAL','{"x":1}','{}',source_refs,'[]','PROPOSED',v_cur,curator_evidence->>'execution_id',repeat('0',64) from programacion.input_family_assessments where id=v_assessment_id;
      raise exception 'NEG_DID_NOT_REJECT_PROPOSAL_EVIDENCE';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_PROPOSAL_EVIDENCE' or sqlerrm not like 'V512_PROPOSAL_EVIDENCE_REQUIRED:%' then raise; end if;
      v_passed:=v_passed||'["PROPOSAL_WITHOUT_REQUIRED_EVIDENCE"]'::jsonb;
    end;

    begin
      insert into programacion.input_gap_proposals(run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,source_refs,evidence_refs,status,curator_identity,curator_execution_id,curator_sha256)
      select v_test_run,id,'FEATURE_FLAGS','NEG_PROPOSAL_SOURCE','HUMAN_DECISION_REQUIRED','{"x":1}','{}','[{"kind":"INPUT_GAP_PROPOSAL","id":999999}]','[]','PROPOSED',v_cur,curator_evidence->>'execution_id',repeat('0',64) from programacion.input_family_assessments where id=v_assessment_id;
      raise exception 'NEG_DID_NOT_REJECT_PROPOSAL_SOURCE';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_PROPOSAL_SOURCE' or sqlerrm not like 'V512_PROPOSAL_CANNOT_USE_PROPOSAL_AS_CANONICAL_SOURCE:%' then raise; end if;
      v_passed:=v_passed||'["PROPOSAL_USED_AS_CANONICAL_SOURCE"]'::jsonb;
    end;

    insert into programacion.input_gap_proposals(run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,source_refs,evidence_refs,status,curator_identity,curator_execution_id,curator_sha256)
    select v_test_run,id,'FEATURE_FLAGS','NEG_VALID_BASE','HUMAN_DECISION_REQUIRED','{"x":1}','{}',source_refs,'[]','PROPOSED',v_cur,curator_evidence->>'execution_id',repeat('0',64) from programacion.input_family_assessments where id=v_assessment_id returning id into v_proposal_id;

    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_test_run;
    select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_test_run;

    begin
      update programacion.input_gap_proposals set status='HUMAN_DECISION_REQUIRED',validator_identity=v_cur,validator_outcome='PASS',validator_evidence=jsonb_build_object('direct_source_readback',true,'source_snapshot_sha256',v_sha,'source_readbacks','[]'::jsonb) where id=v_proposal_id;
      raise exception 'NEG_DID_NOT_REJECT_SELF_VALIDATE';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_SELF_VALIDATE' or sqlerrm not like 'V512_PROPOSAL_VALIDATOR_NOT_INDEPENDENT:%' then raise; end if;
      v_passed:=v_passed||'["CURATOR_SELF_VALIDATES_PROPOSAL"]'::jsonb;
    end;

    begin
      update programacion.input_gap_proposals set status='HUMAN_DECISION_REQUIRED',validator_identity=v_val,validator_outcome='PASS',validator_evidence=jsonb_build_object('direct_source_readback',true,'source_snapshot_sha256',repeat('f',64),'source_readbacks','[]'::jsonb) where id=v_proposal_id;
      raise exception 'NEG_DID_NOT_REJECT_STALE_PROPOSAL';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_STALE_PROPOSAL' or sqlerrm not like 'V512_PROPOSAL_SOURCE_SNAPSHOT_MISMATCH:%' then raise; end if;
      v_passed:=v_passed||'["PROPOSAL_STALE_SOURCE_WITHOUT_REVALIDATION"]'::jsonb;
    end;

    if coalesce((select (especificacion#>>'{proposal_contract,auto_promotion}')='DENY' from programacion.contratos where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT'),false) is not true then raise exception 'NEG_AUTOPROMOTION_NOT_DENIED'; end if;
    v_passed:=v_passed||'["RESEARCH_PROPOSAL_SILENTLY_PROMOTED"]'::jsonb;

    if exists(select 1 from programacion.input_family_assessments a cross join lateral jsonb_array_elements(a.source_refs) s where a.run_id in (175,176,177,178,179) and s->>'kind'='INPUT_GAP_PROPOSAL') then raise exception 'NEG_CANON_FROM_PROPOSAL_FOUND'; end if;
    v_passed:=v_passed||'["CANONICAL_VALUE_ORIGINATES_ONLY_FROM_PROPOSAL"]'::jsonb;

    select id,semantic_depth_sha256,curator_sha256,curator_evidence->>'execution_id' into v_assessment_id,v_sem,v_cur_sha,v_exec from programacion.input_family_assessments where run_id=v_test_run and family_code='REDUCED_MOTION';
    v_assert:=programacion.fn_input_v58_build_assertions(v_test_run,v_parent,'REDUCED_MOTION');
    begin
      update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]',validator_identity=v_val,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_VALIDATOR','contract_revision','5.12','direct_source_readback',true,'source_snapshot_sha256',v_sha,'curator_sha256',v_cur_sha,'semantic_depth_sha256',v_sem,'validated_curator_execution_id',v_exec,'assertions',v_assert),validator_assessed_at=now() where id=v_assessment_id;
      raise exception 'NEG_DID_NOT_REJECT_POSITIVE_MISSING';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_POSITIVE_MISSING' or sqlerrm not like 'V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH:%' then raise; end if;
      v_passed:=v_passed||'["POSITIVE_RULE_ASSERTION_WITH_COVERAGE_MISSING"]'::jsonb;
    end;

    select id,semantic_depth_sha256,curator_sha256,curator_evidence->>'execution_id' into v_assessment_id,v_sem,v_cur_sha,v_exec from programacion.input_family_assessments where run_id=v_test_run and family_code='FORCED_COLORS_CONTRAST';
    v_assert:=programacion.fn_input_v58_build_assertions(v_test_run,v_parent,'FORCED_COLORS_CONTRAST');
    begin
      update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]',validator_identity=v_val,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_VALIDATOR','contract_revision','5.12','direct_source_readback',true,'source_snapshot_sha256',v_sha,'curator_sha256',v_cur_sha,'semantic_depth_sha256',v_sem,'validated_curator_execution_id',v_exec,'assertions',v_assert),validator_assessed_at=now() where id=v_assessment_id;
      raise exception 'NEG_DID_NOT_REJECT_FALSE_MISSING';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_FALSE_MISSING' or sqlerrm not like 'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE:%' then raise; end if;
      v_passed:=v_passed||'["POSITIVE_RULE_ASSERTION_WITH_FALSE_MISSING_BLOCKER"]'::jsonb;
    end;

    select id,semantic_depth_sha256,curator_sha256,curator_evidence->>'execution_id' into v_assessment_id,v_sem,v_cur_sha,v_exec from programacion.input_family_assessments where run_id=v_test_run and family_code='BROWSER_PLATFORM';
    v_assert:=programacion.fn_input_v58_build_assertions(v_test_run,v_parent,'BROWSER_PLATFORM');
    begin
      update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]',validator_identity=v_val,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_VALIDATOR','contract_revision','5.12','direct_source_readback',true,'source_snapshot_sha256',v_sha,'curator_sha256',v_cur_sha,'semantic_depth_sha256',v_sem,'validated_curator_execution_id',v_exec,'assertions',v_assert),validator_assessed_at=now() where id=v_assessment_id;
      raise exception 'NEG_EXPECTED_ACCEPT_SOURCE_SEMANTICS';
    exception when others then
      if sqlerrm<>'NEG_EXPECTED_ACCEPT_SOURCE_SEMANTICS' then raise; end if;
      v_passed:=v_passed||'["SOURCE_PRESENCE_DOES_NOT_EQUAL_SUFFICIENCY"]'::jsonb;
    end;

    select programacion.fn_input_assertion_is_relevant('PERMISSIONS','{"kind":"RULE","codigo":"B2B-RULE-AUTH-033"}'::jsonb,'["observed","valor_config"]'::jsonb) into v_rel;
    if v_rel is not true then raise exception 'NEG_DIRECT_PERMISSION_RULE_NOT_RELEVANT'; end if;
    v_passed:=v_passed||'["PERMISSIONS_DIRECT_RULE_EXCLUSION_RELEVANT"]'::jsonb;

    select programacion.fn_input_assertion_is_relevant('PERMISSIONS','{"kind":"SCREEN_CANONICAL_GRAPH","pantalla_id":54}'::jsonb,'["observed","canonical_contract","rules"]'::jsonb) into v_rel;
    if v_rel is not false then raise exception 'NEG_BROAD_PERMISSION_PATH_ACCEPTED'; end if;
    v_passed:=v_passed||'["PERMISSIONS_GRAPH_RULES_BROAD_PATH_REJECTED"]'::jsonb;

    begin
      perform programacion.fn_input_v58_build_assertions(v_test_run,v_parent,'PERMISSIONS');
      raise exception 'NEG_DID_NOT_REJECT_UNDECLARED_PERMISSION_RULE';
    exception when others then
      if sqlerrm='NEG_DID_NOT_REJECT_UNDECLARED_PERMISSION_RULE' or sqlerrm not like 'ASSERTION_SOURCE_NOT_DECLARED:%' then raise; end if;
      v_passed:=v_passed||'["PERMISSIONS_EXCLUSION_RULE_MUST_BE_DECLARED_SOURCE"]'::jsonb;
    end;

    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_guard_input_family_semantic_depth_v510';
    if position('5.12' in coalesce(v_def,''))=0 or not exists(select 1 from pg_trigger t where t.tgrelid='programacion.input_family_assessments'::regclass and t.tgfoid='programacion.fn_guard_input_family_semantic_depth_v510()'::regprocedure and not t.tgisinternal) then raise exception 'NEG_V512_SEMANTIC_GUARD_INACTIVE'; end if;
    v_passed:=v_passed||'["V512_SEMANTIC_DEPTH_GUARD_ACTIVE"]'::jsonb;

    select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_guard_input_stage_earliest_boundary';
    if position('5.12' in coalesce(v_def,''))=0 or not exists(select 1 from pg_trigger t where t.tgrelid='programacion.input_family_assessments'::regclass and t.tgfoid='programacion.fn_guard_input_stage_earliest_boundary()'::regprocedure and not t.tgisinternal) then raise exception 'NEG_V512_STAGE_GUARD_INACTIVE'; end if;
    v_passed:=v_passed||'["V512_STAGE_BOUNDARY_GUARD_ACTIVE"]'::jsonb;

    if jsonb_array_length(v_passed)<>18 then raise exception 'V512_NEGATIVE_SUITE_COUNT expected=18 actual=%',jsonb_array_length(v_passed); end if;
    raise exception 'V512_NEGATIVE_SANDBOX_ROLLBACK';
  exception when others then
    if sqlerrm<>'V512_NEGATIVE_SANDBOX_ROLLBACK' then raise; end if;
  end;

  if jsonb_array_length(v_passed)<>18 then raise exception 'V512_NEGATIVE_SUITE_NOT_18_AFTER_ROLLBACK:%',v_passed; end if;
end;
$do$;