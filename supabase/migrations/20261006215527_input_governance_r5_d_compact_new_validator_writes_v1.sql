-- R5-D candidate. DRAFT ONLY. Requires CONTRACT-5.13.1 (#1818) first.
do $r5d_preflight$
declare
  v_revision text;
  v_contract_sha text;
  v_actual text;
  v_compact bigint;
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
    and c.estado='defined' and c.fail_closed;

  if v_revision is distinct from '5.13.1'
     or v_contract_sha is distinct from 'dc78d22793bfbb78a3d678b91ffdff39a3499a36d3824c65c181734e80c57516' then
    raise exception 'R5D_CONTRACT_5131_REQUIRED revision=% sha=%',
      coalesce(v_revision,'<NULL>'),coalesce(v_contract_sha,'<NULL>');
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)'::regprocedure));
  if v_actual is distinct from '1fcbd090ac0d38945d61bc385870ab64' then
    raise exception 'R5D_REHYDRATOR_BASE_DRIFT:%',v_actual;
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_family_assessment_update()'::regprocedure));
  if v_actual is distinct from '3992ea214300ed7a4c444667d9927f1e' then
    raise exception 'R5D_ASSESSMENT_GUARD_BASE_DRIFT:%',v_actual;
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_guard_input_validator_semantic_coherence_v512()'::regprocedure));
  if v_actual is distinct from '81d56655cdd96927b62aa3aef7359e35' then
    raise exception 'R5D_SEMANTIC_COHERENCE_5131_REQUIRED:%',v_actual;
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_validate_v1(bigint,text)'::regprocedure));
  if v_actual is distinct from '9a624388dc01183f05f78e8e32d5c5fc' then raise exception 'R5D_WRITER_BASE_DRIFT:bootstrap:%',v_actual; end if;
  v_actual:=md5(pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure));
  if v_actual is distinct from '7970d71ff66d40236bd085a13a0abadd' then raise exception 'R5D_WRITER_BASE_DRIFT:validate_v2:%',v_actual; end if;
  v_actual:=md5(pg_get_functiondef('programacion.fn_input_governance_validator_rebind_v1(bigint,text)'::regprocedure));
  if v_actual is distinct from '1242cb67ae2f6a9713fafe0b1928b266' then raise exception 'R5D_WRITER_BASE_DRIFT:validator_rebind:%',v_actual; end if;

  select count(*) into v_compact
  from programacion.input_family_assessments
  where validator_evidence ? 'assertion_set_sha256';
  if v_compact<>0 then
    raise exception 'R5D_UNEXPECTED_PREEXISTING_COMPACT_ROWS:%',v_compact;
  end if;
end;
$r5d_preflight$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_validate_v1(p_run_id bigint, p_validator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text; v_existing_validator text; v_contract_revision text; v_validator_component bigint; v_source_sha text; v_pass integer;
  v_pre jsonb; v_assertions jsonb; v_expected jsonb; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb; a record; v_assertion_set_sha256 text; v_assertion_set jsonb; v_logical_evidence jsonb; v_physical_evidence jsonb;
begin
  if p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_IDENTITY_INVALID'; end if;
  select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision from programacion.input_readiness_runs where id=p_run_id and version_id=v_version and supersedes_run_id is null and scope->>'mode'='GOVERNED_CANONICAL_BOOTSTRAP_V1';
  if v_status is null then raise exception 'BOOTSTRAP_VALIDATOR_RUN_NOT_FOUND:%',p_run_id; end if; if v_status='COMPLETED' then return jsonb_build_object('status','NOOP_COMPLETED','run_id',p_run_id,'promotion_authorized',false,'production_authorized',false); end if; if p_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',v_pantalla_id,p_run_id); if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR'; end if;
  select id into v_validator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_VALIDATOR'; if v_validator_component is null then raise exception 'BOOTSTRAP_VALIDATOR_COMPONENT_UNRESOLVED'; end if;
  if v_status='CURATING' then if (select count(*) from programacion.input_family_assessments where run_id=p_run_id)<>v_family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE'; end if; update programacion.input_readiness_runs set status='VALIDATING',validator_identity=p_validator_identity,validator_component_id=v_validator_component where id=p_run_id;
  elsif v_status='VALIDATING' then if v_existing_validator is distinct from p_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH'; end if; else raise exception 'BOOTSTRAP_VALIDATOR_INVALID_RUN_STATUS:%',v_status; end if;
  select source_snapshot_sha256,contract_revision into v_source_sha,v_contract_revision from programacion.input_readiness_runs where id=p_run_id;
  for a in select * from programacion.input_family_assessments where run_id=p_run_id order by family_code loop
    v_expected:=programacion.fn_input_governance_bootstrap_classify_v1(v_pantalla_id,a.family_code,v_version);
    if a.curator_evidence->>'bootstrap_classifier_sha256' is distinct from v_expected->>'classifier_sha256' or a.severity is distinct from v_expected->>'severity' or a.applicability is distinct from v_expected->>'applicability' or a.coverage_status is distinct from v_expected->>'coverage_status' or a.well_defined_status is distinct from v_expected->>'well_defined_status' or a.story_ready_status is distinct from v_expected->>'story_ready_status' or a.implementation_ready_status is distinct from v_expected->>'implementation_ready_status' or a.qa_ready_status is distinct from v_expected->>'qa_ready_status' or a.production_ready_status is distinct from v_expected->>'production_ready_status' or a.source_refs is distinct from v_expected->'source_refs' or a.blockers is distinct from v_expected->'blockers' then raise exception 'BOOTSTRAP_VALIDATOR_CLASSIFIER_MISMATCH:%',a.family_code; end if;
    v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code); if jsonb_array_length(v_assertions)=0 then raise exception 'BOOTSTRAP_VALIDATOR_ASSERTIONS_EMPTY:%',a.family_code; end if;
    v_logical_evidence:=jsonb_build_object('component_id',v_validator_component,'execution_id',v_exec_id,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1','direct_source_readback',true,'contract_revision',v_contract_revision,'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'bootstrap_classifier_sha256',v_expected->>'classifier_sha256','assertions',v_assertions);
    v_assertion_set_sha256:=programacion.fn_v09_sha256_jsonb(v_assertions);
    insert into programacion.input_validator_assertion_sets_v1(assertion_set_sha256,assertions)
    values(v_assertion_set_sha256,v_assertions)
    on conflict (assertion_set_sha256) do nothing;
    select s.assertions into v_assertion_set
    from programacion.input_validator_assertion_sets_v1 s
    where s.assertion_set_sha256=v_assertion_set_sha256;
    if not found
       or v_assertion_set is distinct from v_assertions
       or programacion.fn_v09_sha256_jsonb(v_assertion_set) is distinct from v_assertion_set_sha256 then
      raise exception 'R5D_ASSERTION_SET_READBACK_MISMATCH:%',a.family_code;
    end if;
    v_physical_evidence:=(v_logical_evidence-'assertions')
      || jsonb_build_object('assertion_set_sha256',v_assertion_set_sha256);
    if programacion.fn_input_validator_evidence_rehydrate_v1(v_physical_evidence)
         is distinct from v_logical_evidence then
      raise exception 'R5D_LOGICAL_EVIDENCE_REHYDRATION_MISMATCH:%',a.family_code;
    end if;
    update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_evidence=v_physical_evidence,validator_identity=p_validator_identity,validator_assessed_at=now() where id=a.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=p_run_id;
  select count(*) into v_pass from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity; if v_pass<>v_family_count then raise exception 'BOOTSTRAP_VALIDATOR_CARDINALITY_MISMATCH expected=% actual=%',v_family_count,v_pass; end if;
  v_payload:=jsonb_build_object('status','COMPLETED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,'required_role','DISPATCHER_FINALIZE','bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end; $function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validate_v2(p_run_id bigint, p_validator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text;
  v_existing_validator text; v_contract_revision text; v_validator_component bigint; v_source_sha text; v_pass integer; v_pending integer;
  v_pre jsonb; v_assertions jsonb; v_expected jsonb; v_exec_id text:=gen_random_uuid()::text; v_assertion_set_sha256 text; v_assertion_set jsonb; v_logical_evidence jsonb; v_physical_evidence jsonb;
  v_payload jsonb; v_result jsonb; v_prop jsonb; a record; v_pending_before integer;
  v_started timestamptz:=clock_timestamp(); v_completed timestamptz; v_phase_started timestamptz; v_prev_completed timestamptz;
  v_classification_ms bigint:=0; v_assertions_ms bigint:=0; v_ekb_ms bigint:=0; v_gap_ms bigint:=0; v_db_write_ms bigint:=0;
  v_wait_ms bigint:=0; v_chunk_no integer; v_families_processed integer:=0;
begin
  if p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_IDENTITY_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('input_governance_validator_v2:'||p_run_id::text,0));
  select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision
    into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision
  from programacion.input_readiness_runs
  where id=p_run_id and version_id=v_version and scope->>'analysis_revision'='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX';
  if v_status is null then raise exception 'INPUT_REMEDIATION_VALIDATOR_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_status='COMPLETED' then return jsonb_build_object('status','NOOP_COMPLETED','run_id',p_run_id,'promotion_authorized',false,'production_authorized',false); end if;
  if p_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;

  v_phase_started:=clock_timestamp();
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',v_pantalla_id,p_run_id);
  v_ekb_ms:=round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR'; end if;

  select id into v_validator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_VALIDATOR';
  if v_validator_component is null then raise exception 'INPUT_REMEDIATION_VALIDATOR_COMPONENT_UNRESOLVED'; end if;
  if v_status='CURATING' then
    if (select count(*) from programacion.input_family_assessments where run_id=p_run_id)<>v_family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE'; end if;
    v_phase_started:=clock_timestamp();
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=p_validator_identity,validator_component_id=v_validator_component where id=p_run_id;
    v_db_write_ms:=v_db_write_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
  elsif v_status='VALIDATING' then
    if v_existing_validator is distinct from p_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH'; end if;
  else raise exception 'INPUT_REMEDIATION_VALIDATOR_INVALID_RUN_STATUS:%',v_status; end if;

  select source_snapshot_sha256,contract_revision into v_source_sha,v_contract_revision from programacion.input_readiness_runs where id=p_run_id;
  select count(*) into v_pending_before from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PENDING';

  for a in
    select * from programacion.input_family_assessments
    where run_id=p_run_id and validator_outcome='PENDING'
    order by family_code
    limit 10
  loop
    v_phase_started:=clock_timestamp();
    v_expected:=programacion.fn_input_governance_bootstrap_classify_v2(v_pantalla_id,a.family_code,v_version);
    v_classification_ms:=v_classification_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    if a.curator_evidence->>'bootstrap_classifier_sha256' is distinct from v_expected->>'classifier_sha256'
       or a.severity is distinct from v_expected->>'severity'
       or a.applicability is distinct from v_expected->>'applicability'
       or a.coverage_status is distinct from v_expected->>'coverage_status'
       or a.well_defined_status is distinct from v_expected->>'well_defined_status'
       or a.story_ready_status is distinct from v_expected->>'story_ready_status'
       or a.implementation_ready_status is distinct from v_expected->>'implementation_ready_status'
       or a.qa_ready_status is distinct from v_expected->>'qa_ready_status'
       or a.production_ready_status is distinct from v_expected->>'production_ready_status'
       or a.source_refs is distinct from v_expected->'source_refs'
       or a.blockers is distinct from v_expected->'blockers'
    then raise exception 'INPUT_REMEDIATION_VALIDATOR_CLASSIFIER_MISMATCH:%',a.family_code; end if;

    v_phase_started:=clock_timestamp();
    v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code);
    v_assertions_ms:=v_assertions_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    if jsonb_array_length(v_assertions)=0 then raise exception 'INPUT_REMEDIATION_VALIDATOR_ASSERTIONS_EMPTY:%',a.family_code; end if;

    v_phase_started:=clock_timestamp();
    v_logical_evidence:=jsonb_build_object('component_id',v_validator_component,'execution_id',v_exec_id,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1','direct_source_readback',true,'contract_revision',v_contract_revision,'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'bootstrap_classifier_sha256',v_expected->>'classifier_sha256','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','assertions',v_assertions);
    v_assertion_set_sha256:=programacion.fn_v09_sha256_jsonb(v_assertions);
    insert into programacion.input_validator_assertion_sets_v1(assertion_set_sha256,assertions)
    values(v_assertion_set_sha256,v_assertions)
    on conflict (assertion_set_sha256) do nothing;
    select s.assertions into v_assertion_set
    from programacion.input_validator_assertion_sets_v1 s
    where s.assertion_set_sha256=v_assertion_set_sha256;
    if not found
       or v_assertion_set is distinct from v_assertions
       or programacion.fn_v09_sha256_jsonb(v_assertion_set) is distinct from v_assertion_set_sha256 then
      raise exception 'R5D_ASSERTION_SET_READBACK_MISMATCH:%',a.family_code;
    end if;
    v_physical_evidence:=(v_logical_evidence-'assertions')
      || jsonb_build_object('assertion_set_sha256',v_assertion_set_sha256);
    if programacion.fn_input_validator_evidence_rehydrate_v1(v_physical_evidence)
         is distinct from v_logical_evidence then
      raise exception 'R5D_LOGICAL_EVIDENCE_REHYDRATION_MISMATCH:%',a.family_code;
    end if;
    update programacion.input_family_assessments
    set validator_outcome='PASS',validator_findings='[]'::jsonb,
        validator_evidence=v_physical_evidence,
        validator_identity=p_validator_identity,validator_assessed_at=now()
    where id=a.id;
    v_db_write_ms:=v_db_write_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_families_processed:=v_families_processed+1;
  end loop;

  select count(*) into v_pass from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity;
  select count(*) into v_pending from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PENDING';
  if v_pass<v_family_count then
    if v_pending=0 then raise exception 'INPUT_REMEDIATION_VALIDATOR_CARDINALITY_STALLED expected=% pass=%',v_family_count,v_pass; end if;
    v_result:=jsonb_build_object('status','VALIDATOR_CONTINUE_REQUIRED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'pending_count',v_pending,'validator_identity',p_validator_identity,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','promotion_authorized',false,'production_authorized',false);
  elsif v_pending_before>0 then
    v_result:=jsonb_build_object('status','VALIDATOR_CONTINUE_REQUIRED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'pending_count',v_pending,'validator_identity',p_validator_identity,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','next_phase','PROPOSAL_VALIDATION','promotion_authorized',false,'production_authorized',false);
  else
    v_phase_started:=clock_timestamp();
    v_prop:=programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id,p_validator_identity);
    v_gap_ms:=round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_phase_started:=clock_timestamp();
    update programacion.input_readiness_runs set status='COMPLETED',validator_completed_at=now() where id=p_run_id;
    v_db_write_ms:=v_db_write_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_payload:=jsonb_build_object('status','COMPLETED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,'required_role','DISPATCHER_FINALIZE','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','proposal_validation',v_prop,'promotion_authorized',false,'production_authorized',false);
    v_result:=v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  v_completed:=clock_timestamp();
  select coalesce(max(chunk_no),0)+1,max(completed_at) into v_chunk_no,v_prev_completed
  from programacion.input_validator_chunk_timings where run_id=p_run_id and validator_identity=p_validator_identity;
  if v_prev_completed is not null then v_wait_ms:=greatest(0,round(extract(epoch from(v_started-v_prev_completed))*1000)::bigint); end if;
  insert into programacion.input_validator_chunk_timings(
    run_id,validator_identity,chunk_no,route,started_at,completed_at,duration_ms,result_status,
    validator_pass_count,family_count,pending_count,classification_ms,assertions_ms,ekb_ms,gap_proposals_ms,db_write_ms,wait_resume_ms,families_processed
  ) values(
    p_run_id,p_validator_identity,v_chunk_no,'VALIDATE_V2',v_started,v_completed,
    round(extract(epoch from(v_completed-v_started))*1000)::bigint,v_result->>'status',v_pass,v_family_count,v_pending,
    v_classification_ms,v_assertions_ms,v_ekb_ms,v_gap_ms,v_db_write_ms,v_wait_ms,v_families_processed
  );
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_rebind_v1(p_run_id bigint, p_validator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_validator_component_id bigint;
  v_component_count integer;
  v_status text;
  v_pantalla_id integer;
  v_parent bigint;
  v_family_count integer;
  v_curator_identity text;
  v_existing_validator text;
  v_contract_revision text;
  v_source_sha text;
  v_pass integer;
  v_pre jsonb;
  v_assertions jsonb; v_assertion_set_sha256 text; v_assertion_set jsonb; v_logical_evidence jsonb; v_physical_evidence jsonb;
  a record;
  v_payload jsonb;
begin
  select count(*),min(id)
    into v_component_count,v_validator_component_id
  from programacion.componentes
  where version_id=v_version and componente_codigo='INPUT_VALIDATOR';
  if v_component_count<>1 then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_COMPONENT_BINDING_AMBIGUOUS_OR_MISSING version=% count=%',v_version,v_component_count;
  end if;

  if p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_IDENTITY_INVALID';
  end if;

  select status,pantalla_id,supersedes_run_id,family_count,curator_identity,validator_identity,contract_revision
  into v_status,v_pantalla_id,v_parent,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision
  from programacion.input_readiness_runs where id=p_run_id and version_id=v_version;
  if v_status is null then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_status='COMPLETED' then
    return jsonb_build_object('status','NOOP_COMPLETED','run_id',p_run_id,'promotion_authorized',false,'production_authorized',false);
  end if;
  if v_parent is null then raise exception 'INPUT_GOVERNANCE_VALIDATOR_PREDECESSOR_REQUIRED:%',p_run_id; end if;
  if p_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;

  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',v_pantalla_id,p_run_id);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR'; end if;

  if v_status='CURATING' then
    if (select count(*) from programacion.input_family_assessments where run_id=p_run_id)<>v_family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE'; end if;
    update programacion.input_readiness_runs
    set status='VALIDATING',validator_identity=p_validator_identity,validator_component_id=v_validator_component_id
    where id=p_run_id;
  elsif v_status='VALIDATING' then
    if v_existing_validator is distinct from p_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH'; end if;
  else
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_INVALID_RUN_STATUS:%',v_status;
  end if;

  select source_snapshot_sha256,contract_revision into v_source_sha,v_contract_revision
  from programacion.input_readiness_runs where id=p_run_id;

  for a in select * from programacion.input_family_assessments where run_id=p_run_id order by family_code
  loop
    v_assertions:=programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code);
    v_logical_evidence:=jsonb_build_object(
          'component_id',v_validator_component_id,'execution_id',gen_random_uuid()::text,
          'validated_curator_execution_id',a.curator_evidence->>'execution_id',
          'execution_mode','INDEPENDENT_VALIDATOR',
          'runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
          'direct_source_readback',true,'contract_revision',v_contract_revision,
          'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,
          'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assertions
        );
    v_assertion_set_sha256:=programacion.fn_v09_sha256_jsonb(v_assertions);
    insert into programacion.input_validator_assertion_sets_v1(assertion_set_sha256,assertions)
    values(v_assertion_set_sha256,v_assertions)
    on conflict (assertion_set_sha256) do nothing;
    select s.assertions into v_assertion_set
    from programacion.input_validator_assertion_sets_v1 s
    where s.assertion_set_sha256=v_assertion_set_sha256;
    if not found
       or v_assertion_set is distinct from v_assertions
       or programacion.fn_v09_sha256_jsonb(v_assertion_set) is distinct from v_assertion_set_sha256 then
      raise exception 'R5D_ASSERTION_SET_READBACK_MISMATCH:%',a.family_code;
    end if;
    v_physical_evidence:=(v_logical_evidence-'assertions')
      || jsonb_build_object('assertion_set_sha256',v_assertion_set_sha256);
    if programacion.fn_input_validator_evidence_rehydrate_v1(v_physical_evidence)
         is distinct from v_logical_evidence then
      raise exception 'R5D_LOGICAL_EVIDENCE_REHYDRATION_MISMATCH:%',a.family_code;
    end if;
    update programacion.input_family_assessments
    set validator_outcome='PASS',validator_findings='[]'::jsonb,
        validator_evidence=v_physical_evidence,
        validator_identity=p_validator_identity,
        validator_assessed_at=now()
    where id=a.id;
  end loop;

  update programacion.input_readiness_runs set status='COMPLETED' where id=p_run_id;
  select count(*) into v_pass from programacion.input_family_assessments
  where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity;
  if v_pass<>v_family_count then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_CARDINALITY_MISMATCH expected=% actual=%',v_family_count,v_pass; end if;

  v_payload:=jsonb_build_object(
    'status','COMPLETED','run_id',p_run_id,'parent_run_id',v_parent,'pantalla_id',v_pantalla_id,
    'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,
    'required_role','DISPATCHER_FINALIZE','promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

do $r5d_postcheck$
declare
  v_actual text;
begin
  v_actual:=md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_validate_v1(bigint,text)'::regprocedure));
  if v_actual is distinct from 'b9da62afa568dc8551536d6b0713764d' then
    raise exception 'R5D_FINAL_MD5_MISMATCH function=programacion.fn_input_governance_bootstrap_validate_v1(bigint,text) expected=b9da62afa568dc8551536d6b0713764d actual=%',v_actual;
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure));
  if v_actual is distinct from 'e02287a6273b59191b1386801e58c9f3' then
    raise exception 'R5D_FINAL_MD5_MISMATCH function=programacion.fn_input_governance_validate_v2(bigint,text) expected=e02287a6273b59191b1386801e58c9f3 actual=%',v_actual;
  end if;

  v_actual:=md5(pg_get_functiondef('programacion.fn_input_governance_validator_rebind_v1(bigint,text)'::regprocedure));
  if v_actual is distinct from '1881979fffff8dd1f954c3d982592b41' then
    raise exception 'R5D_FINAL_MD5_MISMATCH function=programacion.fn_input_governance_validator_rebind_v1(bigint,text) expected=1881979fffff8dd1f954c3d982592b41 actual=%',v_actual;
  end if;
end;
$r5d_postcheck$;
