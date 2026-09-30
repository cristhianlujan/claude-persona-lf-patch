alter table programacion.input_readiness_runs
  drop constraint if exists input_readiness_runs_contract_version_check;
alter table programacion.input_readiness_runs
  add constraint input_readiness_runs_contract_version_check
  check (contract_version = any (array[1,2,3,4]));

create or replace function programacion.fn_input_design_readiness(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_graph jsonb;
  v_summary jsonb;
  v_design_system_id bigint;
  v_design_status text;
  v_missing_fields integer;
  v_missing_layouts integer;
  v_ref_failures integer;
  v_nonprod_components integer;
  v_broken integer;
  v_coverage text := 'COMPLETE';
  v_well text := 'COMPLETE';
  v_story text := 'READY';
  v_impl text := 'READY';
  v_qa text := 'READY';
  v_prod text := 'READY';
  v_blockers jsonb := '[]'::jsonb;
begin
  begin
    v_graph:=programacion.fn_input_design_binding_graph(p_pantalla_id);
  exception when others then
    return jsonb_build_object(
      'coverage_status','MISSING','well_defined_status','BLOCKED','story_ready_status','BLOCKED',
      'implementation_ready_status','BLOCKED','qa_ready_status','BLOCKED','production_ready_status','BLOCKED',
      'blockers',jsonb_build_array(jsonb_build_object('code','DESIGN_AUTHORITY_UNRESOLVED','detail',sqlerrm)),
      'binding_graph',null
    );
  end;

  v_summary:=v_graph->'summary';
  v_design_system_id:=(v_graph->>'design_system_id')::bigint;
  select status into v_design_status from lf_design.design_systems where design_system_id=v_design_system_id;
  if v_design_status is null then
    v_coverage:='MISSING'; v_well:='BLOCKED'; v_story:='BLOCKED'; v_impl:='BLOCKED'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DESIGN_SYSTEM_NOT_FOUND','design_system_id',v_design_system_id));
  end if;

  v_missing_fields:=coalesce((v_summary->>'field_component_missing_count')::integer,0);
  v_missing_layouts:=coalesce((v_summary->>'variant_layout_missing_count')::integer,0);
  v_ref_failures:=coalesce((v_summary->>'referential_integrity_failure_count')::integer,0);

  if v_missing_fields>0 then
    v_well:='PARTIAL'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SCREEN_FIELD_COMPONENT_BINDING_MISSING','count',v_missing_fields));
  end if;
  if v_missing_layouts>0 then
    v_well:='PARTIAL'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SCREEN_VARIANT_LAYOUT_BINDING_MISSING','count',v_missing_layouts));
  end if;
  if v_ref_failures>0 then
    v_well:='BLOCKED'; v_impl:='BLOCKED'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DESIGN_REFERENCE_INTEGRITY_FAILURE','count',v_ref_failures));
  end if;

  -- Candidate visual components can guide candidate implementation, but are not production-ready.
  select count(*) into v_nonprod_components
  from (
    select distinct (x->>'component_token_id')::bigint component_token_id
    from jsonb_array_elements(v_graph->'fields') f
    cross join lateral jsonb_array_elements(
      case when f->'component_receipt'->'component' is null then '[]'::jsonb
           else jsonb_build_array(f->'component_receipt'->'component') end
    ) x
    union
    select distinct (x->>'component_token_id')::bigint
    from jsonb_array_elements(v_graph->'variants') vv
    cross join lateral jsonb_array_elements(
      case when vv->'layout_component_receipt'->'component' is null then '[]'::jsonb
           else jsonb_build_array(vv->'layout_component_receipt'->'component') end
    ) x
  ) c
  join lf_design.component_tokens ct using(component_token_id)
  where ct.status not in ('VIGENTE');

  if v_design_status<>'VIGENTE' or v_nonprod_components>0 then
    v_prod:='NOT_READY';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','DESIGN_SOURCE_NOT_PRODUCTION_STATUS',
      'design_system_status',v_design_status,
      'non_vigente_component_count',v_nonprod_components
    ));
  end if;

  return jsonb_build_object(
    'coverage_status',v_coverage,
    'well_defined_status',v_well,
    'story_ready_status',v_story,
    'implementation_ready_status',v_impl,
    'qa_ready_status',v_qa,
    'production_ready_status',v_prod,
    'blockers',v_blockers,
    'binding_graph',v_graph,
    'policy',jsonb_build_object(
      'generic_design_rule_alone_is_implementation_ready',false,
      'candidate_visual_may_guide_candidate_implementation',true,
      'candidate_visual_is_production_ready',false
    )
  );
end;
$$;
revoke all on function programacion.fn_input_design_readiness(integer) from public;

create or replace function programacion.fn_guard_input_family_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_status text;
  v_contract_version integer;
  v_pantalla_id integer;
  v_version_id bigint;
  v_families jsonb;
  v_payload jsonb;
  v_ref jsonb;
  v_mode text;
begin
  select r.status,r.contract_version,r.pantalla_id,r.version_id,q.valor_config->'families'
    into v_status,v_contract_version,v_pantalla_id,v_version_id,v_families
  from programacion.input_readiness_runs r join lf_ops.reglas q on q.id=r.universe_rule_id where r.id=new.run_id;
  if v_status is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND'; end if;
  if v_contract_version not in (3,4) then raise exception 'LEGACY_INPUT_READINESS_RUN_NOT_WRITABLE'; end if;
  if v_status<>'CURATING' then raise exception 'CURATOR_INSERT_CLOSED_FOR_RUN_STATUS_%',v_status; end if;
  if jsonb_typeof(v_families)<>'array' or not (v_families ? new.family_code) then raise exception 'FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',new.family_code; end if;
  if jsonb_typeof(new.source_refs)<>'array' or jsonb_array_length(new.source_refs)=0 then raise exception 'SOURCE_REFS_REQUIRED:%',new.family_code; end if;
  for v_ref in select value from jsonb_array_elements(new.source_refs) loop
    perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);
  end loop;
  if new.applicability='UNRESOLVED' and new.story_ready_status='READY' then raise exception 'UNRESOLVED_APPLICABILITY_CANNOT_BE_STORY_READY:%',new.family_code; end if;
  if new.validator_outcome<>'PENDING' or new.validator_identity is not null or new.validator_sha256 is not null
     or new.validator_assessed_at is not null or new.validator_findings<>'[]'::jsonb or new.validator_evidence<>'{}'::jsonb then
    raise exception 'CURATOR_CANNOT_PREVALIDATE:%',new.family_code;
  end if;
  v_mode:=case when v_contract_version=4 then 'DB_MANIFEST_V4' else 'DB_MANIFEST_V3' end;
  new.freshness:=jsonb_build_object('mode',v_mode,'status','PENDING_RUN_SNAPSHOT');
  v_payload:=jsonb_build_object('run_id',new.run_id,'family_code',new.family_code,'severity',new.severity,'applicability',new.applicability,
    'coverage_status',new.coverage_status,'well_defined_status',new.well_defined_status,'story_ready_status',new.story_ready_status,
    'implementation_ready_status',new.implementation_ready_status,'qa_ready_status',new.qa_ready_status,'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,'rationale',new.rationale,'blockers',new.blockers,'negative_requirements',new.negative_requirements,
    'test_obligations',new.test_obligations,'freshness',new.freshness,'curator_evidence',new.curator_evidence);
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

create or replace function programacion.fn_guard_input_readiness_run()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_agent_code text;
  v_rule_code text;
  v_families jsonb;
  v_universe_payload jsonb;
  v_expected_count integer;
  v_assessment_count integer;
  v_pass_count integer;
  v_bad_validator integer;
  v_curator_code text;
  v_validator_code text;
  v_component_version bigint;
  v_manifest jsonb;
  v_current_manifest jsonb;
  v_current_sha text;
  v_version_code text;
begin
  if tg_op='INSERT' then
    if new.contract_version not in (3,4) then raise exception 'NEW_INPUT_READINESS_RUN_REQUIRES_SUPPORTED_CONTRACT'; end if;
    if new.status<>'CURATING' or new.curator_completed_at is not null or new.validator_identity is not null
       or new.validator_completed_at is not null or new.validator_component_id is not null or new.blocked_reason is not null
       or new.source_snapshot_sha256 is not null or new.source_manifest<>'[]'::jsonb or new.source_observed_at is not null then
      raise exception 'INPUT_READINESS_RUN_MUST_START_CLEAN_CURATING';
    end if;
    if new.curator_identity !~ '^INPUT_CURATOR:' then raise exception 'INVALID_CURATOR_IDENTITY'; end if;
    select a.agente_codigo,v.version_codigo into v_agent_code,v_version_code
    from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id where v.id=new.version_id;
    if v_agent_code<>'INPUT_GOVERNANCE_AGENT' then raise exception 'INVALID_INPUT_GOVERNANCE_AGENT_VERSION'; end if;
    if new.contract_version=4 and v_version_code not like 'v0.3-input-readiness-semantic-bindings%' then
      raise exception 'CONTRACT_V4_REQUIRES_V03_SEMANTIC_BINDINGS_VERSION';
    end if;
    if new.contract_version=3 and v_version_code like 'v0.3-input-readiness-semantic-bindings%' then
      raise exception 'V03_SEMANTIC_BINDINGS_REQUIRES_CONTRACT_V4';
    end if;
    select c.componente_codigo,c.version_id into v_curator_code,v_component_version from programacion.componentes c where c.id=new.curator_component_id;
    if v_curator_code<>'INPUT_CURATOR' or v_component_version<>new.version_id then raise exception 'INVALID_CURATOR_COMPONENT'; end if;
    select q.codigo,q.valor_config->'families' into v_rule_code,v_families from lf_ops.reglas q where q.id=new.universe_rule_id;
    if v_rule_code<>'B2B-RULE-STORY-READINESS-001' then raise exception 'INVALID_INPUT_FAMILY_UNIVERSE_RULE:%',coalesce(v_rule_code,'NULL'); end if;
    if jsonb_typeof(v_families)<>'array' then raise exception 'INVALID_CANONICAL_FAMILY_UNIVERSE'; end if;
    v_expected_count:=jsonb_array_length(v_families);
    if new.family_count<>v_expected_count then raise exception 'FAMILY_COUNT_MISMATCH expected=% actual=%',v_expected_count,new.family_count; end if;
    v_universe_payload:=jsonb_build_object('rule_code',v_rule_code,'families',v_families);
    if new.universe_snapshot_sha256<>programacion.fn_v09_sha256_jsonb(v_universe_payload) then raise exception 'UNIVERSE_SNAPSHOT_DIGEST_MISMATCH'; end if;
    return new;
  end if;

  if new.contract_version in (1,2) then
    if old.status in ('COMPLETED','BLOCKED') then raise exception 'TERMINAL_INPUT_READINESS_RUN_IMMUTABLE'; end if;
    raise exception 'LEGACY_INPUT_READINESS_RUN_NOT_MUTABLE';
  end if;

  if new.version_id is distinct from old.version_id or new.pantalla_id is distinct from old.pantalla_id or new.universe_rule_id is distinct from old.universe_rule_id
     or new.supersedes_run_id is distinct from old.supersedes_run_id or new.scope is distinct from old.scope
     or new.universe_snapshot_sha256 is distinct from old.universe_snapshot_sha256 or new.family_count is distinct from old.family_count
     or new.curator_identity is distinct from old.curator_identity or new.curator_component_id is distinct from old.curator_component_id
     or new.contract_version is distinct from old.contract_version or new.created_at is distinct from old.created_at then raise exception 'INPUT_READINESS_RUN_IDENTITY_IMMUTABLE'; end if;
  if old.status in ('COMPLETED','BLOCKED') then raise exception 'TERMINAL_INPUT_READINESS_RUN_IMMUTABLE'; end if;
  if old.status='CURATING' and new.status not in ('CURATING','VALIDATING','BLOCKED') then raise exception 'INVALID_RUN_TRANSITION:%->%',old.status,new.status; end if;
  if old.status='VALIDATING' and new.status not in ('VALIDATING','COMPLETED','BLOCKED') then raise exception 'INVALID_RUN_TRANSITION:%->%',old.status,new.status; end if;
  if not (old.status='CURATING' and new.status='VALIDATING') then
    if new.source_snapshot_sha256 is distinct from old.source_snapshot_sha256 or new.source_manifest is distinct from old.source_manifest
       or new.source_observed_at is distinct from old.source_observed_at then raise exception 'SOURCE_MANIFEST_FIELDS_IMMUTABLE'; end if;
    if new.validator_identity is distinct from old.validator_identity or new.validator_component_id is distinct from old.validator_component_id then raise exception 'RUN_VALIDATOR_IDENTITY_IMMUTABLE'; end if;
  end if;
  if old.status='CURATING' and new.status='VALIDATING' then
    if new.source_snapshot_sha256 is distinct from old.source_snapshot_sha256 or new.source_manifest is distinct from old.source_manifest
       or new.source_observed_at is distinct from old.source_observed_at then raise exception 'SOURCE_MANIFEST_MUST_BE_DB_GENERATED'; end if;
    if new.validator_identity is null or new.validator_identity !~ '^INPUT_VALIDATOR:' or new.validator_identity=new.curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
    if new.validator_component_id is null then raise exception 'VALIDATOR_COMPONENT_REQUIRED'; end if;
    select c.componente_codigo,c.version_id into v_validator_code,v_component_version from programacion.componentes c where c.id=new.validator_component_id;
    if v_validator_code<>'INPUT_VALIDATOR' or v_component_version<>new.version_id or new.validator_component_id=new.curator_component_id then raise exception 'INVALID_VALIDATOR_COMPONENT'; end if;
    select count(*) into v_assessment_count from programacion.input_family_assessments where run_id=old.id;
    if v_assessment_count<>old.family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE expected=% actual=%',old.family_count,v_assessment_count; end if;
    v_manifest:=programacion.fn_input_build_source_manifest(old.id);
    new.source_manifest:=v_manifest;
    new.source_snapshot_sha256:=programacion.fn_v09_sha256_jsonb(v_manifest);
    new.source_observed_at:=now();
    new.curator_completed_at:=coalesce(new.curator_completed_at,now());
  end if;
  if new.status='COMPLETED' then
    if new.validator_identity is null or new.validator_component_id is null then raise exception 'RUN_VALIDATOR_AUTHORITY_REQUIRED'; end if;
    v_current_manifest:=programacion.fn_input_build_source_manifest(old.id);
    v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
    if v_current_sha<>old.source_snapshot_sha256 or v_current_manifest<>old.source_manifest then raise exception 'SOURCE_SNAPSHOT_STALE_AT_COMPLETION'; end if;
    select count(*),count(*) filter(where validator_outcome='PASS'),count(*) filter(where validator_identity is distinct from old.validator_identity or validator_evidence->>'source_snapshot_sha256' is distinct from old.source_snapshot_sha256)
      into v_assessment_count,v_pass_count,v_bad_validator from programacion.input_family_assessments where run_id=old.id;
    if v_assessment_count<>old.family_count or v_pass_count<>old.family_count or v_bad_validator>0 then raise exception 'VALIDATOR_UNIVERSE_NOT_FULL_AUTHORIZED_PASS expected=% assessed=% pass=% bad=%',old.family_count,v_assessment_count,v_pass_count,v_bad_validator; end if;
    new.validator_completed_at:=coalesce(new.validator_completed_at,now());
  end if;
  return new;
end;
$$;

create or replace function programacion.fn_input_readiness_run_is_current(p_run_id bigint)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, programacion
as $$
declare
  v_status text;
  v_contract_version integer;
  v_stored_manifest jsonb;
  v_stored_sha text;
  v_current_manifest jsonb;
  v_current_sha text;
begin
  select status,contract_version,source_manifest,source_snapshot_sha256 into v_status,v_contract_version,v_stored_manifest,v_stored_sha
  from programacion.input_readiness_runs where id=p_run_id;
  if v_status<>'COMPLETED' or v_contract_version not in (3,4) or v_stored_sha is null then return false; end if;
  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  return v_current_sha=v_stored_sha and v_current_manifest=v_stored_manifest;
exception when others then return false;
end;
$$;