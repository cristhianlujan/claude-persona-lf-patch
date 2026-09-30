insert into programacion.versiones_agente(agente_id,version_codigo,objetivo,estado,supersedes_version_id,notas)
select agente_id,'v0.4-input-readiness-semantic-sufficiency-r1-candidate',
       objetivo || ' Permite validar applicability/readiness contra la fuente funcional específica además del contrato.',
       'candidate',id,
       'CANDIDATE_V5_3_2026-08-18: applicability screen-specific must be semantically groundable in screen rules/sources. No promotion.'
from programacion.versiones_agente
where id=16
  and not exists(select 1 from programacion.versiones_agente where version_codigo='v0.4-input-readiness-semantic-sufficiency-r1-candidate');

insert into programacion.componentes(version_id,componente_codigo,tipo,nombre,responsabilidad,orden_ejecucion,independencia_requerida,configuracion,estado)
select nv.id,c.componente_codigo,c.tipo,c.nombre,c.responsabilidad,c.orden_ejecucion,c.independencia_requerida,
       c.configuracion || jsonb_build_object('applicability_source_grounding','CONTRACT_PLUS_SCREEN_SOURCE_V5_3'),c.estado
from programacion.componentes c
join programacion.versiones_agente nv on nv.version_codigo='v0.4-input-readiness-semantic-sufficiency-r1-candidate'
where c.version_id=16
  and not exists(select 1 from programacion.componentes x where x.version_id=nv.id and x.componente_codigo=c.componente_codigo);

insert into programacion.contratos(version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,especificacion,fail_closed,estado)
select nv.id,c.contrato_codigo,c.tipo,c.nombre,
       c.descripcion || ' V5.3 exige grounding de applicability screen-specific en fuentes funcionales resolubles.',
       (select nc.id from programacion.componentes nc where nc.version_id=nv.id and nc.componente_codigo='INPUT_VALIDATOR'),null,
       jsonb_set(c.especificacion,'{contract_revision}','"5.3"'::jsonb,true)
       || jsonb_build_object(
          'assertion_relevance_policy','FAMILY_SOURCE_PATH_ALLOWLIST_V5_3_APPLICABILITY_CROSS_SOURCE',
          'applicability_source_grounding',jsonb_build_object(
             'contract_invariants','CONTRACT',
             'screen_specific_applicability','SCREEN_CANONICAL_GRAPH.rules OR DECLARED SPECIALIZED SOURCE',
             'na_by_absence','DENY',
             'unresolved_requires_explicit_source','REQUIRED'
          ),
          'negative_tests',(c.especificacion->'negative_tests') || jsonb_build_array('SCREEN_APPLICABILITY_WITHOUT_SOURCE_GROUNDING'),
          'audit_remediation',(c.especificacion->'audit_remediation') || jsonb_build_array('AUD-IGA-010_APPLICABILITY_SOURCE_GROUNDING')
       ),
       c.fail_closed,c.estado
from programacion.contratos c
join programacion.versiones_agente nv on nv.version_codigo='v0.4-input-readiness-semantic-sufficiency-r1-candidate'
where c.id=31
  and not exists(select 1 from programacion.contratos x where x.version_id=nv.id and x.contrato_codigo=c.contrato_codigo);

create or replace function programacion.fn_input_assertion_is_relevant(p_family_code text, p_source_ref jsonb, p_path jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
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
    when 'SECURITY' then return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/policies/security%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%');
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
    when 'API_DATA_CONTRACT','LOADING_EMPTY_ERROR_STATES','IDEMPOTENCY_CONCURRENCY','TESTING_OBLIGATIONS','BROWSER_PLATFORM','ROLLOUT_PRODUCTION_GATES','CONTEXT_BUDGET_RETRIEVAL_POLICY' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
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
end;
$$;