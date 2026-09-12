-- V5.12: permissions N/A may be authorized by a direct canonical RULE exclusion, not by empty matrices or a broad graph/rules path.
update programacion.contratos
set especificacion=jsonb_set(
  especificacion,
  '{negative_tests}',
  case when (especificacion->'negative_tests') ? 'PERMISSIONS_DIRECT_RULE_EXCLUSION_RELEVANT'
       then especificacion->'negative_tests'
       else (especificacion->'negative_tests') || '["PERMISSIONS_DIRECT_RULE_EXCLUSION_RELEVANT","PERMISSIONS_GRAPH_RULES_BROAD_PATH_REJECTED"]'::jsonb end,
  true
)
where version_id=19 and contrato_codigo='INPUT_READINESS_CONTRACT';

create or replace function programacion.fn_input_assertion_is_relevant(p_family_code text, p_source_ref jsonb, p_path jsonb)
returns boolean
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare v_kind text:=coalesce(p_source_ref->>'kind',''); v_path text;
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
    when 'PERMISSIONS' then return (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/screen_permissions%' or v_path like 'observed/profile_permissions%')) or (v_kind='RULE' and v_path like 'observed/valor_config%');
    when 'ERRORS' then return (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/errors%' or v_path like 'observed/canonical_contract/rules%')) or (v_kind='ERROR_SET' and v_path like 'observed%');
    when 'UI_MESSAGES' then return (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/messages%' or v_path like 'observed/canonical_contract/fields%')) or (v_kind='MESSAGE_SET' and v_path like 'observed%');
    when 'SESSION' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/session%' or v_path like 'observed/canonical_contract/rules%');
    when 'RATE_LIMIT' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/rate_limit%' or v_path like 'observed/canonical_contract/rules%');
    when 'TIMEOUT_RETRY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/timeout%' or v_path like 'observed/canonical_contract/rules%');
    when 'SECURITY' then return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/security%' or v_path like 'observed/canonical_contract/rules%'));
    when 'MFA_OTP_SSO' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%');
    when 'PRIVACY_PII' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/fields%' or v_path like 'observed/canonical_contract/rules%');
    when 'AUDIT' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'ANALYTICS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/analytics%';
    when 'OBSERVABILITY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/analytics%');
    when 'PERFORMANCE' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'RESPONSIVE' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/visual/variants%';
    when 'THEME_LIGHT_DARK_SYSTEM' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual%' or v_path like 'observed/canonical_contract/rules%');
    when 'FORCED_COLORS_CONTRAST','REDUCED_MOTION','ACCESSIBILITY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/visual%');
    when 'DESIGN_SYSTEM' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual/design_system%' or v_path like 'observed/canonical_contract/visual/design_bindings%');
    when 'ASSETS_ICONS' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual/components%' or v_path like 'observed/canonical_contract/evidence%' or v_path like 'observed/canonical_contract/rules%');
    when 'API_DATA_CONTRACT' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/api_contract_resolution%');
    when 'LOADING_EMPTY_ERROR_STATES','IDEMPOTENCY_CONCURRENCY','TESTING_OBLIGATIONS','BROWSER_PLATFORM','ROLLOUT_PRODUCTION_GATES','CONTEXT_BUDGET_RETRIEVAL_POLICY' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'FEATURE_FLAGS' then return v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='FEATURE_FLAGS' and v_path like 'observed/%';
    when 'I18N_FORMATS' then return v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='I18N_FORMATS' and v_path like 'observed/%';
    when 'DEPENDENCIES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/context/screen/dependencies%';
    when 'VISUAL_EVIDENCE' then return (v_kind='CURRENT_VISUAL_ARTIFACT' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/evidence%');
    when 'EKB' then return v_kind in ('EKB_ERROR_SET','EKB_PREVENTION_SET','EKB_DECISION_SET') and v_path like 'observed%';
    when 'RUNTIME_CONFIG' then return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%'));
    when 'SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE' then return v_kind='CONTRACT' and v_path like 'observed/especificacion/%';
    when 'APPLICABILITY_READINESS' then return (v_kind='CONTRACT' and v_path like 'observed/especificacion/%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%') or (v_kind in ('CAPABILITY_ABSENCE','SECURITY_POLICY_SET','ROUTE_SET','SCREEN_STATE_SET','TRANSITION_SET') and v_path like 'observed%');
    else return false;
  end case;
end$function$;
revoke all on function programacion.fn_input_assertion_is_relevant(text,jsonb,jsonb) from public;
grant execute on function programacion.fn_input_assertion_is_relevant(text,jsonb,jsonb) to postgres;

create or replace function programacion.fn_input_v512_assertion_template(p_pantalla_id integer,p_family_code text,p_assertion jsonb)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','programacion'
as $function$
declare v jsonb;
begin
  v:=programacion.fn_input_v58_assertion_template(p_pantalla_id,p_family_code,p_assertion);
  if p_family_code='MFA_OTP_SSO' and p_pantalla_id=52 then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',52),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-028","config":{"otp_policy_id":2,"otp_operation_id":5,"success_context_scope":"PASSWORD_RECOVERY_CHALLENGE_ONLY","authentication_completion":"DENY","operational_session_creation":"DENY"}}]'::jsonb);
  elsif p_family_code='PERMISSIONS' and p_pantalla_id=52 then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-AUTH-028'),'path',jsonb_build_array('observed','valor_config'),'operator','CONTAINS','expected','{"operational_access_grant":"DENY","authentication_completion":"DENY","operational_session_creation":"DENY"}'::jsonb);
  elsif p_family_code='PERMISSIONS' and p_pantalla_id in (53,56) then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-AUTH-029'),'path',jsonb_build_array('observed','valor_config'),'operator','CONTAINS','expected','{"recovery_context_scope":"PASSWORD_UPDATE_ONLY","operational_authorization_before_completion":"DENY"}'::jsonb);
  elsif p_family_code='PERMISSIONS' and p_pantalla_id=54 then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-AUTH-033'),'path',jsonb_build_array('observed','valor_config'),'operator','CONTAINS','expected','{"mfa_route_full_operational_session_required":false,"mfa_route_direct_navigation_without_challenge":"DENY"}'::jsonb);
  end if;
  return v - 'actual' - 'result' - 'source_observed_sha256';
end;
$function$;
revoke all on function programacion.fn_input_v512_assertion_template(integer,text,jsonb) from public;
grant execute on function programacion.fn_input_v512_assertion_template(integer,text,jsonb) to postgres;

update public.lf_error_knowledge
set frecuencia=coalesce(frecuencia,0)+1,
    ultima_vez=now(),
    evidencia=concat_ws(E'\n',nullif(evidencia,''),'2026-08-22 V5.12 recurrence: screen56 successor validation rejected a PERMISSIONS assertion because v512 initially used SCREEN_CANONICAL_GRAPH/canonical_contract/rules, while the relevance contract allowed only permission matrices. The transaction rolled back cleanly. The correction uses a direct canonical RULE source and valor_config path for explicit pre-auth exclusion semantics; the broad graph/rules path remains disallowed.'),
    prevencion=concat_ws(E'\n',nullif(prevencion,''),'V5.12: when PERMISSIONS N/A is authorized by an explicit AUTH exclusion, bind the assertion to the exact RULE source and valor_config path. Do not broaden SCREEN_CANONICAL_GRAPH/rules relevance merely to make an assertion pass.'),
    validacion=concat_ws(E'\n',nullif(validacion,''),'Negative: PERMISSIONS + SCREEN_CANONICAL_GRAPH/canonical_contract/rules remains irrelevant. Positive: PERMISSIONS + RULE AUTH-028/029/033 + observed/valor_config is relevant and must match the explicit DENY semantics.'),
    source_context='INPUT_GOVERNANCE_V512_PERMISSIONS_RULE_RELEVANCE_20260822',
    source_ref='programacion.fn_input_assertion_is_relevant + programacion.fn_input_v512_assertion_template'
where codigo='AUD-039';

update public.lf_prevention_rules
set regla=concat_ws(E'\n',nullif(regla,''),'V5.12: para exclusiones PERMISSIONS pre-auth, usar RULE canónica directa + valor_config; mantener rechazada la ruta amplia SCREEN_CANONICAL_GRAPH/rules.'),
    justificacion=concat_ws(E'\n',nullif(justificacion,''),'Recurrencia 2026-08-22: assertion PERMISSIONS inicialmente usó una ruta semánticamente demasiado amplia y fue correctamente vetada por relevancia.')
where regla_codigo='PRV-AUD-039';