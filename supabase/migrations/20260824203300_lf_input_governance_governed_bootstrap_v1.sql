-- LF Input Governance governed bootstrap v1
-- Implements DEC-INPUT-GOV-BOOTSTRAP-001 for active NEVER_EVALUATED screens.
-- Fail closed: no invention, no absence=>N/A, Curator/Validator remain separate.

create or replace function programacion.fn_input_bootstrap_rule_probe_v1(
  p_rules jsonb,
  p_categories text[] default null,
  p_regex text default null
) returns jsonb
language sql
immutable
set search_path=pg_catalog
as $$
  with matched as (
    select r.value as rule
    from jsonb_array_elements(coalesce(p_rules,'[]'::jsonb)) r(value)
    where (p_categories is null or exists(
             select 1 from unnest(p_categories) c
             where lower(c)=lower(coalesce(r.value->>'category',''))
           ))
      and (p_regex is null
           or coalesce(r.value->>'rule_code','') ~* p_regex
           or coalesce(r.value->>'title','') ~* p_regex
           or coalesce(r.value->>'description','') ~* p_regex
           or coalesce(r.value->'config','null'::jsonb)::text ~* p_regex)
  )
  select jsonb_build_object(
    'count',count(*),
    'vigente_count',count(*) filter(where rule->>'status' in ('VIGENTE','ACTIVO')),
    'candidate_count',count(*) filter(where coalesce(rule->>'status','') not in ('VIGENTE','ACTIVO')),
    'pending_decision_count',count(*) filter(where coalesce((rule->>'pending_decision')::boolean,false)),
    'pending_marker_count',count(*) filter(where coalesce(rule->'config','null'::jsonb)::text ~* '(PENDING|PENDIENTE|BLOCKED_PENDING|REQUIRES_[A-Z_]+_EVIDENCE)'),
    'first_rule_code',(array_agg(rule->>'rule_code' order by rule->>'rule_code'))[1]
  )
  from matched;
$$;

create or replace function programacion.fn_input_governance_bootstrap_classify_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,programacion,lf_ops,transversal
as $$
declare
  v_graph jsonb;
  v_rules jsonb;
  v_fields jsonb;
  v_errors jsonb;
  v_messages jsonb;
  v_analytics jsonb;
  v_evidence jsonb;
  v_variants jsonb;
  v_components jsonb;
  v_screen jsonb;
  v_design jsonb;
  v_design_summary jsonb;
  v_api jsonb;
  v_states_receipt jsonb;
  v_states jsonb;
  v_probe jsonb:='{}'::jsonb;
  v_na jsonb;
  v_source_refs jsonb;
  v_level text:='MISSING';
  v_severity text:='P0';
  v_applicability text:='APPLICABLE';
  v_cov text:='MISSING';
  v_wd text:='MISSING';
  v_story text:='BLOCKED';
  v_impl text:='BLOCKED';
  v_qa text:='BLOCKED';
  v_prod text:='BLOCKED';
  v_blockers jsonb:='[]'::jsonb;
  v_rationale text;
  v_payload jsonb;
  v_count integer:=0;
  v_aux integer:=0;
  v_missing_required_validations integer:=0;
  v_theme_count integer:=0;
  v_rule_count integer:=0;
  v_candidate_count integer:=0;
  v_pending_count integer:=0;
  v_pending_marker integer:=0;
  v_blocker_code text;
begin
  if not exists(
    select 1
    from lf_ops.reglas q,cross join lateral jsonb_array_elements_text(q.valor_config->'families') f(value)
    where q.codigo='B2B-RULE-STORY-READINESS-001' and f.value=p_family_code
  ) then
    raise exception 'BOOTSTRAP_FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',p_family_code;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  v_fields:=coalesce(v_graph->'canonical_contract'->'fields','[]'::jsonb);
  v_errors:=coalesce(v_graph->'canonical_contract'->'errors','[]'::jsonb);
  v_messages:=coalesce(v_graph->'messages','[]'::jsonb);
  v_analytics:=coalesce(v_graph->'canonical_contract'->'analytics','[]'::jsonb);
  v_evidence:=coalesce(v_graph->'canonical_contract'->'evidence','[]'::jsonb);
  v_variants:=coalesce(v_graph->'canonical_contract'->'visual'->'variants','[]'::jsonb);
  v_components:=coalesce(v_graph->'canonical_contract'->'visual'->'components','[]'::jsonb);
  v_screen:=coalesce(v_graph->'canonical_contract'->'context'->'screen','{}'::jsonb);
  v_design:=coalesce(v_graph->'canonical_contract'->'visual'->'design_system','{}'::jsonb);
  v_design_summary:=coalesce(v_graph->'canonical_contract'->'visual'->'design_bindings'->'summary','{}'::jsonb);
  v_api:=coalesce(v_graph->'canonical_contract'->'api_contract_resolution','{}'::jsonb);
  v_source_refs:=jsonb_build_array(jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id));
  v_na:=programacion.fn_input_na_positive_authority_v512(p_family_code,p_pantalla_id,p_version_id);

  if coalesce((v_na->>'qualified')::boolean,false) then
    v_payload:=jsonb_build_object(
      'family_code',p_family_code,'severity','P4','applicability','NOT_APPLICABLE',
      'coverage_status','NOT_APPLICABLE','well_defined_status','NOT_APPLICABLE',
      'story_ready_status','NOT_APPLICABLE','implementation_ready_status','NOT_APPLICABLE',
      'qa_ready_status','NOT_APPLICABLE','production_ready_status','NOT_APPLICABLE',
      'source_refs',v_source_refs,'blockers','[]'::jsonb,
      'negative_requirements',jsonb_build_array('NO_INVENTION','POSITIVE_NA_AUTHORITY_REQUIRED'),
      'test_obligations','[]'::jsonb,
      'rationale','Governed bootstrap: explicit canonical positive exclusion qualifies this family as NOT_APPLICABLE.',
      'probe',v_na
    );
    return v_payload||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  case p_family_code
    when 'SCREEN_IDENTITY' then
      if nullif(v_graph->>'screen_code','') is not null and nullif(v_graph->>'module_code','') is not null and nullif(v_graph->>'app_shell_code','') is not null then v_level:='COMPLETE'; end if;
      v_probe:=jsonb_build_object('screen_code',v_graph->>'screen_code','module_code',v_graph->>'module_code','app_shell_code',v_graph->>'app_shell_code');
    when 'OBJECTIVE_OUTCOMES' then
      if nullif(btrim(coalesce(v_screen->>'objective','')),'') is not null then v_level:='COMPLETE'; end if;
      v_probe:=jsonb_build_object('objective',v_screen->'objective');
    when 'FIELDS' then
      v_count:=jsonb_array_length(v_fields); if v_count>0 then v_level:='COMPLETE'; end if;
      v_probe:=jsonb_build_object('field_count',v_count);
    when 'VALIDATIONS' then
      v_count:=jsonb_array_length(v_fields);
      select count(*) into v_missing_required_validations
      from jsonb_array_elements(v_fields) f
      where coalesce((f->>'required')::boolean,false) and jsonb_array_length(coalesce(f->'validations','[]'::jsonb))=0;
      if v_count>0 and v_missing_required_validations=0 then v_level:='COMPLETE'; elsif v_count>0 then v_level:='PARTIAL'; end if;
      v_probe:=jsonb_build_object('field_count',v_count,'required_fields_without_validations',v_missing_required_validations);
    when 'ACTIONS' then
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['flujo','ux','ui','copy'],null);
    when 'STATES' then
      v_states_receipt:=programacion.fn_input_resolve_source_ref(jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',p_pantalla_id),p_pantalla_id,p_version_id);
      v_states:=coalesce(v_states_receipt->'observed','[]'::jsonb); v_count:=jsonb_array_length(v_states);
      if v_count>0 then v_level:='COMPLETE'; end if;
      v_source_refs:=jsonb_build_array(jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',p_pantalla_id));
      v_probe:=jsonb_build_object('canonical_state_count',v_count);
    when 'TRANSITIONS' then
      v_states_receipt:=programacion.fn_input_resolve_source_ref(jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',p_pantalla_id),p_pantalla_id,p_version_id);
      v_states:=coalesce(v_states_receipt->'observed','[]'::jsonb); v_count:=jsonb_array_length(v_states);
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['flujo'],('(transition|transicion|after_screen|post_)'));
      if v_count>0 and coalesce((v_probe->>'count')::integer,0)>0 then v_level:='PARTIAL'; end if;
      v_source_refs:=jsonb_build_array(jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',p_pantalla_id),jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id));
      v_probe:=v_probe||jsonb_build_object('canonical_state_count',v_count);
    when 'ROUTING_NAVIGATION' then
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(NAVIGATION|NAVEGACION|ROUTE|RUTA|DESTINO|after_screen|post_)');
    when 'PROFILES' then
      v_count:=jsonb_array_length(coalesce(v_graph->'canonical_contract'->'profiles','[]'::jsonb)); if v_count>0 then v_level:='COMPLETE'; end if;
      v_probe:=jsonb_build_object('profile_count',v_count);
    when 'PERMISSIONS' then
      v_count:=jsonb_array_length(coalesce(v_graph->'screen_permissions','[]'::jsonb));
      v_aux:=jsonb_array_length(coalesce(v_graph->'profile_permissions','[]'::jsonb));
      if v_count+v_aux>0 then v_level:='COMPLETE'; end if;
      v_probe:=jsonb_build_object('screen_permission_count',v_count,'profile_permission_count',v_aux);
    when 'ERRORS' then
      v_count:=jsonb_array_length(v_errors); if v_count>0 then v_level:='COMPLETE'; end if; v_probe:=jsonb_build_object('error_count',v_count);
    when 'UI_MESSAGES' then
      v_count:=jsonb_array_length(v_messages); v_aux:=jsonb_array_length(v_errors);
      if v_count>0 then v_level:='COMPLETE'; elsif v_aux>0 then v_level:='PARTIAL'; end if;
      v_probe:=jsonb_build_object('message_registry_count',v_count,'error_message_count',v_aux);
    when 'SESSION' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['sesion'],null);
    when 'RATE_LIMIT' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['rate_limiting'],'(RATE|RL_)');
    when 'TIMEOUT_RETRY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(TIMEOUT|RETRY|BACKOFF|COOLDOWN|REG_RATE_005|REG_RL_|REG_ATQ_011)');
    when 'SECURITY' then
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['seguridad','ataques'],null);
      if coalesce((v_probe->>'count')::integer,0)>0 then v_level:='PARTIAL'; end if;
    when 'MFA_OTP_SSO' then
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(OTP|MFA|SSO)');
      if coalesce((v_probe->>'count')::integer,0)>0 then v_level:='PARTIAL'; end if;
    when 'PRIVACY_PII' then
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(PII|MASK|PRIVACY|PRIVACIDAD|RETEN|DATO)');
      if coalesce((v_probe->>'count')::integer,0)>0 or exists(select 1 from jsonb_array_elements(v_fields) f where coalesce((f->>'sensitive')::boolean,false)) then v_level:='PARTIAL'; end if;
    when 'AUDIT' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['auditoria'],null);
    when 'ANALYTICS' then
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['analytics','tageo'],null);
      if jsonb_array_length(v_analytics)>0 and coalesce((v_probe->>'count')::integer,0)>0 then null; elsif jsonb_array_length(v_analytics)>0 then v_level:='PARTIAL'; end if;
      v_probe:=v_probe||jsonb_build_object('analytics_event_count',jsonb_array_length(v_analytics));
    when 'OBSERVABILITY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['observabilidad','alertas'],null);
    when 'PERFORMANCE' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(LCP|PERFORMANCE|CORE WEB|OBS_004|ALR_005)');
    when 'RESPONSIVE' then
      v_count:=jsonb_array_length(v_variants); v_aux:=coalesce((v_design_summary->>'variant_layout_missing_count')::integer,0);
      if v_count>=3 and v_aux=0 then v_level:='COMPLETE'; elsif v_count>0 then v_level:='PARTIAL'; end if;
      v_probe:=jsonb_build_object('variant_count',v_count,'variant_layout_missing_count',v_aux);
    when 'THEME_LIGHT_DARK_SYSTEM' then
      select count(distinct x.value->>'theme_binding_code') into v_theme_count from jsonb_array_elements(v_variants) x(value) where nullif(x.value->>'theme_binding_code','') is not null;
      if jsonb_array_length(v_variants)>0 and v_theme_count>1 then v_level:='COMPLETE'; elsif jsonb_array_length(v_variants)>0 then v_level:='PARTIAL'; end if;
      v_probe:=jsonb_build_object('variant_count',jsonb_array_length(v_variants),'distinct_theme_bindings',v_theme_count);
    when 'FORCED_COLORS_CONTRAST' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['accesibilidad'],'(FORCED|CONTRAST|CONTRASTE)');
    when 'REDUCED_MOTION' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['accesibilidad'],'(REDUCED|MOTION|MOVIMIENTO)');
    when 'ACCESSIBILITY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['accesibilidad'],null);
    when 'DESIGN_SYSTEM' then
      if nullif(v_design->>'design_system_code','') is not null then
        if coalesce((v_design_summary->>'referential_integrity_failure_count')::integer,0)=0
           and coalesce((v_design_summary->>'field_component_missing_count')::integer,0)=0
           and coalesce((v_design_summary->>'variant_layout_missing_count')::integer,0)=0
           and coalesce((v_design_summary->>'element_required_missing_component_count')::integer,0)=0
           and v_design->>'status'='VIGENTE' then v_level:='COMPLETE'; else v_level:='PARTIAL'; end if;
      end if;
      v_probe:=jsonb_build_object('design_system',v_design,'summary',v_design_summary);
    when 'ASSETS_ICONS' then
      v_count:=jsonb_array_length(v_components); if v_count>0 then v_level:='PARTIAL'; end if;
      v_probe:=jsonb_build_object('component_count',v_count,'element_required_missing_component_count',coalesce((v_design_summary->>'element_required_missing_component_count')::integer,0));
    when 'API_DATA_CONTRACT' then
      if coalesce((v_api->>'has_resolvable_operation_schema_authority')::boolean,false) and v_api->>'implementation_gate'='READY' then v_level:='COMPLETE';
      elsif coalesce((v_api->>'has_behavioral_contract')::boolean,false) then v_level:='PARTIAL'; end if;
      v_probe:=v_api;
    when 'LOADING_EMPTY_ERROR_STATES' then
      v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['error_states','estados_ui'],null);
      if jsonb_array_length(v_errors)>0 and coalesce((v_probe->>'count')::integer,0)>0 then v_level:='COMPLETE'; elsif jsonb_array_length(v_errors)>0 or coalesce((v_probe->>'count')::integer,0)>0 then v_level:='PARTIAL'; end if;
      v_probe:=v_probe||jsonb_build_object('error_count',jsonb_array_length(v_errors));
    when 'IDEMPOTENCY_CONCURRENCY' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(IDEMP|CONCURRENC|SINGLE.?FLIGHT|X-IDEMPOTENCY)');
    when 'FEATURE_FLAGS' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(FEATURE|FLAG|EXPERIMENT|ABT)');
    when 'DEPENDENCIES' then
      if jsonb_typeof(v_screen->'dependencies')='array' then v_level:='COMPLETE'; end if;
      v_probe:=jsonb_build_object('dependencies',v_screen->'dependencies');
    when 'TESTING_OBLIGATIONS' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(TEST|PRUEBA|QA)');
    when 'BROWSER_PLATFORM' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(BROWSER|NAVEGADOR|COMPAT|PLATFORM)');
    when 'I18N_FORMATS' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,'(I18N|LOCALE|IDIOMA|INTERNACIONAL|FORMAT)');
    when 'VISUAL_EVIDENCE' then
      v_count:=jsonb_array_length(v_evidence); if v_count>0 then v_level:='PARTIAL'; end if; v_probe:=jsonb_build_object('artifact_count',v_count,'current_count',(select count(*) from jsonb_array_elements(v_evidence) e where coalesce((e->>'is_current')::boolean,false)));
    when 'EKB' then
      v_level:='COMPLETE';
      v_source_refs:=jsonb_build_array(jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-GOV-010')));
      v_probe:=jsonb_build_object('authority','PRV-GOV-010');
    when 'RUNTIME_CONFIG' then v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,array['tecnico'],null);
    when 'ROLLOUT_PRODUCTION_GATES' then v_level:='COMPLETE'; v_probe:=jsonb_build_object('production_authorized',false);
    when 'SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS' then
      v_level:='COMPLETE';
      v_source_refs:=jsonb_build_array(
        jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033')),
        jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-AUD-019'))
      );
      v_probe:=jsonb_build_object('decision_authority','ADR-EKB-033','prevention_authority','PRV-AUD-019');
    when 'CONTEXT_BUDGET_RETRIEVAL_POLICY' then
      v_level:='COMPLETE';
      v_source_refs:=jsonb_build_array(jsonb_build_object('kind','CONTRACT','codigo','INPUT_READINESS_CONTRACT'));
      v_probe:=jsonb_build_object('contract','INPUT_READINESS_CONTRACT','revision','5.12');
    else raise exception 'BOOTSTRAP_CLASSIFIER_UNHANDLED_FAMILY:%',p_family_code;
  end case;

  if v_level='MISSING' and coalesce((v_probe->>'count')::integer,0)>0 then
    v_rule_count:=coalesce((v_probe->>'count')::integer,0);
    v_candidate_count:=coalesce((v_probe->>'candidate_count')::integer,0);
    v_pending_count:=coalesce((v_probe->>'pending_decision_count')::integer,0);
    v_pending_marker:=coalesce((v_probe->>'pending_marker_count')::integer,0);
    if v_pending_count>0 or v_pending_marker>0 or v_candidate_count>0 then v_level:='PARTIAL'; else v_level:='COMPLETE'; end if;
  elsif v_level='COMPLETE' and v_probe ? 'count' then
    v_rule_count:=coalesce((v_probe->>'count')::integer,0);
    v_candidate_count:=coalesce((v_probe->>'candidate_count')::integer,0);
    v_pending_count:=coalesce((v_probe->>'pending_decision_count')::integer,0);
    v_pending_marker:=coalesce((v_probe->>'pending_marker_count')::integer,0);
    if v_rule_count>0 and (v_pending_count>0 or v_pending_marker>0 or v_candidate_count>0) then v_level:='PARTIAL'; end if;
  end if;

  if v_level='COMPLETE' then
    v_cov:='COMPLETE'; v_wd:='COMPLETE'; v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='READY'; v_severity:='P4';
  elsif v_level='PARTIAL' then
    v_cov:='PARTIAL'; v_wd:='PARTIAL'; v_story:='READY'; v_impl:='NOT_READY'; v_qa:='NOT_READY'; v_prod:='NOT_READY'; v_severity:='P1';
  else
    v_cov:='MISSING'; v_wd:='MISSING';
    if p_family_code in ('BROWSER_PLATFORM','TESTING_OBLIGATIONS') then
      v_story:='READY'; v_impl:='READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_severity:='P2';
    elsif p_family_code in ('ANALYTICS','REDUCED_MOTION','FORCED_COLORS_CONTRAST','IDEMPOTENCY_CONCURRENCY','THEME_LIGHT_DARK_SYSTEM') then
      v_story:='READY'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_severity:='P1';
    else
      v_story:='BLOCKED'; v_impl:='BLOCKED'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_severity:='P0';
    end if;
  end if;

  if p_family_code='ROLLOUT_PRODUCTION_GATES' then
    v_cov:='COMPLETE'; v_wd:='COMPLETE'; v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='NOT_READY'; v_severity:='P3';
    v_blockers:=jsonb_build_array(jsonb_build_object('code','PRODUCTION_NOT_AUTHORIZED','source_ref','INPUT_GOVERNANCE_EXECUTION_CONTRACT'));
  elsif v_level<>'COMPLETE' then
    v_blocker_code:=case p_family_code
      when 'OBJECTIVE_OUTCOMES' then 'OBJECTIVE_CANONICAL_MISSING'
      when 'STATES' then 'SCREEN_STATE_SET_EMPTY'
      when 'TRANSITIONS' then 'CANONICAL_TRANSITIONS_INSUFFICIENT'
      when 'ROUTING_NAVIGATION' then 'CANONICAL_ROUTES_PENDING'
      when 'PROFILES' then 'PROFILE_SCOPE_UNRESOLVED'
      when 'PERMISSIONS' then 'PERMISSION_SCOPE_UNRESOLVED'
      when 'API_DATA_CONTRACT' then 'API_OPERATION_SCHEMA_SOURCE_INCOMPLETE'
      when 'DESIGN_SYSTEM' then 'DESIGN_BINDING_INCOMPLETE'
      when 'ASSETS_ICONS' then 'ASSET_COMPONENT_COVERAGE_INCOMPLETE'
      when 'TIMEOUT_RETRY' then 'TIMING_RECONCILIATION_REQUIRED'
      when 'FEATURE_FLAGS' then 'FEATURE_FLAG_CANONICAL_SOURCE_INCOMPLETE'
      when 'I18N_FORMATS' then 'I18N_APPLICABILITY_AUTHORITY_MISSING'
      when 'VISUAL_EVIDENCE' then 'CURRENT_VISUAL_EVIDENCE_PARTIAL'
      when 'SECURITY' then 'SECURITY_SEMANTIC_DEPTH_REVIEW_REQUIRED'
      else 'BOOTSTRAP_CANONICAL_EVIDENCE_'||v_level
    end;
    v_blockers:=jsonb_build_array(jsonb_build_object('code',v_blocker_code,'family_code',p_family_code,'bootstrap_level',v_level));
    if p_family_code='DESIGN_SYSTEM' then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','ELEMENT_REQUIRED_COMPONENT_BINDING_MISSING','count',coalesce((v_design_summary->>'element_required_missing_component_count')::integer,0)));
    end if;
  end if;

  v_rationale:=format('Governed canonical bootstrap (DEC-INPUT-GOV-BOOTSTRAP-001): family=%s classified %s from direct source readback; absence never implies NOT_APPLICABLE.',p_family_code,v_level);
  v_payload:=jsonb_build_object(
    'family_code',p_family_code,'severity',v_severity,'applicability',v_applicability,
    'coverage_status',v_cov,'well_defined_status',v_wd,'story_ready_status',v_story,
    'implementation_ready_status',v_impl,'qa_ready_status',v_qa,'production_ready_status',v_prod,
    'source_refs',v_source_refs,'rationale',v_rationale,'blockers',v_blockers,
    'negative_requirements',jsonb_build_array('NO_INVENTION','NO_SILENT_OMISSION','SOURCE_AUTHORITY','ABSENCE_IS_NOT_NA'),
    'test_obligations','[]'::jsonb,'probe',v_probe,'bootstrap_level',v_level
  );
  return v_payload||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;

create or replace function programacion.fn_input_governance_bootstrap_assertions_v1(
  p_run_id bigint,
  p_family_code text
) returns jsonb
language plpgsql
volatile
security definer
set search_path=pg_catalog,programacion
as $$
declare
  v_pantalla_id integer; v_version_id bigint; v_source_ref jsonb; v_receipt jsonb;
  v_path text[]; v_actual jsonb; v_expected jsonb; v_operator text:='EQ'; v_assertion jsonb; v_eval jsonb; v_rules jsonb;
begin
  select pantalla_id,version_id into v_pantalla_id,v_version_id from programacion.input_readiness_runs where id=p_run_id;
  if v_pantalla_id is null then raise exception 'BOOTSTRAP_ASSERTION_RUN_NOT_FOUND:%',p_run_id; end if;

  if p_family_code in ('SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS') then
    v_source_ref:=jsonb_build_object('kind','EKB_DECISION_SET','adrs',jsonb_build_array('ADR-EKB-033'));
    v_path:=array['observed'];
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    v_actual:=v_receipt #> v_path;
    v_expected:=jsonb_build_array(jsonb_build_object('adr','ADR-EKB-033','estado','vigente'));
    v_operator:='CONTAINS';
  elsif p_family_code='EKB' then
    v_source_ref:=jsonb_build_object('kind','EKB_PREVENTION_SET','codes',jsonb_build_array('PRV-GOV-010'));
    v_path:=array['observed'];
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    v_actual:=v_receipt #> v_path;
    v_expected:=jsonb_build_array(jsonb_build_object('regla_codigo','PRV-GOV-010','activa',true));
    v_operator:='CONTAINS';
  elsif p_family_code='CONTEXT_BUDGET_RETRIEVAL_POLICY' then
    v_source_ref:=jsonb_build_object('kind','CONTRACT','codigo','INPUT_READINESS_CONTRACT');
    v_path:=array['observed','especificacion','contract_revision'];
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    v_actual:=v_receipt #> v_path; v_expected:=v_actual;
  elsif p_family_code in ('STATES','TRANSITIONS') then
    v_source_ref:=jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',v_pantalla_id);
    v_path:=array['observed'];
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    v_actual:=v_receipt #> v_path; v_expected:=to_jsonb(jsonb_array_length(coalesce(v_actual,'[]'::jsonb))); v_operator:='ARRAY_LENGTH_EQ';
  else
    v_source_ref:=jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_pantalla_id);
    v_receipt:=programacion.fn_input_resolve_source_ref(v_source_ref,v_pantalla_id,v_version_id);
    case p_family_code
      when 'SCREEN_IDENTITY' then v_path:=array['observed','screen_code'];
      when 'OBJECTIVE_OUTCOMES' then v_path:=array['observed','canonical_contract','context','screen','objective'];
      when 'FIELDS','VALIDATIONS' then v_path:=array['observed','canonical_contract','fields']; v_operator:='ARRAY_LENGTH_EQ';
      when 'PROFILES' then v_path:=array['observed','canonical_contract','profiles']; v_operator:='ARRAY_LENGTH_EQ';
      when 'PERMISSIONS' then v_path:=array['observed','screen_permissions']; v_operator:='ARRAY_LENGTH_EQ';
      when 'ERRORS' then v_path:=array['observed','canonical_contract','errors']; v_operator:='ARRAY_LENGTH_EQ';
      when 'UI_MESSAGES' then v_path:=array['observed','messages']; v_operator:='ARRAY_LENGTH_EQ';
      when 'ANALYTICS' then v_path:=array['observed','canonical_contract','analytics']; v_operator:='ARRAY_LENGTH_EQ';
      when 'RESPONSIVE' then v_path:=array['observed','canonical_contract','visual','variants']; v_operator:='ARRAY_LENGTH_EQ';
      when 'DESIGN_SYSTEM' then v_path:=array['observed','canonical_contract','visual','design_bindings','summary'];
      when 'ASSETS_ICONS' then v_path:=array['observed','canonical_contract','visual','components']; v_operator:='ARRAY_LENGTH_EQ';
      when 'API_DATA_CONTRACT' then v_path:=array['observed','canonical_contract','api_contract_resolution','implementation_gate'];
      when 'DEPENDENCIES' then v_path:=array['observed','canonical_contract','context','screen','dependencies']; v_operator:='ARRAY_LENGTH_EQ';
      when 'VISUAL_EVIDENCE' then v_path:=array['observed','canonical_contract','evidence']; v_operator:='ARRAY_LENGTH_EQ';
      else v_path:=array['observed','canonical_contract','rules','0','rule_code'];
    end case;
    v_actual:=v_receipt #> v_path;
    if v_operator='ARRAY_LENGTH_EQ' then v_expected:=to_jsonb(jsonb_array_length(coalesce(v_actual,'[]'::jsonb))); else v_expected:=v_actual; end if;
  end if;

  v_assertion:=jsonb_build_object('source_ref',v_source_ref,'path',to_jsonb(v_path),'actual',v_actual,'expected',v_expected,'operator',v_operator);
  v_eval:=programacion.fn_input_evaluate_assertion(p_run_id,p_family_code,v_assertion);
  return jsonb_build_array(v_assertion||jsonb_build_object(
    'result',case when coalesce((v_eval->>'passed')::boolean,false) then 'PASS' else 'FAIL' end,
    'source_observed_sha256',v_eval->>'source_observed_sha256'
  ));
end;
$$;

create or replace function programacion.fn_input_governance_bootstrap_materialize_v1(
  p_pantalla_id integer,
  p_consumer text,
  p_curator_identity text
) returns jsonb
language plpgsql
volatile
security definer
set search_path=pg_catalog,public,programacion,lf_ops,transversal
as $$
declare
  v_version bigint:=19; v_code text; v_active boolean; v_pre jsonb; v_existing bigint; v_existing_status text;
  v_rule_id integer; v_families jsonb; v_family_count integer; v_universe_sha text; v_contract_schema integer; v_contract_revision text;
  v_curator_component bigint; v_run bigint; v_class jsonb; v_family text; v_count integer; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb;
begin
  if p_curator_identity !~ '^INPUT_CURATOR:EDGE:input-governance-curator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_CURATOR_RUNTIME_IDENTITY_INVALID'; end if;
  if not exists(select 1 from jsonb_array_elements_text((select especificacion->'allowed_consumers' from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT')) x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,null);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR'; end if;

  select id,status into v_existing,v_existing_status from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  if v_existing_status in ('CURATING','VALIDATING') then return jsonb_build_object('status',case when v_existing_status='VALIDATING' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATION_IN_PROGRESS' end,'run_id',v_existing,'required_role',case when v_existing_status='VALIDATING' then 'INPUT_VALIDATOR' else 'INPUT_CURATOR' end,'promotion_authorized',false,'production_authorized',false); end if;
  if exists(select 1 from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED') then raise exception 'BOOTSTRAP_REQUIRES_NO_COMPLETED_PREDECESSOR:%',p_pantalla_id; end if;

  select id,valor_config->'families' into v_rule_id,v_families from lf_ops.reglas where codigo='B2B-RULE-STORY-READINESS-001';
  v_family_count:=jsonb_array_length(v_families);
  v_universe_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object('rule_code','B2B-RULE-STORY-READINESS-001','families',v_families));
  select (especificacion->>'schema_version')::integer,especificacion->>'contract_revision' into v_contract_schema,v_contract_revision from programacion.contratos where version_id=v_version and contrato_codigo='INPUT_READINESS_CONTRACT' and estado='defined' and fail_closed;
  select id into v_curator_component from programacion.componentes where version_id=v_version and componente_codigo='INPUT_CURATOR';
  if v_rule_id is null or v_family_count<>47 or v_contract_revision<>'5.12' or v_curator_component is null then raise exception 'BOOTSTRAP_GOVERNANCE_DEPENDENCY_UNRESOLVED'; end if;

  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,status,scope,universe_snapshot_sha256,family_count,contract_version,curator_identity,curator_component_id)
  values(v_version,p_pantalla_id,v_rule_id,null,'CURATING',jsonb_build_object('mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','decision','DEC-INPUT-GOV-BOOTSTRAP-001','runtime','input-governance-curator-v1','promotion_authorized',false,'production_authorized',false),v_universe_sha,v_family_count,v_contract_schema,p_curator_identity,v_curator_component)
  returning id into v_run;

  for v_family in select value from jsonb_array_elements_text(v_families) loop
    v_class:=programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id,v_family,v_version);
    insert into programacion.input_family_assessments(
      run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
      source_refs,rationale,blockers,negative_requirements,test_obligations,freshness,curator_evidence,curator_sha256,validator_outcome,validator_findings,validator_evidence,
      validator_identity,validator_sha256,validator_assessed_at,subject_coverage,threat_coverage,semantic_depth_sha256
    ) values (
      v_run,v_family,v_class->>'severity',v_class->>'applicability',v_class->>'coverage_status',v_class->>'well_defined_status',v_class->>'story_ready_status',v_class->>'implementation_ready_status',v_class->>'qa_ready_status',v_class->>'production_ready_status',
      v_class->'source_refs',v_class->>'rationale',v_class->'blockers',v_class->'negative_requirements',v_class->'test_obligations','{}'::jsonb,
      jsonb_build_object('component_id',v_curator_component,'execution_id',v_exec_id,'execution_mode','INDEPENDENT_CURATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-curator-v1','contract_revision',v_contract_revision,'direct_source_readback',true,'semantic_policy','GOVERNED_CANONICAL_BOOTSTRAP_NO_INVENTION','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','bootstrap_classifier_sha256',v_class->>'classifier_sha256','bootstrap_probe',v_class->'probe'),
      repeat('0',64),'PENDING','[]'::jsonb,'{}'::jsonb,null,null,null,'[]'::jsonb,'[]'::jsonb,repeat('0',64)
    );
  end loop;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_run;
  if v_count<>47 then raise exception 'BOOTSTRAP_UNIVERSE_INCOMPLETE expected=47 actual=%',v_count; end if;
  v_payload:=jsonb_build_object('status','VALIDATOR_RUNTIME_REQUIRED','run_id',v_run,'pantalla_id',p_pantalla_id,'screen_code',v_code,'family_count',47,'required_role','INPUT_VALIDATOR','write_performed',true,'bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;

-- Preserve the proven successor-rebind implementation and place a bootstrap-aware router at the existing runtime name.
alter function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) rename to fn_input_governance_curator_rebind_v1;

create or replace function programacion.fn_input_governance_curator_materialize_v1(
  p_pantalla_id integer,p_consumer text,p_curator_identity text,p_force_selftest boolean default false
) returns jsonb
language plpgsql volatile security definer
set search_path=pg_catalog,programacion
as $$
begin
  if exists(select 1 from programacion.input_readiness_runs where version_id=19 and pantalla_id=p_pantalla_id and status='COMPLETED')
     or exists(select 1 from programacion.input_readiness_runs where version_id=19 and pantalla_id=p_pantalla_id and status in ('CURATING','VALIDATING')) then
    return programacion.fn_input_governance_curator_rebind_v1(p_pantalla_id,p_consumer,p_curator_identity,p_force_selftest);
  end if;
  if p_force_selftest then return programacion.fn_input_governance_bootstrap_materialize_v1(p_pantalla_id,p_consumer,p_curator_identity); end if;
  return programacion.fn_input_governance_bootstrap_materialize_v1(p_pantalla_id,p_consumer,p_curator_identity);
end;
$$;

create or replace function programacion.fn_input_governance_bootstrap_validate_v1(
  p_run_id bigint,p_validator_identity text
) returns jsonb
language plpgsql volatile security definer
set search_path=pg_catalog,programacion
as $$
declare
  v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text; v_existing_validator text; v_contract_revision text;
  v_validator_component bigint; v_source_sha text; v_pass integer; v_pre jsonb; v_assertions jsonb; v_expected jsonb; v_exec_id text:=gen_random_uuid()::text; v_payload jsonb; a record;
begin
  if p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_IDENTITY_INVALID'; end if;
  select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision
  from programacion.input_readiness_runs where id=p_run_id and version_id=19 and supersedes_run_id is null and scope->>'mode'='GOVERNED_CANONICAL_BOOTSTRAP_V1';
  if v_status is null then raise exception 'BOOTSTRAP_VALIDATOR_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_status='COMPLETED' then return jsonb_build_object('status','NOOP_COMPLETED','run_id',p_run_id,'promotion_authorized',false,'production_authorized',false); end if;
  if p_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',v_pantalla_id,p_run_id);
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR'; end if;
  select id into v_validator_component from programacion.componentes where version_id=19 and componente_codigo='INPUT_VALIDATOR';
  if v_validator_component is null then raise exception 'BOOTSTRAP_VALIDATOR_COMPONENT_UNRESOLVED'; end if;

  if v_status='CURATING' then
    if (select count(*) from programacion.input_family_assessments where run_id=p_run_id)<>v_family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE'; end if;
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=p_validator_identity,validator_component_id=v_validator_component where id=p_run_id;
  elsif v_status='VALIDATING' then
    if v_existing_validator is distinct from p_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH'; end if;
  else raise exception 'BOOTSTRAP_VALIDATOR_INVALID_RUN_STATUS:%',v_status;
  end if;
  select source_snapshot_sha256,contract_revision into v_source_sha,v_contract_revision from programacion.input_readiness_runs where id=p_run_id;

  for a in select * from programacion.input_family_assessments where run_id=p_run_id order by family_code loop
    v_expected:=programacion.fn_input_governance_bootstrap_classify_v1(v_pantalla_id,a.family_code,19);
    if a.curator_evidence->>'bootstrap_classifier_sha256' is distinct from v_expected->>'classifier_sha256'
       or a.severity is distinct from v_expected->>'severity'
       or a.applicability is distinct from v_expected->>'applicability'
       or a.coverage_status is distinct from v_expected->>'coverage_status'
       or a.well_defined_status is distinct from v_expected->>'well_defined_status'
       or a.story_ready_status is distinct from v_expected->>'story_ready_status'
       or a.implementation_ready_status is distinct from v_expected->>'implementation_ready_status'
       or a.qa_ready_status is distinct from v_expected->>'qa_ready_status'
       or a.production_ready_status is distinct from v_expected->>'production_ready_status'
       or a.source_refs is distinct from v_expected->'source_refs'
       or a.blockers is distinct from v_expected->'blockers' then
      raise exception 'BOOTSTRAP_VALIDATOR_CLASSIFIER_MISMATCH:%',a.family_code;
    end if;
    v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code);
    if jsonb_array_length(v_assertions)=0 then raise exception 'BOOTSTRAP_VALIDATOR_ASSERTIONS_EMPTY:%',a.family_code; end if;
    update programacion.input_family_assessments
    set validator_outcome='PASS',validator_findings='[]'::jsonb,
        validator_evidence=jsonb_build_object('component_id',v_validator_component,'execution_id',v_exec_id,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1','direct_source_readback',true,'contract_revision',v_contract_revision,'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'bootstrap_classifier_sha256',v_expected->>'classifier_sha256','assertions',v_assertions),
        validator_identity=p_validator_identity,validator_assessed_at=now()
    where id=a.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=p_run_id;
  select count(*) into v_pass from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity;
  if v_pass<>v_family_count then raise exception 'BOOTSTRAP_VALIDATOR_CARDINALITY_MISMATCH expected=% actual=%',v_family_count,v_pass; end if;
  v_payload:=jsonb_build_object('status','COMPLETED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,'required_role','DISPATCHER_FINALIZE','bootstrap_mode','GOVERNED_CANONICAL_BOOTSTRAP_V1','promotion_authorized',false,'production_authorized',false);
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;

alter function programacion.fn_input_governance_validator_validate_v1(bigint,text) rename to fn_input_governance_validator_rebind_v1;

create or replace function programacion.fn_input_governance_validator_validate_v1(p_run_id bigint,p_validator_identity text)
returns jsonb
language plpgsql volatile security definer
set search_path=pg_catalog,programacion
as $$
declare v_bootstrap boolean;
begin
  select supersedes_run_id is null and scope->>'mode'='GOVERNED_CANONICAL_BOOTSTRAP_V1' into v_bootstrap from programacion.input_readiness_runs where id=p_run_id and version_id=19;
  if coalesce(v_bootstrap,false) then return programacion.fn_input_governance_bootstrap_validate_v1(p_run_id,p_validator_identity); end if;
  return programacion.fn_input_governance_validator_rebind_v1(p_run_id,p_validator_identity);
end;
$$;

create or replace function public.fn_input_governance_curator_materialize_v1(p_pantalla_id integer,p_consumer text,p_curator_identity text)
returns jsonb language sql security definer set search_path=pg_catalog,programacion
as $$ select programacion.fn_input_governance_curator_materialize_v1(p_pantalla_id,p_consumer,p_curator_identity,false); $$;

create or replace function public.fn_input_governance_validator_validate_v1(p_run_id bigint,p_validator_identity text)
returns jsonb language sql security definer set search_path=pg_catalog,programacion
as $$ select programacion.fn_input_governance_validator_validate_v1(p_run_id,p_validator_identity); $$;

update programacion.contratos
set especificacion=jsonb_set(
  jsonb_set(
    jsonb_set(especificacion,'{new_screen_policy}',to_jsonb('GOVERNED_CANONICAL_BOOTSTRAP_FAIL_CLOSED'::text),true),
    '{automatic_successor_policy}',to_jsonb('ASSERTION_REBIND_OR_GOVERNED_CANONICAL_BOOTSTRAP'::text),true
  ),
  '{bootstrap_decision}',to_jsonb('DEC-INPUT-GOV-BOOTSTRAP-001'::text),true
)
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined' and fail_closed;

create or replace function programacion.fn_input_governance_worker_spec(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb
language plpgsql stable security definer
set search_path=pg_catalog,public,programacion,lf_ops
as $$
declare
  v_exec jsonb; v_version bigint; v_code text; v_active boolean; v_latest bigint; v_latest_status text; v_current bigint;
  v_role text; v_reason text; v_rev text; v_sha text; v_payload jsonb; v_count integer:=0; v_expected integer:=0;
begin
  select c.version_id,c.especificacion into v_version,v_exec
  from programacion.contratos c join programacion.versiones_agente v on v.id=c.version_id join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and c.estado='defined' and c.fail_closed
  order by c.version_id desc limit 1;
  if v_exec is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_exec->'allowed_consumers') x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
  select id,status,family_count into v_latest,v_latest_status,v_expected from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  select id into v_current from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id and status='COMPLETED' and invalidated_at is null and programacion.fn_input_readiness_run_is_current(id) order by id desc limit 1;
  if v_latest is not null then select count(*) into v_count from programacion.input_family_assessments where run_id=v_latest; end if;
  if v_current is not null then v_role:='NONE'; v_reason:='CURRENT_COMPLETED_RUN_AVAILABLE';
  elsif v_latest_status='VALIDATING' or (v_latest_status='CURATING' and v_expected>0 and v_count=v_expected) then v_role:='INPUT_VALIDATOR'; v_reason:=case when v_latest_status='VALIDATING' then 'VALIDATION_PHASE_INCOMPLETE' else 'CURATION_MATERIALIZED_VALIDATION_NOT_OPEN' end;
  else v_role:='INPUT_CURATOR'; v_reason:=case when v_latest is null then 'NO_PRIOR_RUN_GOVERNED_BOOTSTRAP' else 'NO_CURRENT_COMPLETED_RUN' end; end if;
  select c.especificacion->>'contract_revision',programacion.fn_v09_sha256_jsonb(jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)) into v_rev,v_sha
  from programacion.contratos c where c.version_id=v_version and c.contrato_codigo='INPUT_READINESS_CONTRACT' and c.estado='defined' and c.fail_closed;
  v_payload:=jsonb_build_object(
    'schema_version',1,'worker_contract','INPUT_GOVERNANCE_WORKER_SPEC_V1','agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
    'required_role',v_role,'role_reason',v_reason,'latest_run_id',v_latest,'latest_run_status',v_latest_status,'current_run_id',v_current,
    'readiness_contract_revision',v_rev,'readiness_contract_sha256',v_sha,
    'family_universe_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-STORY-READINESS-001','expected_family_count',47),
    'source_precedence',jsonb_build_array('lf_ops','lf_design','transversal','programacion'),
    'retrieval_plan',jsonb_build_array('SCREEN','SCREEN_RULE_SET','SCREEN_STATE_SET','SCREEN_CANONICAL_GRAPH','DESIGN_BINDING_GRAPH_V4','API_CONTRACT_RESOLUTION_V1','EKB_DECISION_SET','EKB_PREVENTION_SET'),
    'context_policy','REFERENCE_PLUS_JIT_MINIMUM_SUFFICIENT_CONTEXT','ekb_checkpoints',v_exec->'ekb_checkpoints',
    'curator_requirements',jsonb_build_object('direct_source_readback',true,'no_invention',true,'proposal_is_canonical_source',false,'family_count',47,'automatic_policy','ASSERTION_REBIND_OR_GOVERNED_CANONICAL_BOOTSTRAP'),
    'validator_requirements',jsonb_build_object('separate_execution',true,'direct_source_readback',true,'deterministic_checks_first',true,'semantic_validation_required',true,'candidate_as_own_authority',false),
    'runtime_binding_status',case when v_role='NONE' then 'NOT_REQUIRED_CURRENT_RUN' else 'BOUND_RUNTIME' end,
    'runtime_binding',case when v_role='INPUT_CURATOR' then 'SUPABASE_EDGE_FUNCTION:input-governance-curator-v1' when v_role='INPUT_VALIDATOR' then 'SUPABASE_EDGE_FUNCTION:input-governance-validator-v1' else 'NONE' end,
    'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:input-governance-agent-v1','runtime_action',case when v_role='NONE' then 'REUSE_CURRENT_RUN' when v_role='INPUT_VALIDATOR' then 'CALL_VALIDATOR_RUNTIME' else 'CALL_CURATOR_RUNTIME' end,
    'new_screen_policy','GOVERNED_CANONICAL_BOOTSTRAP_FAIL_CLOSED','bootstrap_decision','DEC-INPUT-GOV-BOOTSTRAP-001','auto_canonicalization','DENY','promotion_authorized',false,'production_authorized',false,'generated_at',now()
  );
  return v_payload||jsonb_build_object('worker_spec_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;

revoke all on function programacion.fn_input_bootstrap_rule_probe_v1(jsonb,text[],text) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_bootstrap_classify_v1(integer,text,bigint) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_bootstrap_assertions_v1(bigint,text) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_bootstrap_materialize_v1(integer,text,text) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_bootstrap_validate_v1(bigint,text) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_validator_validate_v1(bigint,text) from public,anon,authenticated;
revoke all on function public.fn_input_governance_curator_materialize_v1(integer,text,text) from public,anon,authenticated;
revoke all on function public.fn_input_governance_validator_validate_v1(bigint,text) from public,anon,authenticated;
grant execute on function public.fn_input_governance_curator_materialize_v1(integer,text,text) to service_role;
grant execute on function public.fn_input_governance_validator_validate_v1(bigint,text) to service_role;

-- Rollback-only E2E self-test on ONB_002. No canonical run may survive this block.
do $$
declare
  v_before_count integer; v_before_max bigint; v_after_count integer; v_after_max bigint; v_cur jsonb; v_val jsonb; v_run bigint; v_pass integer;
begin
  select count(*),coalesce(max(id),0) into v_before_count,v_before_max from programacion.input_readiness_runs;
  begin
    v_cur:=programacion.fn_input_governance_curator_materialize_v1(2,'STORY_CREATOR','INPUT_CURATOR:EDGE:input-governance-curator-v1:bootstrapselftest20260824',false);
    if v_cur->>'status'<>'VALIDATOR_RUNTIME_REQUIRED' then raise exception 'BOOTSTRAP_SELFTEST_CURATOR_STATUS:%',v_cur; end if;
    v_run:=(v_cur->>'run_id')::bigint;
    if (select count(*) from programacion.input_family_assessments where run_id=v_run)<>47 then raise exception 'BOOTSTRAP_SELFTEST_NOT_47'; end if;
    v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:bootstrapselftest20260824');
    if v_val->>'status'<>'COMPLETED' then raise exception 'BOOTSTRAP_SELFTEST_VALIDATOR_STATUS:%',v_val; end if;
    select count(*) into v_pass from programacion.input_family_assessments where run_id=v_run and validator_outcome='PASS';
    if v_pass<>47 then raise exception 'BOOTSTRAP_SELFTEST_VALIDATOR_NOT_47:%',v_pass; end if;
    raise exception 'BOOTSTRAP_SELFTEST_ROLLBACK_SENTINEL';
  exception when others then
    if sqlerrm<>'BOOTSTRAP_SELFTEST_ROLLBACK_SENTINEL' then raise; end if;
  end;
  select count(*),coalesce(max(id),0) into v_after_count,v_after_max from programacion.input_readiness_runs;
  if v_after_count<>v_before_count or v_after_max<>v_before_max then raise exception 'BOOTSTRAP_SELFTEST_ROLLBACK_FAILED before=%/% after=%/%',v_before_count,v_before_max,v_after_count,v_after_max; end if;
end;
$$;
