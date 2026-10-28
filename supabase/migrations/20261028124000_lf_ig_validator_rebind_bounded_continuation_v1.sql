-- Governed fix: the canonical Validator rebind processed 47 families in one
-- transaction and reached SQLSTATE 57014 at the existing 30s public RPC budget.
-- Keep existing entrypoints, independent identity, assertions/rehydration,
-- currentness/handoff checks, and service-role-only ACL unchanged.
-- Only reduce internal work per RPC to 3 PENDING families and return truthful
-- VALIDATOR_CONTINUE_REQUIRED for existing Edge continuation handling.
-- Precondition pins the exact live production function to avoid clobbering drift.
DO $baseline$
DECLARE v_oid oid:=to_regprocedure('programacion.fn_input_governance_validator_rebind_v1(bigint,text)');
BEGIN
 IF v_oid IS NULL OR
    md5(pg_get_functiondef(v_oid))<>'e1142b53d349623b12377cfa69b75872' OR
    NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_oid) OR
    pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=v_oid))<>'postgres'
 THEN RAISE EXCEPTION 'IG_VALIDATOR_REBIND_BASELINE_DRIFT'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure) IS NOT TRUE
 THEN RAISE EXCEPTION 'IG_VALIDATOR_PUBLIC_BOUNDARY_DRIFT'; END IF;
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
  v_pending integer;
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

  for a in
    select * from programacion.input_family_assessments
    where run_id=p_run_id and validator_outcome='PENDING'
    order by family_code
    limit 3
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

  select count(*) into v_pass from programacion.input_family_assessments
  where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity;
  select count(*) into v_pending from programacion.input_family_assessments
  where run_id=p_run_id and validator_outcome='PENDING';

  -- Preserve exact cardinality and identity; never finalize incomplete runs.
  if v_pass+v_pending<>v_family_count then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_CARDINALITY_MISMATCH expected=% pass=% pending=%',
      v_family_count,v_pass,v_pending;
  end if;
  if v_pending>0 then
    return jsonb_build_object(
      'status','VALIDATOR_CONTINUE_REQUIRED',
      'run_id',p_run_id,'parent_run_id',v_parent,
      'pantalla_id',v_pantalla_id,'family_count',v_family_count,
      'validator_pass_count',v_pass,'pending_count',v_pending,
      'validator_identity',p_validator_identity,'required_role','VALIDATOR_RESUME',
      'promotion_authorized',false,'production_authorized',false
    );
  end if;

  -- Only after every governed family is passed.
  update programacion.input_readiness_runs
    set status='COMPLETED',validator_completed_at=clock_timestamp()
    where id=p_run_id;


  v_payload:=jsonb_build_object(
    'status','COMPLETED','run_id',p_run_id,'parent_run_id',v_parent,'pantalla_id',v_pantalla_id,
    'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,
    'required_role','DISPATCHER_FINALIZE','promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

DO $verify$
DECLARE v_oid oid:='programacion.fn_input_governance_validator_rebind_v1(bigint,text)'::regprocedure;
BEGIN
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_oid)
    OR position('limit 3' IN pg_get_functiondef(v_oid))=0
    OR position('VALIDATOR_CONTINUE_REQUIRED' IN pg_get_functiondef(v_oid))=0
    OR has_schema_privilege('service_role','programacion','USAGE')
 THEN RAISE EXCEPTION 'IG_VALIDATOR_BOUNDED_CONTINUATION_VERIFICATION_FAILED'; END IF;
END $verify$;
