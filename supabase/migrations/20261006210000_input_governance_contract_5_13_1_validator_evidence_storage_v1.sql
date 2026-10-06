-- CONTRACT-5.13.1 candidate. DRAFT ONLY: do not apply without Claude review + explicit Cristhian OK.
-- Prerequisite for R5-D/R5-E. R5-C remains valid under 5.13.
begin;

do $preflight$
declare
  v_active bigint;
  v_active_ids text;
  v_revision text;
  v_contract_sha text;
  r record;
begin
  select c.especificacion->>'contract_revision',
         programacion.fn_v09_sha256_jsonb(jsonb_build_object(
           'id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,
           'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion
         ))
    into v_revision,v_contract_sha
  from programacion.contratos c
  where c.version_id=19
    and c.contrato_codigo='INPUT_READINESS_CONTRACT'
    and c.estado='defined'
    and c.fail_closed;

  if v_revision is distinct from '5.13'
     or v_contract_sha is distinct from 'e2db44d0bc4aeb6f5205d95f84c3366d37cf1644b5ec69dfd3240c4c82bbf25b' then
    raise exception 'CONTRACT_5131_BASE_DRIFT revision=% sha=%',
      coalesce(v_revision,'<NULL>'),coalesce(v_contract_sha,'<NULL>');
  end if;

  for r in
    select * from (values
      ('programacion.fn_guard_input_family_semantic_depth_v510()','34368d67fbc7c1cf234a7be0c76f1d76'),
      ('programacion.fn_guard_input_na_positive_authority_v512()','4db6bd12af2ece03171627cd14e310f9'),
      ('programacion.fn_guard_input_stage_earliest_boundary()','150b5acf8fb918ff37d81fd1ce6705dc'),
      ('programacion.fn_guard_input_validator_semantic_coherence_v512()','5f47ef6f1e0a8d5ee8ccd830ef9ba297'),
      ('programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)','4921a8d69a47e037212edaae7738475e')
    ) x(sig,expected_md5)
  loop
    if to_regprocedure(r.sig) is null then
      raise exception 'CONTRACT_5131_REQUIRED_FUNCTION_MISSING:%',r.sig;
    end if;
    if md5(pg_get_functiondef(to_regprocedure(r.sig)::oid)) is distinct from r.expected_md5 then
      raise exception 'CONTRACT_5131_FUNCTION_BASE_DRIFT:% expected=% actual=%',
        r.sig,r.expected_md5,md5(pg_get_functiondef(to_regprocedure(r.sig)::oid));
    end if;
  end loop;

  select count(*),string_agg(id::text,',' order by id)
    into v_active,v_active_ids
  from programacion.input_readiness_runs
  where invalidated_at is null
    and status in ('CURATING','VALIDATING');

  if v_active<>0 then
    raise exception 'CONTRACT_5131_NONTERMINAL_RUNS_PRESENT count=% ids=%',
      v_active,coalesce(v_active_ids,'');
  end if;
end;
$preflight$;

update programacion.contratos c
set especificacion =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          c.especificacion,
          '{contract_revision}','"5.13.1"'::jsonb,true
        ),
        '{revision_lineage}',
        coalesce(c.especificacion->'revision_lineage','{}'::jsonb)
        || jsonb_build_object(
          'previous_revision','5.13',
          'previous_contract_sha256','e2db44d0bc4aeb6f5205d95f84c3366d37cf1644b5ec69dfd3240c4c82bbf25b',
          'revision_reason','R5_LOGICAL_VALIDATOR_EVIDENCE_STORAGE_REPRESENTATION',
          'migration_mode','GOVERNED_CONTRACT_REVISION',
          'production_authorized',false
        ),true
      ),
      '{validator_evidence_required_fields_scope}',
      '"LOGICAL_REHYDRATED_EVIDENCE"'::jsonb,true
    ),
    '{validator_evidence_storage_contract}',
    jsonb_build_object(
      'schema_version','input-validator-evidence-storage/v1',
      'assertions_logical_required',true,
      'logical_field','assertions',
      'physical_representations',jsonb_build_array('INLINE_ASSERTIONS','ASSERTION_SET_SHA256'),
      'assertion_set_table','programacion.input_validator_assertion_sets_v1',
      'rehydrator','programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)',
      'reference_integrity','ASSERTION_SET_SHA256_EQUALS_CANONICAL_ASSERTIONS_SHA256',
      'validator_sha256_basis','LOGICAL_REHYDRATED_EVIDENCE',
      'storage_compaction','SEMANTICALLY_NEUTRAL_REPRESENTATION_TRANSFORM'
    ),true
  )
where c.version_id=19
  and c.contrato_codigo='INPUT_READINESS_CONTRACT'
  and c.estado='defined'
  and c.fail_closed
  and c.especificacion->>'contract_revision'='5.13';

CREATE OR REPLACE FUNCTION programacion.fn_guard_input_family_semantic_depth_v510()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare v_revision text; v_pantalla_id integer; v_expected_subject jsonb:='[]'::jsonb; v_expected_threat jsonb:='[]'::jsonb; v_bad integer:=0; v_expected_count integer:=0;
begin
  select r.contract_revision,r.pantalla_id into v_revision,v_pantalla_id from programacion.input_readiness_runs r where r.id=coalesce(new.run_id,old.run_id);
  if v_revision not in ('5.10','5.11','5.12','5.13','5.13.1') then return new; end if;
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
end$function$;
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_na_positive_authority_v512()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_revision text;
  v_version_id bigint;
  v_pantalla_id integer;
  v_authority jsonb;
begin
  select contract_revision,version_id,pantalla_id
    into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs where id=new.run_id;
  if (v_revision is null or v_revision not in ('5.12','5.13','5.13.1')) or new.applicability<>'NOT_APPLICABLE' then
    return new;
  end if;
  v_authority := programacion.fn_input_na_positive_authority_v512(new.family_code,v_pantalla_id,v_version_id);
  if coalesce((v_authority->>'qualified')::boolean,false) is not true then
    raise exception 'V512_NOT_APPLICABLE_REQUIRES_EXPLICIT_SEMANTIC_EXCLUSION:%:%',v_pantalla_id,new.family_code;
  end if;
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_stage_earliest_boundary()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_revision text;
  v_version_id bigint;
  v_pantalla_id integer;
  v_cfg jsonb;
  v_stage text;
  v_incomplete boolean;
  v_conditional boolean;
  v_authority_applies boolean;
begin
  select r.contract_revision,r.version_id,r.pantalla_id
    into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs r
  where r.id=new.run_id;

  if v_revision not in ('5.10','5.11','5.12','5.13','5.13.1') or new.applicability<>'APPLICABLE' then
    return new;
  end if;

  select coalesce(c.especificacion->'family_stage_requirements'->new.family_code,'{}'::jsonb)
    into v_cfg
  from programacion.contratos c
  where c.version_id=v_version_id
    and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if coalesce(v_cfg,'{}'::jsonb)='{}'::jsonb then
    raise exception 'CONTRACT_STAGE_UNRESOLVED:%',new.family_code;
  end if;

  v_incomplete:=new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE';
  if not v_incomplete then
    return new;
  end if;

  v_conditional:=coalesce((v_cfg->>'conditional')::boolean,false);
  v_authority_applies:=programacion.fn_input_stage_authority_applies_v1(
    new.family_code,v_pantalla_id,v_version_id,new.coverage_status,new.well_defined_status
  );

  if v_conditional and not v_authority_applies then
    if new.story_ready_status='READY' or new.severity<>'P0' then
      raise exception 'STAGE_CONDITIONAL_AUTHORITY_MISSING:%',new.family_code;
    end if;
    return new;
  end if;

  v_stage:=upper(coalesce(
    case when v_conditional then v_cfg->>'eligible_coverage_required_by' end,
    v_cfg->>'coverage_required_by',''
  ));

  if v_stage not in ('STORY','IMPLEMENTATION','QA','PRODUCTION') then
    raise exception 'CONTRACT_STAGE_UNRESOLVED:%',new.family_code;
  end if;

  if v_stage='STORY' then
    if new.story_ready_status='READY' or new.severity<>'P0' then
      raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P0 actual=%',new.family_code,new.severity;
    end if;
  elsif v_stage='IMPLEMENTATION' then
    if new.story_ready_status<>'READY' then
      raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:STORY',new.family_code;
    end if;
    if new.severity<>'P1' then
      raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P1 actual=%',new.family_code,new.severity;
    end if;
  elsif v_stage='QA' then
    if new.story_ready_status<>'READY' or new.implementation_ready_status<>'READY' then
      raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:PRE_QA',new.family_code;
    end if;
    if new.severity<>'P2' then
      raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P2 actual=%',new.family_code,new.severity;
    end if;
  elsif v_stage='PRODUCTION' then
    if new.story_ready_status<>'READY' or new.implementation_ready_status<>'READY' or new.qa_ready_status<>'READY' then
      raise exception 'STAGE_AUTHORITY_EARLIER_STAGE_OVERBLOCK:%:PRE_PRODUCTION',new.family_code;
    end if;
    if new.severity<>'P3' then
      raise exception 'STAGE_AUTHORITY_SEVERITY_MISMATCH:% expected=P3 actual=%',new.family_code,new.severity;
    end if;
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_validator_semantic_coherence_v512()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_logical_validator_evidence jsonb;
  v_revision text;
  v_version_id bigint;
  v_pantalla_id integer;
  v_assertion jsonb;
  v_eval jsonb;
  v_positive_requirement boolean := false;
  v_na_authority jsonb;
  v_blocker jsonb;
  v_false_missing boolean := false;
  v_graph jsonb;
  v_rules jsonb;
  v_otp_present boolean := false;
  v_a11y_core_complete boolean := false;
begin
  if old.validator_outcome<>'PENDING' or new.validator_outcome='PENDING' then return new; end if;
  v_logical_validator_evidence:=programacion.fn_input_validator_evidence_rehydrate_v1(new.validator_evidence);
  select contract_revision,version_id,pantalla_id into v_revision,v_version_id,v_pantalla_id
  from programacion.input_readiness_runs where id=old.run_id;
  if (v_revision is null or v_revision not in ('5.12','5.13','5.13.1')) then return new; end if;

  if jsonb_typeof(v_logical_validator_evidence->'assertions')='array' then
    for v_assertion in select value from jsonb_array_elements(v_logical_validator_evidence->'assertions')
    loop
      if coalesce(v_assertion->>'operator','')='CONTAINS'
         and jsonb_typeof(v_assertion->'expected')='array'
         and jsonb_array_length(v_assertion->'expected')>0
         and coalesce(v_assertion->'source_ref'->>'kind','') in ('SCREEN_CANONICAL_GRAPH','SCREEN_RULE_SET','RULE','SECURITY_POLICY_SET','SCREEN_STATE_SET') then
        v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
        if coalesce((v_eval->>'passed')::boolean,false) is true then v_positive_requirement:=true; end if;
      end if;
    end loop;
  end if;

  if new.validator_outcome='PASS' and old.applicability='NOT_APPLICABLE' then
    v_na_authority:=programacion.fn_input_na_positive_authority_v512(old.family_code,v_pantalla_id,v_version_id);
    if coalesce((v_na_authority->>'qualified')::boolean,false) is not true then
      raise exception 'V512_VALIDATOR_NA_WITHOUT_POSITIVE_EXCLUSION:%:%',v_pantalla_id,old.family_code;
    end if;
  end if;

  if new.validator_outcome='PASS' and v_positive_requirement then
    if old.family_code in ('REDUCED_MOTION','FORCED_COLORS_CONTRAST') then
      if old.applicability<>'APPLICABLE' or old.coverage_status<>'COMPLETE' or old.well_defined_status<>'COMPLETE' then
        raise exception 'V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH:%:% expected=APPLICABLE/COMPLETE/COMPLETE actual=%/%/%',v_pantalla_id,old.family_code,old.applicability,old.coverage_status,old.well_defined_status;
      end if;
    elsif old.family_code='THEME_LIGHT_DARK_SYSTEM' then
      if old.applicability<>'APPLICABLE' or old.coverage_status not in ('PARTIAL','COMPLETE') or old.well_defined_status not in ('PARTIAL','COMPLETE') then
        raise exception 'V512_VALIDATOR_THEME_SEMANTICS_MISMATCH:% actual=%/%/%',v_pantalla_id,old.applicability,old.coverage_status,old.well_defined_status;
      end if;
    end if;

    for v_blocker in select value from jsonb_array_elements(coalesce(old.blockers,'[]'::jsonb))
    loop
      if (old.family_code='REDUCED_MOTION' and v_blocker->>'code'='REDUCED_MOTION_REQUIREMENT_MISSING')
         or (old.family_code='FORCED_COLORS_CONTRAST' and v_blocker->>'code'='FORCED_COLORS_REQUIREMENT_MISSING')
         or (old.family_code='THEME_LIGHT_DARK_SYSTEM' and v_blocker->>'code'='THEME_REQUIREMENTS_NOT_LINKED') then
        v_false_missing:=true;
      end if;
    end loop;
    if v_false_missing then raise exception 'V512_VALIDATOR_FALSE_MISSING_BLOCKER_CONTRADICTS_SOURCE:%:%',v_pantalla_id,old.family_code; end if;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(v_pantalla_id,v_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  if new.validator_outcome='PASS' and old.family_code='ACCESSIBILITY' then
    select count(distinct r->>'rule_code')=4 into v_a11y_core_complete
    from jsonb_array_elements(v_rules) r
    where r->>'rule_code' in ('B2B-RULE-A11Y-001','B2B-RULE-A11Y-002','B2B-RULE-A11Y-003','B2B-RULE-A11Y-004');
    if v_a11y_core_complete and (old.coverage_status<>'COMPLETE' or old.well_defined_status<>'COMPLETE') then
      raise exception 'V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE:%',v_pantalla_id;
    end if;
  end if;

  if new.validator_outcome='PASS' and old.family_code='MFA_OTP_SSO' then
    select exists(
      select 1 from jsonb_array_elements(v_rules) r
      where (r->'config' ? 'otp_operation_id') or (r->'config' ? 'otp_policy_id') or (r->'config' ? 'email_otp_policy_code')
    ) into v_otp_present;
    if v_otp_present and old.applicability='NOT_APPLICABLE' then
      raise exception 'V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE:%',v_pantalla_id;
    end if;
  end if;
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION programacion.fn_input_deterministic_assess(p_subject jsonb, p_family text, p_graph jsonb, p_contract jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_screen int; v_version bigint; v_family text:=upper(nullif(trim(p_family),''));
  v_policy jsonb; v_ref jsonb; v_resolved jsonb; v_stage jsonb; v_assessment jsonb; v_payload jsonb;
  v_graph_sha text; v_contract_sha text;
begin
  if jsonb_typeof(p_subject)<>'object' or jsonb_typeof(p_graph)<>'object' or jsonb_typeof(p_contract)<>'object' then raise exception 'DETERMINISTIC_ASSESS_INVALID_INPUT'; end if;
  if upper(coalesce(p_subject->>'source_class','DETERMINISTIC'))='SEMANTIC' then raise exception 'DETERMINISTIC_ASSESS_SEMANTIC_INPUT_FORBIDDEN'; end if;
  v_screen:=nullif(p_subject->>'pantalla_id','')::int;
  v_version:=coalesce(nullif(p_subject->>'version_id','')::bigint,nullif(p_graph->>'agent_contract_version_id','')::bigint);
  if v_screen is null or v_version is null or v_family is null then raise exception 'DETERMINISTIC_ASSESS_IDENTITY_REQUIRED'; end if;
  if p_contract->>'contract_revision' not in ('5.13','5.13.1') then raise exception 'DETERMINISTIC_ASSESS_CONTRACT_REVISION'; end if;
  if p_graph->>'graph_contract' is distinct from p_contract->>'screen_graph_contract' then raise exception 'DETERMINISTIC_ASSESS_GRAPH_CONTRACT'; end if;
  if nullif(p_graph->>'agent_contract_version_id','')::bigint is distinct from v_version then raise exception 'DETERMINISTIC_ASSESS_VERSION_PIN'; end if;
  v_policy:=p_contract->'family_stage_requirements'->v_family;
  if v_policy is null then raise exception 'DETERMINISTIC_ASSESS_FAMILY'; end if;
  if coalesce(p_subject->>'applicability','')='' or coalesce(p_subject->>'coverage_status','')='' or coalesce(p_subject->>'well_defined_status','')='' then raise exception 'DETERMINISTIC_ASSESS_STATUS_REQUIRED'; end if;
  v_ref:=jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_screen);
  v_resolved:=programacion.fn_input_resolve_source_ref(v_ref,v_screen,v_version);
  v_graph_sha:=programacion.fn_v09_sha256_jsonb(p_graph);
  if v_resolved->>'observed_sha256' is distinct from v_graph_sha then raise exception 'DETERMINISTIC_ASSESS_GRAPH_DRIFT'; end if;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(p_contract);
  v_stage:=programacion.fn_input_stage_resolve_v2(v_family,v_screen,v_version,p_subject->>'coverage_status',p_subject->>'well_defined_status');
  v_assessment:=p_subject-'pantalla_id'-'version_id'-'source_class';
  if jsonb_typeof(v_assessment->'blockers') is distinct from 'array' then v_assessment:=jsonb_set(v_assessment,'{blockers}','[]'::jsonb,true); end if;
  v_assessment:=programacion.fn_input_apply_stage_authority_v2(v_assessment,v_screen,v_family,v_version);
  v_payload:=jsonb_build_object('contract','DETERMINISTIC_ASSESS_V1','subject_identity',jsonb_build_object('pantalla_id',v_screen,'version_id',v_version),'family_code',v_family,'contract_revision',p_contract->>'contract_revision','contract_sha256',v_contract_sha,'graph_contract',p_graph->>'graph_contract','graph_sha256',v_graph_sha,'graph_resolution',jsonb_build_object('ref',v_ref,'observed_sha256',v_resolved->>'observed_sha256','matches_provided',true),'family_policy',v_policy,'stage_resolution',v_stage,'assessment',v_assessment,'semantic_boundary','EXCLUDED','semantic_calls','[]'::jsonb);
  return v_payload||jsonb_build_object('result_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;$function$;

do $postcheck$
declare
  v_spec jsonb;
begin
  select especificacion into v_spec
  from programacion.contratos
  where version_id=19
    and contrato_codigo='INPUT_READINESS_CONTRACT'
    and estado='defined'
    and fail_closed;

  if v_spec->>'contract_revision'<>'5.13.1' then
    raise exception 'CONTRACT_5131_REVISION_POSTCHECK';
  end if;
  if not (v_spec->'validator_evidence_required_fields' ? 'assertions') then
    raise exception 'CONTRACT_5131_ASSERTIONS_LOGICAL_REQUIREMENT_MISSING';
  end if;
  if v_spec->>'validator_evidence_required_fields_scope'<>'LOGICAL_REHYDRATED_EVIDENCE' then
    raise exception 'CONTRACT_5131_LOGICAL_SCOPE_POSTCHECK';
  end if;
  if v_spec->'validator_evidence_storage_contract'->>'storage_compaction'
       <> 'SEMANTICALLY_NEUTRAL_REPRESENTATION_TRANSFORM' then
    raise exception 'CONTRACT_5131_STORAGE_COMPACTION_POSTCHECK';
  end if;
  if position('5.13.1' in pg_get_functiondef('programacion.fn_guard_input_family_semantic_depth_v510()'::regprocedure))=0
     or position('5.13.1' in pg_get_functiondef('programacion.fn_guard_input_na_positive_authority_v512()'::regprocedure))=0
     or position('5.13.1' in pg_get_functiondef('programacion.fn_guard_input_stage_earliest_boundary()'::regprocedure))=0
     or position('5.13.1' in pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure))=0
     or position('5.13.1' in pg_get_functiondef('programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)'::regprocedure))=0 then
    raise exception 'CONTRACT_5131_FUNCTION_POSTCHECK';
  end if;
end;
$postcheck$;

commit;
