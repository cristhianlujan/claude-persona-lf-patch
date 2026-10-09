-- IG_CURATOR_VALIDATOR_REFACTOR_V2: candidate repair of legacy rebind path.
-- Source: exact current pg_get_functiondef readback on 2026-10-08.
-- Not activated by this artifact. REQUIRES independent oracle integration
-- before production use, since it intentionally fails closed on semantic PASS.
-- No new source resolver or judge; uses fn_input_evaluate_assertion.
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
  v_semantic_required_families text[];
  v_comparison_requested boolean;
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
  v_outcome text;
  v_findings jsonb;
  v_assertion jsonb;
  v_evaluation jsonb;
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

  v_semantic_required_families:=programacion.fn_input_validator_semantic_scope_v1(p_run_id);
  for a in select * from programacion.input_family_assessments where run_id=p_run_id order by family_code
  loop
    v_comparison_requested:=a.family_code=ANY(v_semantic_required_families);
    v_assertions:=programacion.fn_input_v58_build_assertions(p_run_id,v_parent,a.family_code);
    if jsonb_typeof(v_assertions) is distinct from 'array' or jsonb_array_length(v_assertions)=0 then
      raise exception 'REBOUND_VALIDATOR_ASSERTIONS_REQUIRED:%',a.family_code;
    end if;
    v_logical_evidence:=jsonb_build_object(
          'component_id',v_validator_component_id,'execution_id',gen_random_uuid()::text,
          'validated_curator_execution_id',a.curator_evidence->>'execution_id',
          'execution_mode','INDEPENDENT_VALIDATOR',
          'runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1',
          'direct_source_readback',true,'contract_revision',v_contract_revision,
          'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,
          'semantic_depth_sha256',a.semantic_depth_sha256,'validation_phase','SOURCE_INTEGRITY','semantic_comparison_requested',v_comparison_requested,'semantic_independence_credited',false,'assertions',v_assertions
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
    -- Rebinding an old assertion is only assertion *construction*, not its
    -- successful independent evaluation. Re-resolve each assertion against
    -- current canonical authority with the existing source evaluator.
    v_findings:='[]'::jsonb;
    for v_assertion in select x.value from jsonb_array_elements(v_assertions) x(value) loop
      v_evaluation:=programacion.fn_input_evaluate_assertion(p_run_id,a.family_code,v_assertion);
      if coalesce((v_evaluation->>'passed')::boolean,false) is not true then
        v_findings:=v_findings||jsonb_build_array(jsonb_build_object(
          'finding_type','SOURCE_ASSERTION_FAILED',
          'path',v_evaluation->'path',
          'operator',v_evaluation->>'operator',
          'expected',v_evaluation->'expected',
          'actual',v_evaluation->'actual'
        ));
      end if;
    end loop;

    if jsonb_array_length(v_findings)>0 then
      v_outcome:='FAIL';
    else
      -- Unrequested families retain their existing source-integrity PASS.
      -- A specifically requested semantic comparison cannot be certified here.
      IF v_comparison_requested THEN
        v_outcome:='BLOCKED';
        v_findings:=jsonb_build_array(jsonb_build_object(
          'finding_type','INDEPENDENT_SEMANTIC_ORACLE_UNPROVEN',
          'phase','SEMANTIC','source_integrity_passed',true,
          'family_code',a.family_code
        ));
      ELSE
        v_outcome:='PASS';
        v_findings:='[]'::jsonb;
      END IF;
    end if;
    update programacion.input_family_assessments
    set validator_outcome=v_outcome,validator_findings=v_findings,
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

  if v_pass+v_fail+v_blocked<>v_family_count then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_CARDINALITY_MISMATCH expected=% actual=%',
      v_family_count,v_pass+v_fail+v_blocked;
  end if;

  -- Preserve ordinary source-integrity completion when no semantic
  -- comparison was requested, without accrediting independent semantics.
  IF v_fail=0 AND v_blocked=0 THEN
    UPDATE programacion.input_readiness_runs SET status='COMPLETED' WHERE id=p_run_id;
  END IF;
  v_payload:=jsonb_build_object(
    'status',case WHEN v_blocked>0 THEN 'VALIDATION_BLOCKED'
                  WHEN v_fail>0 THEN 'VALIDATION_FAILED'
                  ELSE 'COMPLETED' END,
    'run_id',p_run_id,'parent_run_id',v_parent,'pantalla_id',v_pantalla_id,
    'family_count',v_family_count,'validator_pass_count',v_pass,
    'validator_fail_count',v_fail,'validator_blocked_count',v_blocked,
    'validator_identity',p_validator_identity,
    'source_assertions_re_evaluated',true,
    'semantic_comparison_count',cardinality(v_semantic_required_families),
    'validator_pass_scope','SOURCE_INTEGRITY_ONLY',
    'independent_semantic_oracle_verified',false,
    'required_role','DISPATCHER_FINALIZE','promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$

