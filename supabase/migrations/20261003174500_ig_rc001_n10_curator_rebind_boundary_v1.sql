-- N-10 / RC-001
-- Close the live Curator -> Validator assertion-builder boundary leak without changing
-- the current 5.13 rebind semantics. Curator copies the predecessor assessment and
-- leaves validator fields PENDING; assertion construction remains Validator-owned.

create or replace function programacion.fn_input_governance_curator_rebind_v1(
  p_pantalla_id integer,
  p_consumer text,
  p_curator_identity text,
  p_force_selftest boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'programacion', 'lf_ops', 'transversal'
as $function$
declare
  v_version bigint:=public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT');
  v_code text;
  v_active boolean;
  v_current bigint;
  v_latest bigint;
  v_latest_status text;
  v_parent bigint;
  v_new bigint;
  v_contract_schema integer;
  v_contract_revision text;
  v_contract_sha text;
  v_parent_contract_sha text;
  v_family_count integer;
  v_assessed integer;
  v_pre jsonb;
  a record;
  v_payload jsonb;
begin
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID';
  end if;
  if not exists(
    select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v)
    where x.v=p_consumer
  ) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;

  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;

  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;

  select id into v_current from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(id)
  order by id desc limit 1;
  if v_current is not null and not p_force_selftest then
    return jsonb_build_object('status','NOOP_CURRENT','run_id',v_current,'required_role','NONE','promotion_authorized',false,'production_authorized',false);
  end if;

  select id,status into v_latest,v_latest_status from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_latest is not null and v_latest_status in ('CURATING','VALIDATING') and not p_force_selftest then
    return jsonb_build_object(
      'status',case when v_latest_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,
      'run_id',v_latest,
      'required_role',case when v_latest_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,
      'promotion_authorized',false,'production_authorized',false
    );
  end if;

  select id,contract_snapshot_sha256,family_count into v_parent,v_parent_contract_sha,v_family_count
  from programacion.input_readiness_runs
  where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED'
  order by id desc limit 1;
  if v_parent is null then
    v_payload:=jsonb_build_object(
      'status','BOOTSTRAP_SEMANTIC_PROFILE_REQUIRED','pantalla_id',p_pantalla_id,'screen_code',v_code,
      'required_role','HUMAN_OR_GOVERNED_SEMANTIC_BOOTSTRAP','write_performed',false,
      'reason','NO_COMPLETED_PREDECESSOR_TO_REBIND','proposal_is_canonical_source',false,
      'promotion_authorized',false,'production_authorized',false
    );
    return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  select (c.especificacion->>'schema_version')::integer,c.especificacion->>'contract_revision',
         programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion))
  into v_contract_schema,v_contract_revision,v_contract_sha
  from programacion.contratos c
  where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
  if v_contract_revision is null then raise exception 'INPUT_READINESS_CONTRACT_NOT_RESOLVABLE:%',v_version; end if;
  if v_parent_contract_sha is distinct from v_contract_sha then
    if v_contract_revision is not null then
      return programacion.fn_input_governance_recurate_v2(
        p_pantalla_id,p_consumer,p_curator_identity
      );
    end if;
    return jsonb_build_object(
      'status','CONTRACT_CHANGED_SEMANTIC_REVIEW_REQUIRED','parent_run_id',v_parent,
      'required_role','HUMAN_OR_GOVERNED_CONTRACT_MIGRATION','write_performed',false,
      'promotion_authorized',false,'production_authorized',false
    );
  end if;

  insert into programacion.input_readiness_runs(
    version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,
    universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id
  )
  select version_id,pantalla_id,universe_rule_id,id,'CURATING',
         scope||jsonb_build_object(
           'mode','RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1','parent_run_id',id,
           'runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false
         ),
         universe_snapshot_sha256,family_count,v_contract_schema,p_curator_identity,46
  from programacion.input_readiness_runs where id=v_parent
  returning id into v_new;

  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code
  loop
    insert into programacion.input_family_assessments(
      run_id,family_code,severity,applicability,coverage_status,well_defined_status,
      story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
      source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,
      curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,
      validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256
    ) values (
      v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,
      a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,

      case when p_pantalla_id in (52,53,54,56) then
        programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->'source_refs'
      else a.source_refs end,a.rationale,a.blockers,a.negative_requirements,a.test_obligations,'{}'::jsonb,

      jsonb_build_object(
        'component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR',
        'runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,
        'parent_run_id',v_parent,'parent_assessment_id',a.id,'direct_source_readback',true,
        'semantic_policy','NO_INVENTION_REBIND_ONLY',
        'bootstrap_classifier_sha256',case
          when p_pantalla_id in (52,53,54,56) then
            programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->>'classifier_sha256'
          else coalesce(
            nullif(a.curator_evidence->>'bootstrap_classifier_sha256',''),
            programacion.fn_input_governance_bootstrap_classify_v2(p_pantalla_id,a.family_code,v_version)->>'classifier_sha256'
          )
        end
      ),
      repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,
      a.subject_coverage,a.threat_coverage,a.semantic_depth_sha256
    );
  end loop;

  select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_new;
  if v_assessed<>v_family_count then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_UNIVERSE_INCOMPLETE expected=% actual=%',v_family_count,v_assessed; end if;

  v_payload:=jsonb_build_object(
    'status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent,
    'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',v_family_count,
    'curator_identity',p_curator_identity,'run_status','CURATING','required_role','INPUT_VALIDATOR',
    'write_performed',true,'promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

comment on function programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean) is
  'N-10 RC-001: Curator-owned rebind only. Copies eligible predecessor assessments and leaves validator state PENDING; Validator owns assertion construction.';

do $verify$
begin
  if position(
    'fn_input_v58_build_assertions' in
    pg_get_functiondef('programacion.fn_input_governance_curator_rebind_v1(integer,text,text,boolean)'::regprocedure)
  ) > 0 then
    raise exception 'N10_CURATOR_STILL_CALLS_VALIDATOR_ASSERTION_BUILDER';
  end if;

  if position(
    'fn_input_v58_build_assertions' in
    pg_get_functiondef('programacion.fn_input_governance_validator_rebind_v1(bigint,text)'::regprocedure)
  ) = 0 then
    raise exception 'N10_VALIDATOR_ASSERTION_OWNERSHIP_MISSING';
  end if;
end;
$verify$;
