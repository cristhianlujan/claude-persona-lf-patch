-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.5 / PAULO-070
-- EXPLICIT_FINGERPRINT
-- Canonical Curator fingerprint is produced before INSERT with fn_v09_sha256_jsonb.
-- Storage guard verifies the supplied fingerprint and no longer synthesizes it.

begin;

create or replace function programacion.fn_guard_input_family_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_status text; v_contract_version integer; v_contract_pin_revision text; v_contract_pin_sha text;
  v_pantalla_id integer; v_version_id bigint; v_families jsonb; v_payload jsonb; v_ref jsonb; v_mode text; v_states text[];
  v_governance_family boolean; v_has_independent_ekb boolean; v_has_contract_ref boolean;
  v_contract_schema integer; v_contract_revision text; v_contract_payload jsonb; v_contract_sha text;
  v_non_absence_authority boolean:=false; v_stage_cfg jsonb;
  v_allow_story_incomplete boolean:=false; v_allow_impl_incomplete boolean:=false; v_allow_qa_incomplete boolean:=false; v_allow_prod_incomplete boolean:=false;
begin
  select r.status,r.contract_version,r.contract_revision,r.contract_snapshot_sha256,r.pantalla_id,r.version_id,q.valor_config->'families'
    into v_status,v_contract_version,v_contract_pin_revision,v_contract_pin_sha,v_pantalla_id,v_version_id,v_families
  from programacion.input_readiness_runs r join lf_ops.reglas q on q.id=r.universe_rule_id where r.id=new.run_id;
  if v_status is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND'; end if;

  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',
         jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)
    into v_contract_schema,v_contract_revision,v_contract_payload
  from programacion.contratos c where c.version_id=v_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_contract_version<>v_contract_schema or v_contract_pin_revision is distinct from v_contract_revision or v_contract_pin_sha is distinct from v_contract_sha then
    raise exception 'INPUT_READINESS_CONTRACT_PIN_STALE_FOR_CURATOR:%',new.family_code;
  end if;
  v_stage_cfg:=coalesce(v_contract_payload->'especificacion'->'family_stage_requirements'->new.family_code,'{}'::jsonb);
  v_allow_story_incomplete:=coalesce((v_stage_cfg->>'allow_story_ready_when_incomplete')::boolean,false);
  v_allow_impl_incomplete:=coalesce((v_stage_cfg->>'allow_implementation_ready_when_incomplete')::boolean,false);
  v_allow_qa_incomplete:=coalesce((v_stage_cfg->>'allow_qa_ready_when_incomplete')::boolean,false);
  v_allow_prod_incomplete:=coalesce((v_stage_cfg->>'allow_production_ready_when_incomplete')::boolean,false);

  if v_status<>'CURATING' then raise exception 'CURATOR_INSERT_CLOSED_FOR_RUN_STATUS_%',v_status; end if;
  if jsonb_typeof(v_families)<>'array' or not (v_families ? new.family_code) then raise exception 'FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',new.family_code; end if;
  if jsonb_typeof(new.source_refs)<>'array' or jsonb_array_length(new.source_refs)=0 then raise exception 'SOURCE_REFS_REQUIRED:%',new.family_code; end if;
  if new.severity not in ('P0','P1','P2','P3','P4') then raise exception 'SEVERITY_MUST_BE_RESOLVED_P0_P4:%:%',new.family_code,new.severity; end if;

  for v_ref in select value from jsonb_array_elements(new.source_refs) loop
    if v_ref->>'kind' in ('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','CURRENT_VISUAL_ARTIFACT','CAPABILITY_ABSENCE') then
      if not (v_ref ? 'pantalla_id') or (v_ref->>'pantalla_id')::integer<>v_pantalla_id then
        raise exception 'SCREEN_SCOPED_SOURCE_REF_REQUIRES_EXPLICIT_PANTALLA_ID:%:%',new.family_code,v_ref->>'kind';
      end if;
    end if;
    if v_ref->>'kind'<>'CAPABILITY_ABSENCE' then v_non_absence_authority:=true; end if;
    perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);
  end loop;

  if new.applicability='NOT_APPLICABLE' and not v_non_absence_authority then
    raise exception 'NOT_APPLICABLE_REQUIRES_POSITIVE_NON_ABSENCE_AUTHORITY:%',new.family_code;
  end if;

  v_governance_family:=new.family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS');
  if v_governance_family then
    select coalesce(bool_or(programacion.fn_input_source_authority_class(value)='INDEPENDENT_EKB'),false),coalesce(bool_or(value->>'kind'='CONTRACT'),false)
      into v_has_independent_ekb,v_has_contract_ref from jsonb_array_elements(new.source_refs);
    if not v_has_independent_ekb then raise exception 'GOVERNANCE_FAMILY_REQUIRES_INDEPENDENT_EKB_AUTHORITY:%',new.family_code; end if;
    if v_has_contract_ref then raise exception 'GOVERNANCE_FAMILY_CONTRACT_CANNOT_SELF_AUTHORIZE:%',new.family_code; end if;
  end if;

  if coalesce(new.curator_evidence->>'contract_revision','')<>v_contract_revision then raise exception 'CURATOR_EVIDENCE_CONTRACT_REVISION_MISMATCH:%',new.family_code; end if;

  v_states:=array[new.coverage_status,new.well_defined_status,new.story_ready_status,new.implementation_ready_status,new.qa_ready_status,new.production_ready_status];
  if new.applicability='APPLICABLE' and 'NOT_APPLICABLE'=any(v_states) then raise exception 'APPLICABLE_FAMILY_CANNOT_HAVE_NOT_APPLICABLE_READINESS:%',new.family_code; end if;
  if new.applicability='NOT_APPLICABLE' and exists(select 1 from unnest(v_states) s where s<>'NOT_APPLICABLE') then raise exception 'NOT_APPLICABLE_FAMILY_REQUIRES_ALL_NOT_APPLICABLE_READINESS:%',new.family_code; end if;
  if new.applicability='UNRESOLVED' then
    if new.story_ready_status='READY' then raise exception 'UNRESOLVED_APPLICABILITY_CANNOT_BE_STORY_READY:%',new.family_code; end if;
    if new.severity<>'P0' then raise exception 'UNRESOLVED_APPLICABILITY_REQUIRES_P0:%',new.family_code; end if;
  end if;
  if new.applicability='APPLICABLE' then
    if new.story_ready_status<>'READY' and new.severity<>'P0' then raise exception 'STORY_OPEN_REQUIRES_P0:%',new.family_code; end if;
    if new.story_ready_status='READY' and (new.coverage_status in ('MISSING','PENDING','BLOCKED') or new.well_defined_status in ('MISSING','PENDING','BLOCKED')) and not v_allow_story_incomplete then raise exception 'STORY_READY_REQUIRES_NON_MISSING_COVERAGE_AND_DEFINITION:%',new.family_code; end if;
    if new.implementation_ready_status='READY' and new.story_ready_status<>'READY' then raise exception 'IMPLEMENTATION_READY_REQUIRES_STORY_READY:%',new.family_code; end if;
    if new.implementation_ready_status='READY' and (new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE') and not v_allow_impl_incomplete then raise exception 'IMPLEMENTATION_READY_REQUIRES_COMPLETE_COVERAGE_DEFINITION:%',new.family_code; end if;
    if new.qa_ready_status='READY' and new.implementation_ready_status<>'READY' then raise exception 'QA_READY_REQUIRES_IMPLEMENTATION_READY:%',new.family_code; end if;
    if new.qa_ready_status='READY' and (new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE') and not v_allow_qa_incomplete then raise exception 'QA_READY_REQUIRES_COMPLETE_COVERAGE_DEFINITION:%',new.family_code; end if;
    if new.production_ready_status='READY' and new.qa_ready_status<>'READY' then raise exception 'PRODUCTION_READY_REQUIRES_QA_READY:%',new.family_code; end if;
    if new.production_ready_status='READY' and (new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE') and not v_allow_prod_incomplete then raise exception 'PRODUCTION_READY_REQUIRES_COMPLETE_COVERAGE_DEFINITION:%',new.family_code; end if;
  end if;

  if new.validator_outcome<>'PENDING' or new.validator_identity is not null or new.validator_sha256 is not null or new.validator_assessed_at is not null or new.validator_findings<>'[]'::jsonb or new.validator_evidence<>'{}'::jsonb then raise exception 'CURATOR_CANNOT_PREVALIDATE:%',new.family_code; end if;
  v_mode:='DB_MANIFEST_V'||v_contract_version::text;
  new.freshness:=jsonb_build_object('mode',v_mode,'status','PENDING_RUN_SNAPSHOT');
  v_payload:=jsonb_build_object(
    'run_id',new.run_id,'family_code',new.family_code,'severity',new.severity,'applicability',new.applicability,
    'coverage_status',new.coverage_status,'well_defined_status',new.well_defined_status,'story_ready_status',new.story_ready_status,
    'implementation_ready_status',new.implementation_ready_status,'qa_ready_status',new.qa_ready_status,'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,'rationale',new.rationale,'blockers',new.blockers,'negative_requirements',new.negative_requirements,
    'test_obligations',new.test_obligations,'freshness',new.freshness,'curator_evidence',new.curator_evidence,
    'subject_coverage',new.subject_coverage,'threat_coverage',new.threat_coverage,'semantic_depth_sha256',new.semantic_depth_sha256
  );
  if coalesce(new.curator_sha256,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'M5_5_CURATOR_FINGERPRINT_REQUIRED:%',new.family_code;
  end if;
  if new.curator_sha256 is distinct from programacion.fn_v09_sha256_jsonb(v_payload) then
    raise exception 'M5_5_CURATOR_FINGERPRINT_MISMATCH:%',new.family_code;
  end if;
  return new;
end;
$function$;

create or replace function programacion.fn_input_governance_bootstrap_materialize_v1(p_pantalla_id integer,p_consumer text,p_curator_identity text)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_version bigint:=19; v_code text; v_active boolean; v_pre jsonb; v_existing bigint; v_existing_status text; v_rule_id integer; v_families jsonb; v_family_count integer;
  v_universe_sha text; v_contract_schema integer; v_contract_revision text; v_curator_component bigint; v_run bigint; v_class jsonb; v_family text; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb;
  v_freshness jsonb; v_evidence jsonb; v_subject jsonb; v_threat jsonb; v_semantic_sha text; v_curator_sha text;
begin
  perform pg_advisory_xact_lock(hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text,0));
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null); if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;
  select id,status into v_existing,v_existing_status from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_existing_status in ('CURATING','VALIDATING') then return jsonb_build_object('status',case when v_existing_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,'run_id',v_existing,'required_role',case when v_existing_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,'promotion_authorized',false,'production_authorized',false); end if;
  if exists(select 1 from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED') then raise exception 'BOOTSTRAP_REQUIRES_NO_COMPLETED_PREDECESSOR:%',p_pantalla_id; end if;
  select id,valor_config->'families' into v_rule_id,v_families from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001'; v_family_count:=jsonb_array_length(v_families);
  v_universe_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('rule_code','B2B-RULE-STORY-READINESS-001','families',v_families));
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR';
  if v_rule_id is null or v_family_count<>47 or v_contract_revision is distinct from (programacion.fn_input_contract_clause_v1(v_version,'INPUT_READINESS_CONTRACT',array['family_stage_requirements'])->>'contract_revision') or v_curator_component is null then raise exception 'BOOTSTRAP_GOVERNANCE_DEPENDENCY_UNRESOLVED'; end if;
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_version,p_pantalla_id,v_rule_id,null,'CURATING',jsonb_build_object('mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','decision','DEC-INPUT-GOV-BOOTSTRAP-001','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_universe_sha,v_family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_run;
  for v_family in select value from jsonb_array_elements_text(v_families) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id,v_family,v_version);
    v_freshness:=jsonb_build_object('mode','DB_MANIFEST_V'||v_contract_schema::text,'status','PENDING_RUN_SNAPSHOT');
    v_subject:=case when v_family in ('DESIGN_SYSTEM','SECURITY') then programacion.fn_input_subject_depth_expected(p_pantalla_id,v_family) else '[]'::jsonb end;
    v_threat:=case when v_family='SECURITY' then programacion.fn_input_security_threat_expected(p_pantalla_id) else '[]'::jsonb end;
    v_semantic_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',v_family,'subject_coverage',v_subject,'threat_coverage',v_threat));
    v_evidence:=jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'direct_source_readback',true,'semantic_policy','GOVERNED_CANONICAL_BOOTSTRAP_NO_INVENTION','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe','semantic_depth_sha256',v_semantic_sha);
    v_curator_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('run_id',v_run,'family_code',v_family,'severity',v_class->>'severity','applicability',v_class->>'applicability','coverage_status',v_class->>'coverage_status','well_defined_status',v_class->>'well_defined_status','story_ready_status',v_class->>'story_ready_status','implementation_ready_status',v_class->>'implementation_ready_status','qa_ready_status',v_class->>'qa_ready_status','production_ready_status',v_class->>'production_ready_status','source_refs',v_class->'source_refs','rationale',v_class->>'rationale','blockers',v_class->'blockers','negative_requirements',v_class->'negative_requirements','test_obligations',v_class->'test_obligations','freshness',v_freshness,'curator_evidence',v_evidence,'subject_coverage',v_subject,'threat_coverage',v_threat,'semantic_depth_sha256',v_semantic_sha));
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_run,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations',v_freshness,v_evidence,v_curator_sha,'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,v_subject,v_threat,v_semantic_sha);
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_run; if v_count<>47 then raise exception 'BOOTSTRAP_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_run,'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',47,'required_role','INPUT_VALIDATOR','write_performed',true,'bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id integer,p_consumer text,p_curator_identity text)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'); v_code text; v_active boolean; v_pre jsonb; v_existing bigint; v_existing_status text;
  v_rule_id integer; v_families jsonb; v_family_count integer; v_universe_sha text; v_contract_schema integer; v_contract_revision text;
  v_curator_component bigint; v_run bigint; v_class jsonb; v_family text; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb; v_prop jsonb;
  v_freshness jsonb; v_evidence jsonb; v_subject jsonb; v_threat jsonb; v_semantic_sha text; v_curator_sha text;
begin
  perform pg_advisory_xact_lock(hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text,0));
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null); if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;
  select id,status into v_existing,v_existing_status from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_existing_status in ('CURATING','VALIDATING') then return jsonb_build_object('status',case when v_existing_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,'run_id',v_existing,'required_role',case when v_existing_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,'promotion_authorized',false,'production_authorized',false); end if;
  if exists(select 1 from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED') then raise exception 'BOOTSTRAP_REQUIRES_NO_COMPLETED_PREDECESSOR:%',p_pantalla_id; end if;
  select id,valor_config->'families' into v_rule_id,v_families from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001'; v_family_count:=jsonb_array_length(v_families); v_universe_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('rule_code','B2B-RULE-STORY-READINESS-001','families',v_families));
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR'; if v_rule_id is null or v_family_count<>47 or v_contract_revision is null or v_curator_component is null then raise exception 'BOOTSTRAP_GOVERNANCE_DEPENDENCY_UNRESOLVED'; end if;
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_version,p_pantalla_id,v_rule_id,null,'CURATING',jsonb_build_object('mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','decision','DEC-INPUT-GOV-BOOTSTRAP-001','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_universe_sha,v_family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_run;
  for v_family in select value from jsonb_array_elements_text(v_families) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,v_family,v_version);
    v_freshness:=jsonb_build_object('mode','DB_MANIFEST_V'||v_contract_schema::text,'status','PENDING_RUN_SNAPSHOT');
    v_subject:=case when v_family in ('DESIGN_SYSTEM','SECURITY') then programacion.fn_input_subject_depth_expected(p_pantalla_id,v_family) else '[]'::jsonb end;
    v_threat:=case when v_family='SECURITY' then programacion.fn_input_security_threat_expected(p_pantalla_id) else '[]'::jsonb end;
    v_semantic_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',v_family,'subject_coverage',v_subject,'threat_coverage',v_threat));
    v_evidence:=jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'direct_source_readback',true,'semantic_policy','GOVERNED_CANONICAL_BOOTSTRAP_NO_INVENTION','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe','semantic_depth_sha256',v_semantic_sha);
    v_curator_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('run_id',v_run,'family_code',v_family,'severity',v_class->>'severity','applicability',v_class->>'applicability','coverage_status',v_class->>'coverage_status','well_defined_status',v_class->>'well_defined_status','story_ready_status',v_class->>'story_ready_status','implementation_ready_status',v_class->>'implementation_ready_status','qa_ready_status',v_class->>'qa_ready_status','production_ready_status',v_class->>'production_ready_status','source_refs',v_class->'source_refs','rationale',v_class->>'rationale','blockers',v_class->'blockers','negative_requirements',v_class->'negative_requirements','test_obligations',v_class->'test_obligations','freshness',v_freshness,'curator_evidence',v_evidence,'subject_coverage',v_subject,'threat_coverage',v_threat,'semantic_depth_sha256',v_semantic_sha));
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_run,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations',v_freshness,v_evidence,v_curator_sha,'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,v_subject,v_threat,v_semantic_sha);
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_run; if v_count<>47 then raise exception 'BOOTSTRAP_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_run);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_run,'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',47,'required_role','INPUT_VALIDATOR','write_performed',true,'bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_recurate_v2(p_pantalla_id integer,p_consumer text,p_curator_identity text)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_parent record; v_contract_schema int; v_contract_revision text; v_curator_component bigint; v_new bigint; v_family text;
  v_class jsonb; v_graph jsonb; v_count int; v_exec_id text:=gen_random_uuid()::text; v_prop jsonb; v_payload jsonb;
  v_freshness jsonb; v_evidence jsonb; v_subject jsonb; v_threat jsonb; v_semantic_sha text; v_curator_sha text;
begin
  perform pg_advisory_xact_lock(hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text,0));
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select * into v_parent from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' order by id desc limit 1;
  if not found then return programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id,p_consumer,p_curator_identity); end if;
  if programacion.fn_input_readiness_run_is_current(v_parent.id) then return jsonb_build_object('status','NOOP_CURRENT','run_id',v_parent.id,'required_role','NONE','promotion_authorized',false,'production_authorized',false); end if;
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_RECURATION_CONTRACT_REVISION_UNSUPPORTED:%',v_contract_revision; end if;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR';
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_parent.version_id,v_parent.pantalla_id,v_parent.universe_rule_id,v_parent.id,'CURATING',v_parent.scope || jsonb_build_object('mode','RUNTIME_GOVERNED_RECURATION_V2','parent_run_id',v_parent.id,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_parent.universe_snapshot_sha256,v_parent.family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_new;
  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);
  for v_family in select value from jsonb_array_elements_text((select valor_config->'families' from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001')) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph);
    v_freshness:=jsonb_build_object('mode','DB_MANIFEST_V'||v_contract_schema::text,'status','PENDING_RUN_SNAPSHOT');
    v_subject:=case when v_family in ('DESIGN_SYSTEM','SECURITY') then programacion.fn_input_subject_depth_expected(p_pantalla_id,v_family) else '[]'::jsonb end;
    v_threat:=case when v_family='SECURITY' then programacion.fn_input_security_threat_expected(p_pantalla_id) else '[]'::jsonb end;
    v_semantic_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',v_family,'subject_coverage',v_subject,'threat_coverage',v_threat));
    v_evidence:=jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'parent_run_id',v_parent.id,'direct_source_readback',true,'semantic_policy','GOVERNED_RECURATION_FROM_CANONICAL_SOURCES','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe','semantic_depth_sha256',v_semantic_sha);
    v_curator_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('run_id',v_new,'family_code',v_family,'severity',v_class->>'severity','applicability',v_class->>'applicability','coverage_status',v_class->>'coverage_status','well_defined_status',v_class->>'well_defined_status','story_ready_status',v_class->>'story_ready_status','implementation_ready_status',v_class->>'implementation_ready_status','qa_ready_status',v_class->>'qa_ready_status','production_ready_status',v_class->>'production_ready_status','source_refs',v_class->'source_refs','rationale',v_class->>'rationale','blockers',v_class->'blockers','negative_requirements',v_class->'negative_requirements','test_obligations',v_class->'test_obligations','freshness',v_freshness,'curator_evidence',v_evidence,'subject_coverage',v_subject,'threat_coverage',v_threat,'semantic_depth_sha256',v_semantic_sha));
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_new,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations',v_freshness,v_evidence,v_curator_sha,'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,v_subject,v_threat,v_semantic_sha);
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_new; if v_count<>47 then raise exception 'INPUT_RECURATION_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_new);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent.id,'pantalla_id',p_pantalla_id,'family_count',47,'required_role','INPUT_VALIDATOR','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_recurate_source_stale_v1(p_pantalla_id integer,p_consumer text,p_curator_identity text,p_parent_run_id bigint)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_parent programacion.input_readiness_runs%rowtype; v_contract_schema integer; v_contract_revision text; v_curator_component bigint; v_new bigint; v_family text; v_class jsonb; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_prop jsonb; v_payload jsonb; v_delta jsonb; v_changed integer:=0; v_affected integer:=0; v_successor_required boolean:=false; v_resolution_errors integer:=0; v_graph jsonb;
  v_freshness jsonb; v_evidence jsonb; v_subject jsonb; v_threat jsonb; v_semantic_sha text; v_curator_sha text;
begin
  perform pg_advisory_xact_lock(hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text,0));
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select * into v_parent from programacion.input_readiness_runs where id=p_parent_run_id and version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null;
  if not found then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_INVALID:%',p_parent_run_id; end if;
  if p_parent_run_id is distinct from (select id from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' order by id desc limit 1) then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_NOT_LATEST:%',p_parent_run_id; end if;
  v_delta:=programacion.fn_input_freshness_delta(p_parent_run_id); v_changed:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0); v_affected:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0); v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);
  select count(*) into v_resolution_errors from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value) where x.value->>'state'='RESOLUTION_ERROR';
  if v_delta->>'run_state'<>'STALE' or v_changed<=0 or v_affected<=0 or v_successor_required or v_resolution_errors<>0 then raise exception 'INPUT_SOURCE_STALE_RECURATION_PROOF_INVALID:run=% summary=%',p_parent_run_id,v_delta->'summary'; end if;
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_RECURATION_CONTRACT_REVISION_UNSUPPORTED:%',v_contract_revision; end if;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR'; if v_curator_component is null then raise exception 'INPUT_CURATOR_COMPONENT_UNRESOLVED'; end if;
  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,v_version);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_parent.version_id,v_parent.pantalla_id,v_parent.universe_rule_id,v_parent.id,'CURATING',v_parent.scope || jsonb_build_object('mode','RUNTIME_GOVERNED_RECURATION_V2','parent_run_id',v_parent.id,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','runtime','input-governance-curator-v1','source_stale_proof','INPUT_FRESHNESS_DELTA_V1','source_stale_affected_family_count',v_affected,'classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT','promotion_authorized',false,'production_authorized',false),v_parent.universe_snapshot_sha256,v_parent.family_count,v_contract_schema,p_curator_identity,v_curator_component) returning id into v_new;
  for v_family in select value from jsonb_array_elements_text((select valor_config->'families' from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001')) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(p_pantalla_id,v_family,v_version,v_graph);
    v_freshness:=jsonb_build_object('mode','DB_MANIFEST_V'||v_contract_schema::text,'status','PENDING_RUN_SNAPSHOT');
    v_subject:=case when v_family in ('DESIGN_SYSTEM','SECURITY') then programacion.fn_input_subject_depth_expected(p_pantalla_id,v_family) else '[]'::jsonb end;
    v_threat:=case when v_family='SECURITY' then programacion.fn_input_security_threat_expected(p_pantalla_id) else '[]'::jsonb end;
    v_semantic_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',v_family,'subject_coverage',v_subject,'threat_coverage',v_threat));
    v_evidence:=jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'parent_run_id',v_parent.id,'direct_source_readback',true,'semantic_policy','GOVERNED_RECURATION_FROM_CANONICAL_SOURCES','remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe','source_stale_proof','INPUT_FRESHNESS_DELTA_V1','classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT','semantic_depth_sha256',v_semantic_sha);
    v_curator_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('run_id',v_new,'family_code',v_family,'severity',v_class->>'severity','applicability',v_class->>'applicability','coverage_status',v_class->>'coverage_status','well_defined_status',v_class->>'well_defined_status','story_ready_status',v_class->>'story_ready_status','implementation_ready_status',v_class->>'implementation_ready_status','qa_ready_status',v_class->>'qa_ready_status','production_ready_status',v_class->>'production_ready_status','source_refs',v_class->'source_refs','rationale',v_class->>'rationale','blockers',v_class->'blockers','negative_requirements',v_class->'negative_requirements','test_obligations',v_class->'test_obligations','freshness',v_freshness,'curator_evidence',v_evidence,'subject_coverage',v_subject,'threat_coverage',v_threat,'semantic_depth_sha256',v_semantic_sha));
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_new,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations',v_freshness,v_evidence,v_curator_sha,'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,v_subject,v_threat,v_semantic_sha);
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_new; if v_count<>47 then raise exception 'INPUT_RECURATION_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_new);
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent.id,'pantalla_id',p_pantalla_id,'family_count',47,'required_role','INPUT_VALIDATOR','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,'source_stale_proof','INPUT_FRESHNESS_DELTA_V1','affected_family_count',v_affected,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id integer,p_consumer text,p_curator_identity text,p_force_selftest boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_curator_component_id bigint; v_component_count integer; v_code text; v_active boolean; v_current bigint; v_latest bigint; v_latest_status text; v_parent bigint; v_new bigint; v_contract_schema integer; v_contract_revision text; v_contract_sha text; v_parent_contract_sha text; v_family_count integer; v_assessed integer; v_pre jsonb; a record; v_payload jsonb; v_classifier jsonb;
  v_freshness jsonb; v_evidence jsonb; v_subject jsonb; v_threat jsonb; v_semantic_sha text; v_curator_sha text; v_assessment_exec_id text;
begin
  perform pg_advisory_xact_lock(hashtextextended('LF_INPUT_GOVERNANCE_RUN_PAIR:'||v_version::text||':'||p_pantalla_id::text,0));
  select count(*),min(id) into v_component_count,v_curator_component_id from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR';
  if v_component_count<>1 then raise exception 'INPUT_GOVERNANCE_CURATOR_COMPONENT_BINDING_AMBIGUOUS_OR_MISSING version=% count=%',v_version,v_component_count; end if;
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id; if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if; if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null); if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;
  select id into v_current from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null and programacion.fn_input_readiness_run_is_current(id) order by id desc limit 1;
  if v_current is not null and not p_force_selftest then return jsonb_build_object('status','NOOP_CURRENT','run_id',v_current,'required_role','NONE','promotion_authorized',false,'production_authorized',false); end if;
  select id,status into v_latest,v_latest_status from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_latest is not null and v_latest_status in ('CURATING','VALIDATING') and not p_force_selftest then return jsonb_build_object('status',case when v_latest_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,'run_id',v_latest,'required_role',case when v_latest_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,'promotion_authorized',false,'production_authorized',false); end if;
  select id,contract_snapshot_sha256,family_count into v_parent,v_parent_contract_sha,v_family_count from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' order by id desc limit 1;
  if v_parent is null then
    v_payload:=jsonb_build_object('status','BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED','pantalla_id',p_pantalla_id,'screen_code',v_code,'required_role','HUMAN_OR_GOVERNED_SEMANTIC_BOOTSTRAP','write_performed',false,'reason','NO_COMPLETED_PREDECESSOR_TO_REBIND','proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false);
    return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;
  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)) into v_contract_schema,v_contract_revision,v_contract_sha from programacion.contratos c where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_READINESS_CONTRACT_NOT_RESOLVABLE:%',v_version; end if;
  if v_parent_contract_sha is distinct from v_contract_sha then return programacion.fn_input_governance_recurate_v2(p_pantalla_id,p_consumer,p_curator_identity); end if;
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  select version_id,pantalla_id,universe_rule_id,id,'CURATING',scope||jsonb_build_object('mode','RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1','parent_run_id',id,'runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),universe_snapshot_sha256,family_count,v_contract_schema,p_curator_identity,v_curator_component_id from programacion.input_readiness_runs where id=v_parent returning id into v_new;
  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code loop
    v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version);
    v_freshness:=jsonb_build_object('mode','DB_MANIFEST_V'||v_contract_schema::text,'status','PENDING_RUN_SNAPSHOT');
    v_subject:=case when a.family_code in ('DESIGN_SYSTEM','SECURITY') then programacion.fn_input_subject_depth_expected(p_pantalla_id,a.family_code) else '[]'::jsonb end;
    v_threat:=case when a.family_code='SECURITY' then programacion.fn_input_security_threat_expected(p_pantalla_id) else '[]'::jsonb end;
    v_semantic_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('family_code',a.family_code,'subject_coverage',v_subject,'threat_coverage',v_threat));
    v_assessment_exec_id:=gen_random_uuid()::text;
    v_evidence:=jsonb_build_object('component_id',v_curator_component_id,'execution_id',v_assessment_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'parent_run_id',v_parent,'parent_assessment_id',a.id,'direct_source_readback',true,'semantic_policy','NO_INVENTION_REBIND_ONLY','bootstrap_classifier_sha256',v_classifier->>'classifier_sha256','semantic_depth_sha256',v_semantic_sha);
    v_curator_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('run_id',v_new,'family_code',a.family_code,'severity',a.severity,'applicability',a.applicability,'coverage_status',a.coverage_status,'well_defined_status',a.well_defined_status,'story_ready_status',a.story_ready_status,'implementation_ready_status',a.implementation_ready_status,'qa_ready_status',a.qa_ready_status,'production_ready_status',a.production_ready_status,'source_refs',coalesce(v_classifier->'source_refs','[]'::jsonb),'rationale',a.rationale,'blockers',a.blockers,'negative_requirements',a.negative_requirements,'test_obligations',a.test_obligations,'freshness',v_freshness,'curator_evidence',v_evidence,'subject_coverage',v_subject,'threat_coverage',v_threat,'semantic_depth_sha256',v_semantic_sha));
    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256)
    values(v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,coalesce(v_classifier->'source_refs','[]'::jsonb),a.rationale,a.blockers,a.negative_requirements,a.test_obligations,v_freshness,v_evidence,v_curator_sha,'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,v_subject,v_threat,v_semantic_sha);
  end loop;
  select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_new; if v_assessed<>v_family_count then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_UNIVERSE_INCOMPLETE expected=% actual=%',v_family_count,v_assessed; end if;
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent,'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',v_family_count,'curator_identity',p_curator_identity,'run_status','CURATING','required_role','INPUT_VALIDATOR','write_performed',true,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

do $verify$
declare
  v_bad integer;
  v_guard text;
begin
  select count(*) into v_bad
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_governance_bootstrap_materialize_v1',
      'fn_input_governance_bootstrap_materialize_v2',
      'fn_input_governance_recurate_source_stale_v1',
      'fn_input_governance_recurate_v2',
      'fn_input_governance_curator_rebind_v1'
    )
    and p.prosrc like '%repeat(''0'',64)%';
  if v_bad<>0 then raise exception 'M5_5_ZERO_SHA_PRODUCER_REMAINS:%',v_bad; end if;

  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure) into v_guard;
  if position('M5_5_CURATOR_FINGERPRINT_MISMATCH' in v_guard)=0
     or position('new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload)' in replace(v_guard,' ',''))>0 then
    raise exception 'M5_5_GUARD_NOT_VERIFY_ONLY';
  end if;
end;
$verify$;

commit;
