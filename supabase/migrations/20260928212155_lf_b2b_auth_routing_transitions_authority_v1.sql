-- B2B-AUTH-001 routing + AUTH_FLOW transition authority v1
-- Story-definition closure only. Routes/transitions remain CANDIDATO, so implementation stays fail-closed.

begin;

do $materialize_authority$
declare
  v_decision_number bigint;
  v_rule_id integer;
  v_route lf_ops.rutas%rowtype;
begin
  -- Canonical functional decision for login routing/state semantics.
  select d.decision_number
    into v_decision_number
  from public.lf_decisiones_gov d
  where d.id_decision='DEC-B2B-AUTH-ROUTING-001';

  if v_decision_number is null then
    select coalesce(max(decision_number),0)+1
      into v_decision_number
    from public.lf_decisiones_gov;

    insert into public.lf_decisiones_gov(
      id_decision,fecha,decision,contexto,impacto,
      estado_original,estado_normalizado,documento_relacionado,observaciones,
      source_sheet_name,migration_batch_id,raw_payload,decision_number,
      created_by_execution_id,updated_by_execution_id
    ) values (
      'DEC-B2B-AUTH-ROUTING-001',
      '2026-09-28',
      'Definir la navegación y la máquina de estados canónica del Login B2B. B2B_ROUTE_AUTH_LOGIN es la entrada pública pre-auth; MFA_REQUIRED dirige al desafío B2B_ROUTE_AUTH_MFA_VERIFY; AUTHENTICATED crea/confirma sesión server-side y resuelve el destino post-login exclusivamente mediante B2B-RULE-AUTH-023. INVALID_CREDENTIALS, RATE_LIMITED, ACCESS_DENIED y SERVICE_UNAVAILABLE no proyectan un nuevo estado de autenticación.',
      'B2B-AUTH-001 ya tenía ruta, estados y tres transiciones AUTH_FLOW, pero la ruta carecía de decisión fuente y el resolver de Input Governance exigía una regla de estados diseñada para UPLOAD_BATCH. Se formaliza autoridad específica de autenticación sin promover implementación ni producción.',
      'Cierra la definición Story de ROUTING_NAVIGATION y TRANSITIONS para B2B-AUTH-001. No promueve rutas ni transiciones fuera de CANDIDATO; Implementation/QA/Production continúan fail-closed hasta promoción explícita.',
      'PENDIENTE_DEFINICION_CANONICA',
      'CANDIDATO_CONTROLADO',
      'B2B-AUTH-001; B2B_ROUTE_AUTH_LOGIN; B2B-RULE-AUTH-STATE-001; INPUT_GOVERNANCE_CONTRACT_5.13',
      'El destino post-login no se hardcodea. Se conserva la estrategia FIRST_AUTHORIZED_VISIBLE_MENU_ROUTE de B2B-RULE-AUTH-023 y la navegación directa al desafío MFA sin contexto transitorio sigue denegada.',
      '06_DECISIONES',
      gen_random_uuid(),
      jsonb_build_object(
        'screen_code','B2B-AUTH-001',
        'entry_route_code','B2B_ROUTE_AUTH_LOGIN',
        'mfa_route_code','B2B_ROUTE_AUTH_MFA_VERIFY',
        'state_rule_code','B2B-RULE-AUTH-STATE-001',
        'entity_type','AUTH_FLOW',
        'production_authorized',false
      ),
      v_decision_number,
      'MIG-B2B-AUTH-ROUTING-TRANSITIONS-20260928-001',
      'MIG-B2B-AUTH-ROUTING-TRANSITIONS-20260928-001'
    );
  end if;

  -- Route provenance: fail closed if another authority was attached meanwhile.
  select *
    into v_route
  from lf_ops.rutas
  where route_code='B2B_ROUTE_AUTH_LOGIN';

  if not found then
    raise exception 'B2B_AUTH_LOGIN_ROUTE_NOT_FOUND';
  end if;

  if v_route.pantalla_id is distinct from 51
     or v_route.route_pattern is distinct from '/b2b/auth/login'
     or v_route.authentication_required is distinct from false then
    raise exception 'B2B_AUTH_LOGIN_ROUTE_SOURCE_DRIFT:%',to_jsonb(v_route);
  end if;

  if v_route.source_decision_id is not null
     and v_route.source_decision_id<>'DEC-B2B-AUTH-ROUTING-001' then
    raise exception 'B2B_AUTH_LOGIN_ROUTE_FOREIGN_AUTHORITY:%',v_route.source_decision_id;
  end if;

  update lf_ops.rutas
  set source_decision_id='DEC-B2B-AUTH-ROUTING-001',
      source_decision_number=v_decision_number
  where route_code='B2B_ROUTE_AUTH_LOGIN';

  -- AUTH_FLOW-specific transition authority. Do not reuse UPLOAD_BATCH semantics.
  insert into lf_ops.reglas(
    codigo,categoria,titulo,descripcion,razon,valor_config,
    es_transversal,estado,origen,pendiente_decision,pendiente_detalle,created_by
  ) values (
    'B2B-RULE-AUTH-STATE-001',
    'WORKFLOW',
    'Máquina de estados del flujo de autenticación B2B',
    'Las transiciones de autenticación B2B son autoritativas únicamente cuando están registradas en lf_ops.estados_transiciones con entity_type=AUTH_FLOW. El servidor determina estado origen/destino y resultado; el cliente no puede imponer estado destino ni saltar una transición. MFA_REQUIRED y AUTHENTICATED proyectan estado. INVALID_CREDENTIALS, RATE_LIMITED, ACCESS_DENIED y SERVICE_UNAVAILABLE preservan el estado no autenticado o el estado MFA vigente según corresponda.',
    'Separar la autoridad AUTH_FLOW de B2B-RULE-STATE-001, cuya semántica canónica corresponde a UPLOAD_BATCH.',
    jsonb_build_object(
      'registry','lf_ops.estados_transiciones',
      'state_registry','lf_ops.estados_catalogo',
      'entity_type','AUTH_FLOW',
      'server_side_transition_authority','REQUIRED',
      'client_supplied_target_state_authoritative','DENY',
      'unregistered_transition','DENY',
      'audit_required',true,
      'allowed_transition_codes',jsonb_build_array(
        'TR_AUTH_LOGIN_MFA_REQUIRED',
        'TR_AUTH_LOGIN_AUTHENTICATED',
        'TR_AUTH_MFA_AUTHENTICATED'
      ),
      'state_bearing_outcomes',jsonb_build_array('MFA_REQUIRED','AUTHENTICATED'),
      'non_state_outcomes',jsonb_build_array(
        'INVALID_CREDENTIALS','RATE_LIMITED','ACCESS_DENIED','SERVICE_UNAVAILABLE'
      ),
      'entry_route_code','B2B_ROUTE_AUTH_LOGIN',
      'mfa_route_code','B2B_ROUTE_AUTH_MFA_VERIFY',
      'post_login_resolution_rule_code','B2B-RULE-AUTH-023',
      'source_decision_id','DEC-B2B-AUTH-ROUTING-001',
      'source_decision_number',v_decision_number,
      'production_authorized',false
    ),
    false,
    'CANDIDATO',
    'DEC-B2B-AUTH-ROUTING-001',
    false,
    null,
    'MIG-B2B-AUTH-ROUTING-TRANSITIONS-20260928-001'
  )
  on conflict (codigo) do nothing;

  select id
    into v_rule_id
  from lf_ops.reglas
  where codigo='B2B-RULE-AUTH-STATE-001';

  if v_rule_id is null then
    raise exception 'B2B_AUTH_STATE_RULE_NOT_MATERIALIZED';
  end if;

  if not exists (
    select 1 from lf_ops.reglas
    where id=v_rule_id
      and estado<>'DEPRECADO'
      and not pendiente_decision
      and valor_config->>'registry'='lf_ops.estados_transiciones'
      and valor_config->>'entity_type'='AUTH_FLOW'
      and valor_config->>'server_side_transition_authority'='REQUIRED'
  ) then
    raise exception 'B2B_AUTH_STATE_RULE_SOURCE_DRIFT';
  end if;

  insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
  values(
    v_rule_id,
    51,
    'Autoridad específica AUTH_FLOW para B2B-AUTH-001; decisión DEC-B2B-AUTH-ROUTING-001.'
  )
  on conflict (regla_id,pantalla_id) do nothing;
end;
$materialize_authority$;

-- Generalize TRANSITIONS semantic authority by matching the rule entity_type
-- to the actual transition entity_type for the screen.
do $patch_transition_resolver$
declare
  r record;
  v_def text;
  v_old text :=
$old$select count(*) into v_rule_count from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id where rp.pantalla_id=p_pantalla_id and r.codigo='B2B-RULE-STATE-001' and r.estado<>'DEPRECADO' and not r.pendiente_decision and r.valor_config->>'registry'='lf_ops.estados_transiciones';$old$;
  v_new text :=
$new$select count(*) into v_rule_count
    from lf_ops.reglas_pantallas rp
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
      );$new$;
begin
  for r in
    select *
    from (
      values
        ('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'),
        ('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)')
    ) x(sig)
  loop
    select pg_get_functiondef(to_regprocedure(r.sig)) into v_def;

    if v_def is null then
      raise exception 'B2B_AUTH_TRANSITION_RESOLVER_FUNCTION_MISSING:%',r.sig;
    end if;

    if position(v_new in v_def)=0 then
      if position(v_old in v_def)=0 then
        raise exception 'B2B_AUTH_TRANSITION_RESOLVER_SOURCE_DRIFT:%',r.sig;
      end if;
      v_def:=replace(v_def,v_old,v_new);
      execute v_def;
    end if;
  end loop;
end;
$patch_transition_resolver$;

do $postconditions$
declare
  v_route jsonb;
  v_routing jsonb;
  v_transitions jsonb;
begin
  select to_jsonb(r)
    into v_route
  from lf_ops.rutas r
  where r.route_code='B2B_ROUTE_AUTH_LOGIN';

  if v_route->>'source_decision_id'<>'DEC-B2B-AUTH-ROUTING-001'
     or nullif(v_route->>'source_decision_number','') is null then
    raise exception 'B2B_AUTH_ROUTE_PROVENANCE_POSTCONDITION_FAILED:%',v_route;
  end if;

  if not exists (
    select 1
    from lf_ops.reglas_pantallas rp
    join lf_ops.reglas r on r.id=rp.regla_id
    where rp.pantalla_id=51
      and r.codigo='B2B-RULE-AUTH-STATE-001'
      and r.valor_config->>'entity_type'='AUTH_FLOW'
  ) then
    raise exception 'B2B_AUTH_STATE_RULE_LINK_POSTCONDITION_FAILED';
  end if;

  v_routing:=programacion.fn_input_governance_bootstrap_classify_v2(
    51,'ROUTING_NAVIGATION',19
  );
  if v_routing->>'coverage_status'<>'COMPLETE'
     or v_routing->>'well_defined_status'<>'COMPLETE'
     or v_routing->>'story_ready_status'<>'READY'
     or v_routing->>'implementation_ready_status'<>'NOT_READY'
     or v_routing#>>'{probe,resolution_contract}'<>'B2B_ROUTE_GRAPH_RESOLUTION_V1' then
    raise exception 'B2B_AUTH_ROUTING_POSTCONDITION_FAILED:%',v_routing;
  end if;

  v_transitions:=programacion.fn_input_governance_bootstrap_classify_v2(
    51,'TRANSITIONS',19
  );
  if v_transitions->>'coverage_status'<>'COMPLETE'
     or v_transitions->>'well_defined_status'<>'COMPLETE'
     or v_transitions->>'story_ready_status'<>'READY'
     or v_transitions->>'implementation_ready_status'<>'NOT_READY'
     or v_transitions#>>'{probe,resolution_contract}'<>'B2B_TRANSITION_GRAPH_RESOLUTION_V1' then
    raise exception 'B2B_AUTH_TRANSITIONS_POSTCONDITION_FAILED:%',v_transitions;
  end if;
end;
$postconditions$;

commit;
