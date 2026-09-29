-- B2B-AUTH-001 provider-agnostic session contract readiness v1
-- Replaces the Client-specific SQL session-context assumption with a governed
-- B2B session contract backed by lf_ops.politicas_sesion.
-- The policy/rule remain CANDIDATO, so Implementation stays NOT_READY.

begin;

do $preflight$
declare
  v_rule jsonb;
  v_policy record;
begin
  select valor_config into v_rule
  from lf_ops.reglas
  where codigo='B2B-RULE-AUTH-022';

  if v_rule is null then
    raise exception 'B2B_RULE_AUTH_022_MISSING';
  end if;

  if coalesce(v_rule->>'session_policy_id','')<>'1'
     or coalesce(v_rule->>'session_creation_authority','')<>'SERVER_ONLY'
     or coalesce(v_rule->>'session_before_mfa_completion','')<>'DENY' then
    raise exception 'B2B_RULE_AUTH_022_SESSION_CONTRACT_DRIFT:%',v_rule;
  end if;

  select * into v_policy
  from lf_ops.politicas_sesion
  where session_policy_id=1;

  if v_policy.session_policy_id is null
     or v_policy.policy_code<>'SESSION-B2B-DEFAULT'
     or v_policy.scope_code<>'B2B_APP_SHELL' then
    raise exception 'B2B_SESSION_POLICY_DRIFT:%',row_to_json(v_policy);
  end if;

  if v_policy.status not in ('CANDIDATO','EN_REVISION') then
    raise exception 'B2B_SESSION_POLICY_UNEXPECTED_STATUS:%',v_policy.status;
  end if;
end;
$preflight$;

update lf_ops.reglas
set valor_config=
      (coalesce(valor_config,'{}'::jsonb)
        - 'application_repository'
        - 'application_head_observed')
      || jsonb_build_object(
        'session_contract_code','B2B_AUTH_SESSION_CONTRACT_V1',
        'session_policy_id',1,
        'session_policy_registry','lf_ops.politicas_sesion',
        'session_creation_authority','SERVER_ONLY',
        'required_auth_outcome','AUTHENTICATED',
        'session_before_mfa_completion','DENY',
        'token_validation_authority','SPRING_BOOT_CORE',
        'token_validation_contract','ISSUER_JWKS_CLAIMS',
        'refresh_rotation','POLICY_DRIVEN',
        'client_session_parameters_authoritative','DENY',
        'browser_session_authority','DENY',
        'provider_binding','OIDC_PROVIDER_AGNOSTIC',
        'identity_protocol','OIDC_JWT',
        'aws_identity_target','AMAZON_COGNITO',
        'implementation_status','PENDING_IMPLEMENTATION_QA',
        'production_authorized',false,
        'source_authority','SUPABASE_GOVERNED_CANONICAL_POLICY'
      ),
    updated_at=now()
where codigo='B2B-RULE-AUTH-022';

do $patch$
declare
  r record;
  v_def text;
  v_anchor text := $$  if p_family_code='SECURITY' and v_screen_code like 'B2B-%' then$$;
  v_insert text :=
$$  if p_family_code='SESSION' and v_screen_code like 'B2B-%' then
    with session_rules as (
      select r.*
      from lf_ops.reglas_pantallas rp
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

  if p_family_code='SECURITY' and v_screen_code like 'B2B-%' then$$;
begin
  for r in
    select sig
    from (
      values
        ('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'),
        ('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)')
    ) x(sig)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;

    if v_def is null then
      raise exception 'B2B_SESSION_READINESS_SEMANTIC_FUNCTION_MISSING:%',r.sig;
    end if;

    if position('B2B_SESSION_POLICY_RESOLUTION_V2' in v_def)=0 then
      if position(v_anchor in v_def)=0 then
        raise exception 'B2B_SESSION_READINESS_SEMANTIC_SOURCE_DRIFT:%',r.sig;
      end if;
      v_def:=replace(v_def,v_anchor,v_insert);
      execute v_def;
    end if;
  end loop;
end;
$patch$;

do $postconditions$
declare
  v_session jsonb;
  v_rule jsonb;
begin
  select valor_config into v_rule
  from lf_ops.reglas
  where codigo='B2B-RULE-AUTH-022';

  if v_rule->>'session_contract_code'<>'B2B_AUTH_SESSION_CONTRACT_V1'
     or v_rule->>'session_policy_id'<>'1'
     or v_rule ? 'application_repository'
     or v_rule ? 'application_head_observed' then
    raise exception 'B2B_SESSION_RULE_POSTCONDITION_FAILED:%',v_rule;
  end if;

  v_session:=programacion.fn_input_governance_bootstrap_classify_v2(51,'SESSION',19);

  if v_session->>'coverage_status'<>'COMPLETE'
     or v_session->>'well_defined_status'<>'COMPLETE'
     or v_session->>'story_ready_status'<>'READY'
     or v_session->>'implementation_ready_status'<>'NOT_READY'
     or v_session->'blockers'->0->>'code'<>'SESSION_POLICY_CANDIDATE_NOT_IMPLEMENTATION_READY'
     or v_session#>>'{probe,resolution_contract}'<>'B2B_SESSION_POLICY_RESOLUTION_V2' then
    raise exception 'B2B_SESSION_CLASSIFIER_POSTCONDITION_FAILED:%',v_session;
  end if;
end;
$postconditions$;

commit;
