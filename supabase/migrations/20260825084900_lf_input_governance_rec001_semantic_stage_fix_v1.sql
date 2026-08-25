-- INPUT_GOVERNANCE_AGENT 5.12
-- Deterministic semantic remediation for Client account recovery.
-- No canonical business values are invented; this only recognizes positive existing authority
-- and restores stage semantics already declared by INPUT_READINESS_CONTRACT 5.12.

create or replace function programacion.fn_input_na_positive_authority_v512(
  p_family_code text,
  p_pantalla_id integer,
  p_version_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
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
  v_route_public boolean := false;
  v_profile_link_count integer := 0;
  v_permission_link_count integer := 0;
  v_client_recovery_no_access boolean := false;
begin
  v_graph := programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules := coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  v_screen_permissions := coalesce(v_graph->'screen_permissions','[]'::jsonb);
  v_profile_permissions := coalesce(v_graph->'profile_permissions','[]'::jsonb);

  select exists(
    select 1
    from lf_ops.rutas rt
    where rt.pantalla_id=p_pantalla_id
      and rt.status='VIGENTE'
      and rt.authentication_required is false
  ) into v_route_public;

  select count(*) into v_profile_link_count
  from lf_ops.pantallas_perfiles pp
  where pp.pantalla_id=p_pantalla_id
    and pp.status<>'ARCHIVADO';

  select count(*) into v_permission_link_count
  from lf_ops.pantallas_permisos pp
  where pp.pantalla_id=p_pantalla_id
    and pp.status<>'ARCHIVADO';

  select exists(
    select 1
    from jsonb_array_elements(v_rules) x(rule)
    where x.rule->>'status'='VIGENTE'
      and coalesce((x.rule->>'transversal')::boolean,false) is false
      and x.rule->>'rule_code' in (
        'REG_CLIENT_RECOVERY_IDV_STEPUP_001',
        'REG_CLIENT_RECOVERY_REBIND_ATOMIC_001',
        'REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001'
      )
      and (
        x.rule->'config'->>'operational_access_before_verified'='DENY'
        or x.rule->'config'->>'operational_access_before_commit'='DENY'
        or x.rule->'config'->>'partial_recovery_session_promotion'='DENY'
      )
  ) into v_client_recovery_no_access;

  if p_family_code='SESSION' then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if coalesce(v_rule->'config'->>'operational_session_creation','')='DENY' then
        v_qualified:=true;
        v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code');
      end if;
    end loop;

  elsif p_family_code='PERMISSIONS'
        and jsonb_array_length(v_screen_permissions)=0
        and jsonb_array_length(v_profile_permissions)=0 then
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

    if not v_qualified
       and v_route_public
       and v_profile_link_count=0
       and v_permission_link_count=0
       and v_client_recovery_no_access then
      v_qualified:=true;
      select coalesce(jsonb_agg(x.rule->>'rule_code' order by x.rule->>'rule_code'),'[]'::jsonb)
      into v_codes
      from jsonb_array_elements(v_rules) x(rule)
      where x.rule->>'status'='VIGENTE'
        and x.rule->>'rule_code' in (
          'REG_CLIENT_RECOVERY_IDV_STEPUP_001',
          'REG_CLIENT_RECOVERY_REBIND_ATOMIC_001',
          'REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001'
        );
    end if;

  elsif p_family_code='PROFILES'
        and v_route_public
        and v_profile_link_count=0
        and v_permission_link_count=0
        and v_client_recovery_no_access then
    v_qualified:=true;
    select coalesce(jsonb_agg(x.rule->>'rule_code' order by x.rule->>'rule_code'),'[]'::jsonb)
    into v_codes
    from jsonb_array_elements(v_rules) x(rule)
    where x.rule->>'status'='VIGENTE'
      and x.rule->>'rule_code' in (
        'REG_CLIENT_RECOVERY_IDV_STEPUP_001',
        'REG_CLIENT_RECOVERY_REBIND_ATOMIC_001',
        'REG_CLIENT_RECOVERY_ACCESS_AFTER_REBIND_001'
      );

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
    'profile_permission_count',jsonb_array_length(v_profile_permissions),
    'screen_profile_link_count',v_profile_link_count,
    'screen_permission_link_count',v_permission_link_count,
    'public_unauthenticated_route',v_route_public,
    'client_recovery_operational_access_denied',v_client_recovery_no_access
  );
end;
$function$;

create or replace function programacion.fn_input_governance_bootstrap_classify_v2(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
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
  v_api jsonb;
  v_otp_rule jsonb;
  v_otp_operation text;
  v_otp_field text;
  v_otp_operation_ok boolean:=false;
  v_otp_field_ok boolean:=false;
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

  if v->>'applicability'<>'NOT_APPLICABLE' and p_family_code='API_DATA_CONTRACT' then
    v_api:=programacion.fn_input_api_contract_resolution(p_pantalla_id);
    if coalesce((v_api->>'has_behavioral_contract')::boolean,false)
       and coalesce((v_api->>'broken_contract_ref_count')::integer,0)=0
       and coalesce((v_api->>'has_resolvable_operation_schema_authority')::boolean,false) is false then
      v:=jsonb_set(v,'{probe}',v_api,true);
      v:=jsonb_set(v,'{bootstrap_level}','"PARTIAL"'::jsonb,true);
      v:=jsonb_set(v,'{severity}','"P1"'::jsonb,true);
      v:=jsonb_set(v,'{coverage_status}','"PARTIAL"'::jsonb,true);
      v:=jsonb_set(v,'{well_defined_status}','"COMPLETE"'::jsonb,true);
      v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);
      v:=jsonb_set(v,'{implementation_ready_status}','"NOT_READY"'::jsonb,true);
      v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
      v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
      v:=jsonb_set(v,'{blockers}',jsonb_build_array(jsonb_build_object(
        'code','API_OPERATION_SCHEMA_SOURCE_INCOMPLETE',
        'family_code',p_family_code,
        'bootstrap_level','PARTIAL',
        'earliest_blocking_stage','IMPLEMENTATION'
      )),true);
      v:=jsonb_set(v,'{rationale}',to_jsonb(
        'INPUT_READINESS_CONTRACT 5.12: behavioral contract is sufficient for Story acceptance criteria; resolvable operation/schema authority remains required for Implementation.'
      ),true);
    end if;
  end if;

  if v->>'applicability'<>'NOT_APPLICABLE' and p_family_code='MFA_OTP_SSO' then
    select r into v_otp_rule
    from jsonb_array_elements(
      coalesce(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->'canonical_contract'->'rules','[]'::jsonb)
    ) r
    where r->>'status'='VIGENTE'
      and r->>'rule_code'='REG_CLIENT_RECOVERY_PHONE_CONTROL_001'
      and nullif(r->'config'->>'old_phone_otp_operation','') is not null
      and nullif(r->'config'->>'old_phone_otp_field_code','') is not null
    limit 1;

    v_otp_operation:=v_otp_rule->'config'->>'old_phone_otp_operation';
    v_otp_field:=v_otp_rule->'config'->>'old_phone_otp_field_code';

    if v_otp_operation is not null then
      select exists(
        select 1
        from lf_ops.otp_operaciones o
        join lf_ops.otp_politicas p on p.id=o.politica_id
        where o.codigo=v_otp_operation
          and o.estado='ACTIVO'
          and p.estado='ACTIVO'
          and p.longitud is not null
          and p.max_intentos is not null
          and p.max_reenvios is not null
          and p.bloqueo_reenvio_min is not null
      ) into v_otp_operation_ok;
    end if;

    if v_otp_field is not null then
      select exists(
        select 1 from lf_ops.campos c
        where c.codigo=v_otp_field
          and c.estado='ACTIVO'
          and c.es_sensible
      ) into v_otp_field_ok;
    end if;

    if v_otp_operation_ok and v_otp_field_ok then
      v:=jsonb_set(v,'{probe}',jsonb_build_object(
        'resolution_contract','CLIENT_RECOVERY_OTP_SEMANTICS_V1',
        'authority_rule','REG_CLIENT_RECOVERY_PHONE_CONTROL_001',
        'otp_operation_code',v_otp_operation,
        'otp_operation_active',v_otp_operation_ok,
        'otp_field_code',v_otp_field,
        'otp_field_catalog_active_sensitive',v_otp_field_ok,
        'otp_role','RECOVERY_PROOF_NOT_MFA',
        'mfa_satisfied_by_recovery_otp',false
      ),true);
      v:=jsonb_set(v,'{bootstrap_level}','"COMPLETE"'::jsonb,true);
      v:=jsonb_set(v,'{severity}','"P4"'::jsonb,true);
      v:=jsonb_set(v,'{coverage_status}','"COMPLETE"'::jsonb,true);
      v:=jsonb_set(v,'{well_defined_status}','"COMPLETE"'::jsonb,true);
      v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);
      v:=jsonb_set(v,'{implementation_ready_status}','"READY"'::jsonb,true);
      v:=jsonb_set(v,'{qa_ready_status}','"READY"'::jsonb,true);
      v:=jsonb_set(v,'{production_ready_status}','"READY"'::jsonb,true);
      v:=jsonb_set(v,'{blockers}','[]'::jsonb,true);
      v:=jsonb_set(v,'{rationale}',to_jsonb(
        'Direct VIGENTE Client recovery rule binds an active governed recovery OTP operation and active sensitive OTP field catalog. The OTP is a recovery proof and does not satisfy MFA.'
      ),true);
    end if;
  end if;

  if v->>'applicability'<>'NOT_APPLICABLE'
     and not (p_family_code='API_DATA_CONTRACT' and v->>'story_ready_status'='READY')
     and not (p_family_code='MFA_OTP_SSO' and v->>'bootstrap_level'='COMPLETE') then
    v_sem:=programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id,p_family_code,p_version_id);
    if coalesce((v_sem->>'handled')::boolean,false) then
      v_level:=v_sem->>'level';
      v_blocker:=v_sem->>'blocker_code';
      v:=jsonb_set(v,'{probe}',v_sem->'probe',true);
      v:=jsonb_set(v,'{bootstrap_level}',to_jsonb(v_level),true);
      v:=jsonb_set(v,'{rationale}',to_jsonb(
        'Governed semantic resolution '||coalesce(v_sem->'probe'->>'resolution_contract','SEMANTIC_PROBE_V1')||': '||
        p_family_code||'='||v_level||' from direct canonical source readback; absence never implies N/A.'
      ),true);
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
        v:=jsonb_set(v,'{blockers}',jsonb_build_array(jsonb_build_object(
          'code',v_blocker,'family_code',p_family_code,'bootstrap_level',v_level
        )),true);
      end if;
    end if;
  end if;

  v:=v-'classifier_sha256';
  return v||jsonb_build_object('classifier_sha256',programacion.fn_v09_sha256_jsonb(v));
end;
$function$;

do $block$
declare
  j jsonb;
begin
  j:=programacion.fn_input_na_positive_authority_v512('PROFILES',58,19);
  if coalesce((j->>'qualified')::boolean,false) is not true then
    raise exception 'SELFTEST_REC001_PROFILES_POSITIVE_NA_FAILED:%',j;
  end if;

  j:=programacion.fn_input_na_positive_authority_v512('PERMISSIONS',58,19);
  if coalesce((j->>'qualified')::boolean,false) is not true then
    raise exception 'SELFTEST_REC001_PERMISSIONS_POSITIVE_NA_FAILED:%',j;
  end if;

  j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'PROFILES',19);
  if j->>'applicability'<>'NOT_APPLICABLE' or j->>'story_ready_status'<>'NOT_APPLICABLE' then
    raise exception 'SELFTEST_REC001_PROFILES_CLASSIFICATION_FAILED:%',j;
  end if;

  j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'PERMISSIONS',19);
  if j->>'applicability'<>'NOT_APPLICABLE' or j->>'story_ready_status'<>'NOT_APPLICABLE' then
    raise exception 'SELFTEST_REC001_PERMISSIONS_CLASSIFICATION_FAILED:%',j;
  end if;

  j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'MFA_OTP_SSO',19);
  if j->>'coverage_status'<>'COMPLETE'
     or j->>'story_ready_status'<>'READY'
     or j->'probe'->>'otp_role'<>'RECOVERY_PROOF_NOT_MFA' then
    raise exception 'SELFTEST_REC001_RECOVERY_OTP_SEMANTICS_FAILED:%',j;
  end if;

  j:=programacion.fn_input_governance_bootstrap_classify_v2(58,'API_DATA_CONTRACT',19);
  if j->>'story_ready_status'<>'READY'
     or j->>'implementation_ready_status'<>'NOT_READY'
     or j->>'severity'<>'P1' then
    raise exception 'SELFTEST_REC001_API_STAGE_SEMANTICS_FAILED:%',j;
  end if;

  j:=programacion.fn_input_governance_bootstrap_classify_v2(51,'PROFILES',19);
  if j->>'coverage_status'<>'COMPLETE' or j->>'story_ready_status'<>'READY' then
    raise exception 'SELFTEST_B2B_AUTH001_PROFILES_REGRESSION:%',j;
  end if;

  j:=programacion.fn_input_governance_bootstrap_classify_v2(51,'PERMISSIONS',19);
  if j->>'coverage_status'<>'COMPLETE' or j->>'story_ready_status'<>'READY' then
    raise exception 'SELFTEST_B2B_AUTH001_PERMISSIONS_REGRESSION:%',j;
  end if;
end;
$block$;

comment on function programacion.fn_input_na_positive_authority_v512(text,integer,bigint)
is '5.12 positive N/A authority. Adds explicit unauthenticated Client recovery exclusion for screen profiles/permissions; absence alone remains insufficient.';

comment on function programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)
is '5.12 semantic classifier. Recognizes governed Client recovery OTP semantics and API Story-vs-Implementation stage boundary without weakening fail-closed source requirements.';
