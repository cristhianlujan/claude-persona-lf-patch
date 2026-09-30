update programacion.contratos
set especificacion=jsonb_set(especificacion,'{source_manifest}','"DB_GENERATED_WITH_SCREEN_CANONICAL_GRAPH_V5_2"'::jsonb,true)
where id=31
  and especificacion->>'source_manifest'='DB_GENERATED_WITH_SCREEN_CANONICAL_GRAPH_V5_0';

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
    if new.contract_version=4 and not (
         v_version_code like 'v0.3-input-readiness-semantic-bindings%'
         or v_version_code like 'v0.4-input-readiness-semantic-sufficiency%'
       ) then
      raise exception 'CONTRACT_V4_REQUIRES_SEMANTIC_BINDING_VERSION';
    end if;
    if new.contract_version=3 and (
         v_version_code like 'v0.3-input-readiness-semantic-bindings%'
         or v_version_code like 'v0.4-input-readiness-semantic-sufficiency%'
       ) then
      raise exception 'SEMANTIC_BINDING_VERSION_REQUIRES_CONTRACT_V4';
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