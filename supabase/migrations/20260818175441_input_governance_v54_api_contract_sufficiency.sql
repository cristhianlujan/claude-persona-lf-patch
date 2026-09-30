create or replace function programacion.fn_input_api_contract_resolution(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_rules jsonb := '[]'::jsonb;
  v_behavior_count integer := 0;
  v_materialized_count integer := 0;
  v_broken_count integer := 0;
  v_refs jsonb := '[]'::jsonb;
begin
  with rr as (
    select r.id,r.codigo,r.titulo,r.descripcion,r.valor_config,r.pendiente_decision,r.pendiente_detalle,r.estado
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and (
        r.valor_config ?| array['gateway','method','provider_operation_alias','consumer_contract','required_logical_inputs','required_fields','server_side_generation','server_side_verification','provider_binding']
        or r.descripcion ilike '%API_GATEWAY%'
        or r.valor_config::text ilike '%operation_alias%'
      )
  )
  select count(*),coalesce(jsonb_agg(jsonb_build_object(
    'rule_id',id,'rule_code',codigo,'title',titulo,'description',descripcion,'config',valor_config,
    'pending_decision',pendiente_decision,'pending_detail',pendiente_detalle,'status',estado
  ) order by codigo),'[]'::jsonb)
  into v_behavior_count,v_rules
  from rr;

  with candidate_refs as (
    select r.codigo rule_code,e.key ref_key,e.value ref_value
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    where rp.pantalla_id=p_pantalla_id
      and e.key in ('api_contract_id','operation_contract_id','request_schema_contract_id','response_schema_contract_id')
      and e.value ~ '^[0-9]+$'
  ), resolved as (
    select c.rule_code,c.ref_key,c.ref_value::bigint contract_id,
           pc.id is not null resolved,
           case when pc.id is null then null else jsonb_build_object(
             'contract_id',pc.id,'contract_code',pc.contrato_codigo,'type',pc.tipo,'state',pc.estado,'fail_closed',pc.fail_closed
           ) end contract
    from candidate_refs c
    left join programacion.contratos pc on pc.id=c.ref_value::bigint
  )
  select count(*) filter(where resolved),count(*) filter(where not resolved),
         coalesce(jsonb_agg(jsonb_build_object(
           'rule_code',rule_code,'ref_key',ref_key,'contract_id',contract_id,'resolved',resolved,'contract',contract
         ) order by rule_code,ref_key),'[]'::jsonb)
  into v_materialized_count,v_broken_count,v_refs
  from resolved;

  return jsonb_build_object(
    'resolution_contract','API_CONTRACT_RESOLUTION_V1',
    'pantalla_id',p_pantalla_id,
    'behavioral_contract_rule_count',v_behavior_count,
    'behavioral_contract_rules',v_rules,
    'materialized_contract_ref_count',v_materialized_count,
    'broken_contract_ref_count',v_broken_count,
    'materialized_contract_refs',v_refs,
    'has_behavioral_contract',v_behavior_count>0,
    'has_resolvable_operation_schema_authority',v_materialized_count>0 and v_broken_count=0,
    'implementation_gate',case
      when v_broken_count>0 then 'BLOCKED_BROKEN_CONTRACT_REF'
      when v_materialized_count=0 then 'NOT_READY_SOURCE_INCOMPLETE'
      else 'READY'
    end
  );
end;
$$;
revoke all on function programacion.fn_input_api_contract_resolution(integer) from public;

insert into programacion.versiones_agente(agente_id,version_codigo,objetivo,estado,supersedes_version_id,notas)
select agente_id,'v0.5-input-readiness-api-contract-sufficiency-candidate',
       objetivo || ' Distingue reglas descriptivas de un contrato API/operation/schema materializado y resoluble.',
       'candidate',id,
       'CANDIDATE_V5_4_2026-08-18: behavioral API rule may support Story Ready but cannot yield Implementation Ready without resolvable operation/schema authority. No promotion.'
from programacion.versiones_agente
where id=17
  and not exists(select 1 from programacion.versiones_agente where version_codigo='v0.5-input-readiness-api-contract-sufficiency-candidate');

insert into programacion.componentes(version_id,componente_codigo,tipo,nombre,responsabilidad,orden_ejecucion,independencia_requerida,configuracion,estado)
select nv.id,c.componente_codigo,c.tipo,c.nombre,c.responsabilidad,c.orden_ejecucion,c.independencia_requerida,
       c.configuracion || jsonb_build_object('api_contract_resolution','API_CONTRACT_RESOLUTION_V1','api_implementation_gate','MATERIALIZED_OPERATION_SCHEMA_REQUIRED'),c.estado
from programacion.componentes c
join programacion.versiones_agente nv on nv.version_codigo='v0.5-input-readiness-api-contract-sufficiency-candidate'
where c.version_id=17
  and not exists(select 1 from programacion.componentes x where x.version_id=nv.id and x.componente_codigo=c.componente_codigo);

insert into programacion.contratos(version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,especificacion,fail_closed,estado)
select nv.id,c.contrato_codigo,c.tipo,c.nombre,
       c.descripcion || ' V5.4 añade suficiencia determinística API contract.',
       (select nc.id from programacion.componentes nc where nc.version_id=nv.id and nc.componente_codigo='INPUT_VALIDATOR'),null,
       jsonb_set(
         jsonb_set(
           jsonb_set(c.especificacion,'{contract_revision}','"5.4"'::jsonb,true),
           '{screen_graph_contract}','"SCREEN_CANONICAL_GRAPH_V5_4"'::jsonb,true),
         '{source_manifest}','"DB_GENERATED_WITH_SCREEN_CANONICAL_GRAPH_V5_4"'::jsonb,true
       ) || jsonb_build_object(
          'api_data_contract_readiness',jsonb_build_object(
             'coverage','BEHAVIORAL_CONTRACT_SOURCE_IDENTIFIED',
             'well_defined','BEHAVIORAL_CONTRACT_CLEAR_AND_NON_CONTRADICTORY; MATERIALIZED_SCHEMA_STATUS_EXPLICIT',
             'story_ready','BEHAVIOR_AND_OUTCOMES_SUFFICIENT_TO_WRITE_ACCEPTANCE_CRITERIA',
             'implementation_ready','RESOLVABLE_OPERATION_OR_REQUEST_RESPONSE_SCHEMA_AUTHORITY_REQUIRED',
             'qa_ready','IMPLEMENTATION_READY_PLUS_CONTRACT_TEST_ORACLE',
             'production_ready','QA_READY_PLUS_CURRENT_DEPLOYED_AUTHORIZED_CONTRACT',
             'descriptive_rule_alone_allows_implementation_ready',false,
             'resolution_contract','API_CONTRACT_RESOLUTION_V1'
          ),
          'assertion_relevance_policy','FAMILY_SOURCE_PATH_ALLOWLIST_V5_4_API_CONTRACT',
          'negative_tests',(c.especificacion->'negative_tests') || jsonb_build_array('DESCRIPTIVE_API_RULE_AS_IMPLEMENTATION_READY_WITHOUT_RESOLVABLE_SCHEMA'),
          'audit_remediation',(c.especificacion->'audit_remediation') || jsonb_build_array('AUD-IGA-011_API_CONTRACT_SUFFICIENCY')
       ),
       c.fail_closed,c.estado
from programacion.contratos c
join programacion.versiones_agente nv on nv.version_codigo='v0.5-input-readiness-api-contract-sufficiency-candidate'
where c.version_id=17 and c.contrato_codigo='INPUT_READINESS_CONTRACT'
  and not exists(select 1 from programacion.contratos x where x.version_id=nv.id and x.contrato_codigo=c.contrato_codigo);

create or replace function programacion.fn_input_screen_canonical_graph(p_pantalla_id integer, p_version_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_screen_code text; v_module_code text; v_shell_code text; v_contract jsonb;
  v_permissions jsonb:='[]'::jsonb; v_profile_permissions jsonb:='[]'::jsonb; v_messages jsonb:='[]'::jsonb; v_analytics jsonb:='[]'::jsonb;
  v_version_code text; v_graph_contract text:='SCREEN_CANONICAL_GRAPH_V4_2';
begin
  select p.codigo,m.module_code,s.app_shell_code into v_screen_code,v_module_code,v_shell_code
  from lf_ops.pantallas p join lf_ops.modulos m on m.module_id=p.module_id join lf_ops.app_shells s on s.app_shell_id=m.app_shell_id where p.id=p_pantalla_id;
  if v_screen_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  select version_codigo into v_version_code from programacion.versiones_agente where id=p_version_id;
  if v_version_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_AGENT_VERSION_NOT_FOUND:%',p_version_id; end if;
  select f.contract into v_contract from lf_ops.fn_b2b_backoffice_login_contract(v_shell_code,v_module_code,v_screen_code) f limit 1;
  if v_contract is null then raise exception 'SCREEN_CANONICAL_CONTRACT_UNRESOLVED:%',p_pantalla_id; end if;
  v_contract:=v_contract-'metadata';

  select coalesce(jsonb_agg(jsonb_build_object('analytics_screen',to_jsonb(ap),'event',to_jsonb(ae),'parameters',coalesce((select jsonb_agg(to_jsonb(prm) order by prm.analytics_parameter_id) from lf_ops.analytics_eventos_parametros prm where prm.analytics_event_id=ae.analytics_event_id),'[]'::jsonb)) order by ap.analytics_screen_id),'[]'::jsonb)
  into v_analytics from lf_ops.analytics_pantallas ap join lf_ops.analytics_eventos_definicion ae on ae.analytics_event_id=ap.analytics_event_id where ap.pantalla_id=p_pantalla_id;
  v_contract:=jsonb_set(v_contract,'{analytics}',v_analytics,true);

  select coalesce(jsonb_agg(jsonb_build_object('link',to_jsonb(pp),'permission',to_jsonb(pm)) order by pp.permission_id),'[]'::jsonb) into v_permissions
  from lf_ops.pantallas_permisos pp join lf_ops.permisos pm on pm.permission_id=pp.permission_id where pp.pantalla_id=p_pantalla_id;

  with direct_permissions as (select pp.permission_id from lf_ops.pantallas_permisos pp where pp.pantalla_id=p_pantalla_id and pp.permission_id is not null),
  rule_permissions as (select distinct e.value::bigint permission_id from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e where rp.pantalla_id=p_pantalla_id and (e.key='permission_id' or e.key like '%_permission_id') and e.value~'^[0-9]+$'),
  relevant_permissions as (select permission_id from direct_permissions union select permission_id from rule_permissions)
  select coalesce(jsonb_agg(jsonb_build_object('screen_profile',to_jsonb(sp),'profile_permission',to_jsonb(pp),'permission',to_jsonb(pm),'authority','SCREEN_OR_RULE_SCOPED') order by sp.profile_id,pp.permission_id),'[]'::jsonb)
  into v_profile_permissions from lf_ops.pantallas_perfiles sp join lf_ops.perfiles_permisos pp on pp.profile_id=sp.profile_id join lf_ops.permisos pm on pm.permission_id=pp.permission_id
  where sp.pantalla_id=p_pantalla_id and pp.permission_id in (select permission_id from relevant_permissions);

  with field_ids as (select cp.campo_id,cp.message_id from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id),
  timeout_policy_ids as (select distinct e.value::bigint timeout_policy_id from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e where rp.pantalla_id=p_pantalla_id and (e.key='timeout_policy_id' or e.key like '%_timeout_policy_id') and e.value~'^[0-9]+$'),
  rule_message_ids as (select distinct e.value::bigint message_id from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e where rp.pantalla_id=p_pantalla_id and (e.key='message_id' or e.key like '%_message_id') and e.value~'^[0-9]+$'),
  message_ids as (select message_id from field_ids where message_id is not null union select cv.message_id from lf_ops.campos_validaciones cv join field_ids f on f.campo_id=cv.campo_id where cv.message_id is not null union select tp.message_id from lf_ops.politicas_timeout tp where tp.timeout_policy_id in (select timeout_policy_id from timeout_policy_ids) and tp.message_id is not null union select message_id from rule_message_ids)
  select coalesce(jsonb_agg(to_jsonb(mu) order by mu.message_id),'[]'::jsonb) into v_messages from lf_ops.mensajes_ui mu where mu.message_id in (select message_id from message_ids);

  if v_version_code like 'v0.5-input-readiness-api-contract-sufficiency%' then
    v_contract:=jsonb_set(v_contract,'{visual,design_bindings}',programacion.fn_input_design_binding_graph_v2(p_pantalla_id),true);
    v_contract:=jsonb_set(v_contract,'{api_contract_resolution}',programacion.fn_input_api_contract_resolution(p_pantalla_id),true);
    v_graph_contract:='SCREEN_CANONICAL_GRAPH_V5_4';
  elsif v_version_code like 'v0.4-input-readiness-semantic-sufficiency%' then
    v_contract:=jsonb_set(v_contract,'{visual,design_bindings}',programacion.fn_input_design_binding_graph_v2(p_pantalla_id),true);
    v_graph_contract:='SCREEN_CANONICAL_GRAPH_V5_2';
  elsif v_version_code like 'v0.3-input-readiness-semantic-bindings%' then
    v_contract:=jsonb_set(v_contract,'{visual,design_bindings}',programacion.fn_input_design_binding_graph(p_pantalla_id),true);
    v_graph_contract:='SCREEN_CANONICAL_GRAPH_V5_0';
  end if;

  return jsonb_build_object('graph_contract',v_graph_contract,'screen_code',v_screen_code,'module_code',v_module_code,'app_shell_code',v_shell_code,'canonical_contract',v_contract,'screen_permissions',v_permissions,'profile_permissions',v_profile_permissions,'messages',v_messages,'agent_contract_version_id',p_version_id);
end;
$$;

create or replace function programacion.fn_input_assertion_is_relevant(p_family_code text, p_source_ref jsonb, p_path jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
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
    when 'PERMISSIONS' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/screen_permissions%' or v_path like 'observed/profile_permissions%');
    when 'ERRORS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/errors%';
    when 'UI_MESSAGES' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/messages%' or v_path like 'observed/canonical_contract/fields%');
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
end;
$$;

create or replace function programacion.fn_guard_input_readiness_run()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_agent_code text; v_rule_code text; v_families jsonb; v_universe_payload jsonb; v_expected_count integer;
  v_assessment_count integer; v_pass_count integer; v_bad_validator integer; v_curator_code text; v_validator_code text;
  v_component_version bigint; v_manifest jsonb; v_current_manifest jsonb; v_current_sha text; v_version_code text;
begin
  if tg_op='INSERT' then
    if new.contract_version not in (3,4) then raise exception 'NEW_INPUT_READINESS_RUN_REQUIRES_SUPPORTED_CONTRACT'; end if;
    if new.status<>'CURATING' or new.curator_completed_at is not null or new.validator_identity is not null or new.validator_completed_at is not null or new.validator_component_id is not null or new.blocked_reason is not null or new.source_snapshot_sha256 is not null or new.source_manifest<>'[]'::jsonb or new.source_observed_at is not null then raise exception 'INPUT_READINESS_RUN_MUST_START_CLEAN_CURATING'; end if;
    if new.curator_identity !~ '^INPUT_CURATOR:' then raise exception 'INVALID_CURATOR_IDENTITY'; end if;
    select a.agente_codigo,v.version_codigo into v_agent_code,v_version_code from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id where v.id=new.version_id;
    if v_agent_code<>'INPUT_GOVERNANCE_AGENT' then raise exception 'INVALID_INPUT_GOVERNANCE_AGENT_VERSION'; end if;
    if new.contract_version=4 and not (v_version_code like 'v0.3-input-readiness-semantic-bindings%' or v_version_code like 'v0.4-input-readiness-semantic-sufficiency%' or v_version_code like 'v0.5-input-readiness-api-contract-sufficiency%') then raise exception 'CONTRACT_V4_REQUIRES_SEMANTIC_BINDING_VERSION'; end if;
    if new.contract_version=3 and (v_version_code like 'v0.3-input-readiness-semantic-bindings%' or v_version_code like 'v0.4-input-readiness-semantic-sufficiency%' or v_version_code like 'v0.5-input-readiness-api-contract-sufficiency%') then raise exception 'SEMANTIC_BINDING_VERSION_REQUIRES_CONTRACT_V4'; end if;
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
  if new.contract_version in (1,2) then if old.status in ('COMPLETED','BLOCKED') then raise exception 'TERMINAL_INPUT_READINESS_RUN_IMMUTABLE'; end if; raise exception 'LEGACY_INPUT_READINESS_RUN_NOT_MUTABLE'; end if;
  if new.version_id is distinct from old.version_id or new.pantalla_id is distinct from old.pantalla_id or new.universe_rule_id is distinct from old.universe_rule_id or new.supersedes_run_id is distinct from old.supersedes_run_id or new.scope is distinct from old.scope or new.universe_snapshot_sha256 is distinct from old.universe_snapshot_sha256 or new.family_count is distinct from old.family_count or new.curator_identity is distinct from old.curator_identity or new.curator_component_id is distinct from old.curator_component_id or new.contract_version is distinct from old.contract_version or new.created_at is distinct from old.created_at then raise exception 'INPUT_READINESS_RUN_IDENTITY_IMMUTABLE'; end if;
  if old.status in ('COMPLETED','BLOCKED') then raise exception 'TERMINAL_INPUT_READINESS_RUN_IMMUTABLE'; end if;
  if old.status='CURATING' and new.status not in ('CURATING','VALIDATING','BLOCKED') then raise exception 'INVALID_RUN_TRANSITION:%->%',old.status,new.status; end if;
  if old.status='VALIDATING' and new.status not in ('VALIDATING','COMPLETED','BLOCKED') then raise exception 'INVALID_RUN_TRANSITION:%->%',old.status,new.status; end if;
  if not (old.status='CURATING' and new.status='VALIDATING') then
    if new.source_snapshot_sha256 is distinct from old.source_snapshot_sha256 or new.source_manifest is distinct from old.source_manifest or new.source_observed_at is distinct from old.source_observed_at then raise exception 'SOURCE_MANIFEST_FIELDS_IMMUTABLE'; end if;
    if new.validator_identity is distinct from old.validator_identity or new.validator_component_id is distinct from old.validator_component_id then raise exception 'RUN_VALIDATOR_IDENTITY_IMMUTABLE'; end if;
  end if;
  if old.status='CURATING' and new.status='VALIDATING' then
    if new.source_snapshot_sha256 is distinct from old.source_snapshot_sha256 or new.source_manifest is distinct from old.source_manifest or new.source_observed_at is distinct from old.source_observed_at then raise exception 'SOURCE_MANIFEST_MUST_BE_DB_GENERATED'; end if;
    if new.validator_identity is null or new.validator_identity !~ '^INPUT_VALIDATOR:' or new.validator_identity=new.curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
    if new.validator_component_id is null then raise exception 'VALIDATOR_COMPONENT_REQUIRED'; end if;
    select c.componente_codigo,c.version_id into v_validator_code,v_component_version from programacion.componentes c where c.id=new.validator_component_id;
    if v_validator_code<>'INPUT_VALIDATOR' or v_component_version<>new.version_id or new.validator_component_id=new.curator_component_id then raise exception 'INVALID_VALIDATOR_COMPONENT'; end if;
    select count(*) into v_assessment_count from programacion.input_family_assessments where run_id=old.id;
    if v_assessment_count<>old.family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE expected=% actual=%',old.family_count,v_assessment_count; end if;
    v_manifest:=programacion.fn_input_build_source_manifest(old.id); new.source_manifest:=v_manifest; new.source_snapshot_sha256:=programacion.fn_v09_sha256_jsonb(v_manifest); new.source_observed_at:=now(); new.curator_completed_at:=coalesce(new.curator_completed_at,now());
  end if;
  if new.status='COMPLETED' then
    if new.validator_identity is null or new.validator_component_id is null then raise exception 'RUN_VALIDATOR_AUTHORITY_REQUIRED'; end if;
    v_current_manifest:=programacion.fn_input_build_source_manifest(old.id); v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
    if v_current_sha<>old.source_snapshot_sha256 or v_current_manifest<>old.source_manifest then raise exception 'SOURCE_SNAPSHOT_STALE_AT_COMPLETION'; end if;
    select count(*),count(*) filter(where validator_outcome='PASS'),count(*) filter(where validator_identity is distinct from old.validator_identity or validator_evidence->>'source_snapshot_sha256' is distinct from old.source_snapshot_sha256) into v_assessment_count,v_pass_count,v_bad_validator from programacion.input_family_assessments where run_id=old.id;
    if v_assessment_count<>old.family_count or v_pass_count<>old.family_count or v_bad_validator>0 then raise exception 'VALIDATOR_UNIVERSE_NOT_FULL_AUTHORIZED_PASS expected=% assessed=% pass=% bad=%',old.family_count,v_assessment_count,v_pass_count,v_bad_validator; end if;
    new.validator_completed_at:=coalesce(new.validator_completed_at,now());
  end if;
  return new;
end;
$$;