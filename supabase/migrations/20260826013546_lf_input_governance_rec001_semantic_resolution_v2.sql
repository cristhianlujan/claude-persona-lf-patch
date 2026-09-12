-- INPUT_GOVERNANCE_AGENT 5.12
-- Semantic resolution v2 for positive canonical authority already present on REC_001.
-- No business rule is invented and no stage gate is relaxed.
-- ROUTING_NAVIGATION resolves only when the screen has a VIGENTE canonical route and every
-- route code referenced by direct VIGENTE rules resolves to a VIGENTE canonical route.
-- RESPONSIVE resolves only when a VIGENTE visual decision explicitly scopes both the screen and RESPONSIVE.

create or replace function programacion.fn_input_governance_semantic_probe_v2(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
declare
  v_base jsonb;
  v_graph jsonb;
  v_rules jsonb;
  v_screen_code text;
  v_screen_route_count integer:=0;
  v_referenced_route_count integer:=0;
  v_missing_referenced_route_count integer:=0;
  v_referenced_routes jsonb:='[]'::jsonb;
  v_responsive_authority_count integer:=0;
  v_responsive_decision_codes jsonb:='[]'::jsonb;
begin
  v_base:=programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id,p_family_code,p_version_id);
  if p_family_code not in ('ROUTING_NAVIGATION','RESPONSIVE') then
    return v_base;
  end if;

  v_graph:=programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id);
  v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
  v_screen_code:=nullif(v_graph->>'screen_code','');

  if p_family_code='ROUTING_NAVIGATION' then
    select count(*)
      into v_screen_route_count
    from lf_ops.rutas rr
    where rr.pantalla_id=p_pantalla_id
      and rr.status='VIGENTE';

    with direct_vigente_rules as (
      select r.value as rule
      from jsonb_array_elements(v_rules) r(value)
      where r.value->>'status'='VIGENTE'
    ), route_codes as (
      select distinct route_code
      from (
        select nullif(d.rule->'config'->>'target_route_code','') as route_code from direct_vigente_rules d
        union all
        select nullif(d.rule->'config'->>'post_auth_route','') as route_code from direct_vigente_rules d
      ) s
      where route_code is not null
    )
    select
      count(*),
      count(*) filter(where not exists(
        select 1 from lf_ops.rutas rr
        where rr.route_code=route_codes.route_code and rr.status='VIGENTE'
      )),
      coalesce(jsonb_agg(route_code order by route_code),'[]'::jsonb)
    into v_referenced_route_count,v_missing_referenced_route_count,v_referenced_routes
    from route_codes;

    if v_screen_route_count>0 and v_missing_referenced_route_count=0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'blocker_code',null,
        'probe',jsonb_build_object(
          'resolution_contract','ROUTING_CANONICAL_ROUTE_RESOLUTION_V2',
          'screen_route_count',v_screen_route_count,
          'referenced_route_count',v_referenced_route_count,
          'missing_referenced_route_count',v_missing_referenced_route_count,
          'referenced_route_codes',v_referenced_routes
        )
      );
    end if;
    return v_base;
  end if;

  if p_family_code='RESPONSIVE' then
    select
      count(*),
      coalesce(jsonb_agg(d.value->>'visual_decision_code' order by d.value->>'visual_decision_code'),'[]'::jsonb)
    into v_responsive_authority_count,v_responsive_decision_codes
    from jsonb_array_elements(coalesce(v_graph->'canonical_contract'->'visual'->'decisions','[]'::jsonb)) d(value)
    where d.value->>'status'='VIGENTE'
      and v_screen_code is not null
      and coalesce(d.value->'impact_scope','[]'::jsonb) ? v_screen_code
      and coalesce(d.value->'impact_scope','[]'::jsonb) ? 'RESPONSIVE';

    if v_responsive_authority_count>0 then
      return jsonb_build_object(
        'handled',true,
        'family_code',p_family_code,
        'level','COMPLETE',
        'blocker_code',null,
        'probe',jsonb_build_object(
          'resolution_contract','RESPONSIVE_VISUAL_DECISION_RESOLUTION_V2',
          'screen_code',v_screen_code,
          'responsive_authority_count',v_responsive_authority_count,
          'authority_decision_codes',v_responsive_decision_codes
        )
      );
    end if;
    return v_base;
  end if;

  return v_base;
end;
$function$;

do $patch_classifier$
declare
  vdef text;
  vbefore text;
begin
  select pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure)
    into vdef;
  vbefore:=vdef;

  if position('programacion.fn_input_governance_semantic_probe_v2(' in vdef)=0 then
    vdef:=replace(
      vdef,
      'programacion.fn_input_governance_semantic_probe_v1(',
      'programacion.fn_input_governance_semantic_probe_v2('
    );
    if vdef=vbefore or position('programacion.fn_input_governance_semantic_probe_v2(' in vdef)=0 then
      raise exception 'SELFTEST_SEMANTIC_V2_CLASSIFIER_PATCH_NOT_APPLIED';
    end if;
    execute vdef;
  end if;
end;
$patch_classifier$;

do $selftest$
declare
  vj jsonb;
  vneg integer;
begin
  vj:=programacion.fn_input_governance_semantic_probe_v2(58,'ROUTING_NAVIGATION',19);
  if coalesce((vj->>'handled')::boolean,false) is not true
     or vj->>'level'<>'COMPLETE'
     or coalesce((vj->'probe'->>'screen_route_count')::integer,0)<1
     or coalesce((vj->'probe'->>'missing_referenced_route_count')::integer,-1)<>0 then
    raise exception 'SELFTEST_REC001_ROUTING_SEMANTIC_RESOLUTION_INVALID:%',vj;
  end if;

  vj:=programacion.fn_input_governance_bootstrap_classify_v2(58,'ROUTING_NAVIGATION',19);
  if vj->>'story_ready_status'<>'READY'
     or vj->>'bootstrap_level'<>'COMPLETE'
     or vj->>'severity'<>'P4' then
    raise exception 'SELFTEST_REC001_ROUTING_CLASSIFICATION_INVALID:%',vj;
  end if;

  vj:=programacion.fn_input_governance_semantic_probe_v2(58,'RESPONSIVE',19);
  if coalesce((vj->>'handled')::boolean,false) is not true
     or vj->>'level'<>'COMPLETE'
     or coalesce((vj->'probe'->>'responsive_authority_count')::integer,0)<1
     or not coalesce(vj->'probe'->'authority_decision_codes','[]'::jsonb) @> '["VD_CLIENT_AUTH_MOCKUP_FRAME_20260819"]'::jsonb then
    raise exception 'SELFTEST_REC001_RESPONSIVE_SEMANTIC_RESOLUTION_INVALID:%',vj;
  end if;

  vj:=programacion.fn_input_governance_bootstrap_classify_v2(58,'RESPONSIVE',19);
  if vj->>'story_ready_status'<>'READY'
     or vj->>'bootstrap_level'<>'COMPLETE'
     or vj->>'severity'<>'P4' then
    raise exception 'SELFTEST_REC001_RESPONSIVE_CLASSIFICATION_INVALID:%',vj;
  end if;

  select p.id into vneg
  from lf_ops.pantallas p
  where not exists(
    select 1 from lf_ops.rutas rr where rr.pantalla_id=p.id and rr.status='VIGENTE'
  )
  order by p.id
  limit 1;
  if vneg is not null then
    vj:=programacion.fn_input_governance_semantic_probe_v2(vneg,'ROUTING_NAVIGATION',19);
    if coalesce((vj->>'handled')::boolean,false) and vj->>'level'='COMPLETE' then
      raise exception 'SELFTEST_ROUTING_ABSENCE_MUST_NOT_BECOME_COMPLETE:screen=% payload=%',vneg,vj;
    end if;
  end if;

  if programacion.fn_input_readiness_run_is_current(207) is not false then
    raise exception 'SELFTEST_ARC015_RUN207_MUST_BE_STALE_AFTER_CLASSIFIER_CHANGE';
  end if;
end;
$selftest$;

comment on function programacion.fn_input_governance_semantic_probe_v2(integer,text,bigint)
is 'INPUT_GOVERNANCE semantic resolver v2. Adds fail-closed positive authority resolution for ROUTING_NAVIGATION and RESPONSIVE while delegating all other families to v1.';
