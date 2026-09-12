create or replace function programacion.fn_input_governance_recurate_source_stale_v1(
  p_pantalla_id integer,
  p_consumer text,
  p_curator_identity text,
  p_parent_run_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,programacion,lf_ops,transversal
as $function$
declare
  v_parent programacion.input_readiness_runs%rowtype;
  v_contract_schema integer;
  v_contract_revision text;
  v_curator_component bigint;
  v_new bigint;
  v_family text;
  v_class jsonb;
  v_count integer;
  v_exec_id text:=gen_random_uuid()::text;
  v_prop jsonb;
  v_payload jsonb;
  v_delta jsonb;
  v_changed integer:=0;
  v_affected integer:=0;
  v_successor_required boolean:=false;
  v_resolution_errors integer:=0;
  v_graph jsonb;
begin
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then
    raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID';
  end if;
  if not exists(
    select 1
    from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v)
    where x.v=p_consumer
  ) then
    raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>');
  end if;

  select * into v_parent
  from programacion.input_readiness_runs
  where id=p_parent_run_id
    and version_id=19
    and pantalla_id=p_pantalla_id
    and status='COMPLETED'
    and invalidated_at is null;
  if not found then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_INVALID:%',p_parent_run_id; end if;
  if p_parent_run_id is distinct from (
    select id from programacion.input_readiness_runs
    where version_id=19 and pantalla_id=p_pantalla_id and status='COMPLETED'
    order by id desc limit 1
  ) then raise exception 'INPUT_SOURCE_STALE_RECURATION_PARENT_NOT_LATEST:%',p_parent_run_id; end if;

  v_delta:=programacion.fn_input_freshness_delta(p_parent_run_id);
  v_changed:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0);
  v_affected:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0);
  v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);
  select count(*) into v_resolution_errors
  from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value)
  where x.value->>'state'='RESOLUTION_ERROR';

  if v_delta->>'run_state'<>'STALE'
     or v_changed<=0
     or v_affected<=0
     or v_successor_required
     or v_resolution_errors<>0 then
    raise exception 'INPUT_SOURCE_STALE_RECURATION_PROOF_INVALID:run=% summary=%',p_parent_run_id,v_delta->'summary';
  end if;

  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision'
    into v_contract_schema,v_contract_revision
  from programacion.contratos
  where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  if v_contract_revision<>'5.12' then raise exception 'INPUT_RECURATION_CONTRACT_REVISION_UNSUPPORTED:%',v_contract_revision; end if;
  select id into v_curator_component from programacion.componentes where version_id=19 and componente_codigo='INPUT_CURATOR';
  if v_curator_component is null then raise exception 'INPUT_CURATOR_COMPONENT_UNRESOLVED'; end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,19);

  insert into programacion.input_readiness_runs(
    version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,
    universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id
  ) values(
    v_parent.version_id,v_parent.pantalla_id,v_parent.universe_rule_id,v_parent.id,'CURATING',
    v_parent.scope || jsonb_build_object(
      'mode','RUNTIME_GOVERNED_RECURATION_V2','parent_run_id',v_parent.id,
      'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
      'remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001',
      'remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1',
      'runtime','input-governance-curator-v1',
      'source_stale_proof','INPUT_FRESHNESS_DELTA_V1',
      'source_stale_affected_family_count',v_affected,
      'classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT',
      'promotion_authorized',false,'production_authorized',false
    ),
    v_parent.universe_snapshot_sha256,v_parent.family_count,v_contract_schema,p_curator_identity,v_curator_component
  ) returning id into v_new;

  for v_family in
    select value from jsonb_array_elements_text((select valor_config->'families' from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001'))
  loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(p_pantalla_id,v_family,19,v_graph);
    insert into programacion.input_family_assessments(
      run_id,family_code,severity,applicability,coverage_status,well_defined_status,
      story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
      source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,
      curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,
      validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256
    ) values(
      v_new,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',
      v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',
      v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations','{}'::jsonb,
      jsonb_build_object(
        'component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR',
        'runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,
        'parent_run_id',v_parent.id,'direct_source_readback',true,'semantic_policy','GOVERNED_RECURATION_FROM_CANONICAL_SOURCES',
        'remediation_decision','DEC-INPUT-GOV-SELF-REMEDIATE-001','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
        'remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','bootstrap_classifier_sha256',v_class->>'classifier_sha256',
        'bootstrap_probe',v_class->'probe','source_stale_proof','INPUT_FRESHNESS_DELTA_V1','classifier_mode','CACHED_CANONICAL_GRAPH_EQUIVALENT'
      ),
      repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64)
    );
  end loop;

  select count(*) into v_count from programacion.input_family_assessments where run_id=v_new;
  if v_count<>47 then raise exception 'INPUT_RECURATION_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_prop:=programacion.fn_input_governance_materialize_gap_proposals_v1(v_new);
  v_payload:=jsonb_build_object(
    'status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_new,'parent_run_id',v_parent.id,'pantalla_id',p_pantalla_id,
    'family_count',47,'required_role','INPUT_VALIDATOR','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
    'remediation_policy_revision','POSITIVE_OWNER_AUTHORITY_V1','proposal_materialization',v_prop,
    'source_stale_proof','INPUT_FRESHNESS_DELTA_V1','affected_family_count',v_affected,
    'promotion_authorized',false,'production_authorized',false
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

create or replace function programacion.fn_input_governance_curator_materialize_v1(
  p_pantalla_id integer,
  p_consumer text,
  p_curator_identity text,
  p_force_selftest boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_completed bigint;
  v_scope jsonb;
  v_delta jsonb;
  v_changed_sources integer:=0;
  v_affected_families integer:=0;
  v_successor_required boolean:=false;
  v_resolution_errors integer:=0;
begin
  select id,scope into v_completed,v_scope
  from programacion.input_readiness_runs
  where version_id=19 and pantalla_id=p_pantalla_id and status='COMPLETED'
  order by id desc limit 1;

  if v_completed is null then
    return programacion.fn_input_governance_bootstrap_materialize_v2(p_pantalla_id,p_consumer,p_curator_identity);
  end if;

  if not p_force_selftest
     and coalesce(v_scope->>'mode','') in ('GOVERNED_CANONICAL_BOOTSTRAP_V1','RUNTIME_GOVERNED_RECURATION_V2') then
    v_delta:=programacion.fn_input_freshness_delta(v_completed);
    v_changed_sources:=coalesce((v_delta#>>'{summary,changed_source_count}')::integer,0);
    v_affected_families:=coalesce((v_delta#>>'{summary,affected_family_count}')::integer,0);
    v_successor_required:=coalesce((v_delta#>>'{summary,use_successor_required}')::boolean,false);
    select count(*) into v_resolution_errors
    from jsonb_array_elements(coalesce(v_delta->'source_changes','[]'::jsonb)) x(value)
    where x.value->>'state'='RESOLUTION_ERROR';

    if v_delta->>'run_state'='STALE' and v_changed_sources>0 and not v_successor_required and v_resolution_errors=0 then
      if v_affected_families=0 then
        return programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id,p_consumer,p_curator_identity,p_force_selftest);
      end if;
      return programacion.fn_input_governance_recurate_source_stale_v1(p_pantalla_id,p_consumer,p_curator_identity,v_completed);
    end if;

    if not programacion.fn_input_readiness_run_is_current_cached_v1(v_completed) then
      return programacion.fn_input_governance_recurate_v2(p_pantalla_id,p_consumer,p_curator_identity);
    end if;
  end if;

  return programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id,p_consumer,p_curator_identity,p_force_selftest);
end;
$function$;
