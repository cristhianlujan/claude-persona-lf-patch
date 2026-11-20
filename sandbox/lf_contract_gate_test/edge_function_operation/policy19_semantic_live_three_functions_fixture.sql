-- Read-only snapshot of live function definitions; source md5 pinned in governed migration.
CREATE SCHEMA IF NOT EXISTS programacion;
-- fn_input_governance_semantic_probe_v3 md5 8e2fd437a0ab693ce02fb3d6afe95406
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v3(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_base jsonb;
  v_field_probe jsonb;
  v_graph jsonb;
  v_rules jsonb;
  v_branch_count integer:=0;
  v_outcome_count integer:=0;
  v_commit_count integer:=0;
  v_post_success_count integer:=0;
  v_outcome_integrity_failures integer:=0;
  v_action_rule_codes jsonb:='[]'::jsonb;
  v_screen_code text;
  v_candidate_count integer:=0;
  v_story_source_count integer:=0;
  v_unresolved_count_b2b integer:=0;
  v_broken_ref_count integer:=0;
  v_missing_source_count integer:=0;
  v_required_editable_count integer:=0;
  v_required_editable_without_validation integer:=0;
  v_validation_count integer:=0;
  v_validation_metadata_missing integer:=0;
  v_rule_count integer:=0;
  v_policy_ok boolean:=false;
  v_session_ok boolean:=false;
  v_factor_ok boolean:=false;
  v_implementation_pending boolean:=false;
  v_family_complete jsonb;
begin
  v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);
  v_family_complete:=programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,null);
  if coalesce((v_family_complete->>'handled')::boolean,false) then return v_family_complete; end if;


  v_screen_code:=nullif(programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)->>'screen_code','');

  if p_family_code='SESSION' and true then
    with session_rules as (
      select r.*
      from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
      join lf_ops.reglas r on r.id=rp.regla_id
      where rp.pantalla_id=p_pantalla_id
        and r.codigo='B2B-RULE-AUTH-022'
        and r.estado<>'DEPRECADO'
    ), resolved as (
      select
        r.id as rule_id,
        r.estado as rule_status,
        r.valor_config,
        ps.session_policy_id,
        ps.policy_code,
        ps.scope_code,
        ps.status as policy_status,
        ps.refresh_rotation_enabled,
        ps.cookie_policy
      from session_rules r
      left join lf_ops.politicas_sesion ps
        on coalesce(r.valor_config->>'session_policy_id','') ~ '^[0-9]+$'
       and ps.session_policy_id=(r.valor_config->>'session_policy_id')::bigint
    )
    select
      count(*),
      count(*) filter(where rule_status='CANDIDATO'),
      count(*) filter(where session_policy_id is null),
      count(*) filter(where policy_status in ('CANDIDATO','EN_REVISION')),
      count(*) filter(
        where coalesce(valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      ),
      count(*) filter(
        where session_policy_id is not null
          and policy_code='SESSION-B2B-DEFAULT'
          and scope_code='B2B_APP_SHELL'
          and coalesce(valor_config->>'session_contract_code','')='B2B_AUTH_SESSION_CONTRACT_V1'
          and coalesce(valor_config->>'session_creation_authority','')='SERVER_ONLY'
          and coalesce(valor_config->>'required_auth_outcome','')='AUTHENTICATED'
          and coalesce(valor_config->>'session_before_mfa_completion','')='DENY'
          and coalesce(valor_config->>'token_validation_authority','')='SPRING_BOOT_CORE'
          and coalesce(valor_config->>'token_validation_contract','')='ISSUER_JWKS_CLAIMS'
          and coalesce(valor_config->>'refresh_rotation','')='POLICY_DRIVEN'
          and coalesce(valor_config->>'client_session_parameters_authoritative','')='DENY'
          and coalesce(valor_config->>'browser_session_authority','')='DENY'
          and refresh_rotation_enabled
          and coalesce((cookie_policy->>'secure')::boolean,false)
          and coalesce((cookie_policy->>'http_only')::boolean,false)
          and coalesce(cookie_policy->>'session_storage','')='server_managed'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_broken_ref_count,
      v_unresolved_count_b2b,
      v_missing_source_count,
      v_story_source_count
    from resolved;

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_story_source_count=v_rule_count then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'SESSION_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'NOT_READY' else 'READY' end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','SESSION_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SESSION_POLICY_RESOLUTION_V2',
          'session_contract_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'implementation_pending_count',v_missing_source_count,
          'qualified_contract_count',v_story_source_count,
          'policy_code','SESSION-B2B-DEFAULT',
          'provider_binding','OIDC_PROVIDER_AGNOSTIC'
        )
      );
    end if;

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','SESSION_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','SESSION_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SESSION_POLICY_RESOLUTION_V2',
          'session_contract_rule_count',v_rule_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'qualified_contract_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='SECURITY' and true then
    select
      count(*),
      count(*) filter(where r.estado='CANDIDATO'),
      count(*) filter(
        where coalesce(r.valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='B2B-RULE-SECURITY-BASELINE-001'
      and r.estado<>'DEPRECADO';

    select count(*) into v_broken_ref_count
    from jsonb_array_elements(programacion.fn_input_security_threat_expected(p_pantalla_id)) t
    where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');

    select count(*) into v_unresolved_count_b2b
    from jsonb_array_elements(programacion.fn_input_subject_depth_expected(p_pantalla_id,'SECURITY')) s
    where s->>'status'<>'COMPLETE';

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_unresolved_count_b2b=0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'SECURITY_BASELINE_IMPLEMENTATION_PENDING'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','SECURITY_BASELINE_IMPLEMENTATION_PENDING',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SECURITY_BASELINE_RESOLUTION_V1',
          'baseline_rule_count',v_rule_count,
          'candidate_baseline_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count,
          'threat_incomplete_count',v_broken_ref_count,
          'subject_incomplete_count',v_unresolved_count_b2b
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='TIMEOUT_RETRY' and true then
    with timeout_rules as (
      select r.*
      from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
      join lf_ops.reglas r on r.id=rp.regla_id
      where rp.pantalla_id=p_pantalla_id
        and r.codigo='B2B-RULE-AUTH-016'
        and r.estado<>'DEPRECADO'
    ), resolved as (
      select
        r.id as rule_id,
        r.estado as rule_status,
        r.valor_config,
        p.timeout_policy_id,
        p.policy_code,
        p.operation_code,
        p.retry_limit,
        p.backoff_strategy,
        p.status as policy_status
      from timeout_rules r
      left join lf_ops.politicas_timeout p
        on coalesce(r.valor_config->>'timeout_policy_id','') ~ '^[0-9]+$'
       and p.timeout_policy_id=(r.valor_config->>'timeout_policy_id')::bigint
    )
    select
      count(*),
      count(*) filter(where rule_status='CANDIDATO'),
      count(*) filter(where timeout_policy_id is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
           or coalesce(valor_config->>'policy_assignment_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      ),
      count(*) filter(
        where timeout_policy_id is not null
          and operation_code='AUTH_LOGIN_API'
          and retry_limit=0
          and backoff_strategy='NONE'
          and coalesce(valor_config->>'auth_automatic_retry','')='DENY'
          and coalesce(valor_config->>'session_on_timeout','')='DENY'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_broken_ref_count,
      v_unresolved_count_b2b,
      v_missing_source_count,
      v_story_source_count
    from resolved;

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_story_source_count=v_rule_count then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'NOT_READY' else 'READY' end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2',
          'auth_timeout_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'implementation_pending_count',v_missing_source_count,
          'fail_closed_policy_match_count',v_story_source_count,
          'automatic_retry','DENY'
        )
      );
    end if;

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','TIMEOUT_POLICY_REFERENCE_OR_FAIL_CLOSED_CONTRACT_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','TIMEOUT_POLICY_REFERENCE_OR_FAIL_CLOSED_CONTRACT_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2',
          'auth_timeout_rule_count',v_rule_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'fail_closed_policy_match_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='RATE_LIMIT' then
    with semantic_rules as (
      select
        x.value as rule,
        (x.value->'config'->>'rate_limit_policy_id')::bigint as policy_id
      from jsonb_array_elements(
        coalesce(
          programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
            ->'canonical_contract'->'rules',
          '[]'::jsonb
        )
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and coalesce(x.value->'config'->>'rate_limit_policy_id','') ~ '^[0-9]+$'
    ), resolved as (
      select
        s.rule,
        s.policy_id,
        ps.policy_code,
        ps.status as policy_status
      from semantic_rules s
      left join lf_ops.politicas_rate_limit ps
        on ps.rate_limit_policy_id=s.policy_id
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where policy_code is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(rule->>'status','') in ('VIGENTE','ACTIVO')
          and policy_status='VIGENTE'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_story_source_count
    from resolved;

    if v_rule_count>0 then
      if v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','PARTIAL',
          'severity','P1',
          'blocker_code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation','NOT_READY',
            'qa','BLOCKED',
            'production','BLOCKED'
          ),
          'stage_blockers',jsonb_build_array(jsonb_build_object(
            'code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
            'earliest_blocking_stage','IMPLEMENTATION'
          )),
          'probe',jsonb_build_object(
            'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
            'direct_policy_reference_count',v_rule_count,
            'missing_policy_reference_count',v_missing_source_count,
            'candidate_rule_count',v_candidate_count,
            'candidate_policy_count',v_unresolved_count_b2b,
            'vigente_rule_policy_pair_count',v_story_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0
            then 'RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then
            jsonb_build_array(jsonb_build_object(
              'code','RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
          'direct_policy_reference_count',v_rule_count,
          'resolved_policy_reference_count',v_rule_count-v_missing_source_count,
          'missing_policy_reference_count',v_missing_source_count,
          'candidate_rule_count',v_candidate_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'vigente_rule_policy_pair_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='OBSERVABILITY' then
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
    v_base:=programacion.fn_input_runtime_config_existing_authority_probe_v1(p_pantalla_id,p_version_id,null);
    if coalesce((v_base->>'handled')::boolean,false) then return v_base; end if;

    select
      count(*),
      count(*) filter(where r.estado='CANDIDATO'),
      count(*) filter(
        where nullif(r.valor_config->>'provider_registry','') is not null
          and to_regclass(r.valor_config->>'provider_registry') is not null
          and nullif(r.valor_config->>'auth_policy_registry','') is not null
          and to_regclass(r.valor_config->>'auth_policy_registry') is not null
          and jsonb_typeof(r.valor_config->'active_requires')='array'
          and jsonb_array_length(r.valor_config->'active_requires')>0
          and coalesce(r.valor_config->>'secrets_in_rules','')='DENY'
          and coalesce(r.valor_config->>'credentials_in_rules','')='DENY'
      )
    into v_rule_count,v_candidate_count,v_story_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='B2B-RULE-RUNTIME-001'
      and r.estado<>'DEPRECADO';

    select
      count(*),
      count(*) filter(
        where coalesce(r.valor_config->>'provider_binding','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'local_identity_decision','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'identity_contract_status','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'physical_endpoint','') ~* '^(UNDEFINED|UNBOUND|PENDING)'
           or coalesce(r.valor_config->>'oidc_grant','') ~* '^(UNDEFINED|UNBOUND|PENDING)'
           or coalesce(r.valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_unresolved_count_b2b,v_missing_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.estado<>'DEPRECADO'
      and nullif(r.valor_config->>'frontend_runtime','') is not null
      and nullif(r.valor_config->>'backend_runtime','') is not null;

    if v_rule_count>0
       and v_story_source_count=v_rule_count
       and v_unresolved_count_b2b>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'RUNTIME_CONFIG_BINDING_PENDING'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','RUNTIME_CONFIG_BINDING_PENDING',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V3',
          'runtime_contract_rule_count',v_rule_count,
          'candidate_runtime_rule_count',v_candidate_count,
          'resolved_registry_contract_count',v_story_source_count,
          'runtime_boundary_rule_count',v_unresolved_count_b2b,
          'pending_runtime_binding_count',v_missing_source_count,
          'source_authority','SUPABASE_GOVERNED_CANONICAL_RULES'
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='ANALYTICS' then
    with direct_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(
          programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
            ->'canonical_contract'->'rules',
          '[]'::jsonb
        )
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          upper(coalesce(x.value->>'category',''))='ANALYTICS'
          or jsonb_typeof(x.value->'config'->'providers')='array'
        )
    ), provider_refs as (
      select distinct p.value as provider_code
      from direct_rules d
      cross join lateral jsonb_array_elements_text(
        coalesce(d.rule->'config'->'providers','[]'::jsonb)
      ) p(value)
    ), provider_state as (
      select
        pr.provider_code,
        op.provider_id,
        op.status,
        op.enabled,
        op.integration_status
      from provider_refs pr
      left join lf_ops.observabilidad_proveedores op
        on op.provider_code=pr.provider_code
    ), rel as (
      select *
      from lf_ops.v_b2b_rel_screen_analytics
      where source_code=v_screen_code
    ), event_state as (
      select
        rel.target_code,
        c.event_code,
        c.status,
        c.allowed_parameters
      from rel
      left join lf_ops.v_b2b_analytics_contract c
        on c.event_code=rel.target_code
    )
    select
      (select count(*) from direct_rules),
      (select count(*) from direct_rules where coalesce(rule->>'status','')='CANDIDATO'),
      (select count(*) from rel),
      (select count(*) from event_state where event_code is null
          or jsonb_typeof(allowed_parameters)<>'array'
          or jsonb_array_length(allowed_parameters)=0),
      (select count(*) from provider_state where provider_id is null),
      (
        (select count(*) from provider_state where provider_id is not null)
        +
        (select count(*) from event_state where event_code is not null)
      ),
      exists(
        select 1
        from provider_state
        where provider_id is null
           or status not in ('VIGENTE','ACTIVO')
           or not enabled
           or integration_status not in (
             'ACTIVE','READY','CONFIGURED','IMPLEMENTED','READY_FOR_QA','QA_VERIFIED'
           )
      )
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_broken_ref_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_implementation_pending;

    if v_rule_count>0
       and v_story_source_count>0
       and v_broken_ref_count=0
       and v_missing_source_count=0
       and v_unresolved_count_b2b>=2 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_implementation_pending then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_implementation_pending
            then 'ANALYTICS_RUNTIME_PROVIDER_NOT_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_implementation_pending then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_implementation_pending then
            jsonb_build_array(jsonb_build_object(
              'code','ANALYTICS_RUNTIME_PROVIDER_NOT_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count,
          'resolved_provider_plus_event_count',v_unresolved_count_b2b,
          'runtime_provider_pending',v_implementation_pending
        )
      );
    end if;

    if v_rule_count>0 or v_story_source_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FORCED_COLORS_CONTRAST' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'forced_colors_support','')='REQUIRED'
          and coalesce(x.value->'config'->>'focus_visibility','')='REQUIRED'
          and coalesce(x.value->'config'->>'state_color_only','')='DENY'
          and coalesce(x.value->'config'->>'global_forced_color_adjust_none','')='DENY'
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(
        programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'forced_colors_support'
        or x.value->'config' ? 'state_color_only'
        or x.value->'config' ? 'global_forced_color_adjust_none'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','FORCED_COLORS_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='REDUCED_MOTION' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'preference','')='prefers-reduced-motion'
          and coalesce(x.value->'config'->>'functional_dependency_on_motion','')='DENY'
          and coalesce(x.value->'config'->>'non_essential_motion_when_reduce','')='REDUCE_OR_REMOVE'
          and coalesce((x.value->'config'->>'status_requires_non_motion_cue')::boolean,false)
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(
        programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'preference'
        or x.value->'config' ? 'functional_dependency_on_motion'
        or x.value->'config' ? 'non_essential_motion_when_reduce'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','REDUCED_MOTION_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='AUDIT' then
    with semantic_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(
          programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
            ->'canonical_contract'->'rules',
          '[]'::jsonb
        )
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          x.value->'config' ? 'audit_sink'
          or x.value->'config' ? 'required_audit_actions'
          or x.value->'config' ? 'append_only'
          or x.value->'config' ? 'mutation_blocked'
        )
    ), normalized as (
      select
        rule,
        nullif(coalesce(rule->'config'->>'audit_sink',rule->'config'->>'table'),'') as sink_name,
        case
          when jsonb_typeof(rule->'config'->'required_audit_actions')='array'
            then jsonb_array_length(rule->'config'->'required_audit_actions')
          else 0
        end as action_count,
        (
          coalesce((rule->'config'->>'append_only')::boolean,false)
          or coalesce((rule->'config'->>'mutation_blocked')::boolean,false)
          or coalesce(rule->'config'->>'update_delete','')='DENY'
        ) as immutable_contract,
        (
          coalesce((rule->'config'->>'correlation_id_required')::boolean,false)
          or coalesce((rule->'config'->>'correlation_required')::boolean,false)
        ) as correlation_contract
      from semantic_rules
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where sink_name is not null and to_regclass(sink_name) is not null),
      count(*) filter(where action_count>0),
      count(*) filter(where immutable_contract),
      count(*) filter(where correlation_contract)
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_unresolved_count_b2b,
      v_broken_ref_count,
      v_missing_source_count
    from normalized;

    if v_rule_count>0 then
      if v_story_source_count>0
         and v_unresolved_count_b2b>0
         and v_broken_ref_count>0
         and v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','COMPLETE',
          'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
          'blocker_code',case
            when v_candidate_count>0 then 'AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
            else null
          end,
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
            'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
            'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
          ),
          'stage_blockers',case
            when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
              'code','AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
            else '[]'::jsonb
          end,
          'probe',jsonb_build_object(
            'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
            'semantic_rule_count',v_rule_count,
            'candidate_rule_count',v_candidate_count,
            'resolved_sink_rule_count',v_story_source_count,
            'required_action_contract_count',v_unresolved_count_b2b,
            'immutability_contract_count',v_broken_ref_count,
            'correlation_contract_count',v_missing_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
          'semantic_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'resolved_sink_rule_count',v_story_source_count,
          'required_action_contract_count',v_unresolved_count_b2b,
          'immutability_contract_count',v_broken_ref_count,
          'correlation_contract_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='ACCESSIBILITY' and true then
    select
      count(distinct r.value->>'rule_code'),
      count(*) filter(where coalesce(r.value->>'status','')='CANDIDATO')
    into v_rule_count,v_candidate_count
    from jsonb_array_elements(
      coalesce(
        programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id)
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) r(value)
    where r.value->>'rule_code' in (
      'B2B-RULE-A11Y-001',
      'B2B-RULE-A11Y-002',
      'B2B-RULE-A11Y-003',
      'B2B-RULE-A11Y-004'
    );

    if v_rule_count=4 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
            'code','ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
            'earliest_blocking_stage','IMPLEMENTATION'
          ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_ACCESSIBILITY_CORE_RESOLUTION_V1',
          'core_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'required_rule_codes',jsonb_build_array(
            'B2B-RULE-A11Y-001',
            'B2B-RULE-A11Y-002',
            'B2B-RULE-A11Y-003',
            'B2B-RULE-A11Y-004'
          )
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FIELDS' then
    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id);
    if coalesce((v_field_probe->>'handled')::boolean,false) then return v_field_probe; end if;
    return v_base;
  end if;

  if p_family_code='VALIDATIONS' and true then
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

  if p_family_code='ROUTING_NAVIGATION' and true then
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

  if p_family_code='TRANSITIONS' and true then
    with s as (select state_id from lf_ops.pantallas_estados where pantalla_id=p_pantalla_id), t as (
      select et.* from lf_ops.estados_transiciones et where et.from_state_id in (select state_id from s)
    )
    select count(*),count(*) filter(where status='CANDIDATO'),count(*) filter(where to_state_id not in (select state_id from s)),count(*) filter(where required_permission_id is not null and not exists(select 1 from lf_ops.permisos p where p.permission_id=t.required_permission_id)),count(*) filter(where source_decision_id is null)
      into v_story_source_count,v_candidate_count,v_unresolved_count_b2b,v_broken_ref_count,v_missing_source_count from t;
    select count(*) into v_rule_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.estado<>'DEPRECADO'
      and not r.pendiente_decision
      and r.valor_config->>'registry'='lf_ops.estados_transiciones'
      and exists(
        select 1
        from lf_ops.estados_transiciones et
        where et.from_state_id in (
          select pe.state_id
          from lf_ops.pantallas_estados pe
          where pe.pantalla_id=p_pantalla_id
        )
          and et.entity_type=r.valor_config->>'entity_type'
      );
    if v_story_source_count>0 and (v_rule_count>0 or v_missing_source_count=0) and v_unresolved_count_b2b=0 and v_broken_ref_count=0 and v_missing_source_count=0 then
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

  if p_family_code='MFA_OTP_SSO' and true then
    select count(*) into v_rule_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and r.estado<>'DEPRECADO' and not r.pendiente_decision
      and (r.valor_config->>'mfa_security_policy_id') ~ '^[0-9]+$' and (r.valor_config->>'session_policy_id') ~ '^[0-9]+$';
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and ps.enforcement_level='REQUIRED' and ps.status<>'DEPRECATED' and jsonb_array_length(coalesce(ps.policy_config->'current_required_profile_ids','[]'::jsonb))>0 and jsonb_array_length(coalesce(ps.policy_config->'unresolved_profile_ids','[]'::jsonb))=0
    ) into v_policy_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_sesion ps on ps.session_policy_id=(r.valor_config->>'session_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and ps.scope_code='B2B_APP_SHELL' and ps.status<>'DEPRECATED' and jsonb_array_length(coalesce(ps.mfa_required_profiles,'[]'::jsonb))>0
    ) into v_session_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint join lf_ops.politicas_seguridad factor on factor.security_policy_id=(ps.policy_config->>'factor_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and factor.status<>'DEPRECATED' and factor.policy_config->>'factor_selection_status'='CLOSED_POLICY_DEFINED' and factor.policy_config->>'coverage_status'='ALL_HUMAN_PROFILES'
    ) into v_factor_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint join lf_ops.politicas_seguridad factor on factor.security_policy_id=(ps.policy_config->>'factor_security_policy_id')::bigint
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

  if true then
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

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_branch_count
  from direct_vigente_rules d
  where coalesce((d.rule->'config'->>'ask_old_phone_access')::boolean,false)=true
    and nullif(d.rule->'config'->>'old_phone_accessible','') is not null
    and nullif(d.rule->'config'->>'old_phone_unavailable','') is not null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_outcome_count
  from direct_vigente_rules d
  where jsonb_typeof(d.rule->'config'->'allowed_outcomes')='array'
    and jsonb_array_length(d.rule->'config'->'allowed_outcomes')>0
    and jsonb_typeof(d.rule->'config'->'outcomes')='object';

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
      and jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      and jsonb_array_length(r.value->'config'->'allowed_outcomes')>0
      and jsonb_typeof(r.value->'config'->'outcomes')='object'
  ), allowed as (
    select d.rule, a.value as outcome_code
    from direct_vigente_rules d
    cross join lateral jsonb_array_elements_text(d.rule->'config'->'allowed_outcomes') a(value)
  )
  select count(*) into v_outcome_integrity_failures
  from allowed a
  where not (a.rule->'config'->'outcomes' ? a.outcome_code)
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'rebind','') is null
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'operational_access','') is null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_commit_count
  from direct_vigente_rules d
  where d.rule->'config'->>'atomic_commit'='REQUIRED'
    and d.rule->'config'->>'operational_access_before_commit'='DENY'
    and jsonb_typeof(d.rule->'config'->'accepted_recovery_proofs')='array'
    and jsonb_array_length(d.rule->'config'->'accepted_recovery_proofs')>0;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_post_success_count
  from direct_vigente_rules d
  where nullif(d.rule->'config'->>'success_outcome','') is not null
    and nullif(d.rule->'config'->>'post_auth_route','') is not null
    and nullif(d.rule->'config'->>'invalid_session_action','') is not null
    and nullif(d.rule->'config'->>'required_rebind_outcome','') is not null;

  select coalesce(jsonb_agg(distinct r.value->>'rule_code' order by r.value->>'rule_code'),'[]'::jsonb)
    into v_action_rule_codes
  from jsonb_array_elements(v_rules) r(value)
  where r.value->>'status'='VIGENTE'
    and (
      coalesce((r.value->'config'->>'ask_old_phone_access')::boolean,false)=true
      or jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      or r.value->'config'->>'atomic_commit'='REQUIRED'
      or nullif(r.value->'config'->>'success_outcome','') is not null
    );

  if v_branch_count>0
     and v_outcome_count>0
     and v_outcome_integrity_failures=0
     and v_commit_count>0
     and v_post_success_count>0 then
    return jsonb_build_object(
      'handled',true,
      'family_code',p_family_code,
      'level','COMPLETE',
      'blocker_code',null,
      'probe',jsonb_build_object(
        'resolution_contract','STRUCTURED_ACTION_TOPOLOGY_RESOLUTION_V3',
        'branch_contract_count',v_branch_count,
        'outcome_contract_count',v_outcome_count,
        'outcome_integrity_failures',v_outcome_integrity_failures,
        'atomic_commit_contract_count',v_commit_count,
        'post_success_contract_count',v_post_success_count,
        'action_rule_codes',v_action_rule_codes,
        'pending_provider_copy_visual_does_not_authorize_missing_action_dimensions',true
      )
    );
  end if;

  return v_base;
end;
$function$
;

-- fn_input_governance_semantic_probe_v3_cached_v1 md5 f057bbe4e4fdf0c35d2bd73c1ccc5ac5
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v3_cached_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_base jsonb;
  v_field_probe jsonb;
  v_graph jsonb;
  v_rules jsonb;
  v_branch_count integer:=0;
  v_outcome_count integer:=0;
  v_commit_count integer:=0;
  v_post_success_count integer:=0;
  v_outcome_integrity_failures integer:=0;
  v_action_rule_codes jsonb:='[]'::jsonb;
  v_screen_code text;
  v_candidate_count integer:=0;
  v_story_source_count integer:=0;
  v_unresolved_count_b2b integer:=0;
  v_broken_ref_count integer:=0;
  v_missing_source_count integer:=0;
  v_required_editable_count integer:=0;
  v_required_editable_without_validation integer:=0;
  v_validation_count integer:=0;
  v_validation_metadata_missing integer:=0;
  v_rule_count integer:=0;
  v_policy_ok boolean:=false;
  v_session_ok boolean:=false;
  v_factor_ok boolean:=false;
  v_implementation_pending boolean:=false;
  v_family_complete jsonb;
begin
  v_base:=programacion.fn_input_governance_semantic_probe_v2_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);
  v_family_complete:=programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);
  if coalesce((v_family_complete->>'handled')::boolean,false) then return v_family_complete; end if;


  v_screen_code:=nullif(p_graph->>'screen_code','');

  if p_family_code='SESSION' and true then
    with session_rules as (
      select r.*
      from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
      join lf_ops.reglas r on r.id=rp.regla_id
      where rp.pantalla_id=p_pantalla_id
        and r.codigo='B2B-RULE-AUTH-022'
        and r.estado<>'DEPRECADO'
    ), resolved as (
      select
        r.id as rule_id,
        r.estado as rule_status,
        r.valor_config,
        ps.session_policy_id,
        ps.policy_code,
        ps.scope_code,
        ps.status as policy_status,
        ps.refresh_rotation_enabled,
        ps.cookie_policy
      from session_rules r
      left join lf_ops.politicas_sesion ps
        on coalesce(r.valor_config->>'session_policy_id','') ~ '^[0-9]+$'
       and ps.session_policy_id=(r.valor_config->>'session_policy_id')::bigint
    )
    select
      count(*),
      count(*) filter(where rule_status='CANDIDATO'),
      count(*) filter(where session_policy_id is null),
      count(*) filter(where policy_status in ('CANDIDATO','EN_REVISION')),
      count(*) filter(
        where coalesce(valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      ),
      count(*) filter(
        where session_policy_id is not null
          and policy_code='SESSION-B2B-DEFAULT'
          and scope_code='B2B_APP_SHELL'
          and coalesce(valor_config->>'session_contract_code','')='B2B_AUTH_SESSION_CONTRACT_V1'
          and coalesce(valor_config->>'session_creation_authority','')='SERVER_ONLY'
          and coalesce(valor_config->>'required_auth_outcome','')='AUTHENTICATED'
          and coalesce(valor_config->>'session_before_mfa_completion','')='DENY'
          and coalesce(valor_config->>'token_validation_authority','')='SPRING_BOOT_CORE'
          and coalesce(valor_config->>'token_validation_contract','')='ISSUER_JWKS_CLAIMS'
          and coalesce(valor_config->>'refresh_rotation','')='POLICY_DRIVEN'
          and coalesce(valor_config->>'client_session_parameters_authoritative','')='DENY'
          and coalesce(valor_config->>'browser_session_authority','')='DENY'
          and refresh_rotation_enabled
          and coalesce((cookie_policy->>'secure')::boolean,false)
          and coalesce((cookie_policy->>'http_only')::boolean,false)
          and coalesce(cookie_policy->>'session_storage','')='server_managed'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_broken_ref_count,
      v_unresolved_count_b2b,
      v_missing_source_count,
      v_story_source_count
    from resolved;

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_story_source_count=v_rule_count then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'SESSION_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'NOT_READY' else 'READY' end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','SESSION_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SESSION_POLICY_RESOLUTION_V2',
          'session_contract_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'implementation_pending_count',v_missing_source_count,
          'qualified_contract_count',v_story_source_count,
          'policy_code','SESSION-B2B-DEFAULT',
          'provider_binding','OIDC_PROVIDER_AGNOSTIC'
        )
      );
    end if;

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','SESSION_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','SESSION_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SESSION_POLICY_RESOLUTION_V2',
          'session_contract_rule_count',v_rule_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'qualified_contract_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='SECURITY' and true then
    select
      count(*),
      count(*) filter(where r.estado='CANDIDATO'),
      count(*) filter(
        where coalesce(r.valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='B2B-RULE-SECURITY-BASELINE-001'
      and r.estado<>'DEPRECADO';

    select count(*) into v_broken_ref_count
    from jsonb_array_elements(programacion.fn_input_security_threat_expected(p_pantalla_id)) t
    where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');

    select count(*) into v_unresolved_count_b2b
    from jsonb_array_elements(programacion.fn_input_subject_depth_expected(p_pantalla_id,'SECURITY')) s
    where s->>'status'<>'COMPLETE';

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_unresolved_count_b2b=0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'SECURITY_BASELINE_IMPLEMENTATION_PENDING'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','SECURITY_BASELINE_IMPLEMENTATION_PENDING',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SECURITY_BASELINE_RESOLUTION_V1',
          'baseline_rule_count',v_rule_count,
          'candidate_baseline_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count,
          'threat_incomplete_count',v_broken_ref_count,
          'subject_incomplete_count',v_unresolved_count_b2b
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='TIMEOUT_RETRY' and true then
    with timeout_rules as (
      select r.*
      from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
      join lf_ops.reglas r on r.id=rp.regla_id
      where rp.pantalla_id=p_pantalla_id
        and r.codigo='B2B-RULE-AUTH-016'
        and r.estado<>'DEPRECADO'
    ), resolved as (
      select
        r.id as rule_id,
        r.estado as rule_status,
        r.valor_config,
        p.timeout_policy_id,
        p.policy_code,
        p.operation_code,
        p.retry_limit,
        p.backoff_strategy,
        p.status as policy_status
      from timeout_rules r
      left join lf_ops.politicas_timeout p
        on coalesce(r.valor_config->>'timeout_policy_id','') ~ '^[0-9]+$'
       and p.timeout_policy_id=(r.valor_config->>'timeout_policy_id')::bigint
    )
    select
      count(*),
      count(*) filter(where rule_status='CANDIDATO'),
      count(*) filter(where timeout_policy_id is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
           or coalesce(valor_config->>'policy_assignment_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      ),
      count(*) filter(
        where timeout_policy_id is not null
          and operation_code='AUTH_LOGIN_API'
          and retry_limit=0
          and backoff_strategy='NONE'
          and coalesce(valor_config->>'auth_automatic_retry','')='DENY'
          and coalesce(valor_config->>'session_on_timeout','')='DENY'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_broken_ref_count,
      v_unresolved_count_b2b,
      v_missing_source_count,
      v_story_source_count
    from resolved;

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_story_source_count=v_rule_count then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'NOT_READY' else 'READY' end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2',
          'auth_timeout_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'implementation_pending_count',v_missing_source_count,
          'fail_closed_policy_match_count',v_story_source_count,
          'automatic_retry','DENY'
        )
      );
    end if;

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','TIMEOUT_POLICY_REFERENCE_OR_FAIL_CLOSED_CONTRACT_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','TIMEOUT_POLICY_REFERENCE_OR_FAIL_CLOSED_CONTRACT_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2',
          'auth_timeout_rule_count',v_rule_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'fail_closed_policy_match_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='RATE_LIMIT' then
    with semantic_rules as (
      select
        x.value as rule,
        (x.value->'config'->>'rate_limit_policy_id')::bigint as policy_id
      from jsonb_array_elements(
        coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and coalesce(x.value->'config'->>'rate_limit_policy_id','') ~ '^[0-9]+$'
    ), resolved as (
      select
        s.rule,
        s.policy_id,
        ps.policy_code,
        ps.status as policy_status
      from semantic_rules s
      left join lf_ops.politicas_rate_limit ps
        on ps.rate_limit_policy_id=s.policy_id
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where policy_code is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(rule->>'status','') in ('VIGENTE','ACTIVO')
          and policy_status='VIGENTE'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_story_source_count
    from resolved;

    if v_rule_count>0 then
      if v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','PARTIAL',
          'severity','P1',
          'blocker_code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation','NOT_READY',
            'qa','BLOCKED',
            'production','BLOCKED'
          ),
          'stage_blockers',jsonb_build_array(jsonb_build_object(
            'code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
            'earliest_blocking_stage','IMPLEMENTATION'
          )),
          'probe',jsonb_build_object(
            'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
            'direct_policy_reference_count',v_rule_count,
            'missing_policy_reference_count',v_missing_source_count,
            'candidate_rule_count',v_candidate_count,
            'candidate_policy_count',v_unresolved_count_b2b,
            'vigente_rule_policy_pair_count',v_story_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0
            then 'RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then
            jsonb_build_array(jsonb_build_object(
              'code','RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
          'direct_policy_reference_count',v_rule_count,
          'resolved_policy_reference_count',v_rule_count-v_missing_source_count,
          'missing_policy_reference_count',v_missing_source_count,
          'candidate_rule_count',v_candidate_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'vigente_rule_policy_pair_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='OBSERVABILITY' then
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
    v_base:=programacion.fn_input_runtime_config_existing_authority_probe_v1(p_pantalla_id,p_version_id,p_graph);
    if coalesce((v_base->>'handled')::boolean,false) then return v_base; end if;

    select
      count(*),
      count(*) filter(where r.estado='CANDIDATO'),
      count(*) filter(
        where nullif(r.valor_config->>'provider_registry','') is not null
          and to_regclass(r.valor_config->>'provider_registry') is not null
          and nullif(r.valor_config->>'auth_policy_registry','') is not null
          and to_regclass(r.valor_config->>'auth_policy_registry') is not null
          and jsonb_typeof(r.valor_config->'active_requires')='array'
          and jsonb_array_length(r.valor_config->'active_requires')>0
          and coalesce(r.valor_config->>'secrets_in_rules','')='DENY'
          and coalesce(r.valor_config->>'credentials_in_rules','')='DENY'
      )
    into v_rule_count,v_candidate_count,v_story_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='B2B-RULE-RUNTIME-001'
      and r.estado<>'DEPRECADO';

    select
      count(*),
      count(*) filter(
        where coalesce(r.valor_config->>'provider_binding','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'local_identity_decision','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'identity_contract_status','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'physical_endpoint','') ~* '^(UNDEFINED|UNBOUND|PENDING)'
           or coalesce(r.valor_config->>'oidc_grant','') ~* '^(UNDEFINED|UNBOUND|PENDING)'
           or coalesce(r.valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_unresolved_count_b2b,v_missing_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.estado<>'DEPRECADO'
      and nullif(r.valor_config->>'frontend_runtime','') is not null
      and nullif(r.valor_config->>'backend_runtime','') is not null;

    if v_rule_count>0
       and v_story_source_count=v_rule_count
       and v_unresolved_count_b2b>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'RUNTIME_CONFIG_BINDING_PENDING'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','RUNTIME_CONFIG_BINDING_PENDING',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V3',
          'runtime_contract_rule_count',v_rule_count,
          'candidate_runtime_rule_count',v_candidate_count,
          'resolved_registry_contract_count',v_story_source_count,
          'runtime_boundary_rule_count',v_unresolved_count_b2b,
          'pending_runtime_binding_count',v_missing_source_count,
          'source_authority','SUPABASE_GOVERNED_CANONICAL_RULES'
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='ANALYTICS' then
    with direct_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          upper(coalesce(x.value->>'category',''))='ANALYTICS'
          or jsonb_typeof(x.value->'config'->'providers')='array'
        )
    ), provider_refs as (
      select distinct p.value as provider_code
      from direct_rules d
      cross join lateral jsonb_array_elements_text(
        coalesce(d.rule->'config'->'providers','[]'::jsonb)
      ) p(value)
    ), provider_state as (
      select
        pr.provider_code,
        op.provider_id,
        op.status,
        op.enabled,
        op.integration_status
      from provider_refs pr
      left join lf_ops.observabilidad_proveedores op
        on op.provider_code=pr.provider_code
    ), rel as (
      select *
      from lf_ops.v_b2b_rel_screen_analytics
      where source_code=v_screen_code
    ), event_state as (
      select
        rel.target_code,
        c.event_code,
        c.status,
        c.allowed_parameters
      from rel
      left join lf_ops.v_b2b_analytics_contract c
        on c.event_code=rel.target_code
    )
    select
      (select count(*) from direct_rules),
      (select count(*) from direct_rules where coalesce(rule->>'status','')='CANDIDATO'),
      (select count(*) from rel),
      (select count(*) from event_state where event_code is null
          or jsonb_typeof(allowed_parameters)<>'array'
          or jsonb_array_length(allowed_parameters)=0),
      (select count(*) from provider_state where provider_id is null),
      (
        (select count(*) from provider_state where provider_id is not null)
        +
        (select count(*) from event_state where event_code is not null)
      ),
      exists(
        select 1
        from provider_state
        where provider_id is null
           or status not in ('VIGENTE','ACTIVO')
           or not enabled
           or integration_status not in (
             'ACTIVE','READY','CONFIGURED','IMPLEMENTED','READY_FOR_QA','QA_VERIFIED'
           )
      )
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_broken_ref_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_implementation_pending;

    if v_rule_count>0
       and v_story_source_count>0
       and v_broken_ref_count=0
       and v_missing_source_count=0
       and v_unresolved_count_b2b>=2 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_implementation_pending then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_implementation_pending
            then 'ANALYTICS_RUNTIME_PROVIDER_NOT_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_implementation_pending then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_implementation_pending then
            jsonb_build_array(jsonb_build_object(
              'code','ANALYTICS_RUNTIME_PROVIDER_NOT_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count,
          'resolved_provider_plus_event_count',v_unresolved_count_b2b,
          'runtime_provider_pending',v_implementation_pending
        )
      );
    end if;

    if v_rule_count>0 or v_story_source_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FORCED_COLORS_CONTRAST' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'forced_colors_support','')='REQUIRED'
          and coalesce(x.value->'config'->>'focus_visibility','')='REQUIRED'
          and coalesce(x.value->'config'->>'state_color_only','')='DENY'
          and coalesce(x.value->'config'->>'global_forced_color_adjust_none','')='DENY'
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'forced_colors_support'
        or x.value->'config' ? 'state_color_only'
        or x.value->'config' ? 'global_forced_color_adjust_none'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','FORCED_COLORS_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='REDUCED_MOTION' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'preference','')='prefers-reduced-motion'
          and coalesce(x.value->'config'->>'functional_dependency_on_motion','')='DENY'
          and coalesce(x.value->'config'->>'non_essential_motion_when_reduce','')='REDUCE_OR_REMOVE'
          and coalesce((x.value->'config'->>'status_requires_non_motion_cue')::boolean,false)
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'preference'
        or x.value->'config' ? 'functional_dependency_on_motion'
        or x.value->'config' ? 'non_essential_motion_when_reduce'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','REDUCED_MOTION_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='AUDIT' then
    with semantic_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          x.value->'config' ? 'audit_sink'
          or x.value->'config' ? 'required_audit_actions'
          or x.value->'config' ? 'append_only'
          or x.value->'config' ? 'mutation_blocked'
        )
    ), normalized as (
      select
        rule,
        nullif(coalesce(rule->'config'->>'audit_sink',rule->'config'->>'table'),'') as sink_name,
        case
          when jsonb_typeof(rule->'config'->'required_audit_actions')='array'
            then jsonb_array_length(rule->'config'->'required_audit_actions')
          else 0
        end as action_count,
        (
          coalesce((rule->'config'->>'append_only')::boolean,false)
          or coalesce((rule->'config'->>'mutation_blocked')::boolean,false)
          or coalesce(rule->'config'->>'update_delete','')='DENY'
        ) as immutable_contract,
        (
          coalesce((rule->'config'->>'correlation_id_required')::boolean,false)
          or coalesce((rule->'config'->>'correlation_required')::boolean,false)
        ) as correlation_contract
      from semantic_rules
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where sink_name is not null and to_regclass(sink_name) is not null),
      count(*) filter(where action_count>0),
      count(*) filter(where immutable_contract),
      count(*) filter(where correlation_contract)
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_unresolved_count_b2b,
      v_broken_ref_count,
      v_missing_source_count
    from normalized;

    if v_rule_count>0 then
      if v_story_source_count>0
         and v_unresolved_count_b2b>0
         and v_broken_ref_count>0
         and v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','COMPLETE',
          'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
          'blocker_code',case
            when v_candidate_count>0 then 'AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
            else null
          end,
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
            'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
            'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
          ),
          'stage_blockers',case
            when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
              'code','AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
            else '[]'::jsonb
          end,
          'probe',jsonb_build_object(
            'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
            'semantic_rule_count',v_rule_count,
            'candidate_rule_count',v_candidate_count,
            'resolved_sink_rule_count',v_story_source_count,
            'required_action_contract_count',v_unresolved_count_b2b,
            'immutability_contract_count',v_broken_ref_count,
            'correlation_contract_count',v_missing_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
          'semantic_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'resolved_sink_rule_count',v_story_source_count,
          'required_action_contract_count',v_unresolved_count_b2b,
          'immutability_contract_count',v_broken_ref_count,
          'correlation_contract_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='ACCESSIBILITY' and true then
    select
      count(distinct r.value->>'rule_code'),
      count(*) filter(where coalesce(r.value->>'status','')='CANDIDATO')
    into v_rule_count,v_candidate_count
    from jsonb_array_elements(
      coalesce(p_graph->'canonical_contract'->'rules','[]'::jsonb)
    ) r(value)
    where r.value->>'rule_code' in (
      'B2B-RULE-A11Y-001',
      'B2B-RULE-A11Y-002',
      'B2B-RULE-A11Y-003',
      'B2B-RULE-A11Y-004'
    );

    if v_rule_count=4 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
            'code','ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
            'earliest_blocking_stage','IMPLEMENTATION'
          ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_ACCESSIBILITY_CORE_RESOLUTION_V1',
          'core_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'required_rule_codes',jsonb_build_array(
            'B2B-RULE-A11Y-001',
            'B2B-RULE-A11Y-002',
            'B2B-RULE-A11Y-003',
            'B2B-RULE-A11Y-004'
          )
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FIELDS' then
    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);
    if coalesce((v_field_probe->>'handled')::boolean,false) then return v_field_probe; end if;
    return v_base;
  end if;

  if p_family_code='VALIDATIONS' and true then
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
    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);
    if coalesce((v_field_probe->>'handled')::boolean,false) then return v_field_probe; end if;
    return v_base;
  end if;

  if p_family_code='ROUTING_NAVIGATION' and true then
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

  if p_family_code='TRANSITIONS' and true then
    with s as (select state_id from lf_ops.pantallas_estados where pantalla_id=p_pantalla_id), t as (
      select et.* from lf_ops.estados_transiciones et where et.from_state_id in (select state_id from s)
    )
    select count(*),count(*) filter(where status='CANDIDATO'),count(*) filter(where to_state_id not in (select state_id from s)),count(*) filter(where required_permission_id is not null and not exists(select 1 from lf_ops.permisos p where p.permission_id=t.required_permission_id)),count(*) filter(where source_decision_id is null)
      into v_story_source_count,v_candidate_count,v_unresolved_count_b2b,v_broken_ref_count,v_missing_source_count from t;
    select count(*) into v_rule_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.estado<>'DEPRECADO'
      and not r.pendiente_decision
      and r.valor_config->>'registry'='lf_ops.estados_transiciones'
      and exists(
        select 1
        from lf_ops.estados_transiciones et
        where et.from_state_id in (
          select pe.state_id
          from lf_ops.pantallas_estados pe
          where pe.pantalla_id=p_pantalla_id
        )
          and et.entity_type=r.valor_config->>'entity_type'
      );
    if v_story_source_count>0 and (v_rule_count>0 or v_missing_source_count=0) and v_unresolved_count_b2b=0 and v_broken_ref_count=0 and v_missing_source_count=0 then
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

  if p_family_code='MFA_OTP_SSO' and true then
    select count(*) into v_rule_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and r.estado<>'DEPRECADO' and not r.pendiente_decision
      and (r.valor_config->>'mfa_security_policy_id') ~ '^[0-9]+$' and (r.valor_config->>'session_policy_id') ~ '^[0-9]+$';
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and ps.enforcement_level='REQUIRED' and ps.status<>'DEPRECATED' and jsonb_array_length(coalesce(ps.policy_config->'current_required_profile_ids','[]'::jsonb))>0 and jsonb_array_length(coalesce(ps.policy_config->'unresolved_profile_ids','[]'::jsonb))=0
    ) into v_policy_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_sesion ps on ps.session_policy_id=(r.valor_config->>'session_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and ps.scope_code='B2B_APP_SHELL' and ps.status<>'DEPRECATED' and jsonb_array_length(coalesce(ps.mfa_required_profiles,'[]'::jsonb))>0
    ) into v_session_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint join lf_ops.politicas_seguridad factor on factor.security_policy_id=(ps.policy_config->>'factor_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and factor.status<>'DEPRECATED' and factor.policy_config->>'factor_selection_status'='CLOSED_POLICY_DEFINED' and factor.policy_config->>'coverage_status'='ALL_HUMAN_PROFILES'
    ) into v_factor_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint join lf_ops.politicas_seguridad factor on factor.security_policy_id=(ps.policy_config->>'factor_security_policy_id')::bigint
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

  if true then
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

  v_graph:=p_graph;
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_branch_count
  from direct_vigente_rules d
  where coalesce((d.rule->'config'->>'ask_old_phone_access')::boolean,false)=true
    and nullif(d.rule->'config'->>'old_phone_accessible','') is not null
    and nullif(d.rule->'config'->>'old_phone_unavailable','') is not null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_outcome_count
  from direct_vigente_rules d
  where jsonb_typeof(d.rule->'config'->'allowed_outcomes')='array'
    and jsonb_array_length(d.rule->'config'->'allowed_outcomes')>0
    and jsonb_typeof(d.rule->'config'->'outcomes')='object';

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
      and jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      and jsonb_array_length(r.value->'config'->'allowed_outcomes')>0
      and jsonb_typeof(r.value->'config'->'outcomes')='object'
  ), allowed as (
    select d.rule, a.value as outcome_code
    from direct_vigente_rules d
    cross join lateral jsonb_array_elements_text(d.rule->'config'->'allowed_outcomes') a(value)
  )
  select count(*) into v_outcome_integrity_failures
  from allowed a
  where not (a.rule->'config'->'outcomes' ? a.outcome_code)
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'rebind','') is null
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'operational_access','') is null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_commit_count
  from direct_vigente_rules d
  where d.rule->'config'->>'atomic_commit'='REQUIRED'
    and d.rule->'config'->>'operational_access_before_commit'='DENY'
    and jsonb_typeof(d.rule->'config'->'accepted_recovery_proofs')='array'
    and jsonb_array_length(d.rule->'config'->'accepted_recovery_proofs')>0;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_post_success_count
  from direct_vigente_rules d
  where nullif(d.rule->'config'->>'success_outcome','') is not null
    and nullif(d.rule->'config'->>'post_auth_route','') is not null
    and nullif(d.rule->'config'->>'invalid_session_action','') is not null
    and nullif(d.rule->'config'->>'required_rebind_outcome','') is not null;

  select coalesce(jsonb_agg(distinct r.value->>'rule_code' order by r.value->>'rule_code'),'[]'::jsonb)
    into v_action_rule_codes
  from jsonb_array_elements(v_rules) r(value)
  where r.value->>'status'='VIGENTE'
    and (
      coalesce((r.value->'config'->>'ask_old_phone_access')::boolean,false)=true
      or jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      or r.value->'config'->>'atomic_commit'='REQUIRED'
      or nullif(r.value->'config'->>'success_outcome','') is not null
    );

  if v_branch_count>0
     and v_outcome_count>0
     and v_outcome_integrity_failures=0
     and v_commit_count>0
     and v_post_success_count>0 then
    return jsonb_build_object(
      'handled',true,
      'family_code',p_family_code,
      'level','COMPLETE',
      'blocker_code',null,
      'probe',jsonb_build_object(
        'resolution_contract','STRUCTURED_ACTION_TOPOLOGY_RESOLUTION_V3',
        'branch_contract_count',v_branch_count,
        'outcome_contract_count',v_outcome_count,
        'outcome_integrity_failures',v_outcome_integrity_failures,
        'atomic_commit_contract_count',v_commit_count,
        'post_success_contract_count',v_post_success_count,
        'action_rule_codes',v_action_rule_codes,
        'pending_provider_copy_visual_does_not_authorize_missing_action_dimensions',true
      )
    );
  end if;

  return v_base;
end;
$function$
;

-- fn_input_governance_semantic_probe_v3_ctx md5 58d3ae035dba9c380cbf14fc65edc710
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_semantic_probe_v3_ctx(p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_base jsonb;
  v_field_probe jsonb;
  v_graph jsonb;
  v_rules jsonb;
  v_branch_count integer:=0;
  v_outcome_count integer:=0;
  v_commit_count integer:=0;
  v_post_success_count integer:=0;
  v_outcome_integrity_failures integer:=0;
  v_action_rule_codes jsonb:='[]'::jsonb;
  v_screen_code text;
  v_candidate_count integer:=0;
  v_story_source_count integer:=0;
  v_unresolved_count_b2b integer:=0;
  v_broken_ref_count integer:=0;
  v_missing_source_count integer:=0;
  v_required_editable_count integer:=0;
  v_required_editable_without_validation integer:=0;
  v_validation_count integer:=0;
  v_validation_metadata_missing integer:=0;
  v_rule_count integer:=0;
  v_policy_ok boolean:=false;
  v_session_ok boolean:=false;
  v_factor_ok boolean:=false;
  v_implementation_pending boolean:=false;
  v_family_complete jsonb;
begin
  v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id,p_graph);
  v_family_complete:=programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);
  if coalesce((v_family_complete->>'handled')::boolean,false) then return v_family_complete; end if;


  v_screen_code:=nullif(p_graph->>'screen_code','');

  if p_family_code='SESSION' and true then
    with session_rules as (
      select r.*
      from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
      join lf_ops.reglas r on r.id=rp.regla_id
      where rp.pantalla_id=p_pantalla_id
        and r.codigo='B2B-RULE-AUTH-022'
        and r.estado<>'DEPRECADO'
    ), resolved as (
      select
        r.id as rule_id,
        r.estado as rule_status,
        r.valor_config,
        ps.session_policy_id,
        ps.policy_code,
        ps.scope_code,
        ps.status as policy_status,
        ps.refresh_rotation_enabled,
        ps.cookie_policy
      from session_rules r
      left join lf_ops.politicas_sesion ps
        on coalesce(r.valor_config->>'session_policy_id','') ~ '^[0-9]+$'
       and ps.session_policy_id=(r.valor_config->>'session_policy_id')::bigint
    )
    select
      count(*),
      count(*) filter(where rule_status='CANDIDATO'),
      count(*) filter(where session_policy_id is null),
      count(*) filter(where policy_status in ('CANDIDATO','EN_REVISION')),
      count(*) filter(
        where coalesce(valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      ),
      count(*) filter(
        where session_policy_id is not null
          and policy_code='SESSION-B2B-DEFAULT'
          and scope_code='B2B_APP_SHELL'
          and coalesce(valor_config->>'session_contract_code','')='B2B_AUTH_SESSION_CONTRACT_V1'
          and coalesce(valor_config->>'session_creation_authority','')='SERVER_ONLY'
          and coalesce(valor_config->>'required_auth_outcome','')='AUTHENTICATED'
          and coalesce(valor_config->>'session_before_mfa_completion','')='DENY'
          and coalesce(valor_config->>'token_validation_authority','')='SPRING_BOOT_CORE'
          and coalesce(valor_config->>'token_validation_contract','')='ISSUER_JWKS_CLAIMS'
          and coalesce(valor_config->>'refresh_rotation','')='POLICY_DRIVEN'
          and coalesce(valor_config->>'client_session_parameters_authoritative','')='DENY'
          and coalesce(valor_config->>'browser_session_authority','')='DENY'
          and refresh_rotation_enabled
          and coalesce((cookie_policy->>'secure')::boolean,false)
          and coalesce((cookie_policy->>'http_only')::boolean,false)
          and coalesce(cookie_policy->>'session_storage','')='server_managed'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_broken_ref_count,
      v_unresolved_count_b2b,
      v_missing_source_count,
      v_story_source_count
    from resolved;

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_story_source_count=v_rule_count then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'SESSION_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'NOT_READY' else 'READY' end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','SESSION_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SESSION_POLICY_RESOLUTION_V2',
          'session_contract_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'implementation_pending_count',v_missing_source_count,
          'qualified_contract_count',v_story_source_count,
          'policy_code','SESSION-B2B-DEFAULT',
          'provider_binding','OIDC_PROVIDER_AGNOSTIC'
        )
      );
    end if;

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','SESSION_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','SESSION_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SESSION_POLICY_RESOLUTION_V2',
          'session_contract_rule_count',v_rule_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'qualified_contract_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='SECURITY' and true then
    select
      count(*),
      count(*) filter(where r.estado='CANDIDATO'),
      count(*) filter(
        where coalesce(r.valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='B2B-RULE-SECURITY-BASELINE-001'
      and r.estado<>'DEPRECADO';

    select count(*) into v_broken_ref_count
    from jsonb_array_elements(programacion.fn_input_security_threat_expected(p_pantalla_id)) t
    where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');

    select count(*) into v_unresolved_count_b2b
    from jsonb_array_elements(programacion.fn_input_subject_depth_expected(p_pantalla_id,'SECURITY')) s
    where s->>'status'<>'COMPLETE';

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_unresolved_count_b2b=0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'SECURITY_BASELINE_IMPLEMENTATION_PENDING'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','SECURITY_BASELINE_IMPLEMENTATION_PENDING',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_SECURITY_BASELINE_RESOLUTION_V1',
          'baseline_rule_count',v_rule_count,
          'candidate_baseline_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count,
          'threat_incomplete_count',v_broken_ref_count,
          'subject_incomplete_count',v_unresolved_count_b2b
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='TIMEOUT_RETRY' and true then
    with timeout_rules as (
      select r.*
      from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
      join lf_ops.reglas r on r.id=rp.regla_id
      where rp.pantalla_id=p_pantalla_id
        and r.codigo='B2B-RULE-AUTH-016'
        and r.estado<>'DEPRECADO'
    ), resolved as (
      select
        r.id as rule_id,
        r.estado as rule_status,
        r.valor_config,
        p.timeout_policy_id,
        p.policy_code,
        p.operation_code,
        p.retry_limit,
        p.backoff_strategy,
        p.status as policy_status
      from timeout_rules r
      left join lf_ops.politicas_timeout p
        on coalesce(r.valor_config->>'timeout_policy_id','') ~ '^[0-9]+$'
       and p.timeout_policy_id=(r.valor_config->>'timeout_policy_id')::bigint
    )
    select
      count(*),
      count(*) filter(where rule_status='CANDIDATO'),
      count(*) filter(where timeout_policy_id is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
           or coalesce(valor_config->>'policy_assignment_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      ),
      count(*) filter(
        where timeout_policy_id is not null
          and operation_code='AUTH_LOGIN_API'
          and retry_limit=0
          and backoff_strategy='NONE'
          and coalesce(valor_config->>'auth_automatic_retry','')='DENY'
          and coalesce(valor_config->>'session_on_timeout','')='DENY'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_broken_ref_count,
      v_unresolved_count_b2b,
      v_missing_source_count,
      v_story_source_count
    from resolved;

    if v_rule_count>0
       and v_broken_ref_count=0
       and v_story_source_count=v_rule_count then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
            then 'TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'NOT_READY' else 'READY' end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0
              then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','TIMEOUT_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2',
          'auth_timeout_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'implementation_pending_count',v_missing_source_count,
          'fail_closed_policy_match_count',v_story_source_count,
          'automatic_retry','DENY'
        )
      );
    end if;

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','TIMEOUT_POLICY_REFERENCE_OR_FAIL_CLOSED_CONTRACT_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','TIMEOUT_POLICY_REFERENCE_OR_FAIL_CLOSED_CONTRACT_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','B2B_AUTH_TIMEOUT_POLICY_RESOLUTION_V2',
          'auth_timeout_rule_count',v_rule_count,
          'missing_policy_reference_count',v_broken_ref_count,
          'fail_closed_policy_match_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='RATE_LIMIT' then
    with semantic_rules as (
      select
        x.value as rule,
        (x.value->'config'->>'rate_limit_policy_id')::bigint as policy_id
      from jsonb_array_elements(
        coalesce(
          p_graph
            ->'canonical_contract'->'rules',
          '[]'::jsonb
        )
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and coalesce(x.value->'config'->>'rate_limit_policy_id','') ~ '^[0-9]+$'
    ), resolved as (
      select
        s.rule,
        s.policy_id,
        ps.policy_code,
        ps.status as policy_status
      from semantic_rules s
      left join lf_ops.politicas_rate_limit ps
        on ps.rate_limit_policy_id=s.policy_id
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where policy_code is null),
      count(*) filter(where policy_status='CANDIDATO'),
      count(*) filter(
        where coalesce(rule->>'status','') in ('VIGENTE','ACTIVO')
          and policy_status='VIGENTE'
      )
    into
      v_rule_count,
      v_candidate_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_story_source_count
    from resolved;

    if v_rule_count>0 then
      if v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','PARTIAL',
          'severity','P1',
          'blocker_code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation','NOT_READY',
            'qa','BLOCKED',
            'production','BLOCKED'
          ),
          'stage_blockers',jsonb_build_array(jsonb_build_object(
            'code','RATE_LIMIT_POLICY_REFERENCE_UNRESOLVED',
            'earliest_blocking_stage','IMPLEMENTATION'
          )),
          'probe',jsonb_build_object(
            'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
            'direct_policy_reference_count',v_rule_count,
            'missing_policy_reference_count',v_missing_source_count,
            'candidate_rule_count',v_candidate_count,
            'candidate_policy_count',v_unresolved_count_b2b,
            'vigente_rule_policy_pair_count',v_story_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0
            then 'RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_unresolved_count_b2b>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_unresolved_count_b2b>0 then
            jsonb_build_array(jsonb_build_object(
              'code','RATE_LIMIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RATE_LIMIT_POLICY_RESOLUTION_V1',
          'direct_policy_reference_count',v_rule_count,
          'resolved_policy_reference_count',v_rule_count-v_missing_source_count,
          'missing_policy_reference_count',v_missing_source_count,
          'candidate_rule_count',v_candidate_count,
          'candidate_policy_count',v_unresolved_count_b2b,
          'vigente_rule_policy_pair_count',v_story_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='OBSERVABILITY' then
    v_graph:=p_graph;
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
    v_base:=programacion.fn_input_runtime_config_existing_authority_probe_v1(p_pantalla_id,p_version_id,p_graph);
    if coalesce((v_base->>'handled')::boolean,false) then return v_base; end if;

    select
      count(*),
      count(*) filter(where r.estado='CANDIDATO'),
      count(*) filter(
        where nullif(r.valor_config->>'provider_registry','') is not null
          and to_regclass(r.valor_config->>'provider_registry') is not null
          and nullif(r.valor_config->>'auth_policy_registry','') is not null
          and to_regclass(r.valor_config->>'auth_policy_registry') is not null
          and jsonb_typeof(r.valor_config->'active_requires')='array'
          and jsonb_array_length(r.valor_config->'active_requires')>0
          and coalesce(r.valor_config->>'secrets_in_rules','')='DENY'
          and coalesce(r.valor_config->>'credentials_in_rules','')='DENY'
      )
    into v_rule_count,v_candidate_count,v_story_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.codigo='B2B-RULE-RUNTIME-001'
      and r.estado<>'DEPRECADO';

    select
      count(*),
      count(*) filter(
        where coalesce(r.valor_config->>'provider_binding','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'local_identity_decision','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'identity_contract_status','') ~* '(PENDING|UNDEFINED|NOT_AUTHORIZED)'
           or coalesce(r.valor_config->>'physical_endpoint','') ~* '^(UNDEFINED|UNBOUND|PENDING)'
           or coalesce(r.valor_config->>'oidc_grant','') ~* '^(UNDEFINED|UNBOUND|PENDING)'
           or coalesce(r.valor_config->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_unresolved_count_b2b,v_missing_source_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.estado<>'DEPRECADO'
      and nullif(r.valor_config->>'frontend_runtime','') is not null
      and nullif(r.valor_config->>'backend_runtime','') is not null;

    if v_rule_count>0
       and v_story_source_count=v_rule_count
       and v_unresolved_count_b2b>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_missing_source_count>0 then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'RUNTIME_CONFIG_BINDING_PENDING'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','RUNTIME_CONFIG_BINDING_PENDING',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V3',
          'runtime_contract_rule_count',v_rule_count,
          'candidate_runtime_rule_count',v_candidate_count,
          'resolved_registry_contract_count',v_story_source_count,
          'runtime_boundary_rule_count',v_unresolved_count_b2b,
          'pending_runtime_binding_count',v_missing_source_count,
          'source_authority','SUPABASE_GOVERNED_CANONICAL_RULES'
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='ANALYTICS' then
    with direct_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(
          p_graph
            ->'canonical_contract'->'rules',
          '[]'::jsonb
        )
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          upper(coalesce(x.value->>'category',''))='ANALYTICS'
          or jsonb_typeof(x.value->'config'->'providers')='array'
        )
    ), provider_refs as (
      select distinct p.value as provider_code
      from direct_rules d
      cross join lateral jsonb_array_elements_text(
        coalesce(d.rule->'config'->'providers','[]'::jsonb)
      ) p(value)
    ), provider_state as (
      select
        pr.provider_code,
        op.provider_id,
        op.status,
        op.enabled,
        op.integration_status
      from provider_refs pr
      left join lf_ops.observabilidad_proveedores op
        on op.provider_code=pr.provider_code
    ), rel as (
      select *
      from lf_ops.v_b2b_rel_screen_analytics
      where source_code=v_screen_code
    ), event_state as (
      select
        rel.target_code,
        c.event_code,
        c.status,
        c.allowed_parameters
      from rel
      left join lf_ops.v_b2b_analytics_contract c
        on c.event_code=rel.target_code
    )
    select
      (select count(*) from direct_rules),
      (select count(*) from direct_rules where coalesce(rule->>'status','')='CANDIDATO'),
      (select count(*) from rel),
      (select count(*) from event_state where event_code is null
          or jsonb_typeof(allowed_parameters)<>'array'
          or jsonb_array_length(allowed_parameters)=0),
      (select count(*) from provider_state where provider_id is null),
      (
        (select count(*) from provider_state where provider_id is not null)
        +
        (select count(*) from event_state where event_code is not null)
      ),
      exists(
        select 1
        from provider_state
        where provider_id is null
           or status not in ('VIGENTE','ACTIVO')
           or not enabled
           or integration_status not in (
             'ACTIVE','READY','CONFIGURED','IMPLEMENTED','READY_FOR_QA','QA_VERIFIED'
           )
      )
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_broken_ref_count,
      v_missing_source_count,
      v_unresolved_count_b2b,
      v_implementation_pending;

    if v_rule_count>0
       and v_story_source_count>0
       and v_broken_ref_count=0
       and v_missing_source_count=0
       and v_unresolved_count_b2b>=2 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case
          when v_candidate_count>0 or v_implementation_pending then 'P1'
          else 'P4'
        end,
        'blocker_code',case
          when v_candidate_count>0 or v_implementation_pending
            then 'ANALYTICS_RUNTIME_PROVIDER_NOT_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case
            when v_candidate_count>0 or v_implementation_pending then 'NOT_READY'
            else 'READY'
          end,
          'qa',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end,
          'production',case
            when v_candidate_count>0 or v_implementation_pending then 'BLOCKED'
            else 'READY'
          end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_implementation_pending then
            jsonb_build_array(jsonb_build_object(
              'code','ANALYTICS_RUNTIME_PROVIDER_NOT_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count,
          'resolved_provider_plus_event_count',v_unresolved_count_b2b,
          'runtime_provider_pending',v_implementation_pending
        )
      );
    end if;

    if v_rule_count>0 or v_story_source_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','ANALYTICS_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','ANALYTICS_SEMANTIC_RESOLUTION_V1',
          'analytics_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'screen_event_relation_count',v_story_source_count,
          'broken_or_incomplete_event_count',v_broken_ref_count,
          'missing_provider_reference_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FORCED_COLORS_CONTRAST' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'forced_colors_support','')='REQUIRED'
          and coalesce(x.value->'config'->>'focus_visibility','')='REQUIRED'
          and coalesce(x.value->'config'->>'state_color_only','')='DENY'
          and coalesce(x.value->'config'->>'global_forced_color_adjust_none','')='DENY'
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(
        p_graph
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'forced_colors_support'
        or x.value->'config' ? 'state_color_only'
        or x.value->'config' ? 'global_forced_color_adjust_none'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','FORCED_COLORS_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','FORCED_COLORS_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='REDUCED_MOTION' then
    select
      count(*) filter(
        where coalesce(x.value->'config'->>'preference','')='prefers-reduced-motion'
          and coalesce(x.value->'config'->>'functional_dependency_on_motion','')='DENY'
          and coalesce(x.value->'config'->>'non_essential_motion_when_reduce','')='REDUCE_OR_REMOVE'
          and coalesce((x.value->'config'->>'status_requires_non_motion_cue')::boolean,false)
      ),
      count(*) filter(where coalesce(x.value->>'status','')='CANDIDATO'),
      count(*) filter(
        where coalesce(x.value->'config'->>'implementation_status','') ~* '(PENDING|NOT_READY|BLOCKED)'
      )
    into v_rule_count,v_candidate_count,v_missing_source_count
    from jsonb_array_elements(
      coalesce(
        p_graph
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) x(value)
    where coalesce(x.value->>'status','')<>'DEPRECADO'
      and (
        x.value->'config' ? 'preference'
        or x.value->'config' ? 'functional_dependency_on_motion'
        or x.value->'config' ? 'non_essential_motion_when_reduce'
      );

    if v_rule_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 or v_missing_source_count>0 then 'P1' else 'P4' end,
        'blocker_code',case
          when v_candidate_count>0 or v_missing_source_count>0
            then 'REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
          else null
        end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 or v_missing_source_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 or v_missing_source_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 or v_missing_source_count>0 then
            jsonb_build_array(jsonb_build_object(
              'code','REDUCED_MOTION_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','REDUCED_MOTION_SEMANTIC_RESOLUTION_V1',
          'qualified_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'implementation_pending_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='AUDIT' then
    with semantic_rules as (
      select x.value as rule
      from jsonb_array_elements(
        coalesce(
          p_graph
            ->'canonical_contract'->'rules',
          '[]'::jsonb
        )
      ) x(value)
      where coalesce(x.value->>'status','')<>'DEPRECADO'
        and (
          x.value->'config' ? 'audit_sink'
          or x.value->'config' ? 'required_audit_actions'
          or x.value->'config' ? 'append_only'
          or x.value->'config' ? 'mutation_blocked'
        )
    ), normalized as (
      select
        rule,
        nullif(coalesce(rule->'config'->>'audit_sink',rule->'config'->>'table'),'') as sink_name,
        case
          when jsonb_typeof(rule->'config'->'required_audit_actions')='array'
            then jsonb_array_length(rule->'config'->'required_audit_actions')
          else 0
        end as action_count,
        (
          coalesce((rule->'config'->>'append_only')::boolean,false)
          or coalesce((rule->'config'->>'mutation_blocked')::boolean,false)
          or coalesce(rule->'config'->>'update_delete','')='DENY'
        ) as immutable_contract,
        (
          coalesce((rule->'config'->>'correlation_id_required')::boolean,false)
          or coalesce((rule->'config'->>'correlation_required')::boolean,false)
        ) as correlation_contract
      from semantic_rules
    )
    select
      count(*),
      count(*) filter(where coalesce(rule->>'status','')='CANDIDATO'),
      count(*) filter(where sink_name is not null and to_regclass(sink_name) is not null),
      count(*) filter(where action_count>0),
      count(*) filter(where immutable_contract),
      count(*) filter(where correlation_contract)
    into
      v_rule_count,
      v_candidate_count,
      v_story_source_count,
      v_unresolved_count_b2b,
      v_broken_ref_count,
      v_missing_source_count
    from normalized;

    if v_rule_count>0 then
      if v_story_source_count>0
         and v_unresolved_count_b2b>0
         and v_broken_ref_count>0
         and v_missing_source_count>0 then
        return jsonb_build_object(
          'handled',true,
          'family_code',p_family_code,
          'level','COMPLETE',
          'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
          'blocker_code',case
            when v_candidate_count>0 then 'AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY'
            else null
          end,
          'stage_statuses',jsonb_build_object(
            'story','READY',
            'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
            'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
            'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
          ),
          'stage_blockers',case
            when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
              'code','AUDIT_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
              'earliest_blocking_stage','IMPLEMENTATION'
            ))
            else '[]'::jsonb
          end,
          'probe',jsonb_build_object(
            'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
            'semantic_rule_count',v_rule_count,
            'candidate_rule_count',v_candidate_count,
            'resolved_sink_rule_count',v_story_source_count,
            'required_action_contract_count',v_unresolved_count_b2b,
            'immutability_contract_count',v_broken_ref_count,
            'correlation_contract_count',v_missing_source_count
          )
        );
      end if;

      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','PARTIAL',
        'severity','P1',
        'blocker_code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
        'stage_statuses',jsonb_build_object(
          'story','READY','implementation','NOT_READY','qa','BLOCKED','production','BLOCKED'
        ),
        'stage_blockers',jsonb_build_array(jsonb_build_object(
          'code','AUDIT_CANONICAL_SOURCE_INCOMPLETE',
          'earliest_blocking_stage','IMPLEMENTATION'
        )),
        'probe',jsonb_build_object(
          'resolution_contract','AUDIT_SEMANTIC_RESOLUTION_V1',
          'semantic_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'resolved_sink_rule_count',v_story_source_count,
          'required_action_contract_count',v_unresolved_count_b2b,
          'immutability_contract_count',v_broken_ref_count,
          'correlation_contract_count',v_missing_source_count
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='ACCESSIBILITY' and true then
    select
      count(distinct r.value->>'rule_code'),
      count(*) filter(where coalesce(r.value->>'status','')='CANDIDATO')
    into v_rule_count,v_candidate_count
    from jsonb_array_elements(
      coalesce(
        p_graph
          ->'canonical_contract'->'rules',
        '[]'::jsonb
      )
    ) r(value)
    where r.value->>'rule_code' in (
      'B2B-RULE-A11Y-001',
      'B2B-RULE-A11Y-002',
      'B2B-RULE-A11Y-003',
      'B2B-RULE-A11Y-004'
    );

    if v_rule_count=4 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'severity',case when v_candidate_count>0 then 'P1' else 'P4' end,
        'blocker_code',case when v_candidate_count>0 then 'ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY' else null end,
        'stage_statuses',jsonb_build_object(
          'story','READY',
          'implementation',case when v_candidate_count>0 then 'NOT_READY' else 'READY' end,
          'qa',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end,
          'production',case when v_candidate_count>0 then 'BLOCKED' else 'READY' end
        ),
        'stage_blockers',case
          when v_candidate_count>0 then jsonb_build_array(jsonb_build_object(
            'code','ACCESSIBILITY_SOURCE_CANDIDATE_NOT_IMPLEMENTATION_READY',
            'earliest_blocking_stage','IMPLEMENTATION'
          ))
          else '[]'::jsonb
        end,
        'probe',jsonb_build_object(
          'resolution_contract','B2B_ACCESSIBILITY_CORE_RESOLUTION_V1',
          'core_rule_count',v_rule_count,
          'candidate_rule_count',v_candidate_count,
          'required_rule_codes',jsonb_build_array(
            'B2B-RULE-A11Y-001',
            'B2B-RULE-A11Y-002',
            'B2B-RULE-A11Y-003',
            'B2B-RULE-A11Y-004'
          )
        )
      );
    end if;

    return v_base;
  end if;

  if p_family_code='FIELDS' then
    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);
    if coalesce((v_field_probe->>'handled')::boolean,false) then return v_field_probe; end if;
    return v_base;
  end if;

  if p_family_code='VALIDATIONS' and true then
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
    v_field_probe:=programacion.fn_input_governance_field_reference_probe_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);
    if coalesce((v_field_probe->>'handled')::boolean,false) then return v_field_probe; end if;
    return v_base;
  end if;

  if p_family_code='ROUTING_NAVIGATION' and true then
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

  if p_family_code='TRANSITIONS' and true then
    with s as (select state_id from lf_ops.pantallas_estados where pantalla_id=p_pantalla_id), t as (
      select et.* from lf_ops.estados_transiciones et where et.from_state_id in (select state_id from s)
    )
    select count(*),count(*) filter(where status='CANDIDATO'),count(*) filter(where to_state_id not in (select state_id from s)),count(*) filter(where required_permission_id is not null and not exists(select 1 from lf_ops.permisos p where p.permission_id=t.required_permission_id)),count(*) filter(where source_decision_id is null)
      into v_story_source_count,v_candidate_count,v_unresolved_count_b2b,v_broken_ref_count,v_missing_source_count from t;
    select count(*) into v_rule_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and r.estado<>'DEPRECADO'
      and not r.pendiente_decision
      and r.valor_config->>'registry'='lf_ops.estados_transiciones'
      and exists(
        select 1
        from lf_ops.estados_transiciones et
        where et.from_state_id in (
          select pe.state_id
          from lf_ops.pantallas_estados pe
          where pe.pantalla_id=p_pantalla_id
        )
          and et.entity_type=r.valor_config->>'entity_type'
      );
    if v_story_source_count>0 and (v_rule_count>0 or v_missing_source_count=0) and v_unresolved_count_b2b=0 and v_broken_ref_count=0 and v_missing_source_count=0 then
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

  if p_family_code='MFA_OTP_SSO' and true then
    select count(*) into v_rule_count
    from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and r.estado<>'DEPRECADO' and not r.pendiente_decision
      and (r.valor_config->>'mfa_security_policy_id') ~ '^[0-9]+$' and (r.valor_config->>'session_policy_id') ~ '^[0-9]+$';
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and ps.enforcement_level='REQUIRED' and ps.status<>'DEPRECATED' and jsonb_array_length(coalesce(ps.policy_config->'current_required_profile_ids','[]'::jsonb))>0 and jsonb_array_length(coalesce(ps.policy_config->'unresolved_profile_ids','[]'::jsonb))=0
    ) into v_policy_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_sesion ps on ps.session_policy_id=(r.valor_config->>'session_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and ps.scope_code='B2B_APP_SHELL' and ps.status<>'DEPRECATED' and jsonb_array_length(coalesce(ps.mfa_required_profiles,'[]'::jsonb))>0
    ) into v_session_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint join lf_ops.politicas_seguridad factor on factor.security_policy_id=(ps.policy_config->>'factor_security_policy_id')::bigint
      where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-AUTH-003' and factor.status<>'DEPRECATED' and factor.policy_config->>'factor_selection_status'='CLOSED_POLICY_DEFINED' and factor.policy_config->>'coverage_status'='ALL_HUMAN_PROFILES'
    ) into v_factor_ok;
    select exists(
      select 1 from programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp join lf_ops.reglas r on r.id=rp.regla_id join lf_ops.politicas_seguridad ps on ps.security_policy_id=(r.valor_config->>'mfa_security_policy_id')::bigint join lf_ops.politicas_seguridad factor on factor.security_policy_id=(ps.policy_config->>'factor_security_policy_id')::bigint
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

  if true then
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

  v_graph:=p_graph;
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_branch_count
  from direct_vigente_rules d
  where coalesce((d.rule->'config'->>'ask_old_phone_access')::boolean,false)=true
    and nullif(d.rule->'config'->>'old_phone_accessible','') is not null
    and nullif(d.rule->'config'->>'old_phone_unavailable','') is not null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_outcome_count
  from direct_vigente_rules d
  where jsonb_typeof(d.rule->'config'->'allowed_outcomes')='array'
    and jsonb_array_length(d.rule->'config'->'allowed_outcomes')>0
    and jsonb_typeof(d.rule->'config'->'outcomes')='object';

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
      and jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      and jsonb_array_length(r.value->'config'->'allowed_outcomes')>0
      and jsonb_typeof(r.value->'config'->'outcomes')='object'
  ), allowed as (
    select d.rule, a.value as outcome_code
    from direct_vigente_rules d
    cross join lateral jsonb_array_elements_text(d.rule->'config'->'allowed_outcomes') a(value)
  )
  select count(*) into v_outcome_integrity_failures
  from allowed a
  where not (a.rule->'config'->'outcomes' ? a.outcome_code)
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'rebind','') is null
     or nullif(a.rule->'config'->'outcomes'->a.outcome_code->>'operational_access','') is null;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_commit_count
  from direct_vigente_rules d
  where d.rule->'config'->>'atomic_commit'='REQUIRED'
    and d.rule->'config'->>'operational_access_before_commit'='DENY'
    and jsonb_typeof(d.rule->'config'->'accepted_recovery_proofs')='array'
    and jsonb_array_length(d.rule->'config'->'accepted_recovery_proofs')>0;

  with direct_vigente_rules as (
    select r.value as rule
    from jsonb_array_elements(v_rules) r(value)
    where r.value->>'status'='VIGENTE'
  )
  select count(*) into v_post_success_count
  from direct_vigente_rules d
  where nullif(d.rule->'config'->>'success_outcome','') is not null
    and nullif(d.rule->'config'->>'post_auth_route','') is not null
    and nullif(d.rule->'config'->>'invalid_session_action','') is not null
    and nullif(d.rule->'config'->>'required_rebind_outcome','') is not null;

  select coalesce(jsonb_agg(distinct r.value->>'rule_code' order by r.value->>'rule_code'),'[]'::jsonb)
    into v_action_rule_codes
  from jsonb_array_elements(v_rules) r(value)
  where r.value->>'status'='VIGENTE'
    and (
      coalesce((r.value->'config'->>'ask_old_phone_access')::boolean,false)=true
      or jsonb_typeof(r.value->'config'->'allowed_outcomes')='array'
      or r.value->'config'->>'atomic_commit'='REQUIRED'
      or nullif(r.value->'config'->>'success_outcome','') is not null
    );

  if v_branch_count>0
     and v_outcome_count>0
     and v_outcome_integrity_failures=0
     and v_commit_count>0
     and v_post_success_count>0 then
    return jsonb_build_object(
      'handled',true,
      'family_code',p_family_code,
      'level','COMPLETE',
      'blocker_code',null,
      'probe',jsonb_build_object(
        'resolution_contract','STRUCTURED_ACTION_TOPOLOGY_RESOLUTION_V3',
        'branch_contract_count',v_branch_count,
        'outcome_contract_count',v_outcome_count,
        'outcome_integrity_failures',v_outcome_integrity_failures,
        'atomic_commit_contract_count',v_commit_count,
        'post_success_contract_count',v_post_success_count,
        'action_rule_codes',v_action_rule_codes,
        'pending_provider_copy_visual_does_not_authorize_missing_action_dimensions',true
      )
    );
  end if;

  return v_base;
end;
$function$
;
