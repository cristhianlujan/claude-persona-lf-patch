-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M4.7 / FAIL_BLOCKED_PERSISTED
-- Deterministic attempt outcomes: PASS only when every assertion evaluates true;
-- assertion mismatch => FAIL; curator/classifier contract mismatch => BLOCKED.
-- No new store/capability. Reuses canonical input_family_assessments receipt surface.

DO $m47_preflight$
DECLARE v_boot text; v_v2 text;
BEGIN
  v_boot:=md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_validate_v1(bigint,text)'::regprocedure));
  v_v2:=md5(pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure));
  IF v_boot IS DISTINCT FROM 'b9da62afa568dc8551536d6b0713764d' THEN
    RAISE EXCEPTION 'M4_7_BOOTSTRAP_BASE_DRIFT:%',coalesce(v_boot,'<NULL>');
  END IF;
  IF v_v2 IS DISTINCT FROM 'e02287a6273b59191b1386801e58c9f3' THEN
    RAISE EXCEPTION 'M4_7_VALIDATE_V2_BASE_DRIFT:%',coalesce(v_v2,'<NULL>');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='programacion.input_family_assessments'::regclass
      AND pg_get_constraintdef(oid) LIKE '%FAIL%'
      AND pg_get_constraintdef(oid) LIKE '%BLOCKED%'
  ) THEN
    RAISE EXCEPTION 'M4_7_TERMINAL_OUTCOME_CONSTRAINT_MISSING';
  END IF;
END
$m47_preflight$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_validate_v1(p_run_id bigint, p_validator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text; v_existing_validator text; v_contract_revision text; v_validator_component bigint; v_source_sha text; v_pass integer; v_fail integer; v_blocked integer;
  v_pre jsonb; v_assertions jsonb; v_expected jsonb; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb; a record; v_assertion_set_sha256 text; v_assertion_set jsonb; v_logical_evidence jsonb; v_physical_evidence jsonb; v_classifier_block boolean; v_outcome text; v_findings jsonb; v_assertion jsonb; v_eval jsonb;
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
    v_classifier_block:=(
      a.curator_evidence->>'bootstrap_classifier_sha256' is distinct from v_expected->>'classifier_sha256'
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
    );
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
    v_outcome:='PASS';
    v_findings:='[]'::jsonb;
    if v_classifier_block then
      v_outcome:='BLOCKED';
      v_findings:=jsonb_build_array(jsonb_build_object(
        'finding_type','CONTRACT_MISMATCH',
        'finding_code','VALIDATOR_CLASSIFIER_MISMATCH',
        'family_code',a.family_code
      ));
    else
      for v_assertion in select value from jsonb_array_elements(v_assertions) loop
        v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,a.family_code,v_assertion);
        if coalesce((v_eval->>'passed')::boolean,false) is not true then
          v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
            'finding_type','ASSERTION_FAILURE',
            'finding_code','VALIDATOR_ASSERTION_FAILED',
            'family_code',a.family_code,
            'assertion_class',v_eval->>'assertion_class',
            'source_ref',v_eval->'source_ref',
            'path',v_eval->'path',
            'operator',v_eval->>'operator',
            'expected',v_eval->'expected',
            'actual',v_eval->'actual'
          ));
        end if;
      end loop;
      if jsonb_array_length(v_findings)>0 then v_outcome:='FAIL'; end if;
    end if;
    update programacion.input_family_assessments
       set validator_outcome=v_outcome,
           validator_findings=v_findings,
           validator_evidence=v_physical_evidence,
           validator_identity=p_validator_identity,
           validator_assessed_at=now()
     where id=a.id;
  end loop;
  select count(*) filter (where validator_outcome='PASS'),
         count(*) filter (where validator_outcome='FAIL'),
         count(*) filter (where validator_outcome='BLOCKED')
    into v_pass,v_fail,v_blocked
  from programacion.input_family_assessments
  where run_id=p_run_id and validator_identity=p_validator_identity;

  if v_fail>0 or v_blocked>0 then
    v_payload:=jsonb_build_object(
      'status',case when v_blocked>0 then 'VALIDATION_BLOCKED' else 'VALIDATION_FAILED' end,
      'run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,
      'validator_pass_count',v_pass,'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,
      'validator_identity',p_validator_identity,'bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1',
      'promotion_authorized',false,'production_authorized',false
    );
    return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  update programacion.input_readiness_runs set status='COMPLETED' where id=p_run_id;
  if v_pass<>v_family_count then raise exception 'BOOTSTRAP_VALIDATOR_CARDINALITY_MISMATCH expected=% actual=%',v_family_count,v_pass; end if;
  v_payload:=jsonb_build_object('status','COMPLETED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,'validator_identity',p_validator_identity,'required_role','DISPATCHER_FINALIZE','bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','promotion_authorized',false,'production_authorized',false);
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
  v_existing_validator text; v_contract_revision text; v_validator_component bigint; v_source_sha text; v_pass integer; v_fail integer; v_blocked integer; v_pending integer;
  v_pre jsonb; v_assertions jsonb; v_expected jsonb; v_exec_id text:=gen_random_uuid()::text; v_assertion_set_sha256 text; v_assertion_set jsonb; v_logical_evidence jsonb; v_physical_evidence jsonb;
  v_payload jsonb; v_result jsonb; v_prop jsonb; a record; v_pending_before integer; v_classifier_block boolean; v_outcome text; v_findings jsonb; v_assertion jsonb; v_eval jsonb;
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
    v_classifier_block:=(
      a.curator_evidence->>'bootstrap_classifier_sha256' is distinct from v_expected->>'classifier_sha256'
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
    );

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
    v_outcome:='PASS';
    v_findings:='[]'::jsonb;
    if v_classifier_block then
      v_outcome:='BLOCKED';
      v_findings:=jsonb_build_array(jsonb_build_object(
        'finding_type','CONTRACT_MISMATCH',
        'finding_code','VALIDATOR_CLASSIFIER_MISMATCH',
        'family_code',a.family_code
      ));
    else
      for v_assertion in select value from jsonb_array_elements(v_assertions) loop
        v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,a.family_code,v_assertion);
        if coalesce((v_eval->>'passed')::boolean,false) is not true then
          v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
            'finding_type','ASSERTION_FAILURE',
            'finding_code','VALIDATOR_ASSERTION_FAILED',
            'family_code',a.family_code,
            'assertion_class',v_eval->>'assertion_class',
            'source_ref',v_eval->'source_ref',
            'path',v_eval->'path',
            'operator',v_eval->>'operator',
            'expected',v_eval->'expected',
            'actual',v_eval->'actual'
          ));
        end if;
      end loop;
      if jsonb_array_length(v_findings)>0 then v_outcome:='FAIL'; end if;
    end if;
    update programacion.input_family_assessments
       set validator_outcome=v_outcome,
           validator_findings=v_findings,
           validator_evidence=v_physical_evidence,
           validator_identity=p_validator_identity,
           validator_assessed_at=now()
     where id=a.id;
    v_db_write_ms:=v_db_write_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_families_processed:=v_families_processed+1;
  end loop;

  select count(*) filter (where validator_outcome='PASS'),
         count(*) filter (where validator_outcome='FAIL'),
         count(*) filter (where validator_outcome='BLOCKED'),
         count(*) filter (where validator_outcome='PENDING')
    into v_pass,v_fail,v_blocked,v_pending
  from programacion.input_family_assessments
  where run_id=p_run_id;

  if v_pass<v_family_count then
    if v_pending=0 then
      v_result:=jsonb_build_object(
        'status',case when v_blocked>0 then 'VALIDATION_BLOCKED' else 'VALIDATION_FAILED' end,
        'run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,
        'validator_pass_count',v_pass,'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,
        'pending_count',v_pending,'validator_identity',p_validator_identity,
        'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
        'promotion_authorized',false,'production_authorized',false
      );
    else
      v_result:=jsonb_build_object(
        'status','VALIDATOR_CONTINUE_REQUIRED',
        'run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,
        'validator_pass_count',v_pass,'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,
        'pending_count',v_pending,'validator_identity',p_validator_identity,
        'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
        'promotion_authorized',false,'production_authorized',false
      );
    end if;
  elsif v_pending_before>0 then
    v_result:=jsonb_build_object('status','VALIDATOR_CONTINUE_REQUIRED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'pending_count',v_pending,'validator_identity',p_validator_identity,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','next_phase','PROPOSAL_VALIDATION','promotion_authorized',false,'production_authorized',false);
  else
    v_phase_started:=clock_timestamp();
    v_prop:=programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id,p_validator_identity);
    v_gap_ms:=round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_phase_started:=clock_timestamp();
    update programacion.input_readiness_runs set status='COMPLETED',validator_completed_at=now() where id=p_run_id;
    v_db_write_ms:=v_db_write_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_payload:=jsonb_build_object('status','COMPLETED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,'validator_identity',p_validator_identity,'required_role','DISPATCHER_FINALIZE','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','proposal_validation',v_prop,'promotion_authorized',false,'production_authorized',false);
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


DO $m47_postcheck$
DECLARE v_boot text; v_v2 text;
BEGIN
  v_boot:=pg_get_functiondef('programacion.fn_input_governance_bootstrap_validate_v1(bigint,text)'::regprocedure);
  v_v2:=pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure);
  IF position('validator_outcome=v_outcome' in v_boot)=0
     OR position('VALIDATOR_CLASSIFIER_MISMATCH' in v_boot)=0
     OR position('VALIDATOR_ASSERTION_FAILED' in v_boot)=0
     OR position('VALIDATION_BLOCKED' in v_boot)=0
     OR position('VALIDATION_FAILED' in v_boot)=0 THEN
    RAISE EXCEPTION 'M4_7_BOOTSTRAP_POSTCHECK_FAILED';
  END IF;
  IF position('validator_outcome=v_outcome' in v_v2)=0
     OR position('VALIDATOR_CLASSIFIER_MISMATCH' in v_v2)=0
     OR position('VALIDATOR_ASSERTION_FAILED' in v_v2)=0
     OR position('VALIDATION_BLOCKED' in v_v2)=0
     OR position('VALIDATION_FAILED' in v_v2)=0 THEN
    RAISE EXCEPTION 'M4_7_VALIDATE_V2_POSTCHECK_FAILED';
  END IF;
END
$m47_postcheck$;
