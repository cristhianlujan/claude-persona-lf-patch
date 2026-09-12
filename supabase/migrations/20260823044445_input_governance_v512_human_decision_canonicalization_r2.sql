select setval('lf_ops.estados_catalogo_state_id_seq',(select coalesce(max(state_id),0) from lf_ops.estados_catalogo),true);
select setval('lf_ops.estados_transiciones_transition_id_seq',(select coalesce(max(transition_id),0) from lf_ops.estados_transiciones),true);

do $do$
declare
  v_decision_number bigint;
  v_rule_id integer;
begin
  if exists(select 1 from public.lf_decisiones_gov where id_decision='DEC-INPUT-GOV-512-HUMAN-001') then
    raise exception 'DECISION_ALREADY_EXISTS:DEC-INPUT-GOV-512-HUMAN-001';
  end if;

  select coalesce(max(decision_number),0)+1 into v_decision_number from public.lf_decisiones_gov;

  insert into public.lf_decisiones_gov(
    id_decision,fecha,decision,contexto,impacto,estado_original,estado_normalizado,
    documento_relacionado,observaciones,source_sheet_name,migration_batch_id,raw_payload,
    decision_number,created_by_execution_id
  ) values (
    'DEC-INPUT-GOV-512-HUMAN-001','2026-08-22',
    'Resolver las 18 decisiones humanas pendientes de INPUT_GOVERNANCE_AGENT 5.12 para B2B_AUTENTICACION: excluir FEATURE_FLAGS e I18N_FORMATS del alcance actual y declarar STATES/TRANSITIONS aplicables en AUTH-002, AUTH-003, AUTH-004 y AUTH-006.',
    'El owner aprobó explícitamente la recomendación con el texto "Conforme recomendación" después de readback EKB/ADR, 5/5 runs current, 235/235 Validator PASS y 18 propuestas HUMAN_DECISION_REQUIRED validadas. La decisión no convierte propuestas en canon por sí sola; autoriza materializar autoridad canónica separada.',
    'Cierra únicamente el gate funcional de aplicabilidad de las 18 propuestas. FEATURE_FLAGS queda excluido del alcance actual; I18N_FORMATS queda excluido mientras el alcance continúe single-locale; STATES/TRANSITIONS se modelan canónicamente. No autoriza merge, promoción, producción ni reactivación de AUTH-005.',
    'APROBADO_POR_OWNER','CANDIDATO_CONTROLADO',
    'INPUT_GOVERNANCE_AGENT 5.12; PR179; proposals 13-30',
    'Aplicación fail-closed. Las exclusiones deben reabrirse si cambia el alcance o aparece una fuente canónica de feature flags/i18n. STATES/TRANSITIONS se derivan solo de reglas AUTH existentes. Propuesta y canon permanecen separados.',
    'CHAT_OWNER_DECISION',(md5('DEC-INPUT-GOV-512-HUMAN-001'))::uuid,
    jsonb_build_object(
      'approval_text','Conforme recomendación','approval_date','2026-08-22','contract_revision','5.12','agent_version_id',19,'module_code','B2B_AUTENTICACION',
      'proposal_ids',(select jsonb_agg(id order by id) from programacion.input_gap_proposals where id between 13 and 30),
      'feature_flags',jsonb_build_object('decision','EXCLUDED_CURRENT_SCOPE','screen_codes',jsonb_build_array('B2B-AUTH-001','B2B-AUTH-002','B2B-AUTH-003','B2B-AUTH-004','B2B-AUTH-006'),'reopen_when',jsonb_build_array('FEATURE_FLAG_SOURCE_INTRODUCED','AUTH_SCOPE_EXPANDS')),
      'i18n_formats',jsonb_build_object('decision','EXCLUDED_CURRENT_SINGLE_LOCALE_SCOPE','screen_codes',jsonb_build_array('B2B-AUTH-001','B2B-AUTH-002','B2B-AUTH-003','B2B-AUTH-004','B2B-AUTH-006'),'reopen_when',jsonb_build_array('MULTI_LOCALE_REQUIRED','LOCALE_SOURCE_INTRODUCED')),
      'states_transitions',jsonb_build_object('decision','APPLICABLE','screen_codes',jsonb_build_array('B2B-AUTH-002','B2B-AUTH-003','B2B-AUTH-004','B2B-AUTH-006')),
      'merge_authorized',false,'promotion_authorized',false,'production_authorized',false,'auth005_reactivation',false
    ),
    v_decision_number,'CHAT-LF-INPUT-GOV-20260822-HUMAN-DECISION'
  );

  insert into lf_ops.reglas(codigo,categoria,titulo,descripcion,razon,valor_config,es_transversal,estado,origen,pendiente_decision,created_by)
  values(
    'B2B-RULE-INPUT-APPLICABILITY-001','GOVERNANCE','Aplicabilidad explícita de Feature Flags e I18N en autenticación B2B',
    'Para las pantallas activas del módulo B2B_AUTENTICACION, FEATURE_FLAGS se excluye del alcance funcional actual e I18N_FORMATS se excluye mientras el alcance permanezca single-locale. La ausencia de tablas o reglas no constituye por sí sola autoridad: esta regla materializa la decisión explícita del owner. Si aparece una fuente canónica de feature flags, se amplía el alcance de autenticación o se requiere multi-locale, la exclusión correspondiente debe reabrirse y revalidarse.',
    'Materializa la decisión humana DEC-INPUT-GOV-512-HUMAN-001 sin promover propuestas ni autorizar producción.',
    jsonb_build_object(
      'decision_id','DEC-INPUT-GOV-512-HUMAN-001','decision_number',v_decision_number,'contract_revision','5.12','module_code','B2B_AUTENTICACION',
      'screen_codes',jsonb_build_array('B2B-AUTH-001','B2B-AUTH-002','B2B-AUTH-003','B2B-AUTH-004','B2B-AUTH-006'),
      'input_family_exclusions',jsonb_build_object(
        'FEATURE_FLAGS',jsonb_build_object('status','EXCLUDED_CURRENT_SCOPE','authority','OWNER_DECISION','reopen_when',jsonb_build_array('FEATURE_FLAG_SOURCE_INTRODUCED','AUTH_SCOPE_EXPANDS')),
        'I18N_FORMATS',jsonb_build_object('status','EXCLUDED_CURRENT_SINGLE_LOCALE_SCOPE','authority','OWNER_DECISION','reopen_when',jsonb_build_array('MULTI_LOCALE_REQUIRED','LOCALE_SOURCE_INTRODUCED'))
      ),
      'absence_is_authority',false,'merge_authorized',false,'promotion_authorized',false,'production_authorized',false
    ),false,'CANDIDATO','OWNER_DECISION_INPUT_GOV_5_12',false,'CHAT-LF-INPUT-GOV-20260822-HUMAN-DECISION'
  ) returning id into v_rule_id;

  insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
  select v_rule_id,p.id,'Autoridad explícita de aplicabilidad Input Governance 5.12; decisión DEC-INPUT-GOV-512-HUMAN-001.'
  from lf_ops.pantallas p where p.codigo in ('B2B-AUTH-001','B2B-AUTH-002','B2B-AUTH-003','B2B-AUTH-004','B2B-AUTH-006');

  insert into lf_ops.estados_catalogo(state_id,state_code,entity_type,state_name,description,is_initial,is_terminal,status,source_decision_id,source_decision_number)
  values
    (nextval('lf_ops.estados_catalogo_state_id_seq'),'B2B_RECOVERY_REQUEST_READY','PASSWORD_RECOVERY_REQUEST','Solicitud de recuperación lista','Estado inicial para una solicitud de recuperación válida antes de emitir la respuesta genérica anti-enumeración.',true,false,'CANDIDATO','DEC-INPUT-GOV-512-HUMAN-001',v_decision_number),
    (nextval('lf_ops.estados_catalogo_state_id_seq'),'B2B_RECOVERY_REQUEST_ACCEPTED','PASSWORD_RECOVERY_REQUEST','Solicitud de recuperación aceptada','Resultado terminal visible del paso de solicitud: la respuesta y navegación son genéricas e indistinguibles respecto de la existencia o estado de la cuenta.',false,true,'CANDIDATO','DEC-INPUT-GOV-512-HUMAN-001',v_decision_number),
    (nextval('lf_ops.estados_catalogo_state_id_seq'),'B2B_RECOVERY_OTP_PENDING','PASSWORD_RECOVERY_VERIFY','OTP de recuperación pendiente','Contexto de recuperación pendiente de validación server-side del OTP PASSWORD_RECOVERY.',true,false,'CANDIDATO','DEC-INPUT-GOV-512-HUMAN-001',v_decision_number),
    (nextval('lf_ops.estados_catalogo_state_id_seq'),'B2B_RECOVERY_PASSWORD_UPDATE_ONLY','PASSWORD_RECOVERY_VERIFY','Actualización de contraseña habilitada','Resultado terminal satisfactorio de la verificación de recuperación: habilita únicamente PASSWORD_UPDATE_ONLY y no concede sesión operativa ni satisface MFA.',false,true,'CANDIDATO','DEC-INPUT-GOV-512-HUMAN-001',v_decision_number),
    (nextval('lf_ops.estados_catalogo_state_id_seq'),'B2B_PASSWORD_UPDATE_READY','PASSWORD_UPDATE','Actualización de contraseña lista','Contexto PASSWORD_UPDATE_ONLY válido y listo para validar y actualizar la nueva contraseña según la política central.',true,false,'CANDIDATO','DEC-INPUT-GOV-512-HUMAN-001',v_decision_number),
    (nextval('lf_ops.estados_catalogo_state_id_seq'),'B2B_PASSWORD_UPDATED_LOGIN_REQUIRED','PASSWORD_UPDATE','Contraseña actualizada; nuevo acceso requerido','Resultado terminal satisfactorio: el contexto de recuperación se termina o invalida y el usuario debe iniciar una autenticación completa nueva.',false,true,'CANDIDATO','DEC-INPUT-GOV-512-HUMAN-001',v_decision_number);

  insert into lf_ops.pantallas_estados(pantalla_id,state_code,display_order,is_visible,status,source_decision_id,state_id,source_decision_number)
  select p.id,s.state_code,x.display_order,true,'CANDIDATO','DEC-INPUT-GOV-512-HUMAN-001',s.state_id,v_decision_number
  from (values
    ('B2B-AUTH-002','B2B_RECOVERY_REQUEST_READY',1),('B2B-AUTH-002','B2B_RECOVERY_REQUEST_ACCEPTED',2),
    ('B2B-AUTH-006','B2B_RECOVERY_OTP_PENDING',1),('B2B-AUTH-006','B2B_RECOVERY_PASSWORD_UPDATE_ONLY',2),
    ('B2B-AUTH-003','B2B_PASSWORD_UPDATE_READY',1),('B2B-AUTH-003','B2B_PASSWORD_UPDATED_LOGIN_REQUIRED',2),
    ('B2B-AUTH-004','B2B_AUTH_MFA_REQUIRED',1),('B2B-AUTH-004','B2B_AUTH_AUTHENTICATED',2)
  ) as x(screen_code,state_code,display_order)
  join lf_ops.pantallas p on p.codigo=x.screen_code
  join lf_ops.estados_catalogo s on s.state_code=x.state_code;

  insert into lf_ops.estados_transiciones(transition_id,transition_code,entity_type,from_state_code,to_state_code,action_code,requires_comment,requires_idempotency_key,audit_required,condition_config,status,source_decision_id,from_state_id,to_state_id,source_decision_number)
  select nextval('lf_ops.estados_transiciones_transition_id_seq'),v.transition_code,v.entity_type,v.from_code,v.to_code,v.action_code,false,false,true,
         jsonb_build_object('source_rule_ids',(select jsonb_agg(r.id order by r.id) from lf_ops.reglas r where r.codigo=any(v.rule_codes)),'normalized_outcome',v.normalized_outcome,'owner_decision_id','DEC-INPUT-GOV-512-HUMAN-001') || v.extra,
         'CANDIDATO','DEC-INPUT-GOV-512-HUMAN-001',fs.state_id,ts.state_id,v_decision_number
  from (values
    ('TR_RECOVERY_REQUEST_ACCEPTED','PASSWORD_RECOVERY_REQUEST','B2B_RECOVERY_REQUEST_READY','B2B_RECOVERY_REQUEST_ACCEPTED','RECOVERY_SUBMIT',array['B2B-RULE-AUTH-027','B2B-RULE-AUTH-028']::text[],'GENERIC_RECOVERY_RESPONSE_ACCEPTED',jsonb_build_object('anti_enumeration_required',true,'account_existence_exposure','DENY')),
    ('TR_RECOVERY_OTP_PASSWORD_UPDATE_ONLY','PASSWORD_RECOVERY_VERIFY','B2B_RECOVERY_OTP_PENDING','B2B_RECOVERY_PASSWORD_UPDATE_ONLY','RECOVERY_OTP_VERIFY',array['B2B-RULE-AUTH-029','B2B-RULE-AUTH-037']::text[],'PASSWORD_UPDATE_ONLY',jsonb_build_object('operational_session_creation','DENY','mfa_satisfaction','DENY')),
    ('TR_PASSWORD_UPDATE_LOGIN_REQUIRED','PASSWORD_UPDATE','B2B_PASSWORD_UPDATE_READY','B2B_PASSWORD_UPDATED_LOGIN_REQUIRED','PASSWORD_UPDATE_SUCCESS',array['B2B-RULE-AUTH-030','B2B-RULE-AUTH-031']::text[],'PASSWORD_UPDATED_LOGIN_REQUIRED',jsonb_build_object('fresh_login_required',true,'operational_session_promotion','DENY'))
  ) as v(transition_code,entity_type,from_code,to_code,action_code,rule_codes,normalized_outcome,extra)
  join lf_ops.estados_catalogo fs on fs.state_code=v.from_code
  join lf_ops.estados_catalogo ts on ts.state_code=v.to_code;

  if (select count(*) from lf_ops.reglas_pantallas where regla_id=v_rule_id)<>5 then raise exception 'APPLICABILITY_RULE_SCREEN_LINK_COUNT_MISMATCH'; end if;
  if (select count(*) from lf_ops.pantallas_estados pe join lf_ops.pantallas p on p.id=pe.pantalla_id where p.codigo in ('B2B-AUTH-002','B2B-AUTH-003','B2B-AUTH-004','B2B-AUTH-006'))<>8 then raise exception 'HUMAN_DECISION_STATE_LINK_COUNT_MISMATCH'; end if;
  if (select count(*) from lf_ops.estados_transiciones where source_decision_id='DEC-INPUT-GOV-512-HUMAN-001')<>3 then raise exception 'HUMAN_DECISION_TRANSITION_COUNT_MISMATCH'; end if;
end;
$do$;

create or replace function programacion.fn_input_na_positive_authority_v512(p_family_code text,p_pantalla_id integer,p_version_id bigint)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','programacion' as $function$
declare
  v_graph jsonb; v_rules jsonb; v_screen_permissions jsonb; v_profile_permissions jsonb; v_rule jsonb; v_exclusion jsonb;
  v_codes jsonb := '[]'::jsonb; v_qualified boolean := false;
begin
  v_graph := programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules := coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  v_screen_permissions := coalesce(v_graph->'screen_permissions','[]'::jsonb);
  v_profile_permissions := coalesce(v_graph->'profile_permissions','[]'::jsonb);
  if p_family_code='SESSION' then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if coalesce(v_rule->'config'->>'operational_session_creation','')='DENY' then v_qualified:=true; v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code'); end if;
    end loop;
  elsif p_family_code='PERMISSIONS' and jsonb_array_length(v_screen_permissions)=0 and jsonb_array_length(v_profile_permissions)=0 then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if coalesce(v_rule->>'transversal','true')::boolean is false and (coalesce(v_rule->'config'->>'operational_access_grant','')='DENY' or coalesce(v_rule->'config'->>'operational_authorization_before_completion','')='DENY' or coalesce(v_rule->'config'->>'mfa_route_full_operational_session_required','')='false') then v_qualified:=true; v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code'); end if;
    end loop;
  elsif p_family_code in ('FEATURE_FLAGS','I18N_FORMATS') then
    for v_rule in select value from jsonb_array_elements(v_rules) loop
      if v_rule->>'rule_code'='B2B-RULE-INPUT-APPLICABILITY-001' and coalesce((v_rule->>'pending_decision')::boolean,false) is false and coalesce(v_rule->'config'->>'decision_id','')='DEC-INPUT-GOV-512-HUMAN-001' then
        v_exclusion:=v_rule->'config'->'input_family_exclusions'->p_family_code;
        if (p_family_code='FEATURE_FLAGS' and coalesce(v_exclusion->>'status','')='EXCLUDED_CURRENT_SCOPE') or (p_family_code='I18N_FORMATS' and coalesce(v_exclusion->>'status','')='EXCLUDED_CURRENT_SINGLE_LOCALE_SCOPE') then v_qualified:=true; v_codes:=v_codes||jsonb_build_array(v_rule->>'rule_code'); end if;
      end if;
    end loop;
  end if;
  return jsonb_build_object('qualified',v_qualified,'family_code',p_family_code,'pantalla_id',p_pantalla_id,'authority_kind',case when v_qualified then 'EXPLICIT_CANONICAL_EXCLUSION' else 'NO_POSITIVE_EXCLUSION' end,'rule_codes',v_codes,'screen_permission_count',jsonb_array_length(v_screen_permissions),'profile_permission_count',jsonb_array_length(v_profile_permissions));
end;
$function$;