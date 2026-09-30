create or replace function programacion.fn_input_assertion_is_relevant(
  p_family_code text,
  p_source_ref jsonb,
  p_path jsonb
) returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $$
declare
  v_kind text := coalesce(p_source_ref->>'kind','');
  v_path text;
begin
  if jsonb_typeof(p_path)<>'array' then return false; end if;
  select string_agg(x.value,'/' order by x.ord) into v_path
  from jsonb_array_elements_text(p_path) with ordinality x(value,ord);

  case p_family_code
    when 'SCREEN_IDENTITY' then
      return (v_kind='SCREEN' and v_path like 'observed/%')
          or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path in ('observed/screen_code','observed/module_code','observed/app_shell_code') or v_path like 'observed/canonical_contract/context/screen%'));
    when 'OBJECTIVE_OUTCOMES' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/context/screen/objective%';
    when 'FIELDS' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/fields%';
    when 'VALIDATIONS' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/fields%';
    when 'ACTIONS' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'STATES' then
      return v_kind='SCREEN_STATE_SET' and v_path like 'observed%';
    when 'TRANSITIONS' then
      return v_kind='TRANSITION_SET' and v_path like 'observed%';
    when 'ROUTING_NAVIGATION' then
      return (v_kind='ROUTE_SET' and v_path like 'observed%')
          or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%');
    when 'PROFILES' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/profiles%';
    when 'PERMISSIONS' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/screen_permissions%' or v_path like 'observed/profile_permissions%');
    when 'ERRORS' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/errors%';
    when 'UI_MESSAGES' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/messages%' or v_path like 'observed/canonical_contract/fields%');
    when 'SESSION' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/policies/session%';
    when 'RATE_LIMIT' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/policies/rate_limit%';
    when 'TIMEOUT_RETRY' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/timeout%' or v_path like 'observed/canonical_contract/rules%');
    when 'SECURITY' then
      return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%')
          or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/policies/security%');
    when 'MFA_OTP_SSO' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%');
    when 'PRIVACY_PII' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/fields%' or v_path like 'observed/canonical_contract/rules%');
    when 'AUDIT' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'ANALYTICS' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/analytics%';
    when 'OBSERVABILITY' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/analytics%');
    when 'PERFORMANCE' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'RESPONSIVE' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/visual/variants%';
    when 'THEME_LIGHT_DARK_SYSTEM' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual%' or v_path like 'observed/canonical_contract/rules%');
    when 'FORCED_COLORS_CONTRAST','REDUCED_MOTION','ACCESSIBILITY' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/visual%');
    when 'DESIGN_SYSTEM' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/visual/design_system%';
    when 'ASSETS_ICONS' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual/components%' or v_path like 'observed/canonical_contract/evidence%');
    when 'API_DATA_CONTRACT','LOADING_EMPTY_ERROR_STATES','IDEMPOTENCY_CONCURRENCY','TESTING_OBLIGATIONS','BROWSER_PLATFORM','ROLLOUT_PRODUCTION_GATES' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'FEATURE_FLAGS' then
      return v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='FEATURE_FLAGS' and v_path like 'observed/%';
    when 'I18N_FORMATS' then
      return v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='I18N_FORMATS' and v_path like 'observed/%';
    when 'DEPENDENCIES' then
      return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/context/screen/dependencies%';
    when 'VISUAL_EVIDENCE' then
      return (v_kind='CURRENT_VISUAL_ARTIFACT' and v_path like 'observed%')
          or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/evidence%');
    when 'EKB' then
      return v_kind in ('EKB_ERROR_SET','EKB_PREVENTION_SET','EKB_DECISION_SET') and v_path like 'observed%';
    when 'RUNTIME_CONFIG' then
      return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%')
          or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%'));
    when 'SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS','CONTEXT_BUDGET_RETRIEVAL_POLICY' then
      return v_kind='CONTRACT' and v_path like 'observed/especificacion/%';
    else
      return false;
  end case;
end;
$$;

revoke all on function programacion.fn_input_assertion_is_relevant(text,jsonb,jsonb) from public;
grant execute on function programacion.fn_input_assertion_is_relevant(text,jsonb,jsonb) to postgres;

create or replace function programacion.fn_guard_input_family_assessment_update()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v_payload jsonb;
  v_run_status text;
  v_run_sha text;
  v_curator_identity text;
  v_validator_identity text;
  v_validator_component_id bigint;
  v_current_manifest jsonb;
  v_current_sha text;
  v_bad_assertions integer;
  v_assertion jsonb;
  v_eval jsonb;
begin
  if new.run_id is distinct from old.run_id or new.family_code is distinct from old.family_code or new.severity is distinct from old.severity
     or new.applicability is distinct from old.applicability or new.coverage_status is distinct from old.coverage_status
     or new.well_defined_status is distinct from old.well_defined_status or new.story_ready_status is distinct from old.story_ready_status
     or new.implementation_ready_status is distinct from old.implementation_ready_status or new.qa_ready_status is distinct from old.qa_ready_status
     or new.production_ready_status is distinct from old.production_ready_status or new.source_refs is distinct from old.source_refs
     or new.rationale is distinct from old.rationale or new.blockers is distinct from old.blockers
     or new.negative_requirements is distinct from old.negative_requirements or new.test_obligations is distinct from old.test_obligations
     or new.freshness is distinct from old.freshness or new.curator_evidence is distinct from old.curator_evidence
     or new.curator_sha256 is distinct from old.curator_sha256 or new.created_at is distinct from old.created_at then
    raise exception 'CURATOR_FIELDS_IMMUTABLE:%',old.family_code;
  end if;
  if old.validator_outcome<>'PENDING' then raise exception 'VALIDATOR_RECEIPT_IMMUTABLE:%',old.family_code; end if;
  if new.validator_outcome='PENDING' then raise exception 'VALIDATOR_UPDATE_MUST_BE_TERMINAL:%',old.family_code; end if;
  select status,source_snapshot_sha256,curator_identity,validator_identity,validator_component_id
    into v_run_status,v_run_sha,v_curator_identity,v_validator_identity,v_validator_component_id
  from programacion.input_readiness_runs where id=old.run_id;
  if v_run_status<>'VALIDATING' then raise exception 'VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.family_code; end if;
  if v_validator_component_id is null then raise exception 'RUN_VALIDATOR_COMPONENT_REQUIRED'; end if;
  if v_validator_identity is null or v_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  if new.validator_identity is distinct from v_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH:%',old.family_code; end if;
  if new.validator_assessed_at is null then new.validator_assessed_at:=now(); end if;
  if jsonb_typeof(new.validator_evidence)<>'object' or new.validator_evidence='{}'::jsonb then raise exception 'VALIDATOR_EVIDENCE_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run_sha then raise exception 'VALIDATOR_EVIDENCE_SOURCE_SNAPSHOT_MISMATCH:%',old.family_code; end if;
  if new.validator_evidence->>'curator_sha256' is distinct from old.curator_sha256 then raise exception 'VALIDATOR_EVIDENCE_CURATOR_HASH_MISMATCH:%',old.family_code; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'VALIDATOR_DIRECT_SOURCE_READBACK_REQUIRED:%',old.family_code; end if;
  if new.validator_evidence->>'execution_mode'<>'INDEPENDENT_VALIDATOR' then raise exception 'VALIDATOR_EXECUTION_MODE_REQUIRED:%',old.family_code; end if;
  if jsonb_typeof(new.validator_evidence->'assertions')<>'array' or jsonb_array_length(new.validator_evidence->'assertions')=0 then raise exception 'VALIDATOR_ASSERTIONS_REQUIRED:%',old.family_code; end if;
  select count(*) into v_bad_assertions from jsonb_array_elements(new.validator_evidence->'assertions') a
  where jsonb_typeof(a)<>'object' or not (a ? 'actual') or not (a ? 'expected') or not (a ? 'operator') or not (a ? 'source_ref') or not (a ? 'path');
  if v_bad_assertions>0 then raise exception 'VALIDATOR_ASSERTION_SCHEMA_INVALID:%',old.family_code; end if;

  for v_assertion in select value from jsonb_array_elements(new.validator_evidence->'assertions') loop
    if not programacion.fn_input_assertion_is_relevant(old.family_code,v_assertion->'source_ref',v_assertion->'path') then
      raise exception 'VALIDATOR_ASSERTION_NOT_RELEVANT:%',old.family_code;
    end if;
    v_eval:=programacion.fn_input_evaluate_assertion(old.run_id,old.family_code,v_assertion);
    if new.validator_outcome='PASS' and coalesce((v_eval->>'passed')::boolean,false) is not true then
      raise exception 'VALIDATOR_ASSERTION_FAILED:%',old.family_code;
    end if;
  end loop;

  v_current_manifest:=programacion.fn_input_build_source_manifest(old.run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  if v_current_sha<>v_run_sha then raise exception 'SOURCE_SNAPSHOT_STALE_DURING_VALIDATION:%',old.family_code; end if;
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'source_snapshot_sha256',v_run_sha,
    'validator_outcome',new.validator_outcome,'validator_findings',new.validator_findings,'validator_evidence',new.validator_evidence,
    'validator_identity',new.validator_identity,'validator_assessed_at',new.validator_assessed_at);
  new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

update programacion.contratos
set especificacion = jsonb_set(
  jsonb_set(
    jsonb_set(especificacion,'{contract_revision}','"3.1"'::jsonb,true),
    '{assertion_relevance_policy}','"FAMILY_SOURCE_PATH_ALLOWLIST_V3_1"'::jsonb,true
  ),
  '{audit_remediation}',
  coalesce(especificacion->'audit_remediation','[]'::jsonb) || '"AUD-IGA-005"'::jsonb,
  true
)
where version_id=12 and contrato_codigo='INPUT_READINESS_CONTRACT';