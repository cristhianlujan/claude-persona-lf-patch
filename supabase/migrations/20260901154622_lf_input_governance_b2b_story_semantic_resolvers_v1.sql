-- INPUT_GOVERNANCE_AGENT 5.12
-- Extend existing semantic resolvers for LF Empresa without creating product data.
-- B2B candidate sources may satisfy Story when they are explicit, internally
-- consistent and traceable, while later stages remain fail-closed until current
-- implementation authority exists. API_DATA_CONTRACT is intentionally untouched.

do $migration$
declare
  v_def text;
  v_sha text;
  v_new text;
  v_decl_anchor text := E'  v_action_rule_codes jsonb:=''[]''::jsonb;\n';
  v_decl_replacement text := E'  v_action_rule_codes jsonb:=''[]''::jsonb;\n  v_screen_code text;\n  v_candidate_count integer:=0;\n  v_story_source_count integer:=0;\n  v_unresolved_count_b2b integer:=0;\n  v_broken_ref_count integer:=0;\n  v_missing_source_count integer:=0;\n  v_required_editable_count integer:=0;\n  v_required_editable_without_validation integer:=0;\n  v_validation_count integer:=0;\n  v_validation_metadata_missing integer:=0;\n  v_rule_count integer:=0;\n  v_policy_ok boolean:=false;\n  v_session_ok boolean:=false;\n  v_factor_ok boolean:=false;\n  v_implementation_pending boolean:=false;\n';
  v_flow_anchor text := E'  if p_family_code in (''FIELDS'',''VALIDATIONS'') then\n    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id);\n    if coalesce((v_field_probe->>''handled'')::boolean,false) then\n      return v_field_probe;\n    end if;\n    return v_base;\n  end if;\n\n  if p_family_code<>''ACTIONS'' then\n    return v_base;\n  end if;\n';
  v_flow_replacement text := $patch$
  v_screen_code:=nullif(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->>'screen_code','');

  if p_family_code='FIELDS' then
    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id);
    if coalesce((v_field_probe->>'handled')::boolean,false) then return v_field_probe; end if;
    return v_base;
  end if;

  if p_family_code='VALIDATIONS' and v_screen_code like 'B2B-%' then
    select
      count(*) filter(where coalesce(cp.required_override,c.es_requerido) and (c.source_type='USER' or (jsonb_typeof(cp.editable_by)='array' and jsonb_array_length(cp.editable_by)>0))),
      count(*) filter(where coalesce(cp.required_override,c.es_requerido) and (c.source_type='USER' or (jsonb_typeof(cp.editable_by)='array' and jsonb_array_length(cp.editable_by)>0)) and not exists(select 1 from lf_ops.campos_validaciones cv where cv.campo_id=c.id and cv.estado<>'DEPRECATED')),
      (select count(*) from lf_ops.campos_validaciones cv join lf_ops.campos c2 on c2.id=cv.campo_id join lf_ops.campos_pantallas cp2 on cp2.campo_id=c2.id where cp2.pantalla_id=p_pantalla_id and cv.estado<>'DEPRECATED'),
      (select count(*) from lf_ops.campos_validaciones cv join lf_ops.campos c2 on c2.id=cv.campo_id join lf_ops.campos_pantallas cp2 on cp2.campo_id=c2.id where cp2.pantalla_id=p_pantalla_id and cv.estado<>'DEPRECATED' and (cv.tipo_validacion is null or cv.validation_level is null or cv.blocking is null)),
      (select count(*) from lf_ops.campos_validaciones cv join lf_ops.campos c2 on c2.id=cv.campo_id join lf_ops.campos_pantallas cp2 on cp2.campo_id=c2.id where cp2.pantalla_id=p_pantalla_id and cv.estado='CANDIDATO')
    into v_required_editable_count,v_required_editable_without_validation,v_validation_count,v_validation_metadata_missing,v_candidate_count
    from lf_ops.campos_pantallas cp join lf_ops.campos c on c.id=cp.campo_id
    where cp.pantalla_id=p_pantalla_id;
    if v_required_editable_count>0 and v_required_editable_without_validation=0 and v_validation_count>0 and v_validation_metadata_missing=0 then
      return jsonb_build_object(
        'handled',true,'family_code',p_family_code,'level','COMPLETE','severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'VALIDATION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object('story','READY','implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end),
        'stage_blockers',case when v_candidate_count>0 then jsonb_build_array(jsonb_build_object('code','VALIDATION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY','earliest_blocking_stage','IMPLEMENTATION')) else '[]'::jsonb end,
        'probe',jsonb_build_object('resolution_contract','B2B_EDITABLE_VALIDATION_RESOLUTION_V1','required_editable_field_count',v_required_editable_count,'required_editable_without_validation_count',v_required_editable_without_validation,'validation_count',v_validation_count,'validation_metadata_missing_count',v_validation_metadata_missing,'candidate_validation_count',v_candidate_count,'readonly_required_fields_do_not_require_input_validation',true)
      );
    end if;
    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id);
    if coalesce((v_field_probe->>'handled')::boolean,false) then return v_field_probe; end if;
    return v_base;
  end if;

  if p_family_code='ROUTING_NAVIGATION' and v_screen_code like 'B2B-%' then
    select count(*),count(*) filter(where status='CANDIDATO'),count(*) filter(where source_decision_id is null)
      into v_story_source_count,v_candidate_count,v_missing_source_count
    from lf_ops.rutas where pantalla_id=p_pantalla_id and status<>'DEPRECATED';
    with refs as (
      select distinct substring(x.value from 7) as route_code
      from lf_ops.pantalla_elementos pe cross join lateral jsonb_array_elements_text(pe.source_refs) x(value)
      where pe.pantalla_id=p_pantalla_id and pe.status<>'DEPRECATED' and x.value like 'route:%'
    )
    select count(*) filter(where r.route_code is null)
      into v_broken_ref_count
    from refs q left join lf_ops.rutas r on r.route_code=q.route_code and r.status<>'DEPRECATED';
    select count(*) into v_rule_count from lf_ops.v_b2b_rel_screen_route where source_code=v_screen_code and relation_type='SCREEN_ROUTE';
    if v_story_source_count>0 and v_rule_count>0 and v_broken_ref_count=0 and v_missing_source_count=0 then
      return jsonb_build_object(
        'handled',true,'family_code',p_family_code,'level','COMPLETE','severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'ROUTE_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object('story','READY','implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end),
        'stage_blockers',case when v_candidate_count>0 then jsonb_build_array(jsonb_build_object('code','ROUTE_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY','earliest_blocking_stage','IMPLEMENTATION')) else '[]'::jsonb end,
        'probe',jsonb_build_object('resolution_contract','B2B_ROUTE_GRAPH_RESOLUTION_V1','screen_route_count',v_story_source_count,'screen_route_relation_count',v_rule_count,'broken_referenced_route_count',v_broken_ref_count,'missing_source_decision_count',v_missing_source_count,'candidate_route_count',v_candidate_count)
      );
    end if;
    return v_base;
  end if;

  if p_family_code='TRANSITIONS' and v_screen_code like 'B2B-%' then
    with s as (select state_id from lf_ops.pantallas_estados where pantalla_id=p_pantalla_id), t as (
      select et.* from lf_ops.estados_transiciones et where et.from_state_id in (select state_id from s)
    )
    select count(*),count(*) filter(where status='CANDIDATO'),count(*) filter(where to_state_id not in (select state_id from s)),count(*) filter(where required_permission_id is not null and not exists(select 1 from lf_ops.permisos p where p.permission_id=t.required_permission_id)),count(*) filter(where source_decision_id is null)
      into v_story_source_count,v_candidate_count,v_unresolved_count_b2b,v_broken_ref_count,v_missing_source_count from t;
    select count(*) into v_rule_count from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-STATE-001' and r.estado<>'DEPRECADO' and not r.pendiente_decision and r.valor_config->>'registry'='lf_ops.estados_transiciones';
    if v_story_source_count>0 and v_rule_count>0 and v_unresolved_count_b2b=0 and v_broken_ref_count=0 and v_missing_source_count=0 then
      return jsonb_build_object(
        'handled',true,'family_code',p_family_code,'level','COMPLETE','severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'TRANSITION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object('story','READY','implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end),
        'stage_blockers',case when v_candidate_count>0 then jsonb_build_array(jsonb_build_object('code','TRANSITION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY','earliest_blocking_stage','IMPLEMENTATION')) else '[]'::jsonb end,
        'probe',jsonb_build_object('resolution_contract','B2B_TRANSITION_GRAPH_RESOLUTION_V1','transition_count',v_story_source_count,'candidate_transition_count',v_candidate_count,'cross_screen_state_ref_count',v_unresolved_count_b2b,'broken_permission_ref_count',v_broken_ref_count,'missing_source_decision_count',v_missing_source_count,'state_rule_count',v_rule_count)
      );
    end if;
    return v_base;
  end if;

  if p_family_code='MFA_OTP_SSO' and v_screen_code like 'B2B-%' then
    select count(*) into v_rule_count
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and r.estado<>'DEPRECADO' and not r.pendiente_decision
      and (r.valor_config->>'mfa_security_policy_id') ~ '^[0-9]+$' and (r.valor_config->>'session_policy_id') ~ '^[0-9]+$';
    select exists(
      select 1 from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and ps.enforcement_level='REQUIRED' and ps.status<>'DEPRECATED' and jsonb_array_length(coalesce(ps.policy_config->'current_required_profile_ids','[]'::jsonb))>0 and jsonb_array_length(coalesce(ps.policy_config->'unresolved_profile_ids','[]'::jsonb))=0
    ) into v_policy_ok;
    select exists(
      select 1 from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_sesion ps on ps.session_policy_id=(r.valor_config->>'session_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and ps.scope_code='B2B_APP_SHELL' and ps.status<>'DEPRECATED' and jsonb_array_length(coalesce(ps.mfa_required_profiles,'[]'::jsonb))>0
    ) into v_session_ok;
    select exists(
      select 1 from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint join lf_ops.politicas_seguridad factor on factor.security_policy_id=(ps.policy_config->>'factor_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and factor.status<>'DEPRECATED' and factor.policy_config->>'factor_selection_status'='CLOSED_POLICY_DEFINED' and factor.policy_config->>'coverage_status'='ALL_HUMAN_PROFILES'
    ) into v_factor_ok;
    select exists(
      select 1 from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint join lf_ops.politicas_seguridad factor on factor.security_policy_id=(ps.policy_config->>'factor_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and (coalesce(factor.policy_config->>'admin_method_status','') ilike '%PENDING%' or coalesce(factor.policy_config->>'non_admin_method_status','') ilike '%PENDING%' or coalesce(factor.policy_config->>'non_admin_delivery_provider_status','') ilike '%PENDING%' or coalesce(factor.policy_config->>'admin_provider_configuration_status','') ilike '%PENDING%')
    ) into v_implementation_pending;
    if v_rule_count>0 and v_policy_ok and v_session_ok and v_factor_ok then
      return jsonb_build_object(
        'handled',true,'family_code',p_family_code,'level','COMPLETE','severity',case when v_implementation_pending then 'P1' else 'P4' end,
        'blocker_code',case when v_implementation_pending then 'MFA_PROVIDER_IMPLEMENTATION_PENDING' else null end,
        'stage_statuses',jsonb_build_object('story','READY','implementation',case when v_implementation_pending then 'NOT_READY' else 'READY' end,'qa',case when v_implementation_pending then 'BLOCKED' else 'READY' end,'production',case when v_implementation_pending then 'BLOCKED' else 'READY' end),
        'stage_blockers',case when v_implementation_pending then jsonb_build_array(jsonb_build_object('code','MFA_PROVIDER_IMPLEMENTATION_PENDING','earliest_blocking_stage','IMPLEMENTATION')) else '[]'::jsonb end,
        'probe',jsonb_build_object('resolution_contract','B2B_CENTRAL_MFA_POLICY_RESOLUTION_V1','auth_rule_count',v_rule_count,'mfa_policy_resolved',v_policy_ok,'session_policy_resolved',v_session_ok,'factor_policy_defined',v_factor_ok,'implementation_pending',v_implementation_pending,'scope','B2B_APP_SHELL')
      );
    end if;
    return v_base;
  end if;

  if p_family_code<>'ACTIONS' then return v_base; end if;

  if v_screen_code like 'B2B-%' then
    select count(*),count(*) filter(where status='CANDIDATO'),count(*) filter(where semantic_binding_status not in ('RESOLVED_ID','NOT_APPLICABLE') or jsonb_array_length(coalesce(source_refs,'[]'::jsonb))=0)
      into v_story_source_count,v_candidate_count,v_unresolved_count_b2b
    from lf_ops.pantalla_elementos
    where pantalla_id=p_pantalla_id and status<>'DEPRECATED' and element_role in ('PRIMARY_CTA','SECONDARY_CTA','ROW_DETAIL_ACTION','DOWNLOAD_ACTION','ROW_ACTION','ACTION');
    if v_story_source_count>0 and v_unresolved_count_b2b=0 then
      return jsonb_build_object(
        'handled',true,'family_code',p_family_code,'level','COMPLETE','severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'ACTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object('story','READY','implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end),
        'stage_blockers',case when v_candidate_count>0 then jsonb_build_array(jsonb_build_object('code','ACTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY','earliest_blocking_stage','IMPLEMENTATION')) else '[]'::jsonb end,
        'probe',jsonb_build_object('resolution_contract','B2B_SCREEN_ACTION_RESOLUTION_V1','action_element_count',v_story_source_count,'candidate_action_element_count',v_candidate_count,'unresolved_action_element_count',v_unresolved_count_b2b)
      );
    end if;
  end if;
$patch$;
begin
  select pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure),
         encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure),'UTF8'),'sha256'),'hex')
    into v_def,v_sha;
  if v_sha<>'d2ca8e2626fa272481a036ce5b971ae19330216a702d7a840f1fa087788a8743' then raise exception 'B2B_STORY_SEMANTIC_PROBE_BASELINE_SHA_MISMATCH:%',v_sha; end if;
  if position(v_decl_anchor in v_def)=0 then raise exception 'B2B_STORY_SEMANTIC_PROBE_DECL_ANCHOR_DRIFT'; end if;
  if position(v_flow_anchor in v_def)=0 then raise exception 'B2B_STORY_SEMANTIC_PROBE_FLOW_ANCHOR_DRIFT'; end if;
  v_new:=replace(v_def,v_decl_anchor,v_decl_replacement);
  v_new:=replace(v_new,v_flow_anchor,v_flow_replacement);
  execute v_new;
end;
$migration$;

do $migration$
declare
  v_def text;
  v_sha text;
  v_anchor text := E'        v:=jsonb_set(v,''{blockers}'',jsonb_build_array(jsonb_build_object(\n          ''code'',v_blocker,''family_code'',p_family_code,''bootstrap_level'',v_level\n        )),true);\n      end if;\n    end if;\n  end if;\n\n  v:=programacion.fn_input_apply_stage_authority_v2(v,p_pantalla_id,p_family_code,p_version_id);';
  v_replacement text := E'        v:=jsonb_set(v,''{blockers}'',jsonb_build_array(jsonb_build_object(\n          ''code'',v_blocker,''family_code'',p_family_code,''bootstrap_level'',v_level\n        )),true);\n      end if;\n      if jsonb_typeof(v_sem->''stage_statuses'')=''object'' then\n        v:=jsonb_set(v,''{severity}'',to_jsonb(coalesce(v_sem->>''severity'',v->>''severity'')),true);\n        v:=jsonb_set(v,''{story_ready_status}'',to_jsonb(coalesce(v_sem->''stage_statuses''->>''story'',v->>''story_ready_status'')),true);\n        v:=jsonb_set(v,''{implementation_ready_status}'',to_jsonb(coalesce(v_sem->''stage_statuses''->>''implementation'',v->>''implementation_ready_status'')),true);\n        v:=jsonb_set(v,''{qa_ready_status}'',to_jsonb(coalesce(v_sem->''stage_statuses''->>''qa'',v->>''qa_ready_status'')),true);\n        v:=jsonb_set(v,''{production_ready_status}'',to_jsonb(coalesce(v_sem->''stage_statuses''->>''production'',v->>''production_ready_status'')),true);\n        v:=jsonb_set(v,''{blockers}'',coalesce(v_sem->''stage_blockers'',''[]''::jsonb),true);\n      end if;\n    end if;\n  end if;\n\n  v:=programacion.fn_input_apply_stage_authority_v2(v,p_pantalla_id,p_family_code,p_version_id);';
begin
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure),
         encode(extensions.digest(convert_to(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure),'UTF8'),'sha256'),'hex')
    into v_def,v_sha;
  if v_sha<>'c2e92ee51045e854eb51acb69ae4360bda22a9a3e821418d45e27b44e27b49e1' then raise exception 'B2B_STORY_CLASSIFIER_BASELINE_SHA_MISMATCH:%',v_sha; end if;
  if position(v_anchor in v_def)=0 then raise exception 'B2B_STORY_CLASSIFIER_STAGE_ANCHOR_DRIFT'; end if;
  execute replace(v_def,v_anchor,v_replacement);
end;
$migration$;
