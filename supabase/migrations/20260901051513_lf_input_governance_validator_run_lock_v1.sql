create or replace function programacion.fn_input_governance_validate_v2(
  p_run_id bigint,
  p_validator_identity text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text;
  v_existing_validator text; v_contract_revision text; v_validator_component bigint; v_source_sha text; v_pass integer; v_pending integer;
  v_pre jsonb; v_assertions jsonb; v_expected jsonb; v_exec_id text:=gen_random_uuid()::text;
  v_payload jsonb; v_prop jsonb; a record;
begin
  if p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_IDENTITY_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('input_governance_validator_v2:'||p_run_id::text,0));
  select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision
    into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision
  from programacion.input_readiness_runs
  where id=p_run_id and version_id=19 and scope->>'analysis_revision'='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX';
  if v_status is null then raise exception 'INPUT_REMEDIATION_VALIDATOR_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_status='COMPLETED' then return jsonb_build_object('status','NOOP_COMPLETED','run_id',p_run_id,'promotion_authorized',false,'production_authorized',false); end if;
  if p_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',v_pantalla_id,p_run_id);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR'; end if;
  select id into v_validator_component from programacion.componentes where version_id=19 and componente_codigo='INPUT_VALIDATOR';
  if v_validator_component is null then raise exception 'INPUT_REMEDIATION_VALIDATOR_COMPONENT_UNRESOLVED'; end if;
  if v_status='CURATING' then
    if (select count(*) from programacion.input_family_assessments where run_id=p_run_id)<>v_family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE'; end if;
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=p_validator_identity,validator_component_id=v_validator_component where id=p_run_id;
  elsif v_status='VALIDATING' then
    if v_existing_validator is distinct from p_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH'; end if;
  else raise exception 'INPUT_REMEDIATION_VALIDATOR_INVALID_RUN_STATUS:%',v_status; end if;
  select source_snapshot_sha256,contract_revision into v_source_sha,v_contract_revision from programacion.input_readiness_runs where id=p_run_id;
  for a in
    select * from programacion.input_family_assessments
    where run_id=p_run_id and validator_outcome='PENDING'
    order by family_code
    limit 10
  loop
    v_expected:=programacion.fn_input_governance_bootstrap_classify_v2(v_pantalla_id,a.family_code,19);
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
    v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code);
    if jsonb_array_length(v_assertions)=0 then raise exception 'INPUT_REMEDIATION_VALIDATOR_ASSERTIONS_EMPTY:%',a.family_code; end if;
    update programacion.input_family_assessments
    set validator_outcome='PASS',validator_findings='[]'::jsonb,
        validator_evidence=jsonb_build_object('component_id',v_validator_component,'execution_id',v_exec_id,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1','direct_source_readback',true,'contract_revision',v_contract_revision,'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'bootstrap_classifier_sha256',v_expected->>'classifier_sha256','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','assertions',v_assertions),
        validator_identity=p_validator_identity,validator_assessed_at=now()
    where id=a.id;
  end loop;
  select count(*) into v_pass from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity;
  select count(*) into v_pending from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PENDING';
  if v_pass<v_family_count then
    if v_pending=0 then raise exception 'INPUT_REMEDIATION_VALIDATOR_CARDINALITY_STALLED expected=% pass=%',v_family_count,v_pass; end if;
    return jsonb_build_object('status','VALIDATOR_CONTINUE_REQUIRED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'pending_count',v_pending,'validator_identity',p_validator_identity,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','promotion_authorized',false,'production_authorized',false);
  end if;
  v_prop:=programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id,p_validator_identity);
  update programacion.input_readiness_runs set status='COMPLETED',validator_completed_at=now() where id=p_run_id;
  v_payload:=jsonb_build_object('status','COMPLETED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,'required_role','DISPATCHER_FINALIZE','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','proposal_validation',v_prop,'promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;