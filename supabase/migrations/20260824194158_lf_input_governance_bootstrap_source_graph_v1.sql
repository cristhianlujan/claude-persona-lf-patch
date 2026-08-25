-- LF Input Governance bootstrap source graph v1
-- Adds canonical graph source receipts and bootstrap-relevant assertion paths.

create or replace function programacion.fn_input_resolve_source_ref(p_ref jsonb,p_pantalla_id integer,p_version_id bigint)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion,lf_ops
as $$
declare
  v_kind text:=p_ref->>'kind'; v_ids bigint[]; v_expected integer; v_actual integer; v_observed jsonb;
begin
  if v_kind='SCREEN_CANONICAL_GRAPH' then
    if not (p_ref?'pantalla_id') or (p_ref->>'pantalla_id')::integer<>p_pantalla_id then
      raise exception 'SCREEN_CANONICAL_GRAPH_REQUIRES_EXPLICIT_PANTALLA_ID:%',p_pantalla_id;
    end if;
    v_observed:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
    return jsonb_build_object('ref',p_ref,'observed',v_observed,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed));
  elsif v_kind='ERROR_SET' then
    select array_agg(x::bigint order by x::bigint) into v_ids from jsonb_array_elements_text(p_ref->'ids') x;
    if v_ids is null or cardinality(v_ids)=0 then raise exception 'INVALID_ERROR_SET_REF'; end if;
    v_expected:=cardinality(v_ids);
    select count(*),jsonb_agg(to_jsonb(e) order by e.error_id) into v_actual,v_observed from lf_ops.errores_catalogo e where e.error_id=any(v_ids);
    if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:ERROR_SET expected=% actual=%',v_expected,v_actual; end if;
    return jsonb_build_object('ref',p_ref,'observed',v_observed,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed));
  elsif v_kind='MESSAGE_SET' then
    select array_agg(x::bigint order by x::bigint) into v_ids from jsonb_array_elements_text(p_ref->'ids') x;
    if v_ids is null or cardinality(v_ids)=0 then raise exception 'INVALID_MESSAGE_SET_REF'; end if;
    v_expected:=cardinality(v_ids);
    select count(*),jsonb_agg(jsonb_build_object('message',to_jsonb(m),'screen_links',coalesce((select jsonb_agg(to_jsonb(mp) order by mp.message_screen_id) from lf_ops.mensajes_pantallas mp where mp.message_id=m.message_id),'[]'::jsonb)) order by m.message_id)
      into v_actual,v_observed from lf_ops.mensajes_ui m where m.message_id=any(v_ids);
    if v_actual<>v_expected then raise exception 'SOURCE_REF_UNRESOLVED:MESSAGE_SET expected=% actual=%',v_expected,v_actual; end if;
    return jsonb_build_object('ref',p_ref,'observed',v_observed,'observed_sha256',programacion.fn_v09_sha256_jsonb(v_observed));
  end if;
  return programacion.fn_input_resolve_source_ref_v510(p_ref,p_pantalla_id,p_version_id);
end;
$$;

create or replace function programacion.fn_input_assertion_is_relevant(p_family_code text,p_source_ref jsonb,p_path jsonb)
returns boolean
language plpgsql
immutable
set search_path=pg_catalog
as $$
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
    when 'UI_MESSAGES' then return (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/messages%' or v_path like 'observed/canonical_contract/fields%' or v_path like 'observed/canonical_contract/rules%')) or (v_kind='MESSAGE_SET' and v_path like 'observed%');
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
    when 'LOADING_EMPTY_ERROR_STATES','IDEMPOTENCY_CONCURRENCY','TESTING_OBLIGATIONS','BROWSER_PLATFORM','ROLLOUT_PRODUCTION_GATES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'FEATURE_FLAGS' then return (v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='FEATURE_FLAGS' and v_path like 'observed/%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%');
    when 'I18N_FORMATS' then return (v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='I18N_FORMATS' and v_path like 'observed/%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%');
    when 'DEPENDENCIES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/context/screen/dependencies%';
    when 'VISUAL_EVIDENCE' then return (v_kind='CURRENT_VISUAL_ARTIFACT' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/evidence%');
    when 'EKB' then return v_kind in ('EKB_ERROR_SET','EKB_PREVENTION_SET','EKB_DECISION_SET') and v_path like 'observed%';
    when 'RUNTIME_CONFIG' then return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%'));
    when 'SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE' then return v_kind='CONTRACT' and v_path like 'observed/especificacion/%';
    when 'APPLICABILITY_READINESS' then return (v_kind='CONTRACT' and v_path like 'observed/especificacion/%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%') or (v_kind in ('CAPABILITY_ABSENCE','SECURITY_POLICY_SET','ROUTE_SET','SCREEN_STATE_SET','TRANSITION_SET') and v_path like 'observed%');
    when 'CONTEXT_BUDGET_RETRIEVAL_POLICY' then return (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%') or (v_kind='CONTRACT' and v_path like 'observed/especificacion/%');
    else return false;
  end case;
end;
$$;
