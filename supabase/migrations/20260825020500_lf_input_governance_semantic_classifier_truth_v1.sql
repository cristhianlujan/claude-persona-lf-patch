-- INPUT_GOVERNANCE_AGENT semantic-classifier truth fixes.
-- No screen functional data is modified by this migration.
-- Governing controls: DEC-INPUT-GOV-BOOTSTRAP-001, DEC-INPUT-GOV-SAFE-AUTOFIX-001,
-- PRV-AUD-019, PRV-GOV-012, PRV-ARC-011.

create or replace function programacion.fn_input_na_positive_authority_v512(
  p_family_code text,
  p_pantalla_id integer,
  p_version_id bigint
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_graph jsonb;
  v_rules jsonb;
  v_screen_permissions jsonb;
  v_profile_permissions jsonb;
  v_rule jsonb;
  v_exclusion jsonb;
  v_codes jsonb := '[]'::jsonb;
  v_qualified boolean := false;
  v_has_otp_field boolean := false;
begin
  v_graph := programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules := coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  v_screen_permissions := coalesce(v_graph->'screen_permissions','[]'::jsonb);
  v_profile_permissions := coalesce(v_graph->'profile_permissions','[]'::jsonb);

  if p_family_code='SESSION' then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if coalesce(v_rule->'config'->>'operational_session_creation','')='DENY' then
        v_qualified:=true;
        v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
      end if;
    end loop;
  elsif p_family_code='PERMISSIONS' and jsonb_array_length(v_screen_permissions)=0 and jsonb_array_length(v_profile_permissions)=0 then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if coalesce(v_rule->>'transversal','true')::boolean is false
         and (
           coalesce(v_rule->'config'->>'operational_access_grant','')='DENY'
           or coalesce(v_rule->'config'->>'operational_authorization_before_completion','')='DENY'
           or coalesce(v_rule->'config'->>'mfa_route_full_operational_session_required','')='false'
         ) then
        v_qualified:=true;
        v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
      end if;
    end loop;
  elsif p_family_code in ('FEATURE_FLAGS','I18N_FORMATS') then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if v_rule->>'rule_code'='B2B-RULE-INPUT-APPLICABILITY-001'
         and coalesce((v_rule->>'pending_decision')::boolean,false) is false
         and coalesce(v_rule->'config'->>'decision_id','')='DEC-INPUT-GOV-512-HUMAN-001' then
        v_exclusion:=v_rule->'config'->'input_family_exclusions'->p_family_code;
        if (p_family_code='FEATURE_FLAGS' and coalesce(v_exclusion->>'status','')='EXCLUDED_CURRENT_SCOPE')
           or (p_family_code='I18N_FORMATS' and coalesce(v_exclusion->>'status','')='EXCLUDED_CURRENT_SINGLE_LOCALE_SCOPE') then
          v_qualified:=true;
          v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
        end if;
      end if;
    end loop;
  elsif p_family_code='MFA_OTP_SSO' then
    select exists(
      select 1
      from lf_ops.campos_pantallas cp
      join lf_ops.campos c on c.id=cp.campo_id
      where cp.pantalla_id=p_pantalla_id
        and c.codigo='CAMPO_OTP_CODE'
        and c.estado='ACTIVO'
    ) into v_has_otp_field;

    if not v_has_otp_field then
      for v_rule in select value from jsonb_array_elements(v_rules) loop
        if coalesce(v_rule->>'status','')='VIGENTE'
           and coalesce(v_rule->>'transversal','true')::boolean is false
           and coalesce(v_rule->'config'->>'repeat_current_phone_otp_after_creation','')='false'
           and coalesce(v_rule->'config'->>'current_phone_proof_source','')='ONB_002_SAME_SERVER_SESSION'
           and coalesce(v_rule->'config'->>'session_creation_authority','')='SERVER_ONLY' then
          v_qualified:=true;
          v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
        end if;
      end loop;
    end if;
  end if;

  return jsonb_build_object(
    'qualified',v_qualified,
    'family_code',p_family_code,
    'pantalla_id',p_pantalla_id,
    'authority_kind',case when v_qualified then 'EXPLICIT_CANONICAL_EXCLUSION' else 'NO_POSITIVE_EXCLUSION' end,
    'rule_codes',v_codes,
    'screen_permission_count',jsonb_array_length(v_screen_permissions),
    'profile_permission_count',jsonb_array_length(v_profile_permissions)
  );
end;
$function$;

create or replace function programacion.fn_input_governance_semantic_probe_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_graph jsonb;
  v_rules jsonb;
  v_probe jsonb := '{}'::jsonb;
  v_level text := 'MISSING';
  v_blocker text := null;
  v_count integer := 0;
  v_aux integer := 0;
  v_direct_semantic integer := 0;
  v_direct_vigente integer := 0;
  v_reuse_semantic integer := 0;
  v_policy_code text;
  v_context_contract text;
  v_policy_resolved boolean := false;
  v_context_resolved boolean := false;
  v_subject jsonb := '[]'::jsonb;
  v_threat jsonb := '[]'::jsonb;
  v_subject_bad integer := 0;
  v_threat_bad integer := 0;
  v_retry integer := 0;
  v_timeout integer := 0;
  v_design_summary jsonb := '{}'::jsonb;
  v_required integer := 0;
  v_resolved integer := 0;
  v_na integer := 0;
  v_pending integer := 0;
  v_unresolved integer := 0;
begin
  if p_family_code not in (
    'I18N_FORMATS','LOADING_EMPTY_ERROR_STATES','SESSION','RUNTIME_CONFIG',
    'SECURITY','TIMEOUT_RETRY','ASSETS_ICONS'
  ) then
    return jsonb_build_object('handled',false,'family_code',p_family_code);
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  if p_family_code='I18N_FORMATS' then
    v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(
      v_rules,null,
      '(I18N|LOCALE|IDIOMA|INTERNACIONAL|DATE[_ -]?FORMAT|CURRENCY[_ -]?FORMAT|NUMBER[_ -]?FORMAT|TIME[_ -]?ZONE|TIMEZONE)'
    );
    v_count:=coalesce((v_probe->>'count')::integer,0);
    v_level:=case when v_count>0 then 'PARTIAL' else 'MISSING' end;
    v_blocker:='I18N_APPLICABILITY_AUTHORITY_MISSING';

  elsif p_family_code='LOADING_EMPTY_ERROR_STATES' then
    v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(
      v_rules,array['error_states','estados_ui'],
      '(UI_STATES|ERROR_STATE|LOADING|EMPTY_STATE|supported_errors|error_slots_reserved)'
    );
    v_aux:=jsonb_array_length(coalesce(v_graph->'canonical_contract'->'errors','[]'::jsonb));
    v_count:=coalesce((v_probe->>'count')::integer,0);
    v_probe:=v_probe||jsonb_build_object('error_count',v_aux);
    v_level:=case when v_count>0 and v_aux>0 then 'PARTIAL' else 'MISSING' end;
    v_blocker:=case when v_level='PARTIAL' then 'LOADING_EMPTY_ERROR_STATES_SOURCE_INCOMPLETE' else 'BOOTSTRAP_CANONICAL_EVIDENCE_MISSING' end;

  elsif p_family_code='SESSION' then
    with direct_rules as (
      select x.value as rule
      from jsonb_array_elements(v_rules) x(value)
    ), reuse_codes as (
      select distinct rc.value as codigo
      from direct_rules d
      cross join lateral jsonb_array_elements_text(coalesce(d.rule->'config'->'reuse_rules','[]'::jsonb)) rc(value)
    ), reused as (
      select jsonb_build_object(
        'rule_code',r.codigo,'status',r.estado,'category',r.categoria,
        'title',r.titulo,'description',r.descripcion,'config',r.valor_config
      ) as rule
      from lf_ops.reglas r
      where r.codigo in (select codigo from reuse_codes)
    ), direct_semantic as (
      select rule from direct_rules
      where coalesce(rule->'config','{}'::jsonb) ?| array[
        'session_policy_code','client_session_policy','session_context_contract',
        'session_must_remain_valid','session_creation_authority','invalid_session_states'
      ]
    ), reuse_semantic as (
      select rule from reused
      where lower(coalesce(rule->>'category',''))='sesion'
         or coalesce(rule->'config','{}'::jsonb) ?| array[
           'session_policy_code','client_session_policy','session_context_contract'
         ]
    )
    select
      (select count(*) from direct_semantic),
      (select count(*) from direct_semantic where rule->>'status' in ('VIGENTE','ACTIVO')),
      (select count(*) from reuse_semantic),
      (select coalesce(max(nullif(coalesce(rule->'config'->>'session_policy_code',rule->'config'->>'client_session_policy'),'')),'') from direct_semantic),
      (select coalesce(max(nullif(rule->'config'->>'session_context_contract','')),'') from direct_semantic)
    into v_direct_semantic,v_direct_vigente,v_reuse_semantic,v_policy_code,v_context_contract;

    if nullif(v_policy_code,'') is not null then
      select exists(
        select 1 from lf_ops.politicas_sesion ps
        where ps.policy_code=v_policy_code and ps.status='VIGENTE'
      ) into v_policy_resolved;
    end if;
    if nullif(v_context_contract,'') is not null then
      select to_regproc(v_context_contract) is not null into v_context_resolved;
    end if;

    if v_direct_vigente>0 and v_policy_resolved and v_context_resolved then
      v_level:='COMPLETE';
      v_blocker:=null;
    elsif v_direct_semantic+v_reuse_semantic>0 then
      v_level:='PARTIAL';
      v_blocker:='SESSION_CANONICAL_SOURCE_INCOMPLETE';
    else
      v_level:='MISSING';
      v_blocker:='BOOTSTRAP_CANONICAL_EVIDENCE_MISSING';
    end if;
    v_probe:=jsonb_build_object(
      'direct_semantic_rule_count',v_direct_semantic,
      'direct_vigente_semantic_rule_count',v_direct_vigente,
      'reused_session_rule_count',v_reuse_semantic,
      'policy_code',nullif(v_policy_code,''),
      'policy_resolved_vigente',v_policy_resolved,
      'session_context_contract',nullif(v_context_contract,''),
      'session_context_resolved',v_context_resolved,
      'resolution_contract','SESSION_SEMANTIC_RESOLUTION_V1'
    );

  elsif p_family_code='RUNTIME_CONFIG' then
    with direct_rules as (
      select x.value as rule from jsonb_array_elements(v_rules) x(value)
    ), reuse_codes as (
      select distinct rc.value as codigo
      from direct_rules d
      cross join lateral jsonb_array_elements_text(coalesce(d.rule->'config'->'reuse_rules','[]'::jsonb)) rc(value)
    )
    select
      count(*) filter(where coalesce(rule->'config','{}'::jsonb) ?| array[
        'auth_provider','account_store','phone_binding_store','session_context_contract',
        'client_validation','server_validation','idempotency','automatic_retry'
      ]),
      (select count(*) from lf_ops.reglas r where r.codigo in (select codigo from reuse_codes) and lower(coalesce(r.categoria,''))='tecnico')
    into v_direct_semantic,v_reuse_semantic
    from direct_rules;
    if v_direct_semantic+v_reuse_semantic>0 then
      v_level:='PARTIAL';
      v_blocker:='RUNTIME_CONFIG_SOURCE_INCOMPLETE';
    else
      v_level:='MISSING';
      v_blocker:='BOOTSTRAP_CANONICAL_EVIDENCE_MISSING';
    end if;
    v_probe:=jsonb_build_object(
      'direct_runtime_semantic_rule_count',v_direct_semantic,
      'reused_technical_rule_count',v_reuse_semantic,
      'resolution_contract','RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V1'
    );

  elsif p_family_code='SECURITY' then
    v_subject:=programacion.fn_input_subject_depth_expected(p_pantalla_id,'SECURITY');
    v_threat:=programacion.fn_input_security_threat_expected(p_pantalla_id);
    select count(*) into v_subject_bad from jsonb_array_elements(v_subject) s where s->>'status'<>'COMPLETE';
    select count(*) into v_threat_bad from jsonb_array_elements(v_threat) t where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');
    if jsonb_array_length(v_subject)>0 and v_subject_bad=0 and jsonb_array_length(v_threat)>0 and v_threat_bad=0 then
      v_level:='COMPLETE';
      v_blocker:=null;
    elsif jsonb_array_length(v_subject)>0 or jsonb_array_length(v_threat)>0 then
      v_level:='PARTIAL';
      v_blocker:='SECURITY_SEMANTIC_DEPTH_REVIEW_REQUIRED';
    else
      v_level:='MISSING';
      v_blocker:='SECURITY_SEMANTIC_DEPTH_REVIEW_REQUIRED';
    end if;
    v_probe:=jsonb_build_object(
      'subject_count',jsonb_array_length(v_subject),
      'subject_incomplete_count',v_subject_bad,
      'threat_count',jsonb_array_length(v_threat),
      'threat_incomplete_count',v_threat_bad,
      'capability_profile',programacion.fn_input_security_capability_profile(p_pantalla_id),
      'resolution_contract','SECURITY_SEMANTIC_DEPTH_V1'
    );

  elsif p_family_code='TIMEOUT_RETRY' then
    select
      count(*) filter(where
        coalesce(r.value->'config','{}'::jsonb) ? 'automatic_retry'
        or coalesce(r.value->>'rule_code','') ~* '(RETRY|BACKOFF)'
        or coalesce(r.value->>'title','') ~* '(RETRY|REINTENTO|BACKOFF)'
        or coalesce(r.value->>'description','') ~* '(RETRY|REINTENTO|BACKOFF)'
      ),
      count(*) filter(where
        coalesce(r.value->>'rule_code','') ~* '(TIMEOUT|COOLDOWN|DEADLINE|REG_RATE_005|REG_RL_|REG_ATQ_011)'
        or coalesce(r.value->>'title','') ~* '(TIMEOUT|COOLDOWN|DEADLINE|TIEMPO DE ESPERA)'
        or coalesce(r.value->>'description','') ~* '(TIMEOUT|COOLDOWN|DEADLINE|TIEMPO DE ESPERA)'
        or coalesce(r.value->'config','{}'::jsonb)::text ~* '(_timeout|timeout_|cooldown|deadline)'
      )
    into v_retry,v_timeout
    from jsonb_array_elements(v_rules) r(value);
    if v_retry>0 or v_timeout>0 then v_level:='PARTIAL'; else v_level:='MISSING'; end if;
    v_blocker:=case
      when v_retry>0 and v_timeout=0 then 'TIMEOUT_SOURCE_MISSING'
      when v_retry=0 and v_timeout>0 then 'RETRY_SOURCE_MISSING'
      when v_retry>0 and v_timeout>0 then 'TIMING_RECONCILIATION_REQUIRED'
      else 'BOOTSTRAP_CANONICAL_EVIDENCE_MISSING'
    end;
    v_probe:=jsonb_build_object('retry_rule_count',v_retry,'timeout_rule_count',v_timeout,'resolution_contract','TIMEOUT_RETRY_SEMANTIC_RESOLUTION_V1');

  elsif p_family_code='ASSETS_ICONS' then
    v_design_summary:=coalesce(v_graph->'canonical_contract'->'visual'->'design_bindings'->'summary','{}'::jsonb);
    select
      count(*) filter(where required_for_implementation),
      count(*) filter(where required_for_implementation and semantic_binding_status='RESOLVED_ID' and component_token_id is not null),
      count(*) filter(where required_for_implementation and semantic_binding_status='NOT_APPLICABLE'),
      count(*) filter(where required_for_implementation and semantic_binding_status='PENDING_SEMANTIC_COMPONENT'),
      count(*) filter(where required_for_implementation and (
        semantic_binding_status='PENDING_SEMANTIC_COMPONENT'
        or semantic_binding_status not in ('RESOLVED_ID','NOT_APPLICABLE')
        or (semantic_binding_status='RESOLVED_ID' and component_token_id is null)
      ))
    into v_required,v_resolved,v_na,v_pending,v_unresolved
    from lf_ops.pantalla_elementos
    where pantalla_id=p_pantalla_id and status<>'DEPRECATED';
    v_count:=jsonb_array_length(coalesce(v_graph->'canonical_contract'->'visual'->'components','[]'::jsonb));
    v_level:=case when v_count>0 then 'PARTIAL' else 'MISSING' end;
    v_blocker:='BOOTSTRAP_CANONICAL_EVIDENCE_'||v_level;
    v_probe:=jsonb_build_object(
      'component_count',v_count,
      'required_element_count',v_required,
      'required_semantic_resolved_count',v_resolved,
      'required_semantic_not_applicable_count',v_na,
      'required_semantic_pending_count',v_pending,
      'required_missing_component_count',v_unresolved,
      'referential_integrity_failure_count',coalesce((v_design_summary->>'referential_integrity_failure_count')::integer,0),
      'resolution_contract','ASSET_ICON_SEMANTIC_RESOLUTION_V1'
    );
  end if;

  return jsonb_build_object(
    'handled',true,
    'family_code',p_family_code,
    'level',v_level,
    'probe',v_probe,
    'blocker_code',v_blocker
  );
end;
$function$;

create or replace function programacion.fn_input_governance_bootstrap_classify_v2(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v jsonb;
  v_blockers jsonb;
  v_b jsonb;
  v_new_blockers jsonb:='[]'::jsonb;
  v_required int:=0;
  v_resolved int:=0;
  v_na int:=0;
  v_pending int:=0;
  v_unresolved int:=0;
  v_sem jsonb;
  v_level text;
  v_blocker text;
begin
  v:=programacion.fn_input_governance_bootstrap_classify_v1(p_pantalla_id,p_family_code,p_version_id);

  if p_family_code='DESIGN_SYSTEM' and v->>'applicability'<>'NOT_APPLICABLE' then
    select
      count(*) filter(where required_for_implementation),
      count(*) filter(where required_for_implementation and semantic_binding_status='RESOLVED_ID' and component_token_id is not null),
      count(*) filter(where required_for_implementation and semantic_binding_status='NOT_APPLICABLE'),
      count(*) filter(where required_for_implementation and semantic_binding_status='PENDING_SEMANTIC_COMPONENT'),
      count(*) filter(where required_for_implementation and (
        semantic_binding_status='PENDING_SEMANTIC_COMPONENT'
        or semantic_binding_status not in ('RESOLVED_ID','NOT_APPLICABLE')
        or (semantic_binding_status='RESOLVED_ID' and component_token_id is null)
      ))
    into v_required,v_resolved,v_na,v_pending,v_unresolved
    from lf_ops.pantalla_elementos
    where pantalla_id=p_pantalla_id and status<>'DEPRECATED';

    v:=jsonb_set(
      v,'{probe,summary}',
      coalesce(v->'probe'->'summary','{}'::jsonb)
      || jsonb_build_object(
        'element_required_semantic_resolved_count',v_resolved,
        'element_required_semantic_not_applicable_count',v_na,
        'element_required_semantic_pending_count',v_pending,
        'element_required_semantic_unresolved_count',v_unresolved,
        'element_required_count',v_required,
        'element_required_missing_component_count',v_unresolved,
        'semantic_gap_contract','DESIGN_ELEMENT_BINDING_SEMANTICS_V1'
      ),true
    );

    v_blockers:=coalesce(v->'blockers','[]'::jsonb);
    for v_b in select value from jsonb_array_elements(v_blockers) loop
      if v_b->>'code'<>'ELEMENT_REQUIRED_COMPONENT_BINDING_MISSING' then
        v_new_blockers:=v_new_blockers||jsonb_build_array(v_b);
      end if;
    end loop;
    if v_unresolved>0 then
      v_new_blockers:=v_new_blockers||jsonb_build_array(jsonb_build_object(
        'code','ELEMENT_REQUIRED_SEMANTIC_COMPONENT_UNRESOLVED',
        'count',v_unresolved,
        'not_applicable_count',v_na,
        'pending_semantic_component_count',v_pending
      ));
    end if;
    v:=jsonb_set(v,'{blockers}',v_new_blockers,true);
  end if;

  if v->>'applicability'<>'NOT_APPLICABLE' then
    v_sem:=programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id,p_family_code,p_version_id);
    if coalesce((v_sem->>'handled')::boolean,false) then
      v_level:=v_sem->>'level';
      v_blocker:=v_sem->>'blocker_code';
      v:=jsonb_set(v,'{probe}',v_sem->'probe',true);
      v:=jsonb_set(v,'{bootstrap_level}',to_jsonb(v_level),true);
      if v_level='COMPLETE' then
        v:=jsonb_set(v,'{severity}','"P4"'::jsonb,true);
        v:=jsonb_set(v,'{coverage_status}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{well_defined_status}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);
        v:=jsonb_set(v,'{implementation_ready_status}','"READY"'::jsonb,true);
        v:=jsonb_set(v,'{qa_ready_status}','"READY"'::jsonb,true);
        v:=jsonb_set(v,'{production_ready_status}','"READY"'::jsonb,true);
        v:=jsonb_set(v,'{blockers}','[]'::jsonb,true);
      else
        v:=jsonb_set(v,'{severity}','"P0"'::jsonb,true);
        v:=jsonb_set(v,'{coverage_status}',to_jsonb(case when v_level='PARTIAL' then 'PARTIAL' else 'MISSING' end),true);
        v:=jsonb_set(v,'{well_defined_status}',to_jsonb(case when v_level='PARTIAL' then 'PARTIAL' else 'MISSING' end),true);
        v:=jsonb_set(v,'{story_ready_status}','"BLOCKED"'::jsonb,true);
        v:=jsonb_set(v,'{implementation_ready_status}','"BLOCKED"'::jsonb,true);
        v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
        v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
        v:=jsonb_set(v,'{blockers}',jsonb_build_array(jsonb_build_object('code',v_blocker,'family_code',p_family_code,'bootstrap_level',v_level)),true);
      end if;
    end if;
  end if;

  v:=v-'classifier_sha256';
  return v||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v));
end;
$function$;

create or replace function programacion.fn_input_readiness_run_is_current(p_run_id bigint)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_run record;
  v_current_manifest jsonb;
  v_current_sha text;
  v_contract_schema integer;
  v_contract_revision text;
  v_contract_payload jsonb;
  v_contract_sha text;
  v_has_terminal_successor boolean;
  v_analysis_revision text;
  v_policy_revision text;
  v_pantalla_id integer;
  v_stored_subject jsonb;
  v_stored_threat jsonb;
  v_expected_subject jsonb;
  v_expected_threat jsonb;
  v_assessment record;
  v_expected_classifier jsonb;
begin
  select r.status,r.version_id,r.pantalla_id,r.contract_version,r.contract_revision,r.contract_snapshot_sha256,
         r.source_manifest,r.source_snapshot_sha256,r.invalidated_at,r.scope
  into v_run
  from programacion.input_readiness_runs r
  where r.id=p_run_id;

  if not found then return false; end if;
  if v_run.status<>'COMPLETED' or v_run.source_snapshot_sha256 is null or v_run.invalidated_at is not null then return false; end if;
  v_pantalla_id:=v_run.pantalla_id;

  select (c.especificacion->>'schema_version')::integer,
         c.especificacion->>'contract_revision',
         jsonb_build_object('id',c.id,'version_id',c.version_id,'contrato_codigo',c.contrato_codigo,
                            'fail_closed',c.fail_closed,'estado',c.estado,'especificacion',c.especificacion)
  into v_contract_schema,v_contract_revision,v_contract_payload
  from programacion.contratos c
  where c.version_id=v_run.version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';

  if v_contract_schema is null or v_contract_revision is null then return false; end if;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract_payload);
  if v_run.contract_version<>v_contract_schema
     or v_run.contract_revision is distinct from v_contract_revision
     or v_run.contract_snapshot_sha256 is distinct from v_contract_sha then
    return false;
  end if;

  if coalesce(v_run.scope->>'mode','') in ('GOVERNED_CANONICAL_BOOTSTRAP_V1','RUNTIME_GOVERNED_RECURATION_V2') then
    select especificacion->>'analysis_revision',especificacion->'remediation_loop'->>'policy_revision'
    into v_analysis_revision,v_policy_revision
    from programacion.contratos
    where version_id=v_run.version_id
      and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      and estado='defined'
      and fail_closed;
    if v_analysis_revision is null or v_run.scope->>'analysis_revision' is distinct from v_analysis_revision then return false; end if;
    if v_policy_revision is not null and v_run.scope->>'remediation_policy_revision' is distinct from v_policy_revision then return false; end if;

    for v_assessment in
      select a.family_code,a.curator_evidence->>'bootstrap_classifier_sha256' as stored_classifier_sha
      from programacion.input_family_assessments a
      where a.run_id=p_run_id
      order by a.family_code
    loop
      if nullif(v_assessment.stored_classifier_sha,'') is null then return false; end if;
      v_expected_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(v_pantalla_id,v_assessment.family_code,v_run.version_id);
      if v_assessment.stored_classifier_sha is distinct from v_expected_classifier->>'classifier_sha256' then return false; end if;
    end loop;
  end if;

  select a.subject_coverage
  into v_stored_subject
  from programacion.input_family_assessments a
  where a.run_id=p_run_id and a.family_code='DESIGN_SYSTEM';
  if found then
    v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,'DESIGN_SYSTEM');
    if v_stored_subject is distinct from v_expected_subject then return false; end if;
  end if;

  select a.subject_coverage,a.threat_coverage
  into v_stored_subject,v_stored_threat
  from programacion.input_family_assessments a
  where a.run_id=p_run_id and a.family_code='SECURITY';
  if found then
    v_expected_subject:=programacion.fn_input_subject_depth_expected(v_pantalla_id,'SECURITY');
    v_expected_threat:=programacion.fn_input_security_threat_expected(v_pantalla_id);
    if v_stored_subject is distinct from v_expected_subject or v_stored_threat is distinct from v_expected_threat then return false; end if;
  end if;

  select exists(
    select 1 from programacion.input_readiness_runs n
    where n.supersedes_run_id=p_run_id and n.status in ('COMPLETED','BLOCKED')
  ) into v_has_terminal_successor;
  if v_has_terminal_successor then return false; end if;

  v_current_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
  v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_manifest);
  return v_current_sha=v_run.source_snapshot_sha256 and v_current_manifest=v_run.source_manifest;
end;
$function$;
