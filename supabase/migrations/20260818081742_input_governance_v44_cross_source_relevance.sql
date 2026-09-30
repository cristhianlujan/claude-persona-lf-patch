create or replace function programacion.fn_input_assertion_is_relevant(p_family_code text, p_source_ref jsonb, p_path jsonb)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_kind text:=coalesce(p_source_ref->>'kind','');
  v_path text;
begin
  if jsonb_typeof(p_path)<>'array' then return false; end if;
  select string_agg(x.value,'/' order by x.ord) into v_path from jsonb_array_elements_text(p_path) with ordinality x(value,ord);
  case p_family_code
    when 'SCREEN_IDENTITY' then return (v_kind='SCREEN' and v_path like 'observed/%') or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path in ('observed/screen_code','observed/module_code','observed/app_shell_code') or v_path like 'observed/canonical_contract/context/screen%'));
    when 'OBJECTIVE_OUTCOMES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/context/screen/objective%';
    when 'FIELDS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/fields%';
    when 'VALIDATIONS' then return (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/fields%') or (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%');
    when 'ACTIONS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'STATES' then return v_kind='SCREEN_STATE_SET' and v_path like 'observed%';
    when 'TRANSITIONS' then return (v_kind='TRANSITION_SET' and v_path like 'observed%') or (v_kind='SCREEN_STATE_SET' and v_path like 'observed%');
    when 'ROUTING_NAVIGATION' then return (v_kind='ROUTE_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%');
    when 'PROFILES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/profiles%';
    when 'PERMISSIONS' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/screen_permissions%' or v_path like 'observed/profile_permissions%');
    when 'ERRORS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/errors%';
    when 'UI_MESSAGES' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/messages%' or v_path like 'observed/canonical_contract/fields%');
    when 'SESSION' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/session%' or v_path like 'observed/canonical_contract/rules%');
    when 'RATE_LIMIT' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/rate_limit%' or v_path like 'observed/canonical_contract/rules%');
    when 'TIMEOUT_RETRY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/timeout%' or v_path like 'observed/canonical_contract/rules%');
    when 'SECURITY' then return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/policies/security%');
    when 'MFA_OTP_SSO' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%');
    when 'PRIVACY_PII' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/fields%' or v_path like 'observed/canonical_contract/rules%');
    when 'AUDIT' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'ANALYTICS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/analytics%';
    when 'OBSERVABILITY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/analytics%');
    when 'PERFORMANCE' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'RESPONSIVE' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/visual/variants%';
    when 'THEME_LIGHT_DARK_SYSTEM' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual%' or v_path like 'observed/canonical_contract/rules%');
    when 'FORCED_COLORS_CONTRAST','REDUCED_MOTION','ACCESSIBILITY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/visual%');
    when 'DESIGN_SYSTEM' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/visual/design_system%';
    when 'ASSETS_ICONS' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual/components%' or v_path like 'observed/canonical_contract/evidence%' or v_path like 'observed/canonical_contract/rules%');
    when 'API_DATA_CONTRACT','LOADING_EMPTY_ERROR_STATES','IDEMPOTENCY_CONCURRENCY','TESTING_OBLIGATIONS','BROWSER_PLATFORM','ROLLOUT_PRODUCTION_GATES','CONTEXT_BUDGET_RETRIEVAL_POLICY' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'FEATURE_FLAGS' then return v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='FEATURE_FLAGS' and v_path like 'observed/%';
    when 'I18N_FORMATS' then return v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='I18N_FORMATS' and v_path like 'observed/%';
    when 'DEPENDENCIES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/context/screen/dependencies%';
    when 'VISUAL_EVIDENCE' then return (v_kind='CURRENT_VISUAL_ARTIFACT' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/evidence%');
    when 'EKB' then return v_kind in ('EKB_ERROR_SET','EKB_PREVENTION_SET','EKB_DECISION_SET') and v_path like 'observed%';
    when 'RUNTIME_CONFIG' then return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%'));
    when 'SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS' then return v_kind='CONTRACT' and v_path like 'observed/especificacion/%';
    else return false;
  end case;
end;
$function$;

update programacion.contratos
set especificacion = jsonb_set(
  jsonb_set(especificacion,'{contract_revision}','"4.4"'::jsonb,true),
  '{assertion_relevance_policy}','"FAMILY_SOURCE_PATH_ALLOWLIST_V4_4_CROSS_SOURCE"'::jsonb,true
)
where id=28 and version_id=13 and contrato_codigo='INPUT_READINESS_CONTRACT';