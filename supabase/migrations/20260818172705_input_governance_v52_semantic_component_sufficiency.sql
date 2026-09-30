create or replace function programacion.fn_input_design_binding_graph_v2(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_design_system_id bigint;
  v_design_rule_count integer;
  v_screen jsonb;
  v_fields jsonb;
  v_variants jsonb;
  v_field_count integer;
  v_field_bound integer;
  v_field_semantic_pending integer;
  v_variant_count integer;
  v_variant_bound integer;
  v_integrity_failures integer;
begin
  select to_jsonb(p) into v_screen from lf_ops.pantallas p where p.id=p_pantalla_id;
  if v_screen is null then raise exception 'DESIGN_BINDING_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  select count(distinct (r.valor_config->>'design_system_id')),
         max((r.valor_config->>'design_system_id')::bigint)
  into v_design_rule_count,v_design_system_id
  from lf_ops.reglas_pantallas rp
  join lf_ops.reglas r on r.id=rp.regla_id
  where rp.pantalla_id=p_pantalla_id
    and r.codigo='B2B-RULE-DESIGN-001'
    and coalesce(r.valor_config->>'design_system_id','') ~ '^[0-9]+$';

  if v_design_rule_count<>1 or v_design_system_id is null then
    raise exception 'DESIGN_SYSTEM_ID_UNRESOLVED_OR_CONFLICT:%',p_pantalla_id;
  end if;

  select count(*),
         count(*) filter(where cp.component_token_id is not null),
         count(*) filter(where coalesce(cp.nota,'') ~* 'PENDING_VISUAL_COMPONENT'),
         coalesce(jsonb_agg(jsonb_build_object(
           'screen_field_link_id',cp.id,
           'field_id',c.id,
           'field_code',c.codigo,
           'context_key',cp.context_key,
           'component_token_id',cp.component_token_id,
           'component_token_code',cp.component_token_code,
           'source_note',cp.nota,
           'semantic_binding_pending',coalesce(cp.nota,'') ~* 'PENDING_VISUAL_COMPONENT',
           'binding_status',case
              when cp.component_token_id is null then 'MISSING'
              when coalesce(cp.nota,'') ~* 'PENDING_VISUAL_COMPONENT' then 'PENDING_SEMANTIC_COMPONENT'
              else 'RESOLVED_ID'
            end,
           'component_receipt',case when cp.component_token_id is null then null else programacion.fn_input_component_binding_receipt(cp.component_token_id,v_design_system_id) end
         ) order by cp.orden_visual,cp.id),'[]'::jsonb)
  into v_field_count,v_field_bound,v_field_semantic_pending,v_fields
  from lf_ops.campos_pantallas cp
  join lf_ops.campos c on c.id=cp.campo_id
  where cp.pantalla_id=p_pantalla_id;

  select count(*),count(*) filter(where pv.layout_component_token_id is not null),
         coalesce(jsonb_agg(jsonb_build_object(
           'variant_id',pv.variant_id,
           'variant_code',pv.variant_code,
           'responsive_token_id',pv.responsive_token_id,
           'theme_binding_id',pv.theme_binding_id,
           'layout_component_token_id',pv.layout_component_token_id,
           'layout_component_token_code',pv.layout_component_token_code,
           'source_decision_id',pv.source_decision_id,
           'binding_status',case when pv.layout_component_token_id is null then 'MISSING' else 'RESOLVED_ID' end,
           'layout_component_receipt',case when pv.layout_component_token_id is null then null else programacion.fn_input_component_binding_receipt(pv.layout_component_token_id,v_design_system_id) end
         ) order by pv.variant_id),'[]'::jsonb)
  into v_variant_count,v_variant_bound,v_variants
  from lf_ops.pantalla_variantes pv where pv.pantalla_id=p_pantalla_id;

  select coalesce(sum(x.failures),0)::integer into v_integrity_failures
  from (
    select case when cp.component_token_id is null then 0 else
      ((programacion.fn_input_component_binding_receipt(cp.component_token_id,v_design_system_id)->>'unresolved_expected_ref_count')::integer
       +(programacion.fn_input_component_binding_receipt(cp.component_token_id,v_design_system_id)->>'ambiguous_expected_ref_count')::integer) end failures
    from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id
    union all
    select case when pv.layout_component_token_id is null then 0 else
      ((programacion.fn_input_component_binding_receipt(pv.layout_component_token_id,v_design_system_id)->>'unresolved_expected_ref_count')::integer
       +(programacion.fn_input_component_binding_receipt(pv.layout_component_token_id,v_design_system_id)->>'ambiguous_expected_ref_count')::integer) end
    from lf_ops.pantalla_variantes pv where pv.pantalla_id=p_pantalla_id
  ) x;

  return jsonb_build_object(
    'graph_contract','DESIGN_BINDING_GRAPH_V2',
    'pantalla_id',p_pantalla_id,
    'screen_code',v_screen->>'codigo',
    'design_system_id',v_design_system_id,
    'fields',v_fields,
    'variants',v_variants,
    'summary',jsonb_build_object(
      'field_count',v_field_count,
      'field_component_binding_count',v_field_bound,
      'field_component_missing_count',v_field_count-v_field_bound,
      'field_semantic_component_pending_count',v_field_semantic_pending,
      'variant_count',v_variant_count,
      'variant_layout_binding_count',v_variant_bound,
      'variant_layout_missing_count',v_variant_count-v_variant_bound,
      'referential_integrity_failure_count',v_integrity_failures
    )
  );
end;
$$;
revoke all on function programacion.fn_input_design_binding_graph_v2(integer) from public;

create or replace function programacion.fn_input_design_readiness_v2(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_graph jsonb;
  v_summary jsonb;
  v_design_system_id bigint;
  v_design_status text;
  v_missing_fields integer;
  v_semantic_pending integer;
  v_missing_layouts integer;
  v_ref_failures integer;
  v_nonprod_components integer;
  v_coverage text := 'COMPLETE';
  v_well text := 'COMPLETE';
  v_story text := 'READY';
  v_impl text := 'READY';
  v_qa text := 'READY';
  v_prod text := 'READY';
  v_blockers jsonb := '[]'::jsonb;
begin
  begin
    v_graph:=programacion.fn_input_design_binding_graph_v2(p_pantalla_id);
  exception when others then
    return jsonb_build_object(
      'coverage_status','MISSING','well_defined_status','BLOCKED','story_ready_status','BLOCKED',
      'implementation_ready_status','BLOCKED','qa_ready_status','BLOCKED','production_ready_status','BLOCKED',
      'blockers',jsonb_build_array(jsonb_build_object('code','DESIGN_AUTHORITY_UNRESOLVED','detail',sqlerrm)),
      'binding_graph',null
    );
  end;

  v_summary:=v_graph->'summary';
  v_design_system_id:=(v_graph->>'design_system_id')::bigint;
  select status into v_design_status from lf_design.design_systems where design_system_id=v_design_system_id;
  if v_design_status is null then
    v_coverage:='MISSING'; v_well:='BLOCKED'; v_story:='BLOCKED'; v_impl:='BLOCKED'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DESIGN_SYSTEM_NOT_FOUND','design_system_id',v_design_system_id));
  end if;

  v_missing_fields:=coalesce((v_summary->>'field_component_missing_count')::integer,0);
  v_semantic_pending:=coalesce((v_summary->>'field_semantic_component_pending_count')::integer,0);
  v_missing_layouts:=coalesce((v_summary->>'variant_layout_missing_count')::integer,0);
  v_ref_failures:=coalesce((v_summary->>'referential_integrity_failure_count')::integer,0);

  if v_missing_fields>0 then
    v_well:='PARTIAL'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SCREEN_FIELD_COMPONENT_BINDING_MISSING','count',v_missing_fields));
  end if;
  if v_semantic_pending>0 then
    v_well:='PARTIAL'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SCREEN_FIELD_SEMANTIC_COMPONENT_PENDING','count',v_semantic_pending));
  end if;
  if v_missing_layouts>0 then
    v_well:='PARTIAL'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SCREEN_VARIANT_LAYOUT_BINDING_MISSING','count',v_missing_layouts));
  end if;
  if v_ref_failures>0 then
    v_well:='BLOCKED'; v_impl:='BLOCKED'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DESIGN_REFERENCE_INTEGRITY_FAILURE','count',v_ref_failures));
  end if;

  select count(*) into v_nonprod_components
  from (
    select distinct (f#>>'{component_receipt,component,component_token_id}')::bigint component_token_id
    from jsonb_array_elements(v_graph->'fields') f
    where f#>>'{component_receipt,component,component_token_id}' is not null
    union
    select distinct (v#>>'{layout_component_receipt,component,component_token_id}')::bigint
    from jsonb_array_elements(v_graph->'variants') v
    where v#>>'{layout_component_receipt,component,component_token_id}' is not null
  ) q join lf_design.component_tokens ct using(component_token_id)
  where ct.status<>'VIGENTE';

  if v_design_status<>'VIGENTE' or v_nonprod_components>0 then
    if v_prod='READY' then v_prod:='NOT_READY'; end if;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','DESIGN_SOURCE_NOT_PRODUCTION_STATUS','design_system_status',v_design_status,'non_vigente_component_count',v_nonprod_components));
  end if;

  return jsonb_build_object(
    'coverage_status',v_coverage,'well_defined_status',v_well,'story_ready_status',v_story,
    'implementation_ready_status',v_impl,'qa_ready_status',v_qa,'production_ready_status',v_prod,
    'blockers',v_blockers,'binding_graph',v_graph,
    'policy',jsonb_build_object(
      'generic_design_rule_alone_is_implementation_ready',false,
      'component_id_alone_is_semantic_binding_sufficient',false,
      'explicit_pending_visual_component_blocks_implementation',true,
      'candidate_visual_may_guide_candidate_implementation',true,
      'candidate_visual_is_production_ready',false
    )
  );
end;
$$;
revoke all on function programacion.fn_input_design_readiness_v2(integer) from public;

insert into programacion.versiones_agente(agente_id,version_codigo,objetivo,estado,supersedes_version_id,notas)
select agente_id,'v0.4-input-readiness-semantic-sufficiency-candidate',
       objetivo || ' Distingue existencia referencial de suficiencia semántica del componente visual.',
       'candidate',id,
       'CANDIDATE_V5_2_2026-08-18: PENDING_VISUAL_COMPONENT en fuente canónica bloquea Implementation Ready aunque exista component_token_id. No promotion.'
from programacion.versiones_agente
where id=15
  and not exists(select 1 from programacion.versiones_agente where version_codigo='v0.4-input-readiness-semantic-sufficiency-candidate');

insert into programacion.componentes(version_id,componente_codigo,tipo,nombre,responsabilidad,orden_ejecucion,independencia_requerida,configuracion,estado)
select nv.id,c.componente_codigo,c.tipo,c.nombre,c.responsabilidad,c.orden_ejecucion,c.independencia_requerida,
       c.configuracion || jsonb_build_object('design_binding_graph','DESIGN_BINDING_GRAPH_V2','semantic_component_sufficiency','EXPLICIT_SOURCE_MARKER_REQUIRED'),c.estado
from programacion.componentes c
join programacion.versiones_agente nv on nv.version_codigo='v0.4-input-readiness-semantic-sufficiency-candidate'
where c.version_id=15
  and not exists(select 1 from programacion.componentes x where x.version_id=nv.id and x.componente_codigo=c.componente_codigo);

insert into programacion.contratos(version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,especificacion,fail_closed,estado)
select nv.id,c.contrato_codigo,c.tipo,c.nombre,
       c.descripcion || ' V5.2 diferencia FK válida de binding semánticamente suficiente.',
       (select nc.id from programacion.componentes nc where nc.version_id=nv.id and nc.componente_codigo='INPUT_VALIDATOR'),null,
       jsonb_set(jsonb_set(jsonb_set(c.especificacion,'{contract_revision}','"5.2"'::jsonb,true),'{screen_graph_contract}','"SCREEN_CANONICAL_GRAPH_V5_2"'::jsonb,true),'{design_system_readiness,binding_graph}','"DESIGN_BINDING_GRAPH_V2"'::jsonb,true)
       || jsonb_build_object(
          'semantic_component_sufficiency',jsonb_build_object(
             'component_id_exists','NECESSARY_NOT_SUFFICIENT',
             'explicit_pending_visual_component','BLOCK_IMPLEMENTATION_READY',
             'semantic_mismatch_or_unresolved_role','BLOCK_IMPLEMENTATION_READY',
             'source_marker_pattern','PENDING_VISUAL_COMPONENT%'
          ),
          'negative_tests',(c.especificacion->'negative_tests') || jsonb_build_array('COMPONENT_ID_PRESENT_BUT_SEMANTIC_BINDING_PENDING'),
          'audit_remediation',(c.especificacion->'audit_remediation') || jsonb_build_array('AUD-IGA-009_COMPONENT_ID_NOT_SEMANTIC_SUFFICIENCY')
       ),
       c.fail_closed,c.estado
from programacion.contratos c
join programacion.versiones_agente nv on nv.version_codigo='v0.4-input-readiness-semantic-sufficiency-candidate'
where c.id=30
  and not exists(select 1 from programacion.contratos x where x.version_id=nv.id and x.contrato_codigo=c.contrato_codigo);

create or replace function programacion.fn_input_screen_canonical_graph(p_pantalla_id integer, p_version_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_screen_code text; v_module_code text; v_shell_code text; v_contract jsonb;
  v_permissions jsonb:='[]'::jsonb; v_profile_permissions jsonb:='[]'::jsonb; v_messages jsonb:='[]'::jsonb; v_analytics jsonb:='[]'::jsonb;
  v_version_code text; v_graph_contract text:='SCREEN_CANONICAL_GRAPH_V4_2';
begin
  select p.codigo,m.module_code,s.app_shell_code into v_screen_code,v_module_code,v_shell_code
  from lf_ops.pantallas p join lf_ops.modulos m on m.module_id=p.module_id join lf_ops.app_shells s on s.app_shell_id=m.app_shell_id where p.id=p_pantalla_id;
  if v_screen_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  select version_codigo into v_version_code from programacion.versiones_agente where id=p_version_id;
  if v_version_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_AGENT_VERSION_NOT_FOUND:%',p_version_id; end if;
  select f.contract into v_contract from lf_ops.fn_b2b_backoffice_login_contract(v_shell_code,v_module_code,v_screen_code) f limit 1;
  if v_contract is null then raise exception 'SCREEN_CANONICAL_CONTRACT_UNRESOLVED:%',p_pantalla_id; end if;
  v_contract:=v_contract-'metadata';

  select coalesce(jsonb_agg(jsonb_build_object('analytics_screen',to_jsonb(ap),'event',to_jsonb(ae),'parameters',coalesce((select jsonb_agg(to_jsonb(prm) order by prm.analytics_parameter_id) from lf_ops.analytics_eventos_parametros prm where prm.analytics_event_id=ae.analytics_event_id),'[]'::jsonb)) order by ap.analytics_screen_id),'[]'::jsonb)
  into v_analytics from lf_ops.analytics_pantallas ap join lf_ops.analytics_eventos_definicion ae on ae.analytics_event_id=ap.analytics_event_id where ap.pantalla_id=p_pantalla_id;
  v_contract:=jsonb_set(v_contract,'{analytics}',v_analytics,true);

  select coalesce(jsonb_agg(jsonb_build_object('link',to_jsonb(pp),'permission',to_jsonb(pm)) order by pp.permission_id),'[]'::jsonb) into v_permissions
  from lf_ops.pantallas_permisos pp join lf_ops.permisos pm on pm.permission_id=pp.permission_id where pp.pantalla_id=p_pantalla_id;

  with direct_permissions as (select pp.permission_id from lf_ops.pantallas_permisos pp where pp.pantalla_id=p_pantalla_id and pp.permission_id is not null),
  rule_permissions as (select distinct e.value::bigint permission_id from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e where rp.pantalla_id=p_pantalla_id and (e.key='permission_id' or e.key like '%_permission_id') and e.value~'^[0-9]+$'),
  relevant_permissions as (select permission_id from direct_permissions union select permission_id from rule_permissions)
  select coalesce(jsonb_agg(jsonb_build_object('screen_profile',to_jsonb(sp),'profile_permission',to_jsonb(pp),'permission',to_jsonb(pm),'authority','SCREEN_OR_RULE_SCOPED') order by sp.profile_id,pp.permission_id),'[]'::jsonb)
  into v_profile_permissions from lf_ops.pantallas_perfiles sp join lf_ops.perfiles_permisos pp on pp.profile_id=sp.profile_id join lf_ops.permisos pm on pm.permission_id=pp.permission_id
  where sp.pantalla_id=p_pantalla_id and pp.permission_id in (select permission_id from relevant_permissions);

  with field_ids as (select cp.campo_id,cp.message_id from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id),
  timeout_policy_ids as (select distinct e.value::bigint timeout_policy_id from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e where rp.pantalla_id=p_pantalla_id and (e.key='timeout_policy_id' or e.key like '%_timeout_policy_id') and e.value~'^[0-9]+$'),
  rule_message_ids as (select distinct e.value::bigint message_id from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e where rp.pantalla_id=p_pantalla_id and (e.key='message_id' or e.key like '%_message_id') and e.value~'^[0-9]+$'),
  message_ids as (select message_id from field_ids where message_id is not null union select cv.message_id from lf_ops.campos_validaciones cv join field_ids f on f.campo_id=cv.campo_id where cv.message_id is not null union select tp.message_id from lf_ops.politicas_timeout tp where tp.timeout_policy_id in (select timeout_policy_id from timeout_policy_ids) and tp.message_id is not null union select message_id from rule_message_ids)
  select coalesce(jsonb_agg(to_jsonb(mu) order by mu.message_id),'[]'::jsonb) into v_messages from lf_ops.mensajes_ui mu where mu.message_id in (select message_id from message_ids);

  if v_version_code like 'v0.4-input-readiness-semantic-sufficiency%' then
    v_contract:=jsonb_set(v_contract,'{visual,design_bindings}',programacion.fn_input_design_binding_graph_v2(p_pantalla_id),true);
    v_graph_contract:='SCREEN_CANONICAL_GRAPH_V5_2';
  elsif v_version_code like 'v0.3-input-readiness-semantic-bindings%' then
    v_contract:=jsonb_set(v_contract,'{visual,design_bindings}',programacion.fn_input_design_binding_graph(p_pantalla_id),true);
    v_graph_contract:='SCREEN_CANONICAL_GRAPH_V5_0';
  end if;

  return jsonb_build_object('graph_contract',v_graph_contract,'screen_code',v_screen_code,'module_code',v_module_code,'app_shell_code',v_shell_code,'canonical_contract',v_contract,'screen_permissions',v_permissions,'profile_permissions',v_profile_permissions,'messages',v_messages,'agent_contract_version_id',p_version_id);
end;
$$;