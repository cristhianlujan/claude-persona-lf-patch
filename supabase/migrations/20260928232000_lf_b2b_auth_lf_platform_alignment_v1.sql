-- B2B authentication architecture alignment with the current LF application platform.
--
-- Current application authority (paulozterra/lf-platform):
--   * ADR-006 accepted: Backoffice is Next.js static export; no dynamic Route Handlers.
--   * Core is Spring Boot REST and validates JWT/OIDC.
--   * ADR-003 identity provider is intentionally pending the M1 spike locally.
--   * AWS target is Amazon Cognito with separate pools.
--
-- This migration supersedes only obsolete B2B runtime/provider assumptions.
-- It preserves functional security semantics and remains fail-closed until M1
-- materializes an executable identity contract. Supabase remains the operational
-- source of truth for B2B governance definitions; this does not select Supabase Auth.

begin;

do $decision$
declare
  v_decision_number bigint;
begin
  perform pg_advisory_xact_lock(hashtext('lf_decisiones_gov:decision_number')::bigint);

  if not exists (
    select 1
    from public.lf_decisiones_gov
    where id_decision='DEC-B2B-AUTH-PLATFORM-ALIGNMENT-001'
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
      'DEC-B2B-AUTH-PLATFORM-ALIGNMENT-001',
      '2026-09-28',
      'Alinear la gobernanza de autenticación B2B con la arquitectura vigente de lf-platform: Backoffice Next.js exportado estáticamente, Core Spring Boot como backend REST y autenticación basada en JWT/OIDC. Amazon Cognito es el objetivo AWS; el proveedor local y el intercambio exacto de Login permanecen pendientes del spike M1 de ADR-003.',
      'Las reglas B2B candidatas de agosto conservaban NEXTJS_ROUTE_HANDLERS_NODE y SUPABASE_AUTH como binding técnico. La arquitectura de aplicación aceptada el 24/09 en ADR-006 prohíbe Route Handlers dinámicos y el plan M1/ADR-003 define OIDC/JWT con selección local todavía pendiente. Mantener el contrato anterior produciría un falso Implementation READY.',
      'Retira el contrato técnico B2B_AUTH_LOGIN_OPERATION_CONTRACT v1 como autoridad ejecutable y reabre API_DATA_CONTRACT desde Implementation. Conserva Story y las invariantes funcionales fail-closed. No selecciona endpoint, grant OIDC, payload de credenciales, proveedor local ni autoriza producción.',
      'LEGACY_B2B_RUNTIME_BINDING',
      'CANDIDATO_CONTROLADO',
      'paulozterra/lf-platform@578ea8318924db118c44bcb26182bac49a9154c4; ADR-006; ADR-003; docs/arquitectura.md; docs/plan-inicial.md',
      'Supabase continúa como fuente operativa de definiciones B2B conforme DEC-LF-SUPABASE-SOT-001. Se supersede únicamente el binding de runtime/proveedor. El flujo exacto navegador↔IdP↔Core debe materializarse después del spike M1 y entonces generar un nuevo operation contract.',
      '06_DECISIONES',
      gen_random_uuid(),
      jsonb_build_object(
        'governance_screen_code','B2B-AUTH-001',
        'application_repository','paulozterra/lf-platform',
        'application_head_observed','578ea8318924db118c44bcb26182bac49a9154c4',
        'frontend_runtime','NEXTJS_STATIC_EXPORT',
        'backend_runtime','SPRING_BOOT_CORE',
        'identity_protocol','OIDC_JWT',
        'aws_identity_target','AMAZON_COGNITO',
        'local_identity_decision','PENDING_ADR_003_M1_SPIKE',
        'local_identity_candidates',jsonb_build_array(
          'FLOCI_COGNITO',
          'KEYCLOAK',
          'TEST_JWT_ISSUER'
        ),
        'exact_login_exchange','PENDING_M1_IDENTITY_SPIKE',
        'production_authorized',false
      ),
      v_decision_number,
      'MIG-B2B-AUTH-LF-PLATFORM-ALIGNMENT-20260928-001',
      'MIG-B2B-AUTH-LF-PLATFORM-ALIGNMENT-20260928-001'
    );
  end if;
end;
$decision$;

do $alignment$
declare
  v_contract programacion.contratos%rowtype;
  v_changed integer;
begin
  select *
    into v_contract
  from programacion.contratos
  where version_id=19
    and contrato_codigo='B2B_AUTH_LOGIN_OPERATION_CONTRACT';

  if not found then
    raise exception 'B2B_AUTH_LOGIN_OPERATION_CONTRACT_NOT_FOUND';
  end if;

  if v_contract.estado not in ('defined','deprecated') then
    raise exception
      'B2B_AUTH_LOGIN_OPERATION_CONTRACT_UNEXPECTED_STATE:%',
      v_contract.estado;
  end if;

  if v_contract.estado='defined' and (
       v_contract.especificacion->>'runtime_boundary'<>'NEXTJS_ROUTE_HANDLERS_NODE'
       or v_contract.especificacion->>'selected_server_adapter'<>'SUPABASE_AUTH'
     ) then
    raise exception
      'B2B_AUTH_LOGIN_OPERATION_CONTRACT_SOURCE_DRIFT:%',
      v_contract.especificacion;
  end if;

  update programacion.contratos
  set estado='deprecated',
      especificacion=especificacion || jsonb_build_object(
        'superseded',true,
        'superseded_by_decision','DEC-B2B-AUTH-PLATFORM-ALIGNMENT-001',
        'superseded_reason','LF_PLATFORM_ADR_006_STATIC_EXPORT_AND_ADR_003_OIDC_IDENTITY_SPIKE',
        'superseded_application_repository','paulozterra/lf-platform',
        'superseded_application_head','578ea8318924db118c44bcb26182bac49a9154c4',
        'runtime_activation',false,
        'promotion_authorized',false,
        'production_authorized',false
      )
  where version_id=19
    and contrato_codigo='B2B_AUTH_LOGIN_OPERATION_CONTRACT';

  -- Replace obsolete provider/runtime tokens only inside B2B AUTH candidate rules.
  update lf_ops.reglas
  set descripcion=replace(
        replace(descripcion,'LF_AUTH_API_GATEWAY','LF_AUTH_BOUNDARY'),
        'Supabase Auth',
        'el proveedor OIDC que resulte del spike M1 de ADR-003'
      ),
      valor_config=replace(
        replace(
          replace(
            replace(valor_config::text,
              '"NEXTJS_ROUTE_HANDLERS_NODE"',
              '"NEXTJS_STATIC_EXPORT"'
            ),
            '"SUPABASE_AUTH_SELECTED"',
            '"OIDC_PROVIDER_PENDING_M1_SPIKE"'
          ),
          '"SUPABASE_AUTH"',
          '"OIDC_PROVIDER_PENDING_M1_SPIKE"'
        ),
        '"LF_AUTH_API_GATEWAY"',
        '"LF_AUTH_BOUNDARY"'
      )::jsonb,
      updated_at=now()
  where codigo like 'B2B-RULE-AUTH-%'
    and estado<>'DEPRECADO'
    and (
      descripcion ilike '%LF_AUTH_API_GATEWAY%'
      or descripcion ilike '%Supabase Auth%'
      or valor_config::text ilike '%LF_AUTH_API_GATEWAY%'
      or valor_config::text ilike '%SUPABASE_AUTH%'
      or valor_config::text ilike '%NEXTJS_ROUTE_HANDLERS_NODE%'
    );

  -- Core architectural boundary shared by the Login family.
  update lf_ops.reglas
  set valor_config=valor_config || jsonb_build_object(
        'architecture_alignment_decision','DEC-B2B-AUTH-PLATFORM-ALIGNMENT-001',
        'application_repository','paulozterra/lf-platform',
        'application_head_observed','578ea8318924db118c44bcb26182bac49a9154c4',
        'frontend_runtime','NEXTJS_STATIC_EXPORT',
        'backend_runtime','SPRING_BOOT_CORE',
        'identity_protocol','OIDC_JWT',
        'aws_identity_target','AMAZON_COGNITO',
        'local_identity_decision','PENDING_ADR_003_M1_SPIKE',
        'production_authorized',false
      ),
      updated_at=now()
  where codigo in (
    'B2B-RULE-AUTH-013',
    'B2B-RULE-AUTH-015',
    'B2B-RULE-AUTH-016',
    'B2B-RULE-AUTH-017',
    'B2B-RULE-AUTH-018',
    'B2B-RULE-AUTH-020',
    'B2B-RULE-AUTH-021',
    'B2B-RULE-AUTH-022',
    'B2B-RULE-AUTH-026',
    'B2B-RULE-AUTH-028',
    'B2B-RULE-AUTH-030',
    'B2B-RULE-AUTH-033',
    'B2B-RULE-AUTH-035',
    'B2B-RULE-AUTH-036',
    'B2B-RULE-AUTH-048'
  );

  -- The exact browser/IdP/Core exchange is intentionally unresolved until M1.
  update lf_ops.reglas
  set descripcion=
        'El Login B2B conserva sus invariantes de seguridad, pero el contrato técnico de intercambio de identidad queda pendiente del spike M1 de ADR-003. El Backoffice es un Next.js static export y no puede depender de Route Handlers dinámicos. El backend operativo es Core Spring Boot y valida JWT/OIDC. Hasta seleccionar y probar el flujo local equivalente a Cognito, no existe endpoint, grant OIDC ni payload de credenciales autorizado como contrato ejecutable.',
      valor_config=(
        valor_config
        - 'operation_contract_id'
        - 'method'
        - 'content_type'
        - 'required_logical_inputs'
        - 'credentials_submitted_together'
        - 'server_side_email_validation'
        - 'server_side_password_required_validation'
        - 'empty_password_provider_request'
      ) || jsonb_build_object(
        'identity_contract_status','PENDING_M1_IDENTITY_SPIKE',
        'identity_exchange_status','UNBOUND_FAIL_CLOSED',
        'physical_endpoint','UNDEFINED',
        'oidc_grant','UNDEFINED',
        'credentials_transport_contract','UNDEFINED',
        'transport','HTTPS_REQUIRED',
        'credentials_in_url','DENY',
        'credentials_in_query_string','DENY',
        'credentials_in_logging_headers','DENY',
        'client_supplied_auth_success','NON_AUTHORITATIVE'
      ),
      updated_at=now()
  where codigo='B2B-RULE-AUTH-015';

  update lf_ops.reglas
  set titulo='Proveedor OIDC desacoplado; binding pendiente del spike M1',
      descripcion=
        'El Login B2B no queda acoplado a un proveedor concreto. La arquitectura vigente usa JWT/OIDC; Amazon Cognito es el objetivo AWS y el equivalente local se decide mediante el spike M1 de ADR-003 entre las opciones autorizadas. El Backoffice estático no implementa autenticación server-side. Core Spring Boot valida issuer, JWKS y claims una vez que el IdP haya emitido el token. No se autoriza producción ni se considera implementado el binding hasta completar el spike y sus pruebas.',
      valor_config=(
        valor_config
        - 'business_user_identity_field'
        - 'supabase_auth_adapter_location'
        - 'server_adapter'
        - 'preferred_adapter'
        - 'selected_provider'
        - 'admin_idp_status'
        - 'admin_identity_provider'
      ) || jsonb_build_object(
        'identity_protocol','OIDC_JWT',
        'frontend_runtime','NEXTJS_STATIC_EXPORT',
        'backend_runtime','SPRING_BOOT_CORE',
        'aws_identity_target','AMAZON_COGNITO',
        'local_identity_provider','PENDING_M1_IDENTITY_SPIKE',
        'local_identity_candidates',jsonb_build_array(
          'FLOCI_COGNITO',
          'KEYCLOAK',
          'TEST_JWT_ISSUER'
        ),
        'core_token_validation','ISSUER_PLUS_JWKS',
        'provider_binding','PENDING_M1_IDENTITY_SPIKE',
        'production_binding','NOT_AUTHORIZED',
        'functional_provider_decision_status','REOPENED_BY_PLATFORM_ARCHITECTURE_ALIGNMENT',
        'implementation_validation_status','PENDING_M1_IDENTITY_SPIKE'
      ),
      updated_at=now()
  where codigo='B2B-RULE-AUTH-026';

  get diagnostics v_changed=row_count;
  if v_changed<>1 then
    raise exception 'B2B_AUTH_026_ALIGNMENT_TARGET_COUNT:%',v_changed;
  end if;

  -- AUTH-036/048 retain the logical action but no longer target a Next.js API runtime.
  update lf_ops.reglas
  set valor_config=jsonb_set(
        valor_config,
        '{actions}',
        (
          select jsonb_agg(
            case
              when a.value->>'action_code'='SUBMIT_LOGIN'
                then (a.value-'target') || jsonb_build_object(
                  'target','LF_IDENTITY_BOUNDARY_PENDING_M1',
                  'target_status','PENDING_IDENTITY_SPIKE'
                )
              else a.value
            end
            order by a.ord
          )
          from jsonb_array_elements(valor_config->'actions') with ordinality a(value,ord)
        ),
        true
      ),
      updated_at=now()
  where codigo='B2B-RULE-AUTH-036'
    and jsonb_typeof(valor_config->'actions')='array';

  update lf_ops.reglas
  set valor_config=(valor_config-'submit_target') || jsonb_build_object(
        'submit_target','LF_IDENTITY_BOUNDARY_PENDING_M1',
        'submit_target_status','PENDING_IDENTITY_SPIKE'
      ),
      updated_at=now()
  where codigo='B2B-RULE-AUTH-048';
end;
$alignment$;

do $postconditions$
declare
  v_classifier jsonb;
  v_contract programacion.contratos%rowtype;
  v_stale_count integer;
begin
  select *
    into v_contract
  from programacion.contratos
  where version_id=19
    and contrato_codigo='B2B_AUTH_LOGIN_OPERATION_CONTRACT';

  if v_contract.estado<>'deprecated'
     or coalesce((v_contract.especificacion->>'production_authorized')::boolean,true) then
    raise exception 'B2B_AUTH_LEGACY_CONTRACT_NOT_DEPRECATED:%',to_jsonb(v_contract);
  end if;

  if exists (
    select 1
    from lf_ops.reglas
    where codigo='B2B-RULE-AUTH-015'
      and valor_config ? 'operation_contract_id'
  ) then
    raise exception 'B2B_AUTH_015_LEGACY_OPERATION_CONTRACT_STILL_BOUND';
  end if;

  select count(*)
    into v_stale_count
  from lf_ops.reglas
  where codigo like 'B2B-RULE-AUTH-%'
    and estado<>'DEPRECADO'
    and (
      descripcion ilike '%LF_AUTH_API_GATEWAY%'
      or descripcion ilike '%Supabase Auth%'
      or valor_config::text ilike '%LF_AUTH_API_GATEWAY%'
      or valor_config::text ilike '%SUPABASE_AUTH%'
      or valor_config::text ilike '%NEXTJS_ROUTE_HANDLERS_NODE%'
    );

  if v_stale_count<>0 then
    raise exception 'B2B_AUTH_LEGACY_RUNTIME_REFERENCES_REMAIN:%',v_stale_count;
  end if;

  if not exists (
    select 1
    from lf_ops.reglas
    where codigo='B2B-RULE-AUTH-026'
      and valor_config->>'frontend_runtime'='NEXTJS_STATIC_EXPORT'
      and valor_config->>'backend_runtime'='SPRING_BOOT_CORE'
      and valor_config->>'identity_protocol'='OIDC_JWT'
      and valor_config->>'aws_identity_target'='AMAZON_COGNITO'
      and valor_config->>'local_identity_provider'='PENDING_M1_IDENTITY_SPIKE'
      and coalesce((valor_config->>'production_authorized')::boolean,true)=false
  ) then
    raise exception 'B2B_AUTH_PLATFORM_ALIGNMENT_RULE_POSTCONDITION_FAILED';
  end if;

  v_classifier:=programacion.fn_input_governance_bootstrap_classify_v2(
    51,'API_DATA_CONTRACT',19
  );

  if v_classifier->>'story_ready_status'<>'READY'
     or v_classifier->>'implementation_ready_status'<>'NOT_READY'
     or v_classifier->>'coverage_status'<>'PARTIAL'
     or v_classifier#>>'{blockers,0,code}'<>'API_OPERATION_SCHEMA_SOURCE_INCOMPLETE' then
    raise exception 'B2B_AUTH_API_FAIL_CLOSED_POSTCONDITION_FAILED:%',v_classifier;
  end if;
end;
$postconditions$;

commit;
