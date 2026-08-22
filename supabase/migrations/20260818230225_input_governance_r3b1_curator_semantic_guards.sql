create or replace function programacion.fn_guard_input_family_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $$
declare
  v_status text; v_contract_version integer; v_contract_pin_revision text; v_contract_pin_sha text;
  v_pantalla_id integer; v_version_id bigint; v_families jsonb; v_payload jsonb; v_ref jsonb; v_mode text; v_states text[];
  v_governance_family boolean; v_has_independent_ekb boolean; v_has_contract_ref boolean;
  v_contract_schema integer; v_contract_revision text; v_contract_payload jsonb; v_contract_sha text;
  v_non_absence_authority boolean:=false;
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
    if new.story_ready_status='READY' and (new.coverage_status in ('MISSING','PENDING','BLOCKED') or new.well_defined_status in ('MISSING','PENDING','BLOCKED')) then raise exception 'STORY_READY_REQUIRES_NON_MISSING_COVERAGE_AND_DEFINITION:%',new.family_code; end if;
    if new.implementation_ready_status='READY' and (new.story_ready_status<>'READY' or new.coverage_status<>'COMPLETE' or new.well_defined_status<>'COMPLETE') then raise exception 'IMPLEMENTATION_READY_REQUIRES_STORY_AND_COMPLETE_COVERAGE_DEFINITION:%',new.family_code; end if;
    if new.qa_ready_status='READY' and new.implementation_ready_status<>'READY' then raise exception 'QA_READY_REQUIRES_IMPLEMENTATION_READY:%',new.family_code; end if;
    if new.production_ready_status='READY' and new.qa_ready_status<>'READY' then raise exception 'PRODUCTION_READY_REQUIRES_QA_READY:%',new.family_code; end if;
  end if;

  if new.validator_outcome<>'PENDING' or new.validator_identity is not null or new.validator_sha256 is not null or new.validator_assessed_at is not null or new.validator_findings<>'[]'::jsonb or new.validator_evidence<>'{}'::jsonb then raise exception 'CURATOR_CANNOT_PREVALIDATE:%',new.family_code; end if;
  v_mode:='DB_MANIFEST_V'||v_contract_version::text;
  new.freshness:=jsonb_build_object('mode',v_mode,'status','PENDING_RUN_SNAPSHOT');
  v_payload:=jsonb_build_object('run_id',new.run_id,'family_code',new.family_code,'severity',new.severity,'applicability',new.applicability,'coverage_status',new.coverage_status,'well_defined_status',new.well_defined_status,'story_ready_status',new.story_ready_status,'implementation_ready_status',new.implementation_ready_status,'qa_ready_status',new.qa_ready_status,'production_ready_status',new.production_ready_status,'source_refs',new.source_refs,'rationale',new.rationale,'blockers',new.blockers,'negative_requirements',new.negative_requirements,'test_obligations',new.test_obligations,'freshness',new.freshness,'curator_evidence',new.curator_evidence);
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;