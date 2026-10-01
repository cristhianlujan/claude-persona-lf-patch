-- INV-6.2 - authorized Input Governance recuration screens
-- Exact-version identity: 20261001230029
-- Transport: EXACT_VERSION_SOURCE_FIRST
-- Owner direction: lf_eventos #19834
-- Screen 55 authority: lf_eventos #19722
--
-- This rule governs recuration/currentness scope only.
-- It does NOT grant implementation or navigation authority.

do $preflight$
declare
  v_expected_ids integer[] := array[1,2,3,5,43,51,52,53,54,55,56,57,58];
  v_found_ids integer[];
  v_active_count integer;
  v_existing lf_ops.reglas%rowtype;
  v_expected_config jsonb;
begin
  select array_agg(id order by id), count(*) filter (where activa)
    into v_found_ids,v_active_count
  from lf_ops.pantallas
  where id=any(v_expected_ids);

  if v_found_ids is distinct from v_expected_ids then
    raise exception 'INV_6_2_SCREEN_UNIVERSE_MISMATCH expected=% actual=%',
      v_expected_ids,v_found_ids;
  end if;

  if v_active_count<>13 then
    raise exception 'INV_6_2_SCREEN_ACTIVE_COUNT_MISMATCH expected=13 actual=%',
      v_active_count;
  end if;

  if not exists(
    select 1
    from lf_ops.pantallas
    where id=55
      and codigo='B2B-AUTH-005'
      and estado='VIGENTE'
      and activa
      and descripcion ilike '%trazabilidad%'
      and descripcion ilike '%no debe recibir navegación activa%'
  ) then
    raise exception 'INV_6_2_SCREEN_55_TRACEABILITY_CONTRACT_DRIFT';
  end if;

  if not exists(
    select 1
    from public.lf_eventos
    where id=19834
      and entidad_codigo='DP-INV-7-DP-INV-8-OWNER-DIRECTION'
      and payload#>>'{owner_directions,SCREEN_55,in_scope}'='true'
  ) then
    raise exception 'INV_6_2_OWNER_DIRECTION_MISSING';
  end if;

  v_expected_config := jsonb_build_object(
    'contract_version','1.0.0',
    'scope','INPUT_GOVERNANCE_RECURATION_CURRENTNESS',
    'screen_ids',to_jsonb(v_expected_ids),
    'authorized_screen_count',13,
    'implementation_authority','NOT_GRANTED_BY_THIS_RULE',
    'consumer_mode_default','GOVERNANCE_SCOPE_ONLY',
    'consumer_mode_overrides',jsonb_build_object(
      '55','TRACEABILITY_ONLY'
    ),
    'traceability_only_screen_ids',jsonb_build_array(55),
    'traceability_only_policy',jsonb_build_object(
      'story_creator','DO_NOT_GENERATE_IMPLEMENTABLE_STORY',
      'router','DO_NOT_ROUTE_TO_IMPLEMENTATION',
      'navigation','DO_NOT_NAVIGATE_AS_ACTIVE_ROUTE'
    ),
    'screen_55_authority',jsonb_build_object(
      'owner_direction_event_id',19834,
      'screen_authority_event_id',19722,
      'canonical_completed_run_id',283,
      'operational_navigation','DENY',
      'input_governance_scope','IN_SCOPE'
    ),
    'caller_usage','ALLOWLIST_FOR_GOVERNED_RECURATION',
    'fail_closed',true
  );

  select * into v_existing
  from lf_ops.reglas
  where codigo='INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001';

  if found and (
    v_existing.categoria is distinct from 'GOVERNANCE'
    or v_existing.titulo is distinct from 'Pantallas autorizadas para recuración gobernada de Input Governance'
    or v_existing.estado is distinct from 'VIGENTE'
    or v_existing.valor_config is distinct from v_expected_config
    or v_existing.pendiente_decision
  ) then
    raise exception 'INV_6_2_EXISTING_RULE_DRIFT';
  end if;
end
$preflight$;

insert into lf_ops.reglas(
  codigo,
  categoria,
  titulo,
  descripcion,
  razon,
  valor_config,
  es_transversal,
  estado,
  origen,
  pendiente_decision,
  pendiente_detalle,
  created_by
)
values(
  'INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001',
  'GOVERNANCE',
  'Pantallas autorizadas para recuración gobernada de Input Governance',
  'Define el allowlist canónico de pantallas que pueden ser objeto de recuración/currentness de Input Governance. La pertenencia a esta regla no concede autoridad de implementación ni navegación. La pantalla 55 permanece dentro del alcance de gobernanza únicamente como TRACEABILITY_ONLY.',
  'Evitar recuraciones fuera de alcance y separar explícitamente gobernanza/currentness de autoridad de implementación o navegación.',
  jsonb_build_object(
    'contract_version','1.0.0',
    'scope','INPUT_GOVERNANCE_RECURATION_CURRENTNESS',
    'screen_ids',jsonb_build_array(1,2,3,5,43,51,52,53,54,55,56,57,58),
    'authorized_screen_count',13,
    'implementation_authority','NOT_GRANTED_BY_THIS_RULE',
    'consumer_mode_default','GOVERNANCE_SCOPE_ONLY',
    'consumer_mode_overrides',jsonb_build_object(
      '55','TRACEABILITY_ONLY'
    ),
    'traceability_only_screen_ids',jsonb_build_array(55),
    'traceability_only_policy',jsonb_build_object(
      'story_creator','DO_NOT_GENERATE_IMPLEMENTABLE_STORY',
      'router','DO_NOT_ROUTE_TO_IMPLEMENTATION',
      'navigation','DO_NOT_NAVIGATE_AS_ACTIVE_ROUTE'
    ),
    'screen_55_authority',jsonb_build_object(
      'owner_direction_event_id',19834,
      'screen_authority_event_id',19722,
      'canonical_completed_run_id',283,
      'operational_navigation','DENY',
      'input_governance_scope','IN_SCOPE'
    ),
    'caller_usage','ALLOWLIST_FOR_GOVERNED_RECURATION',
    'fail_closed',true
  ),
  true,
  'VIGENTE',
  'OWNER_DIRECTION_DP_INV_7_20261001',
  false,
  null,
  'CHATGPT-INV-6.2-20261001'
)
on conflict (codigo) do nothing;

do $postconditions$
declare
  v_rule lf_ops.reglas%rowtype;
  v_ids integer[];
begin
  select * into v_rule
  from lf_ops.reglas
  where codigo='INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001';

  if not found then
    raise exception 'INV_6_2_RULE_NOT_CREATED';
  end if;

  select array_agg((x.value)::integer order by (x.value)::integer)
    into v_ids
  from jsonb_array_elements_text(v_rule.valor_config->'screen_ids') x(value);

  if v_ids is distinct from array[1,2,3,5,43,51,52,53,54,55,56,57,58] then
    raise exception 'INV_6_2_RULE_SCREEN_IDS_MISMATCH:%',v_ids;
  end if;

  if v_rule.estado<>'VIGENTE'
     or v_rule.pendiente_decision
     or v_rule.valor_config#>>'{consumer_mode_overrides,55}'<>'TRACEABILITY_ONLY'
     or v_rule.valor_config#>>'{traceability_only_policy,story_creator}'<>'DO_NOT_GENERATE_IMPLEMENTABLE_STORY'
     or v_rule.valor_config#>>'{traceability_only_policy,router}'<>'DO_NOT_ROUTE_TO_IMPLEMENTATION'
     or v_rule.valor_config#>>'{screen_55_authority,operational_navigation}'<>'DENY'
     or v_rule.valor_config#>>'{screen_55_authority,input_governance_scope}'<>'IN_SCOPE'
     or (v_rule.valor_config->>'authorized_screen_count')::integer<>13 then
    raise exception 'INV_6_2_RULE_POSTCONDITION_FAILED:%',to_jsonb(v_rule);
  end if;
end
$postconditions$;
