-- Critical repair, existing REBIND route only. Copy authoritative V2
-- source-integrity evaluation, semantic-scope gate, and proposal phase.
-- No new selector, no family list/constants, no changes to public RPC or ACL.
DO $baseline$
DECLARE v_oid oid:=to_regprocedure('programacion.fn_input_governance_validator_rebind_v1(bigint,text)');
BEGIN
 IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid))<>'474d317d08b91a4b170cb1c0a4145b0a'
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_oid)
    OR pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=v_oid))<>'postgres'
 THEN RAISE EXCEPTION 'IG_VALIDATOR_REBIND_ASSERTION_PARITY_BASELINE_DRIFT'; END IF;
END $baseline$;

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
  v_fail integer;
  v_blocked integer;
  v_pending integer;
  v_pending_before integer;
  v_semantic_required_families text[];
  v_comparison_requested boolean;
  v_outcome text;
  v_findings jsonb;
  v_assertion jsonb;
  v_eval jsonb;
  v_prop jsonb;
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

  if p_validator_identity !~ '^INPUT_VALIDATOR:(EDGE:input-governance-validator-v1|SQL:ig-governed-dispatch-v1):[A-Za-z0-9_-]{6,128}$' then
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

  -- Mirror the already-governed VALIDATE_V2 selection contract. An undeclared
  -- semantic scope is an error, never silent approval of all families.
  v_semantic_required_families:=programacion.fn_input_validator_semantic_scope_v1(p_run_id);

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
  select count(*) into v_pending_before from programacion.input_family_assessments
  where run_id=p_run_id and validator_outcome='PENDING';

  for a in
    select * from programacion.input_family_assessments
    where run_id=p_run_id and validator_outcome='PENDING'
    order by family_code
    limit 3
  loop
    v_comparison_requested:=a.family_code=ANY(v_semantic_required_families);
    -- Preserve V2 provenance-sensitive assertion routing; never replace a
    -- CONTRACT assertion with stale parent evidence.
    v_assertions:=case
      when not exists (
        select 1
        from programacion.input_family_assessments pa
        cross join lateral jsonb_array_elements(
          programacion.fn_input_validator_evidence_rehydrate_v1(pa.validator_evidence)->'assertions'
        ) x(value)
        where pa.run_id=v_parent
          and pa.family_code=a.family_code
          and x.value#>>'{source_ref,kind}'='CONTRACT'
      ) then programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code)
      else programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code)
    end;
    if jsonb_typeof(v_assertions) is distinct from 'array'
       or jsonb_array_length(v_assertions)=0 then
      raise exception 'INPUT_REBIND_VALIDATOR_ASSERTIONS_EMPTY:%',a.family_code;
    end if;
    v_logical_evidence:=jsonb_build_object(
          'component_id',v_validator_component_id,'execution_id',gen_random_uuid()::text,
          'validated_curator_execution_id',a.curator_evidence->>'execution_id',
          'execution_mode','INDEPENDENT_VALIDATOR',
          'runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
          'direct_source_readback',true,'contract_revision',v_contract_revision,
          'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,
          'semantic_depth_sha256',a.semantic_depth_sha256,
          'semantic_conclusion_independence','UNPROVEN',
          'validation_phase','SOURCE_INTEGRITY',
          'semantic_comparison_requested',v_comparison_requested,
          'semantic_independence_credited',false,
          'assertions',v_assertions
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
    -- Hash/rehydration validates evidence transport, not assertion truth.
    -- Evaluate each assertion against its current authoritative source.
    v_findings:='[]'::jsonb;
    for v_assertion in select value from jsonb_array_elements(v_assertions) loop
      v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,a.family_code,v_assertion);
      if coalesce((v_eval->>'passed')::boolean,false) is not true then
        v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
          'finding_type','ASSERTION_FAILURE',
          'finding_code','VALIDATOR_ASSERTION_FAILED',
          'family_code',a.family_code,
          'assertion_class',v_eval->>'assertion_class',
          'source_ref',v_eval->'source_ref','path',v_eval->'path',
          'operator',v_eval->>'operator',
          'expected',v_eval->'expected','actual',v_eval->'actual'
        ));
      end if;
    end loop;
    if jsonb_array_length(v_findings)>0 then
      v_outcome:='FAIL';
    elsif v_comparison_requested then
      v_outcome:='BLOCKED';
      v_findings:=jsonb_build_array(jsonb_build_object(
        'finding_type','INDEPENDENT_SEMANTIC_ORACLE_UNPROVEN',
        'family_code',a.family_code,'source_integrity_passed',true
      ));
    else
      v_outcome:='PASS';
    end if;

    update programacion.input_family_assessments
    set validator_outcome=v_outcome,validator_findings=v_findings,
        validator_evidence=v_physical_evidence,
        validator_identity=p_validator_identity,
        validator_assessed_at=now()
    where id=a.id;
  end loop;

  select count(*) filter(where validator_outcome='PASS' and validator_identity=p_validator_identity),
         count(*) filter(where validator_outcome='FAIL' and validator_identity=p_validator_identity),
         count(*) filter(where validator_outcome='BLOCKED' and validator_identity=p_validator_identity),
         count(*) filter(where validator_outcome='PENDING')
    into v_pass,v_fail,v_blocked,v_pending
  from programacion.input_family_assessments where run_id=p_run_id;

  if v_pass+v_fail+v_blocked+v_pending<>v_family_count then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_CARDINALITY_MISMATCH expected=% pass=% fail=% blocked=% pending=%',
      v_family_count,v_pass,v_fail,v_blocked,v_pending;
  end if;
  if v_pending>0 then
    return jsonb_build_object(
      'status','VALIDATOR_CONTINUE_REQUIRED',
      'run_id',p_run_id,'parent_run_id',v_parent,
      'pantalla_id',v_pantalla_id,'family_count',v_family_count,
      'validator_pass_count',v_pass,'validator_fail_count',v_fail,
      'validator_blocked_count',v_blocked,'pending_count',v_pending,
      'validator_identity',p_validator_identity,'required_role','VALIDATOR_RESUME',
      'promotion_authorized',false,'production_authorized',false
    );
  end if;
  if v_fail>0 or v_blocked>0 then
    return jsonb_build_object(
      'status',case when v_blocked>0 then 'VALIDATION_BLOCKED' else 'VALIDATION_FAILED' end,
      'run_id',p_run_id,'parent_run_id',v_parent,'pantalla_id',v_pantalla_id,
      'family_count',v_family_count,'validator_pass_count',v_pass,
      'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,
      'pending_count',v_pending,'validator_identity',p_validator_identity,
      'promotion_authorized',false,'production_authorized',false
    );
  end if;
  -- Follow V2's ordered transition: after final family, require a separate
  -- proposal-validation invocation, not direct promotion to COMPLETED.
  if v_pending_before>0 then
    return jsonb_build_object(
      'status','VALIDATOR_CONTINUE_REQUIRED','run_id',p_run_id,
      'parent_run_id',v_parent,'pantalla_id',v_pantalla_id,
      'family_count',v_family_count,'validator_pass_count',v_pass,
      'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,
      'pending_count',v_pending,'validator_identity',p_validator_identity,
      'next_phase','PROPOSAL_VALIDATION','promotion_authorized',false,
      'production_authorized',false
    );
  end if;

  v_prop:=programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id,p_validator_identity);
  update programacion.input_readiness_runs
    set status='COMPLETED',validator_completed_at=clock_timestamp()
    where id=p_run_id;

  v_payload:=jsonb_build_object(
    'status','COMPLETED','run_id',p_run_id,'parent_run_id',v_parent,'pantalla_id',v_pantalla_id,
    'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,
    'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,
    'proposal_validation',v_prop,
    'required_role','DISPATCHER_FINALIZE','promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;
DO $verify$
DECLARE v_oid oid:='programacion.fn_input_governance_validator_rebind_v1(bigint,text)'::regprocedure;
DECLARE v_def text:=pg_get_functiondef(v_oid);
BEGIN
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_oid)
    OR position('fn_input_evaluate_assertion(' IN v_def)=0
    OR position('fn_input_validator_semantic_scope_v1(' IN v_def)=0
    OR position('fn_input_governance_validate_gap_proposals_v1(' IN v_def)=0
    OR position('INDEPENDENT_SEMANTIC_ORACLE_UNPROVEN' IN v_def)=0
    OR position('VALIDATOR_CONTINUE_REQUIRED' IN v_def)=0
 THEN RAISE EXCEPTION 'IG_VALIDATOR_REBIND_ASSERTION_PARITY_POSTCHECK_FAILED'; END IF;
END $verify$;
