create or replace function programacion.fn_guard_input_family_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public','programacion','lf_ops'
as $fn$
declare
  v_status text;
  v_families jsonb;
  v_payload jsonb;
begin
  select r.status, q.valor_config->'families'
    into v_status, v_families
  from programacion.input_readiness_runs r
  join lf_ops.reglas q on q.id=r.universe_rule_id
  where r.id=new.run_id;

  if v_status is null then
    raise exception 'INPUT_READINESS_RUN_NOT_FOUND';
  end if;
  if v_status <> 'CURATING' then
    raise exception 'CURATOR_INSERT_CLOSED_FOR_RUN_STATUS_%', v_status;
  end if;
  if jsonb_typeof(v_families) <> 'array' or not (v_families ? new.family_code) then
    raise exception 'FAMILY_NOT_IN_CANONICAL_UNIVERSE:%', new.family_code;
  end if;
  if jsonb_array_length(new.source_refs)=0 then
    raise exception 'SOURCE_REFS_REQUIRED:%', new.family_code;
  end if;
  if new.applicability='UNRESOLVED' and new.story_ready_status='READY' then
    raise exception 'UNRESOLVED_APPLICABILITY_CANNOT_BE_STORY_READY:%', new.family_code;
  end if;
  if new.validator_outcome <> 'PENDING'
     or new.validator_identity is not null
     or new.validator_sha256 is not null
     or new.validator_assessed_at is not null
     or new.validator_findings <> '[]'::jsonb
     or new.validator_evidence <> '{}'::jsonb then
    raise exception 'CURATOR_CANNOT_PREVALIDATE:%', new.family_code;
  end if;

  v_payload:=jsonb_build_object(
    'run_id',new.run_id,
    'family_code',new.family_code,
    'severity',new.severity,
    'applicability',new.applicability,
    'coverage_status',new.coverage_status,
    'well_defined_status',new.well_defined_status,
    'story_ready_status',new.story_ready_status,
    'implementation_ready_status',new.implementation_ready_status,
    'qa_ready_status',new.qa_ready_status,
    'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,
    'rationale',new.rationale,
    'blockers',new.blockers,
    'negative_requirements',new.negative_requirements,
    'test_obligations',new.test_obligations,
    'freshness',new.freshness,
    'curator_evidence',new.curator_evidence
  );
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;$fn$;

create or replace function programacion.fn_guard_input_readiness_run()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public','programacion','lf_ops'
as $fn$
declare
  v_agent_code text;
  v_rule_code text;
  v_families jsonb;
  v_universe_payload jsonb;
  v_expected_count integer;
  v_assessment_count integer;
  v_pass_count integer;
begin
  if tg_op='INSERT' then
    if new.status <> 'CURATING'
       or new.curator_completed_at is not null
       or new.validator_identity is not null
       or new.validator_completed_at is not null
       or new.blocked_reason is not null then
      raise exception 'INPUT_READINESS_RUN_MUST_START_CLEAN_CURATING';
    end if;

    select a.agente_codigo into v_agent_code
    from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id
    where v.id=new.version_id;
    if v_agent_code <> 'INPUT_GOVERNANCE_AGENT' then
      raise exception 'INVALID_INPUT_GOVERNANCE_AGENT_VERSION';
    end if;

    select q.codigo,q.valor_config->'families' into v_rule_code,v_families
    from lf_ops.reglas q where q.id=new.universe_rule_id;
    if v_rule_code <> 'B2B-RULE-STORY-READINESS-001' then
      raise exception 'INVALID_INPUT_FAMILY_UNIVERSE_RULE:%', coalesce(v_rule_code,'NULL');
    end if;
    if jsonb_typeof(v_families)<>'array' then
      raise exception 'INVALID_CANONICAL_FAMILY_UNIVERSE';
    end if;
    v_expected_count:=jsonb_array_length(v_families);
    if new.family_count<>v_expected_count then
      raise exception 'FAMILY_COUNT_MISMATCH expected=% actual=%',v_expected_count,new.family_count;
    end if;
    v_universe_payload:=jsonb_build_object('rule_code',v_rule_code,'families',v_families);
    if new.universe_snapshot_sha256<>programacion.fn_v09_sha256_jsonb(v_universe_payload) then
      raise exception 'UNIVERSE_SNAPSHOT_DIGEST_MISMATCH';
    end if;
    return new;
  end if;

  if new.version_id is distinct from old.version_id
     or new.pantalla_id is distinct from old.pantalla_id
     or new.universe_rule_id is distinct from old.universe_rule_id
     or new.supersedes_run_id is distinct from old.supersedes_run_id
     or new.scope is distinct from old.scope
     or new.source_snapshot_sha256 is distinct from old.source_snapshot_sha256
     or new.universe_snapshot_sha256 is distinct from old.universe_snapshot_sha256
     or new.family_count is distinct from old.family_count
     or new.curator_identity is distinct from old.curator_identity
     or new.created_at is distinct from old.created_at then
    raise exception 'INPUT_READINESS_RUN_IDENTITY_IMMUTABLE';
  end if;

  if old.status in ('COMPLETED','BLOCKED') then
    raise exception 'TERMINAL_INPUT_READINESS_RUN_IMMUTABLE';
  end if;

  if old.status='CURATING' and new.status not in ('CURATING','VALIDATING','BLOCKED') then
    raise exception 'INVALID_RUN_TRANSITION:%->%',old.status,new.status;
  end if;
  if old.status='VALIDATING' and new.status not in ('VALIDATING','COMPLETED','BLOCKED') then
    raise exception 'INVALID_RUN_TRANSITION:%->%',old.status,new.status;
  end if;

  if new.status='VALIDATING' and old.status<>'VALIDATING' then
    if new.curator_completed_at is null then new.curator_completed_at:=now(); end if;
    select count(*) into v_assessment_count from programacion.input_family_assessments where run_id=old.id;
    if v_assessment_count<>old.family_count then
      raise exception 'CURATOR_UNIVERSE_INCOMPLETE expected=% actual=%',old.family_count,v_assessment_count;
    end if;
  end if;

  if new.status='COMPLETED' then
    if new.validator_identity is null or length(btrim(new.validator_identity))=0 then
      raise exception 'RUN_VALIDATOR_IDENTITY_REQUIRED';
    end if;
    if new.validator_completed_at is null then new.validator_completed_at:=now(); end if;
    select count(*), count(*) filter(where validator_outcome='PASS')
      into v_assessment_count,v_pass_count
    from programacion.input_family_assessments where run_id=old.id;
    if v_assessment_count<>old.family_count or v_pass_count<>old.family_count then
      raise exception 'VALIDATOR_UNIVERSE_NOT_FULL_PASS expected=% assessed=% pass=%',old.family_count,v_assessment_count,v_pass_count;
    end if;
  end if;

  return new;
end;$fn$;