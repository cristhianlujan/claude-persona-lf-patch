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
begin
  select r.status,r.contract_version,r.pantalla_id,r.version_id,q.valor_config->'families'
    into v_status,v_contract_version,v_pantalla_id,v_version_id,v_families
  from programacion.input_readiness_runs r join lf_ops.reglas q on q.id=r.universe_rule_id where r.id=new.run_id;
  if v_status is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND'; end if;
  if v_contract_version<>3 then raise exception 'LEGACY_INPUT_READINESS_RUN_NOT_WRITABLE'; end if;
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
  new.freshness:=jsonb_build_object('mode','DB_MANIFEST_V3','status','PENDING_RUN_SNAPSHOT');
  v_payload:=jsonb_build_object('run_id',new.run_id,'family_code',new.family_code,'severity',new.severity,'applicability',new.applicability,
    'coverage_status',new.coverage_status,'well_defined_status',new.well_defined_status,'story_ready_status',new.story_ready_status,
    'implementation_ready_status',new.implementation_ready_status,'qa_ready_status',new.qa_ready_status,'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,'rationale',new.rationale,'blockers',new.blockers,'negative_requirements',new.negative_requirements,
    'test_obligations',new.test_obligations,'freshness',new.freshness,'curator_evidence',new.curator_evidence);
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;
revoke execute on function programacion.fn_guard_input_family_assessment_insert() from public;