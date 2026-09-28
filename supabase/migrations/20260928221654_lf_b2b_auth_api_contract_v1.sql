-- B2B-AUTH-001 technical API contract v1
-- Materializes the operation/schema authority expected by API_CONTRACT_RESOLUTION_V1.
-- This defines the implementation contract only; it does not bind a physical runtime path,
-- activate production, or bypass MFA/session/security gates.

begin;

do $decision$
declare
  v_decision_number bigint;
begin
  perform pg_advisory_xact_lock(hashtext('lf_decisiones_gov:decision_number')::bigint);

  if not exists (
    select 1
    from public.lf_decisiones_gov
    where id_decision='DEC-B2B-AUTH-API-CONTRACT-001'
  ) then
    select coalesce(max(decision_number),0)+1
      into v_decision_number
    from public.lf_decisiones_gov;

    insert into public.lf_decisiones_gov(
      id_decision,fecha,decision,contexto,impacto,
      estado_original,estado_normalizado,documento_relacionado,observaciones,
      source_sheet_name,migration_batch_id,raw_payload,decision_number,
      created_by_execution_id,updated_by_execution_id
    ) values (
      'DEC-B2B-AUTH-API-CONTRACT-001',
      '2026-09-28',
      'Materializar el contrato técnico canónico de SUBMIT_LOGIN para B2B-AUTH-001 sobre LF_AUTH_API_GATEWAY, usando programacion.contratos como autoridad existente de operación/schema.',
      'Input Governance ya dispone de ocho reglas conductuales de autenticación, pero API_CONTRACT_RESOLUTION_V1 reporta operation/schema authority no materializada. El contrato técnico se deriva exclusivamente de reglas canónicas existentes.',
      'API_DATA_CONTRACT puede quedar listo para Implementation como especificación técnica. No se crea ni activa un endpoint físico, no se autoriza producción y no se relajan MFA, sesión, rate limit, seguridad ni observabilidad.',
      'SOURCE_INCOMPLETE',
      'CANDIDATO_CONTROLADO',
      'B2B-AUTH-001; B2B-RULE-AUTH-015; LF_AUTH_API_GATEWAY; INPUT_READINESS_CONTRACT_5.13',
      'El path físico queda UNBOUND_IMPLEMENTATION_DETAIL porque no existe una ruta API canónica declarada. El navegador continúa prohibido de consumir directamente el proveedor de identidad.',
      '06_DECISIONES',
      gen_random_uuid(),
      jsonb_build_object(
        'screen_code','B2B-AUTH-001',
        'operation_code','B2B_AUTH_LOGIN_SUBMIT',
        'action_code','SUBMIT_LOGIN',
        'consumer_contract','LF_AUTH_API_GATEWAY',
        'contract_code','B2B_AUTH_LOGIN_OPERATION_CONTRACT',
        'production_authorized',false
      ),
      v_decision_number,
      'MIG-B2B-AUTH-API-CONTRACT-20260928-001',
      'MIG-B2B-AUTH-API-CONTRACT-20260928-001'
    );
  end if;
end;
$decision$;

do $contract$
declare
  v_contract_id bigint;
  v_spec jsonb;
  v_existing programacion.contratos%rowtype;
  v_rule_config jsonb;
begin
  v_spec:=jsonb_build_object(
    'schema_version',1,
    'contract_revision','1.0',
    'decision_authority','DEC-B2B-AUTH-API-CONTRACT-001',
    'screen_code','B2B-AUTH-001',
    'operation_code','B2B_AUTH_LOGIN_SUBMIT',
    'action_code','SUBMIT_LOGIN',
    'consumer_contract','LF_AUTH_API_GATEWAY',
    'runtime_boundary','NEXTJS_ROUTE_HANDLERS_NODE',
    'runtime_path_binding','UNBOUND_IMPLEMENTATION_DETAIL',
    'provider_agnostic',true,
    'selected_server_adapter','SUPABASE_AUTH',
    'method','POST',
    'transport','HTTPS_REQUIRED',
    'content_type','application/json',
    'request_schema',jsonb_build_object(
      'type','object',
      'additional_properties',false,
      'required',jsonb_build_array('email','password','anti_bot_proof'),
      'properties',jsonb_build_object(
        'email',jsonb_build_object(
          'type','string',
          'format','email',
          'source_field_id',298,
          'trim_external',true,
          'logs_allowed',false
        ),
        'password',jsonb_build_object(
          'type','string',
          'format','password',
          'source_field_id',296,
          'trim','DENY',
          'normalization','DENY',
          'case_transform','DENY',
          'logs_allowed',false
        ),
        'anti_bot_proof',jsonb_build_object(
          'type','string',
          'semantic_type','OPAQUE_TRANSIENT_PROOF',
          'retention','TRANSIENT',
          'logs_allowed',false
        )
      )
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
      'error_catalog','lf_ops.errores_catalogo',
      'credential_echo','DENY',
      'provider_payload_exposure','DENY',
      'provider_error_code_exposure','DENY',
      'session_creation_outcome','AUTHENTICATED',
      'session_before_mfa_completion','DENY'
    ),
    'source_rule_codes',jsonb_build_array(
      'B2B-RULE-AUTH-013',
      'B2B-RULE-AUTH-015',
      'B2B-RULE-AUTH-017',
      'B2B-RULE-AUTH-018',
      'B2B-RULE-AUTH-021',
      'B2B-RULE-AUTH-022',
      'B2B-RULE-AUTH-026',
      'B2B-RULE-AUTH-036'
    ),
    'implementation_contract',true,
    'runtime_activation',false,
    'promotion_authorized',false,
    'production_authorized',false
  );

  select *
    into v_existing
  from programacion.contratos
  where version_id=19
    and contrato_codigo='B2B_AUTH_LOGIN_OPERATION_CONTRACT';

  if found then
    if v_existing.tipo<>'EXECUTION_INTERFACE'
       or v_existing.estado<>'defined'
       or v_existing.fail_closed is distinct from true
       or v_existing.especificacion->>'screen_code'<>'B2B-AUTH-001'
       or v_existing.especificacion->>'operation_code'<>'B2B_AUTH_LOGIN_SUBMIT'
       or v_existing.especificacion->>'consumer_contract'<>'LF_AUTH_API_GATEWAY'
       or v_existing.especificacion->>'method'<>'POST'
       or coalesce((v_existing.especificacion->>'production_authorized')::boolean,true) is not false then
      raise exception 'B2B_AUTH_API_CONTRACT_SOURCE_DRIFT:%',to_jsonb(v_existing);
    end if;
    v_contract_id:=v_existing.id;
  else
    insert into programacion.contratos(
      version_id,contrato_codigo,tipo,nombre,descripcion,
      productor_componente_id,consumidor_componente_id,
      especificacion,fail_closed,estado
    ) values (
      19,
      'B2B_AUTH_LOGIN_OPERATION_CONTRACT',
      'EXECUTION_INTERFACE',
      'B2B Login LF Auth API operation contract',
      'Contrato técnico canónico de SUBMIT_LOGIN hacia LF_AUTH_API_GATEWAY. Define request/response lógico y conserva el desacoplamiento del proveedor.',
      null,
      null,
      v_spec,
      true,
      'defined'
    )
    returning id into v_contract_id;
  end if;

  select valor_config
    into v_rule_config
  from lf_ops.reglas
  where codigo='B2B-RULE-AUTH-015';

  if v_rule_config is null then
    raise exception 'B2B_AUTH_015_RULE_NOT_FOUND';
  end if;

  if nullif(v_rule_config->>'operation_contract_id','') is not null
     and (v_rule_config->>'operation_contract_id')::bigint<>v_contract_id then
    raise exception 'B2B_AUTH_015_FOREIGN_OPERATION_CONTRACT:%',v_rule_config->>'operation_contract_id';
  end if;

  update lf_ops.reglas
  set valor_config=jsonb_set(
        valor_config,
        '{operation_contract_id}',
        to_jsonb(v_contract_id),
        true
      ),
      updated_at=now()
  where codigo='B2B-RULE-AUTH-015';
end;
$contract$;

do $postconditions$
declare
  v_api jsonb;
  v_classifier jsonb;
  v_contract_id bigint;
begin
  select id
    into v_contract_id
  from programacion.contratos
  where version_id=19
    and contrato_codigo='B2B_AUTH_LOGIN_OPERATION_CONTRACT'
    and estado='defined'
    and fail_closed;

  if v_contract_id is null then
    raise exception 'B2B_AUTH_API_CONTRACT_NOT_RESOLVED';
  end if;

  if not exists (
    select 1
    from lf_ops.reglas
    where codigo='B2B-RULE-AUTH-015'
      and valor_config->>'operation_contract_id'=v_contract_id::text
  ) then
    raise exception 'B2B_AUTH_015_CONTRACT_BINDING_MISSING';
  end if;

  v_api:=programacion.fn_input_api_contract_resolution(51);
  if coalesce((v_api->>'has_behavioral_contract')::boolean,false) is not true
     or coalesce((v_api->>'has_resolvable_operation_schema_authority')::boolean,false) is not true
     or coalesce((v_api->>'broken_contract_ref_count')::integer,-1)<>0
     or coalesce((v_api->>'materialized_contract_ref_count')::integer,0)<1
     or v_api->>'implementation_gate'<>'READY' then
    raise exception 'B2B_AUTH_API_RESOLUTION_POSTCONDITION_FAILED:%',v_api;
  end if;

  v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(
    51,'API_DATA_CONTRACT',19
  );

  if v_classifier->>'coverage_status'<>'COMPLETE'
     or v_classifier->>'well_defined_status'<>'COMPLETE'
     or v_classifier->>'story_ready_status'<>'READY'
     or v_classifier->>'implementation_ready_status'<>'READY'
     or jsonb_array_length(coalesce(v_classifier->'blockers','[]'::jsonb))<>0 then
    raise exception 'B2B_AUTH_API_CLASSIFIER_POSTCONDITION_FAILED:%',v_classifier;
  end if;
end;
$postconditions$;

commit;
