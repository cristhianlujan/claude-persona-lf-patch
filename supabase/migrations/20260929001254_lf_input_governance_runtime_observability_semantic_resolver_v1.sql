-- Semantic truth for OBSERVABILITY and RUNTIME_CONFIG.
-- Existing canonical definitions are recognized, but pending provider/runtime
-- bindings remain implementation-blocking.

begin;

do $patch$
declare
  r record;
  v_def text;
begin
  for r in
    select *
    from (
      values
        (
          'programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)',
          $$  if p_family_code='FORCED_COLORS_CONTRAST' then$$,
          $$  if p_family_code='OBSERVABILITY' then
    v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
    v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

    select
      count(*),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where jsonb_typeof(x.value->'config'->'dimensions')='array'
          and jsonb_array_length(x.value->'config'->'dimensions')>0
      ),
      count(*) filter(
        where coalesce((x.value->'config'->>'qa_required')::boolean,false)
          and coalesce((x.value->'config'->>'credentials_required')::boolean,false)
          and jsonb_typeof(x.value->'config'->'required_status_before_active')='array'
          and jsonb_array_length(x.value->'config'->'required_status_before_active')>0
      )
    into v_rule_count,v_candidate_count,v_story_source_count,v_unresolved_count_b2b
    from jsonb_array_elements(v_rules) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        upper(coalesce(x.value->>'category',''))='OBSERVABILITY'
        or x.value->'config' ? 'dimensions'
        or x.value->'config' ? 'required_status_before_active'
      );

    select
      count(*),
      count(*) filter(
        where enabled
          and status in ('VIGENTE','ACTIVO')
          and integration_status in ('ACTIVE','IMPLEMENTED','READY_FOR_QA','VERIFIED')
      )
    into v_broken_ref_count,v_missing_source_count
    from lf_ops.observabilidad_proveedores
    where status<>'DEPRECATED';

    if v_rule_count>0 then
      if v_story_source_count>0
         and v_unresolved_count_b2b>0
         and v_broken_ref_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level',case
            when v_candidate_count=0 and v_missing_source_count>0 then 'COMPLETE'
            else 'PARTIAL'
          end,
          'severity',case
            when v_candidate_count=0 and v_missing_source_count>0 then 'P4'
            else 'P1'
          end,
          'blocker_code',case
            when v_candidate_count=0 and v_missing_source_count>0 then null
            else 'OBSERVABILITY_RUNTIME_PROVIDER_NOT_READY'
          end,
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation',case
              when v_candidate_count=0 and v_missing_source_count>0 then 'READY'
              else 'NOT_READY'
            end,
            'qa',case
              when v_candidate_count=0 and v_missing_source_count>0 then 'READY'
              else 'BLOCKED'
            end,
            'production',case
              when v_candidate_count=0 and v_missing_source_count>0 then 'READY'
              else 'BLOCKED'
            end
          ),
          'stage_blockers',case
            when v_candidate_count=0 and v_missing_source_count>0 then '[]'::jsonb
            else jsonb_build_array(jsonb_build_object(
              'code','OBSERVABILITY_RUNTIME_PROVIDER_NOT_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          end,
          'probe',jsonb_build_object(
            'resolution_contract','OBSERVABILITY_SEMANTIC_RESOLUTION_V1',
            'semantic_rule_count',v_rule_count,
            'candidate_rule_count',v_candidate_count,
            'dimensions_contract_count',v_story_source_count,
            'activation_gate_contract_count',v_unresolved_count_b2b,
            'provider_registry_count',v_broken_ref_count,
            'runtime_ready_provider_count',v_missing_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','OBSERVABILITY_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','OBSERVABILITY_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','OBSERVABILITY_SEMANTIC_RESOLUTION_V1',
          'semantic_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'dimensions_contract_count',v_story_source_count,
          'activation_gate_contract_count',v_unresolved_count_b2b,
          'provider_registry_count',v_broken_ref_count,
          'runtime_ready_provider_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='RUNTIME_CONFIG' then
    v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
    v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

    select
      count(*),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where nullif(x.value->'config'->>'provider_registry','') is not null
          and to_regclass(x.value->'config'->>'provider_registry') is not null
          and nullif(x.value->'config'->>'auth_policy_registry','') is not null
          and to_regclass(x.value->'config'->>'auth_policy_registry') is not null
          and jsonb_typeof(x.value->'config'->'active_requires')='array'
          and coalesce(x.value->'config'->>'secrets_in_rules','')='DENY'
          and coalesce(x.value->'config'->>'credentials_in_rules','')='DENY'
      )
    into v_rule_count,v_candidate_count,v_story_source_count
    from jsonb_array_elements(v_rules) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'provider_registry'
        or x.value->'config' ? 'auth_policy_registry'
        or x.value->'config' ? 'active_requires'
      );

    select
      count(*) filter(
        where nullif(x.value->'config'->>'frontend_runtime','') is not null
          and nullif(x.value->'config'->>'backend_runtime','') is not null
      ),
      count(*) filter(
        where coalesce(x.value->'config'->>'provider_binding','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(x.value->'config'->>'local_identity_decision','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(x.value->'config'->>'identity_contract_status','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(x.value->'config'->>'physical_endpoint','') ~* '^(UNDEFINED|PENDING)'
           or coalesce(x.value->'config'->>'oidc_grant','') ~* '^(UNDEFINED|PENDING)'
      )
    into v_unresolved_count_b2b,v_missing_source_count
    from jsonb_array_elements(v_rules) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO';

    if v_rule_count>0 then
      if v_story_source_count>0 and v_unresolved_count_b2b>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level',case
            when v_candidate_count=0 and v_missing_source_count=0 then 'COMPLETE'
            else 'PARTIAL'
          end,
          'severity',case
            when v_candidate_count=0 and v_missing_source_count=0 then 'P4'
            else 'P1'
          end,
          'blocker_code',case
            when v_candidate_count=0 and v_missing_source_count=0 then null
            else 'RUNTIME_CONFIG_BINDING_PENDING'
          end,
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation',case
              when v_candidate_count=0 and v_missing_source_count=0 then 'READY'
              else 'NOT_READY'
            end,
            'qa',case
              when v_candidate_count=0 and v_missing_source_count=0 then 'READY'
              else 'BLOCKED'
            end,
            'production',case
              when v_candidate_count=0 and v_missing_source_count=0 then 'READY'
              else 'BLOCKED'
            end
          ),
          'stage_blockers',case
            when v_candidate_count=0 and v_missing_source_count=0 then '[]'::jsonb
            else jsonb_build_array(jsonb_build_object(
              'code','RUNTIME_CONFIG_BINDING_PENDING',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          end,
          'probe',jsonb_build_object(
            'resolution_contract','RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V2',
            'runtime_contract_rule_count',v_rule_count,
            'candidate_runtime_rule_count',v_candidate_count,
            'resolved_registry_contract_count',v_story_source_count,
            'runtime_boundary_rule_count',v_unresolved_count_b2b,
            'pending_runtime_binding_count',v_missing_source_count
          )
        );
      end if;
    end if;

    return v_base;
  end if;

  if p_family_code='FORCED_COLORS_CONTRAST' then$$
        ),
        (
          'programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)',
          $$  if p_family_code='FORCED_COLORS_CONTRAST' then$$,
          $$  if p_family_code='OBSERVABILITY' then
    v_rules:=coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb);

    select
      count(*),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where jsonb_typeof(x.value->'config'->'dimensions')='array'
          and jsonb_array_length(x.value->'config'->'dimensions')>0
      ),
      count(*) filter(
        where coalesce((x.value->'config'->>'qa_required')::boolean,false)
          and coalesce((x.value->'config'->>'credentials_required')::boolean,false)
          and jsonb_typeof(x.value->'config'->'required_status_before_active')='array'
          and jsonb_array_length(x.value->'config'->'required_status_before_active')>0
      )
    into v_rule_count,v_candidate_count,v_story_source_count,v_unresolved_count_b2b
    from jsonb_array_elements(v_rules) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        upper(coalesce(x.value->>'category',''))='OBSERVABILITY'
        or x.value->'config' ? 'dimensions'
        or x.value->'config' ? 'required_status_before_active'
      );

    select
      count(*),
      count(*) filter(
        where enabled
          and status in ('VIGENTE','ACTIVO')
          and integration_status in ('ACTIVE','IMPLEMENTED','READY_FOR_QA','VERIFIED')
      )
    into v_broken_ref_count,v_missing_source_count
    from lf_ops.observabilidad_proveedores
    where status<>'DEPRECATED';

    if v_rule_count>0 then
      if v_story_source_count>0
         and v_unresolved_count_b2b>0
         and v_broken_ref_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level',case
            when v_candidate_count=0 and v_missing_source_count>0 then 'COMPLETE'
            else 'PARTIAL'
          end,
          'severity',case
            when v_candidate_count=0 and v_missing_source_count>0 then 'P4'
            else 'P1'
          end,
          'blocker_code',case
            when v_candidate_count=0 and v_missing_source_count>0 then null
            else 'OBSERVABILITY_RUNTIME_PROVIDER_NOT_READY'
          end,
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation',case
              when v_candidate_count=0 and v_missing_source_count>0 then 'READY'
              else 'NOT_READY'
            end,
            'qa',case
              when v_candidate_count=0 and v_missing_source_count>0 then 'READY'
              else 'BLOCKED'
            end,
            'production',case
              when v_candidate_count=0 and v_missing_source_count>0 then 'READY'
              else 'BLOCKED'
            end
          ),
          'stage_blockers',case
            when v_candidate_count=0 and v_missing_source_count>0 then '[]'::jsonb
            else jsonb_build_array(jsonb_build_object(
              'code','OBSERVABILITY_RUNTIME_PROVIDER_NOT_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          end,
          'probe',jsonb_build_object(
            'resolution_contract','OBSERVABILITY_SEMANTIC_RESOLUTION_V1',
            'semantic_rule_count',v_rule_count,
            'candidate_rule_count',v_candidate_count,
            'dimensions_contract_count',v_story_source_count,
            'activation_gate_contract_count',v_unresolved_count_b2b,
            'provider_registry_count',v_broken_ref_count,
            'runtime_ready_provider_count',v_missing_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','OBSERVABILITY_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','OBSERVABILITY_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','OBSERVABILITY_SEMANTIC_RESOLUTION_V1',
          'semantic_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'dimensions_contract_count',v_story_source_count,
          'activation_gate_contract_count',v_unresolved_count_b2b,
          'provider_registry_count',v_broken_ref_count,
          'runtime_ready_provider_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='RUNTIME_CONFIG' then
    v_rules:=coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb);

    select
      count(*),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where nullif(x.value->'config'->>'provider_registry','') is not null
          and to_regclass(x.value->'config'->>'provider_registry') is not null
          and nullif(x.value->'config'->>'auth_policy_registry','') is not null
          and to_regclass(x.value->'config'->>'auth_policy_registry') is not null
          and jsonb_typeof(x.value->'config'->'active_requires')='array'
          and coalesce(x.value->'config'->>'secrets_in_rules','')='DENY'
          and coalesce(x.value->'config'->>'credentials_in_rules','')='DENY'
      )
    into v_rule_count,v_candidate_count,v_story_source_count
    from jsonb_array_elements(v_rules) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'provider_registry'
        or x.value->'config' ? 'auth_policy_registry'
        or x.value->'config' ? 'active_requires'
      );

    select
      count(*) filter(
        where nullif(x.value->'config'->>'frontend_runtime','') is not null
          and nullif(x.value->'config'->>'backend_runtime','') is not null
      ),
      count(*) filter(
        where coalesce(x.value->'config'->>'provider_binding','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(x.value->'config'->>'local_identity_decision','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(x.value->'config'->>'identity_contract_status','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(x.value->'config'->>'physical_endpoint','') ~* '^(UNDEFINED|PENDING)'
           or coalesce(x.value->'config'->>'oidc_grant','') ~* '^(UNDEFINED|PENDING)'
      )
    into v_unresolved_count_b2b,v_missing_source_count
    from jsonb_array_elements(v_rules) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO';

    if v_rule_count>0 and v_story_source_count>0 and v_unresolved_count_b2b>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level',case
          when v_candidate_count=0 and v_missing_source_count=0 then 'COMPLETE'
          else 'PARTIAL'
        end,
        'severity',case
          when v_candidate_count=0 and v_missing_source_count=0 then 'P4'
          else 'P1'
        end,
        'blocker_code',case
          when v_candidate_count=0 and v_missing_source_count=0 then null
          else 'RUNTIME_CONFIG_BINDING_PENDING'
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count=0 and v_missing_source_count=0 then 'READY' else 'NOT_READY' end,
          'qa',case when v_candidate_count=0 and v_missing_source_count=0 then 'READY' else 'BLOCKED' end,
          'production',case when v_candidate_count=0 and v_missing_source_count=0 then 'READY' else 'BLOCKED' end
        ),
        'stage_blockers',case
          when v_candidate_count=0 and v_missing_source_count=0 then '[]'::jsonb
          else jsonb_build_array(jsonb_build_object(
            'code','RUNTIME_CONFIG_BINDING_PENDING',
            'earliest_blocking_stage','IMPLEMENTATION'
          ))
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V2',
          'runtime_contract_rule_count',v_rule_count,
          'candidate_runtime_rule_count',v_candidate_count,
          'resolved_registry_contract_count',v_story_source_count,
          'runtime_boundary_rule_count',v_unresolved_count_b2b,
          'pending_runtime_binding_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FORCED_COLORS_CONTRAST' then$$
        )
    ) x(sig,anchor_text,insert_text)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;
    if v_def is null then
      raise exception 'RUNTIME_OBSERVABILITY_SEMANTIC_FUNCTION_MISSING:%',r.sig;
    end if;
    if position('OBSERVABILITY_SEMANTIC_RESOLUTION_V1' in v_def)=0 then
      if position(r.anchor_text in v_def)=0 then
        raise exception 'RUNTIME_OBSERVABILITY_SEMANTIC_SOURCE_DRIFT:%',r.sig;
      end if;
      v_def:=replace(v_def,r.anchor_text,r.insert_text);
      execute v_def;
    end if;
  end loop;
end;
$patch$;

do $postconditions$
declare
  v_obs jsonb;
  v_runtime jsonb;
  v_graph jsonb;
  v_negative jsonb;
begin
  v_obs:=programacion.fn_input_governance_bootstrap_classify_v2(51,'OBSERVABILITY',19);
  if v_obs->>'coverage_status'<>'PARTIAL'
     or v_obs->>'implementation_ready_status'<>'NOT_READY'
     or v_obs#>>'{probe,resolution_contract}'<>'OBSERVABILITY_SEMANTIC_RESOLUTION_V1'
     or coalesce((v_obs#>>'{probe,semantic_rule_count}')::integer,0)<2
     or coalesce((v_obs#>>'{probe,runtime_ready_provider_count}')::integer,-1)<>0 then
    raise exception 'OBSERVABILITY_CURRENT_POSTCONDITION_FAILED:%',v_obs;
  end if;

  v_runtime:=programacion.fn_input_governance_bootstrap_classify_v2(51,'RUNTIME_CONFIG',19);
  if v_runtime->>'coverage_status'<>'PARTIAL'
     or v_runtime->>'implementation_ready_status'<>'NOT_READY'
     or v_runtime#>>'{probe,resolution_contract}'<>'RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V2'
     or coalesce((v_runtime#>>'{probe,resolved_registry_contract_count}')::integer,0)<1
     or coalesce((v_runtime#>>'{probe,pending_runtime_binding_count}')::integer,0)<1 then
    raise exception 'RUNTIME_CONFIG_CURRENT_POSTCONDITION_FAILED:%',v_runtime;
  end if;

  -- Negative synthetic graph: unrelated rule cannot become handled/complete.
  v_graph:=programacion.fn_input_screen_canonical_graph(51,19);
  v_graph:=jsonb_set(
    v_graph,
    '{canonical_contract,rules}',
    jsonb_build_array(jsonb_build_object(
      'rule_code','TEST-UNRELATED-RUNTIME',
      'status','VIGENTE',
      'config',jsonb_build_object('keyboard',true)
    )),
    true
  );

  v_negative:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'OBSERVABILITY',19,v_graph
  );
  if v_negative#>>'{probe,resolution_contract}'='OBSERVABILITY_SEMANTIC_RESOLUTION_V1'
     or v_negative->>'level'='COMPLETE' then
    raise exception 'OBSERVABILITY_NEGATIVE_FAIL_CLOSED_FAILED:%',v_negative;
  end if;

  v_negative:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
    51,'RUNTIME_CONFIG',19,v_graph
  );
  if v_negative#>>'{probe,resolution_contract}'='RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V2'
     or v_negative->>'level'='COMPLETE' then
    raise exception 'RUNTIME_CONFIG_NEGATIVE_FAIL_CLOSED_FAILED:%',v_negative;
  end if;
end;
$postconditions$;

commit;
