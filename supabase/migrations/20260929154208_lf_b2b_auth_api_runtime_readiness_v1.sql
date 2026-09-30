-- B2B-AUTH-001 API_DATA_CONTRACT + RUNTIME_CONFIG readiness v1
-- Sources of truth: governed Supabase definitions + canonical Git migrations.
-- No application repository/head is used as implementation authority.
--
-- API: materialize a provider-agnostic logical boundary contract without selecting
-- endpoint, HTTP method, OIDC grant, local IdP, or production binding.
-- RUNTIME_CONFIG: separate structural completeness from pending runtime/provider binding.

begin;

do $preflight$
declare
  v_email record;
  v_password record;
  v_auth015 jsonb;
begin
  select c.id,c.codigo,c.tipo_dato,c.es_sensible,c.logs_allowed,c.analytics_allowed,c.estado
    into v_email
  from lf_ops.campos c
  join lf_ops.campos_pantallas cp on cp.campo_id=c.id
  where cp.pantalla_id=51 and c.id=298 and c.codigo='B2B_FLD_LOGIN_EMAIL';

  select c.id,c.codigo,c.tipo_dato,c.es_sensible,c.logs_allowed,c.analytics_allowed,c.estado
    into v_password
  from lf_ops.campos c
  join lf_ops.campos_pantallas cp on cp.campo_id=c.id
  where cp.pantalla_id=51 and c.id=296 and c.codigo='B2B_FLD_LOGIN_PASSWORD';

  if v_email.id is null
     or v_email.tipo_dato<>'email'
     or not v_email.es_sensible
     or coalesce(v_email.logs_allowed,true)
     or coalesce(v_email.analytics_allowed,true) then
    raise exception 'B2B_AUTH_EMAIL_FIELD_AUTHORITY_DRIFT:%',row_to_json(v_email);
  end if;

  if v_password.id is null
     or v_password.tipo_dato<>'password'
     or not v_password.es_sensible
     or coalesce(v_password.logs_allowed,true)
     or coalesce(v_password.analytics_allowed,true) then
    raise exception 'B2B_AUTH_PASSWORD_FIELD_AUTHORITY_DRIFT:%',row_to_json(v_password);
  end if;

  select valor_config into v_auth015
  from lf_ops.reglas
  where codigo='B2B-RULE-AUTH-015';

  if v_auth015 is null then
    raise exception 'B2B_RULE_AUTH_015_MISSING';
  end if;

  if coalesce(v_auth015->>'physical_endpoint','') not in ('UNDEFINED','UNBOUND')
     or coalesce(v_auth015->>'oidc_grant','') not in ('UNDEFINED','UNBOUND')
     or coalesce(v_auth015->>'identity_exchange_status','')<>'UNBOUND_FAIL_CLOSED'
     or coalesce(v_auth015->>'credentials_in_url','')<>'DENY'
     or coalesce(v_auth015->>'credentials_in_query_string','')<>'DENY' then
    raise exception 'B2B_RULE_AUTH_015_EXECUTABLE_BINDING_DRIFT:%',v_auth015;
  end if;

  if not exists (
    select 1
    from lf_ops.reglas
    where codigo='B2B-RULE-RUNTIME-001'
      and estado<>'DEPRECADO'
      and valor_config->>'provider_registry'='lf_ops.observabilidad_proveedores'
      and valor_config->>'auth_policy_registry'='lf_ops.politicas_seguridad'
      and valor_config->>'secrets_in_rules'='DENY'
      and valor_config->>'credentials_in_rules'='DENY'
  ) then
    raise exception 'B2B_RUNTIME_CONTRACT_RULE_DRIFT';
  end if;
end;
$preflight$;

-- Current B2B rules no longer use an application repository/head as authority.
update lf_ops.reglas
set valor_config=coalesce(valor_config,'{}'::jsonb)
      - 'application_repository'
      - 'application_head_observed',
    updated_at=now()
where codigo like 'B2B-RULE-AUTH-%'
  and estado<>'DEPRECADO'
  and (
    valor_config ? 'application_repository'
    or valor_config ? 'application_head_observed'
  );

-- Materialize a logical LF_AUTH_BOUNDARY contract. This is intentionally not an
-- executable identity/provider binding.
do $logical_contract$
declare
  v_contract_id bigint;
  v_existing programacion.contratos%rowtype;
  v_spec jsonb;
begin
  v_spec:=jsonb_build_object(
    'schema_version',1,
    'contract_revision','1.0-logical',
    'screen_code','B2B-AUTH-001',
    'action_code','SUBMIT_LOGIN',
    'operation_code','B2B_AUTH_LOGIN_SUBMIT',
    'contract_scope','LOGICAL_PROVIDER_AGNOSTIC',
    'logical_contract_only',true,
    'consumer_contract','LF_AUTH_BOUNDARY',
    'frontend_runtime','NEXTJS_STATIC_EXPORT',
    'backend_runtime','SPRING_BOOT_CORE',
    'identity_protocol','OIDC_JWT',
    'aws_identity_target','AMAZON_COGNITO',
    'request_schema',jsonb_build_object(
      'type','object',
      'required',jsonb_build_array('email','password'),
      'properties',jsonb_build_object(
        'email',jsonb_build_object(
          'type','string',
          'format','email',
          'source_field_id',298,
          'source_field_code','B2B_FLD_LOGIN_EMAIL',
          'trim_external',true,
          'logs_allowed',false,
          'analytics_allowed',false
        ),
        'password',jsonb_build_object(
          'type','string',
          'format','password',
          'source_field_id',296,
          'source_field_code','B2B_FLD_LOGIN_PASSWORD',
          'trim','DENY',
          'normalization','DENY',
          'case_transform','DENY',
          'logs_allowed',false,
          'analytics_allowed',false
        )
      ),
      'additional_properties',false
    ),
    'response_schema',jsonb_build_object(
      'type','object',
      'required',jsonb_build_array('outcome','correlation_id'),
      'properties',jsonb_build_object(
        'outcome',jsonb_build_object(
          'type','string',
          'enum',jsonb_build_array(
            'AUTHENTICATED',
            'MFA_REQUIRED',
            'INVALID_CREDENTIALS',
            'RATE_LIMITED',
            'ACCESS_DENIED',
            'SERVICE_UNAVAILABLE'
          )
        ),
        'correlation_id',jsonb_build_object(
          'type','string',
          'authority','SERVER_GENERATED'
        ),
        'error_id',jsonb_build_object(
          'type',jsonb_build_array('integer','null'),
          'authority','lf_ops.errores_catalogo.error_id'
        )
      )
    ),
    'response_rules',jsonb_build_object(
      'credential_echo','DENY',
      'internal_token_exposure','DENY',
      'provider_payload_exposure','DENY',
      'provider_error_code_exposure','DENY',
      'session_creation_outcome','AUTHENTICATED',
      'session_before_mfa_completion','DENY',
      'error_catalog','lf_ops.errores_catalogo'
    ),
    'physical_binding',jsonb_build_object(
      'endpoint','UNBOUND',
      'http_method','UNBOUND',
      'oidc_grant','UNBOUND',
      'identity_provider','PENDING_IDENTITY_BINDING'
    ),
    'runtime_activation',false,
    'implementation_status','PENDING_IDENTITY_BINDING_QA',
    'promotion_authorized',false,
    'production_authorized',false,
    'source_authority','SUPABASE_GOVERNED_CANONICAL_RULES',
    'source_rule_codes',jsonb_build_array(
      'B2B-RULE-AUTH-013',
      'B2B-RULE-AUTH-015',
      'B2B-RULE-AUTH-017',
      'B2B-RULE-AUTH-018',
      'B2B-RULE-AUTH-021',
      'B2B-RULE-AUTH-022',
      'B2B-RULE-AUTH-036',
      'B2B-RULE-AUTH-048'
    )
  );

  select * into v_existing
  from programacion.contratos
  where version_id=19
    and contrato_codigo='B2B_AUTH_LOGIN_LOGICAL_BOUNDARY_CONTRACT';

  if found then
    if v_existing.tipo<>'LOGICAL_INTERFACE'
       or v_existing.estado<>'defined'
       or v_existing.fail_closed is distinct from true
       or coalesce((v_existing.especificacion->>'logical_contract_only')::boolean,false) is not true
       or coalesce((v_existing.especificacion->>'runtime_activation')::boolean,true) is not false
       or v_existing.especificacion->>'screen_code'<>'B2B-AUTH-001'
       or v_existing.especificacion->>'operation_code'<>'B2B_AUTH_LOGIN_SUBMIT' then
      raise exception 'B2B_LOGICAL_API_CONTRACT_SOURCE_DRIFT:%',to_jsonb(v_existing);
    end if;
    v_contract_id:=v_existing.id;
  else
    insert into programacion.contratos(
      version_id,contrato_codigo,tipo,nombre,descripcion,
      productor_componente_id,consumidor_componente_id,
      especificacion,fail_closed,estado
    ) values (
      19,
      'B2B_AUTH_LOGIN_LOGICAL_BOUNDARY_CONTRACT',
      'LOGICAL_INTERFACE',
      'B2B Login logical LF auth boundary contract',
      'Contrato lógico provider-agnostic de SUBMIT_LOGIN. Define datos y outcomes canónicos sin seleccionar endpoint, método, grant OIDC, proveedor local ni binding productivo.',
      null,
      null,
      v_spec,
      true,
      'defined'
    )
    returning id into v_contract_id;
  end if;

  update lf_ops.reglas
  set valor_config=(
        coalesce(valor_config,'{}'::jsonb)
        - 'application_repository'
        - 'application_head_observed'
      ) || jsonb_build_object(
        'api_contract_id',v_contract_id,
        'logical_contract_code','B2B_AUTH_LOGIN_LOGICAL_BOUNDARY_CONTRACT',
        'logical_contract_scope','LOGICAL_PROVIDER_AGNOSTIC',
        'source_authority','SUPABASE_GOVERNED_CANONICAL_RULES',
        'implementation_status','PENDING_IDENTITY_BINDING_QA',
        'production_authorized',false
      ),
      updated_at=now()
  where codigo='B2B-RULE-AUTH-015';
end;
$logical_contract$;

-- Enhanced API contract resolution: a logical schema may be complete while an
-- executable binding is still absent.
create or replace function programacion.fn_input_api_contract_resolution(
  p_pantalla_id integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_rules jsonb := '[]'::jsonb;
  v_behavior_count integer := 0;
  v_materialized_count integer := 0;
  v_broken_count integer := 0;
  v_defined_fail_closed_count integer := 0;
  v_logical_count integer := 0;
  v_executable_count integer := 0;
  v_refs jsonb := '[]'::jsonb;
begin
  with rr as (
    select r.id,r.codigo,r.titulo,r.descripcion,r.valor_config,
           r.pendiente_decision,r.pendiente_detalle,r.estado
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=p_pantalla_id
      and (
        r.valor_config ?| array[
          'gateway','method','provider_operation_alias','consumer_contract',
          'required_logical_inputs','required_fields','server_side_generation',
          'server_side_verification','provider_binding','api_contract_id',
          'operation_contract_id','request_schema_contract_id','response_schema_contract_id'
        ]
        or r.descripcion ilike '%API_GATEWAY%'
        or r.valor_config::text ilike '%operation_alias%'
      )
  )
  select count(*),coalesce(jsonb_agg(jsonb_build_object(
    'rule_id',id,'rule_code',codigo,'title',titulo,'description',descripcion,
    'config',valor_config,'pending_decision',pendiente_decision,
    'pending_detail',pendiente_detalle,'status',estado
  ) order by codigo),'[]'::jsonb)
  into v_behavior_count,v_rules
  from rr;

  with candidate_refs as (
    select r.codigo rule_code,e.key ref_key,e.value ref_value
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    where rp.pantalla_id=p_pantalla_id
      and e.key in (
        'api_contract_id','operation_contract_id',
        'request_schema_contract_id','response_schema_contract_id'
      )
      and e.value ~ '^[0-9]+$'
  ), resolved as (
    select
      c.rule_code,
      c.ref_key,
      c.ref_value::bigint contract_id,
      pc.id is not null resolved,
      pc.tipo,
      pc.estado,
      pc.fail_closed,
      pc.especificacion,
      case when pc.id is null then null else jsonb_build_object(
        'contract_id',pc.id,
        'contract_code',pc.contrato_codigo,
        'type',pc.tipo,
        'state',pc.estado,
        'fail_closed',pc.fail_closed,
        'logical_contract_only',coalesce((pc.especificacion->>'logical_contract_only')::boolean,false),
        'runtime_activation',coalesce((pc.especificacion->>'runtime_activation')::boolean,
                                      case when pc.especificacion ? 'runtime_activation' then false else true end)
      ) end contract
    from candidate_refs c
    left join programacion.contratos pc on pc.id=c.ref_value::bigint
  )
  select
    count(*) filter(where resolved),
    count(*) filter(where not resolved),
    count(*) filter(where resolved and estado='defined' and fail_closed),
    count(*) filter(
      where resolved and estado='defined' and fail_closed
        and coalesce((especificacion->>'logical_contract_only')::boolean,false)
        and jsonb_typeof(especificacion->'request_schema')='object'
        and jsonb_typeof(especificacion->'response_schema')='object'
    ),
    count(*) filter(
      where resolved and estado='defined' and fail_closed
        and not coalesce((especificacion->>'logical_contract_only')::boolean,false)
        and coalesce((especificacion->>'runtime_activation')::boolean,true)
    ),
    coalesce(jsonb_agg(jsonb_build_object(
      'rule_code',rule_code,
      'ref_key',ref_key,
      'contract_id',contract_id,
      'resolved',resolved,
      'contract',contract
    ) order by rule_code,ref_key),'[]'::jsonb)
  into
    v_materialized_count,
    v_broken_count,
    v_defined_fail_closed_count,
    v_logical_count,
    v_executable_count,
    v_refs
  from resolved;

  return jsonb_build_object(
    'resolution_contract','API_CONTRACT_RESOLUTION_V2',
    'pantalla_id',p_pantalla_id,
    'behavioral_contract_rule_count',v_behavior_count,
    'behavioral_contract_rules',v_rules,
    'materialized_contract_ref_count',v_materialized_count,
    'broken_contract_ref_count',v_broken_count,
    'defined_fail_closed_contract_count',v_defined_fail_closed_count,
    'logical_schema_contract_count',v_logical_count,
    'executable_contract_count',v_executable_count,
    'materialized_contract_refs',v_refs,
    'has_behavioral_contract',v_behavior_count>0,
    'has_resolvable_operation_schema_authority',
      v_defined_fail_closed_count>0 and v_broken_count=0,
    'has_executable_binding_authority',
      v_executable_count>0 and v_broken_count=0,
    'implementation_gate',case
      when v_broken_count>0 then 'BLOCKED_BROKEN_CONTRACT_REF'
      when v_defined_fail_closed_count=0 then 'NOT_READY_SOURCE_INCOMPLETE'
      when v_executable_count=0 then 'NOT_READY_EXECUTABLE_BINDING_PENDING'
      else 'READY'
    end
  );
end;
$function$;

-- API_DATA_CONTRACT stage semantics: logical schema completeness is distinct from
-- executable identity binding.
do $patch_classifier$
declare
  v_def text;
  v_start integer;
  v_end integer;
  v_block text :=
$$  if v->>'applicability'<>'NOT_APPLICABLE' and p_family_code='API_DATA_CONTRACT' then
    v_api:=programacion.fn_input_api_contract_resolution(p_pantalla_id);

    if coalesce((v_api->>'has_behavioral_contract')::boolean,false)
       and coalesce((v_api->>'broken_contract_ref_count')::integer,0)=0 then

      if coalesce((v_api->>'has_resolvable_operation_schema_authority')::boolean,false) then
        v:=jsonb_set(v,'{probe}',v_api,true);
        v:=jsonb_set(v,'{bootstrap_level}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{coverage_status}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{well_defined_status}','"COMPLETE"'::jsonb,true);
        v:=jsonb_set(v,'{story_ready_status}','"READY"'::jsonb,true);

        if coalesce((v_api->>'has_executable_binding_authority')::boolean,false) then
          v:=jsonb_set(v,'{severity}','"P4"'::jsonb,true);
          v:=jsonb_set(v,'{implementation_ready_status}','"READY"'::jsonb,true);
          v:=jsonb_set(v,'{qa_ready_status}','"READY"'::jsonb,true);
          v:=jsonb_set(v,'{production_ready_status}','"READY"'::jsonb,true);
          v:=jsonb_set(v,'{blockers}','[]'::jsonb,true);
        else
          v:=jsonb_set(v,'{severity}','"P1"'::jsonb,true);
          v:=jsonb_set(v,'{implementation_ready_status}','"NOT_READY"'::jsonb,true);
          v:=jsonb_set(v,'{qa_ready_status}','"BLOCKED"'::jsonb,true);
          v:=jsonb_set(v,'{production_ready_status}','"BLOCKED"'::jsonb,true);
          v:=jsonb_set(v,'{blockers}',jsonb_build_array(jsonb_build_object(
            'code','API_EXECUTABLE_IDENTITY_BINDING_PENDING',
            'family_code',p_family_code,
            'bootstrap_level','COMPLETE',
            'earliest_blocking_stage','IMPLEMENTATION'
          )),true);
        end if;

        v:=jsonb_set(v,'{rationale}',to_jsonb(
          'Provider-agnostic logical LF_AUTH_BOUNDARY request/response schema is canonical and fail-closed. Executable endpoint/grant/provider binding remains independently required for Implementation.'::text
        ),true);

      else
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
      end if;
    end if;
  end if;

$$;
begin
  select pg_get_functiondef(
    'programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure
  ) into v_def;

  v_start:=position(
    $$  if v->>'applicability'<>'NOT_APPLICABLE' and p_family_code='API_DATA_CONTRACT' then$$
    in v_def
  );
  v_end:=position(
    $$  if v->>'applicability'<>'NOT_APPLICABLE' and p_family_code='MFA_OTP_SSO' then$$
    in v_def
  );

  if v_start=0 or v_end=0 or v_end<=v_start then
    raise exception 'API_CLASSIFIER_PATCH_SOURCE_DRIFT';
  end if;

  v_def:=substring(v_def from 1 for v_start-1)
         || v_block
         || substring(v_def from v_end);

  execute v_def;
end;
$patch_classifier$;

-- RUNTIME_CONFIG v3: structural contract completeness does not imply runtime binding.
do $patch_runtime$
declare
  r record;
  v_def text;
  v_start integer;
  v_end integer;
  v_block text :=
$$  if p_family_code='RUNTIME_CONFIG' then
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
    from lf_ops.reglas_pantallas rp
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
    from lf_ops.reglas_pantallas rp
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

$$;
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
      raise exception 'RUNTIME_CONFIG_V3_FUNCTION_MISSING:%',r.sig;
    end if;

    v_start:=position($$  if p_family_code='RUNTIME_CONFIG' then$$ in v_def);
    v_end:=position($$  if p_family_code='ANALYTICS' then$$ in v_def);

    if v_start=0 or v_end=0 or v_end<=v_start then
      raise exception 'RUNTIME_CONFIG_V3_SOURCE_DRIFT:%',r.sig;
    end if;

    v_def:=substring(v_def from 1 for v_start-1)
           || v_block
           || substring(v_def from v_end);

    execute v_def;
  end loop;
end;
$patch_runtime$;

do $postconditions$
declare
  v_contract programacion.contratos%rowtype;
  v_contract_id bigint;
  v_api_resolution jsonb;
  v_api_classifier jsonb;
  v_runtime_classifier jsonb;
  v_stale_repo_refs integer;
begin
  select * into v_contract
  from programacion.contratos
  where version_id=19
    and contrato_codigo='B2B_AUTH_LOGIN_LOGICAL_BOUNDARY_CONTRACT';

  if not found
     or v_contract.tipo<>'LOGICAL_INTERFACE'
     or v_contract.estado<>'defined'
     or v_contract.fail_closed is distinct from true
     or coalesce((v_contract.especificacion->>'logical_contract_only')::boolean,false) is not true
     or coalesce((v_contract.especificacion->>'runtime_activation')::boolean,true) is not false
     or jsonb_typeof(v_contract.especificacion->'request_schema')<>'object'
     or jsonb_typeof(v_contract.especificacion->'response_schema')<>'object'
     or v_contract.especificacion#>>'{physical_binding,endpoint}'<>'UNBOUND'
     or v_contract.especificacion#>>'{physical_binding,http_method}'<>'UNBOUND'
     or v_contract.especificacion#>>'{physical_binding,oidc_grant}'<>'UNBOUND' then
    raise exception 'B2B_LOGICAL_API_CONTRACT_POSTCONDITION_FAILED:%',to_jsonb(v_contract);
  end if;

  v_contract_id:=v_contract.id;

  if not exists (
    select 1
    from lf_ops.reglas
    where codigo='B2B-RULE-AUTH-015'
      and valor_config->>'api_contract_id'=v_contract_id::text
      and valor_config->>'logical_contract_code'='B2B_AUTH_LOGIN_LOGICAL_BOUNDARY_CONTRACT'
      and valor_config->>'source_authority'='SUPABASE_GOVERNED_CANONICAL_RULES'
  ) then
    raise exception 'B2B_AUTH_015_LOGICAL_CONTRACT_BINDING_MISSING';
  end if;

  select count(*) into v_stale_repo_refs
  from lf_ops.reglas
  where codigo like 'B2B-RULE-AUTH-%'
    and estado<>'DEPRECADO'
    and (
      valor_config ? 'application_repository'
      or valor_config ? 'application_head_observed'
    );

  if v_stale_repo_refs<>0 then
    raise exception 'B2B_AUTH_STALE_APPLICATION_AUTHORITY_REFS:%',v_stale_repo_refs;
  end if;

  v_api_resolution:=programacion.fn_input_api_contract_resolution(51);

  if v_api_resolution->>'resolution_contract'<>'API_CONTRACT_RESOLUTION_V2'
     or coalesce((v_api_resolution->>'has_behavioral_contract')::boolean,false) is not true
     or coalesce((v_api_resolution->>'has_resolvable_operation_schema_authority')::boolean,false) is not true
     or coalesce((v_api_resolution->>'has_executable_binding_authority')::boolean,true) is not false
     or coalesce((v_api_resolution->>'logical_schema_contract_count')::integer,0)<1
     or coalesce((v_api_resolution->>'broken_contract_ref_count')::integer,-1)<>0
     or v_api_resolution->>'implementation_gate'<>'NOT_READY_EXECUTABLE_BINDING_PENDING' then
    raise exception 'B2B_API_RESOLUTION_V2_POSTCONDITION_FAILED:%',v_api_resolution;
  end if;

  v_api_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(
    51,'API_DATA_CONTRACT',19
  );

  if v_api_classifier->>'coverage_status'<>'COMPLETE'
     or v_api_classifier->>'well_defined_status'<>'COMPLETE'
     or v_api_classifier->>'story_ready_status'<>'READY'
     or v_api_classifier->>'implementation_ready_status'<>'NOT_READY'
     or v_api_classifier->'blockers'->0->>'code'<>'API_EXECUTABLE_IDENTITY_BINDING_PENDING'
     or v_api_classifier#>>'{probe,resolution_contract}'<>'API_CONTRACT_RESOLUTION_V2' then
    raise exception 'B2B_API_CLASSIFIER_POSTCONDITION_FAILED:%',v_api_classifier;
  end if;

  v_runtime_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(
    51,'RUNTIME_CONFIG',19
  );

  if v_runtime_classifier->>'coverage_status'<>'COMPLETE'
     or v_runtime_classifier->>'well_defined_status'<>'COMPLETE'
     or v_runtime_classifier->>'story_ready_status'<>'READY'
     or v_runtime_classifier->>'implementation_ready_status'<>'NOT_READY'
     or v_runtime_classifier->'blockers'->0->>'code'<>'RUNTIME_CONFIG_BINDING_PENDING'
     or v_runtime_classifier#>>'{probe,resolution_contract}'<>'RUNTIME_CONFIG_SEMANTIC_RESOLUTION_V3' then
    raise exception 'B2B_RUNTIME_CLASSIFIER_POSTCONDITION_FAILED:%',v_runtime_classifier;
  end if;
end;
$postconditions$;

commit;
