-- 1) Canonical B2B unauthenticated destinations for Login legal/support links.
insert into lf_ops.rutas(route_code,route_name,route_pattern,route_type,is_parameterized,authentication_required,status,pantalla_id)
select 'B2B_ROUTE_LEGAL_TERMS','Términos y Condiciones B2B','/b2b/legal/terminos-y-condiciones','INTERNAL',false,false,'CANDIDATO',null
where not exists (select 1 from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_TERMS');

insert into lf_ops.rutas(route_code,route_name,route_pattern,route_type,is_parameterized,authentication_required,status,pantalla_id)
select 'B2B_ROUTE_LEGAL_PRIVACY','Política de Privacidad B2B','/b2b/legal/politica-de-privacidad','INTERNAL',false,false,'CANDIDATO',null
where not exists (select 1 from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_PRIVACY');

insert into lf_ops.rutas(route_code,route_name,route_pattern,route_type,is_parameterized,authentication_required,status,pantalla_id)
select 'B2B_ROUTE_SUPPORT','Soporte B2B','/b2b/soporte','INTERNAL',false,false,'CANDIDATO',null
where not exists (select 1 from lf_ops.rutas where route_code='B2B_ROUTE_SUPPORT');

update lf_ops.reglas
set descripcion='El Login B2B conserva accesos visibles a Términos y Condiciones, Política de Privacidad y Soporte. Los tres destinos son rutas B2B canónicas, accesibles sin iniciar sesión y separadas del frente público; no se reutilizan automáticamente documentos B2C ni URLs externas hardcodeadas.',
    valor_config = valor_config || jsonb_build_object(
      'blocks_story',false,
      'blocks_implementation',false,
      'blocks_production',false,
      'public_front_reuse','DENY',
      'route_target_status','APPROVED_B2B_CANONICAL',
      'current_b2b_route_ids',(
        select jsonb_agg(route_id order by route_id)
        from lf_ops.rutas where route_code in ('B2B_ROUTE_LEGAL_TERMS','B2B_ROUTE_LEGAL_PRIVACY','B2B_ROUTE_SUPPORT')
      ),
      'destinations',jsonb_build_object(
        'TERMS_AND_CONDITIONS',jsonb_build_object('route_code','B2B_ROUTE_LEGAL_TERMS','route_id',(select route_id from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_TERMS'),'authentication_required',false),
        'PRIVACY_POLICY',jsonb_build_object('route_code','B2B_ROUTE_LEGAL_PRIVACY','route_id',(select route_id from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_PRIVACY'),'authentication_required',false),
        'CONTACT_SUPPORT',jsonb_build_object('route_code','B2B_ROUTE_SUPPORT','route_id',(select route_id from lf_ops.rutas where route_code='B2B_ROUTE_SUPPORT'),'authentication_required',false)
      )
    ),
    pendiente_decision=false,
    pendiente_detalle=null,
    updated_at=now()
where codigo='B2B-RULE-NAV-LEGAL-001';

update lf_ops.reglas
set descripcion='Las acciones del Login se resuelven desde reglas, campos y rutas B2B canónicas. Autenticación, visibilidad de contraseña y recuperación conservan sus destinos existentes; Términos, Privacidad y Soporte resuelven a rutas B2B oficiales accesibles sin autenticación.',
    valor_config=jsonb_set(
      valor_config,
      '{actions}',
      jsonb_build_array(
        jsonb_build_object('target','LF_AUTH_API_GATEWAY','field_ids',jsonb_build_array(298,296),'action_code','SUBMIT_LOGIN','source_rule_ids',jsonb_build_array(431,434)),
        jsonb_build_object('field_id',296,'action_code','TOGGLE_PASSWORD_VISIBILITY','source_rule_id',428),
        jsonb_build_object('route_id',9,'screen_id',52,'action_code','START_PASSWORD_RECOVERY','source_rule_id',427),
        jsonb_build_object('route_id',(select route_id from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_TERMS'),'action_code','OPEN_TERMS','target_status','APPROVED_B2B_CANONICAL','source_rule_id',464),
        jsonb_build_object('route_id',(select route_id from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_PRIVACY'),'action_code','OPEN_PRIVACY','target_status','APPROVED_B2B_CANONICAL','source_rule_id',464),
        jsonb_build_object('route_id',(select route_id from lf_ops.rutas where route_code='B2B_ROUTE_SUPPORT'),'action_code','CONTACT_SUPPORT','target_status','APPROVED_B2B_CANONICAL','source_rule_id',464)
      ),
      true
    ),
    updated_at=now()
where codigo='B2B-RULE-AUTH-036';

-- 2) Recovery request does not authenticate or create an operational session.
update lf_ops.reglas
set descripcion='B2B-AUTH-002 envía únicamente el correo validado a LF_AUTH_API_GATEWAY. La respuesta y navegación son anti-enumeración. Para una cuenta elegible, el servidor crea el desafío OTP PASSWORD_RECOVERY mediante la operación B2B de correo y entrega el código por Brevo. Esta etapa no autentica al usuario, no crea sesión operativa y no concede acceso; solo inicia el contexto restringido de recuperación que continúa en B2B-AUTH-006.',
    valor_config=valor_config || jsonb_build_object(
      'operational_session_creation','DENY',
      'authentication_completion','DENY',
      'operational_access_grant','DENY',
      'success_context_scope','PASSWORD_RECOVERY_CHALLENGE_ONLY'
    ),
    updated_at=now()
where codigo='B2B-RULE-AUTH-028';

-- 3) Canonical OTP error copies.
update lf_ops.errores_catalogo
set user_title='Código de recuperación no válido',
    user_message_template='El código ingresado no es válido o ya venció. Solicita un nuevo código para continuar.',
    suggested_action='Solicita un nuevo código de recuperación para continuar.',
    action_label='Reenviar código',
    updated_at=now()
where error_id=39;

update lf_ops.errores_catalogo
set user_title='Código no válido',
    user_message_template='El código ingresado no es válido o ya venció. Solicita uno nuevo e inténtalo nuevamente.',
    suggested_action='Solicita un nuevo código de verificación para continuar.',
    action_label='Reenviar código',
    updated_at=now()
where error_id=40;

-- 4) Retire legacy TOTP from active flow; preserve traceability only.
update lf_ops.reglas
set descripcion='B2B-AUTH-005 queda retirado del flujo operativo. Su contrato TOTP se conserva únicamente como trazabilidad histórica/legacy y no puede activarse, enrutar usuarios, provisionar runtime ni conceder acceso operativo. El segundo control vigente continúa gobernado por LF_EMAIL_OTP según AUTH-033/AUTH-034. Cualquier reintroducción futura de TOTP requiere una nueva decisión canónica explícita.',
    valor_config=valor_config || jsonb_build_object(
      'normal_flow','DENY',
      'legacy_trace_only',true,
      'activation_authority','DENY',
      'implementation_as_active_path','DENY',
      'operational_reactivation','DENY',
      'lifecycle_status','RETIRED_LEGACY_TRACE_ONLY',
      'replacement_factor','LF_EMAIL_OTP'
    ),
    pendiente_decision=false,
    pendiente_detalle=null,
    updated_at=now()
where codigo='B2B-RULE-AUTH-035';

update lf_ops.reglas
set valor_config=valor_config || jsonb_build_object('legacy_totp_operational_status','RETIRED_LEGACY_TRACE_ONLY','legacy_totp_reactivation','DENY'),
    updated_at=now()
where codigo='B2B-RULE-AUTH-033';