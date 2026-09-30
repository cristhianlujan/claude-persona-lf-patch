create or replace function programacion.fn_input_resolve_design_ref(
  p_ref text,
  p_design_system_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_design
as $$
declare
  v_matches jsonb;
  v_count integer;
begin
  if coalesce(btrim(p_ref),'') = '' then
    raise exception 'DESIGN_REF_EMPTY';
  end if;
  if p_design_system_id is null then
    raise exception 'DESIGN_SYSTEM_ID_REQUIRED';
  end if;

  with matches as (
    select 'COMPONENT_TOKEN'::text kind, ct.component_token_id::text object_id,
           ct.component_token_code code, ct.status, ct.design_system_id,
           jsonb_build_object('component_name',ct.component_name,'component_state',ct.component_state,'token_bindings',ct.token_bindings) detail
    from lf_design.component_tokens ct
    where ct.design_system_id=p_design_system_id and ct.component_token_code=p_ref
    union all
    select 'COLOR_TOKEN', c.color_token_id::text, c.token_name, c.status, c.design_system_id,
           jsonb_build_object('semantic_role',c.semantic_role,'hex_value',c.hex_value)
    from lf_design.color_tokens c
    where c.design_system_id=p_design_system_id and c.token_name=p_ref
    union all
    select 'TYPOGRAPHY_TOKEN', t.typography_token_id::text, t.token_name, t.status, t.design_system_id,
           jsonb_build_object('semantic_role',t.semantic_role,'font_family',t.font_family,'font_size_px',t.font_size_px,'line_height_px',t.line_height_px,'font_weight',t.font_weight)
    from lf_design.typography_tokens t
    where t.design_system_id=p_design_system_id and t.token_name=p_ref
    union all
    select 'SPACING_TOKEN', s.spacing_token_id::text, s.token_name, s.status, s.design_system_id,
           jsonb_build_object('semantic_role',s.semantic_role,'value_px',s.value_px,'token_group',s.token_group)
    from lf_design.spacing_tokens s
    where s.design_system_id=p_design_system_id and s.token_name=p_ref
    union all
    select 'RESPONSIVE_TOKEN', r.responsive_token_id::text, r.token_name, r.status, r.design_system_id,
           jsonb_build_object('semantic_role',r.semantic_role,'min_width_px',r.min_width_px,'max_width_px',r.max_width_px)
    from lf_design.responsive_tokens r
    where r.design_system_id=p_design_system_id and r.token_name=p_ref
    union all
    select 'THEME_BINDING', th.theme_binding_id::text, th.theme_binding_code, th.status, th.design_system_id,
           jsonb_build_object('theme_name',th.theme_name,'mode',th.mode,'route_scope',th.route_scope)
    from lf_design.theme_bindings th
    where th.design_system_id=p_design_system_id and th.theme_binding_code=p_ref
    union all
    select 'ICON', i.icon_id::text, i.icon_code, i.status, i.design_system_id,
           jsonb_build_object('semantic_meaning',i.semantic_meaning,'library',i.icon_library,'library_icon_name',i.library_icon_name)
    from lf_design.icon_catalog i
    where i.design_system_id=p_design_system_id and i.icon_code=p_ref
    union all
    select 'BRAND_ASSET', a.brand_asset_id::text, a.asset_code, a.status, p_design_system_id,
           jsonb_build_object('asset_name',a.asset_name,'asset_kind',a.asset_kind,'asset_variant',a.asset_variant,'checksum_sha256',a.checksum_sha256,'is_current',a.is_current)
    from lf_design.brand_assets a
    where a.asset_code=p_ref
  )
  select count(*),coalesce(jsonb_agg(jsonb_build_object(
    'kind',kind,'object_id',object_id,'code',code,'status',status,'design_system_id',design_system_id,'detail',detail
  ) order by kind,object_id),'[]'::jsonb)
  into v_count,v_matches
  from matches;

  return jsonb_build_object(
    'ref',p_ref,
    'design_system_id',p_design_system_id,
    'resolved',v_count>0,
    'ambiguous',v_count>1,
    'match_count',v_count,
    'matches',v_matches
  );
end;
$$;

revoke all on function programacion.fn_input_resolve_design_ref(text,bigint) from public;

create or replace function programacion.fn_input_component_binding_receipt(
  p_component_token_id bigint,
  p_design_system_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_design
as $$
declare
  v_component jsonb;
  v_refs jsonb;
  v_expected integer := 0;
  v_failures integer := 0;
  v_ambiguous integer := 0;
begin
  select to_jsonb(ct) into v_component
  from lf_design.component_tokens ct
  where ct.component_token_id=p_component_token_id
    and ct.design_system_id=p_design_system_id;
  if v_component is null then
    raise exception 'COMPONENT_TOKEN_UNRESOLVED:%:%',p_design_system_id,p_component_token_id;
  end if;

  with pairs as (
    select e.key,
           e.value,
           jsonb_typeof(e.value) value_type,
           case
             when jsonb_typeof(e.value)='string' and (
               e.key in ('text','border','radius','background','width','active_item','touch_target','typography')
               or e.key ~ '(_token|_token_code|_component|_component_code|_asset_code|_color|_typography|_background|_border|_radius|_width)$'
             ) then true else false end expected_ref,
           case when jsonb_typeof(e.value)='string' then trim(both '"' from e.value::text) else null end ref_text
    from jsonb_each(coalesce(v_component->'token_bindings','{}'::jsonb)) e
  ), receipts as (
    select p.*,
           case when p.expected_ref then programacion.fn_input_resolve_design_ref(p.ref_text,p_design_system_id) else null end receipt
    from pairs p
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'binding_key',key,
      'value',value,
      'value_type',value_type,
      'expected_ref',expected_ref,
      'resolution',receipt
    ) order by key),'[]'::jsonb),
    count(*) filter (where expected_ref),
    count(*) filter (where expected_ref and coalesce((receipt->>'resolved')::boolean,false)=false),
    count(*) filter (where expected_ref and coalesce((receipt->>'ambiguous')::boolean,false)=true)
  into v_refs,v_expected,v_failures,v_ambiguous
  from receipts;

  return jsonb_build_object(
    'component',v_component,
    'binding_refs',v_refs,
    'expected_ref_count',v_expected,
    'unresolved_expected_ref_count',v_failures,
    'ambiguous_expected_ref_count',v_ambiguous,
    'reference_integrity_pass',v_failures=0 and v_ambiguous=0
  );
end;
$$;

revoke all on function programacion.fn_input_component_binding_receipt(bigint,bigint) from public;

create or replace function programacion.fn_input_design_binding_graph(p_pantalla_id integer)
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

  select count(*),count(*) filter(where cp.component_token_id is not null),
         coalesce(jsonb_agg(jsonb_build_object(
           'screen_field_link_id',cp.id,
           'field_id',c.id,
           'field_code',c.codigo,
           'context_key',cp.context_key,
           'component_token_id',cp.component_token_id,
           'component_token_code',cp.component_token_code,
           'binding_status',case when cp.component_token_id is null then 'MISSING' else 'RESOLVED_ID' end,
           'component_receipt',case when cp.component_token_id is null then null else programacion.fn_input_component_binding_receipt(cp.component_token_id,v_design_system_id) end
         ) order by cp.orden_visual,cp.id),'[]'::jsonb)
  into v_field_count,v_field_bound,v_fields
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
           'binding_status',case when pv.layout_component_token_id is null then 'MISSING' else 'RESOLVED_ID' end,
           'layout_component_receipt',case when pv.layout_component_token_id is null then null else programacion.fn_input_component_binding_receipt(pv.layout_component_token_id,v_design_system_id) end
         ) order by pv.variant_id),'[]'::jsonb)
  into v_variant_count,v_variant_bound,v_variants
  from lf_ops.pantalla_variantes pv
  where pv.pantalla_id=p_pantalla_id;

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
    'graph_contract','DESIGN_BINDING_GRAPH_V1',
    'pantalla_id',p_pantalla_id,
    'screen_code',v_screen->>'codigo',
    'design_system_id',v_design_system_id,
    'fields',v_fields,
    'variants',v_variants,
    'summary',jsonb_build_object(
      'field_count',v_field_count,
      'field_component_binding_count',v_field_bound,
      'field_component_missing_count',v_field_count-v_field_bound,
      'variant_count',v_variant_count,
      'variant_layout_binding_count',v_variant_bound,
      'variant_layout_missing_count',v_variant_count-v_variant_bound,
      'referential_integrity_failure_count',v_integrity_failures
    )
  );
end;
$$;

revoke all on function programacion.fn_input_design_binding_graph(integer) from public;

-- New immutable candidate version; no promotion of the existing candidate.
insert into programacion.versiones_agente(agente_id,version_codigo,objetivo,estado,supersedes_version_id,notas)
select v.agente_id,
       'v0.3-input-readiness-semantic-bindings-candidate',
       v.objetivo || ' Incorpora resolución determinística de bindings de Design System antes de Implementation Ready.',
       'candidate',
       v.id,
       'CANDIDATE_V5_2026-08-18: añade DESIGN_BINDING_GRAPH_V1 reutilizando lf_ops/lf_design existentes. No crea segunda fuente de verdad. No active/Golden/production promotion.'
from programacion.versiones_agente v
where v.id=(select max(id) from programacion.versiones_agente where agente_id=2)
  and not exists(select 1 from programacion.versiones_agente where version_codigo='v0.3-input-readiness-semantic-bindings-candidate');

insert into programacion.componentes(version_id,componente_codigo,tipo,nombre,responsabilidad,orden_ejecucion,independencia_requerida,configuracion,estado)
select nv.id,c.componente_codigo,c.tipo,c.nombre,
       case when c.componente_codigo='INPUT_CURATOR'
            then c.responsabilidad || ' Para DESIGN_SYSTEM debe declarar bindings observados; no puede inferir componentes faltantes.'
            else c.responsabilidad || ' Para DESIGN_SYSTEM debe re-resolver DESIGN_BINDING_GRAPH_V1 y vetar refs rotas, ambiguas o bindings faltantes cuando el gate los exija.' end,
       c.orden_ejecucion,c.independencia_requerida,
       c.configuracion || case when c.componente_codigo='INPUT_CURATOR'
         then jsonb_build_object('design_binding_graph','DESIGN_BINDING_GRAPH_V1','generic_rule_not_implementation_ready',true)
         else jsonb_build_object('design_binding_graph','DESIGN_BINDING_GRAPH_V1','design_ref_integrity_required',true) end,
       c.estado
from programacion.componentes c
join programacion.versiones_agente ov on ov.id=c.version_id and ov.id=13
join programacion.versiones_agente nv on nv.version_codigo='v0.3-input-readiness-semantic-bindings-candidate'
where not exists(select 1 from programacion.componentes x where x.version_id=nv.id and x.componente_codigo=c.componente_codigo);

insert into programacion.contratos(version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,especificacion,fail_closed,estado)
select nv.id,c.contrato_codigo,c.tipo,c.nombre,
       c.descripcion || ' V5 endurece DESIGN_SYSTEM mediante bindings concretos resolubles sin copiar tokens.',
       (select nc.id from programacion.componentes nc where nc.version_id=nv.id and nc.componente_codigo='INPUT_VALIDATOR'),
       null,
       jsonb_set(
         jsonb_set(
           jsonb_set(
             jsonb_set(
               c.especificacion,
               '{schema_version}','4'::jsonb,true),
             '{contract_revision}','"5.0"'::jsonb,true),
           '{screen_graph_contract}','"SCREEN_CANONICAL_GRAPH_V5_0"'::jsonb,true),
         '{design_system_readiness}',
         jsonb_build_object(
           'coverage','DESIGN_RULE_AND_AUTHORITY_IDENTIFIED',
           'well_defined','DESIGN_REGISTRY_AND_REFERENCES_RESOLVABLE',
           'story_ready','SEMANTIC_UI_REQUIREMENTS_RESOLVED_WITHOUT_VISUAL_HARDCODING',
           'implementation_ready','REQUIRED_SCREEN_ELEMENT_BINDINGS_RESOLVABLE_AND_CURRENT',
           'qa_ready','IMPLEMENTATION_READY_PLUS_TESTABLE_STATES_A11Y_AND_VISUAL_TARGETS_WHEN_APPLICABLE',
           'production_ready','QA_READY_PLUS_CURRENT_NON_DEPRECATED_EVIDENCE_AND_NO_UPSTREAM_STALE',
           'generic_rule_alone_allows_implementation_ready',false,
           'binding_graph','DESIGN_BINDING_GRAPH_V1',
           'binding_authorities',jsonb_build_array('lf_ops.campos_pantallas','lf_ops.pantalla_variantes','lf_design.component_tokens','lf_design.*_tokens','lf_design.theme_bindings','lf_design.brand_assets','lf_design.icon_catalog')
         ),true
       ) || jsonb_build_object(
         'source_manifest','DB_GENERATED_WITH_SCREEN_CANONICAL_GRAPH_V5_0',
         'assertion_relevance_policy','FAMILY_SOURCE_PATH_ALLOWLIST_V5_DESIGN_BINDINGS',
         'negative_tests',(c.especificacion->'negative_tests') || jsonb_build_array('MISSING_COMPONENT_BINDING','BROKEN_COMPONENT_REF','AMBIGUOUS_DESIGN_REF','GENERIC_RULE_AS_IMPLEMENTATION_READY'),
         'audit_remediation',(c.especificacion->'audit_remediation') || jsonb_build_array('AUD-IGA-007_DESIGN_BINDING_READINESS'),
         'production_activation',false
       ),
       c.fail_closed,c.estado
from programacion.contratos c
join programacion.versiones_agente nv on nv.version_codigo='v0.3-input-readiness-semantic-bindings-candidate'
where c.id=28
  and not exists(select 1 from programacion.contratos x where x.version_id=nv.id and x.contrato_codigo=c.contrato_codigo);

-- Extend canonical graph only for v0.3+; v0.2 historical recomputation remains byte-semantically on V4_2.
create or replace function programacion.fn_input_screen_canonical_graph(p_pantalla_id integer, p_version_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops, lf_design
as $$
declare
  v_screen_code text;
  v_module_code text;
  v_shell_code text;
  v_contract jsonb;
  v_permissions jsonb := '[]'::jsonb;
  v_profile_permissions jsonb := '[]'::jsonb;
  v_messages jsonb := '[]'::jsonb;
  v_analytics jsonb := '[]'::jsonb;
  v_version_code text;
  v_graph_contract text := 'SCREEN_CANONICAL_GRAPH_V4_2';
begin
  select p.codigo,m.module_code,s.app_shell_code into v_screen_code,v_module_code,v_shell_code
  from lf_ops.pantallas p join lf_ops.modulos m on m.module_id=p.module_id join lf_ops.app_shells s on s.app_shell_id=m.app_shell_id
  where p.id=p_pantalla_id;
  if v_screen_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  select version_codigo into v_version_code from programacion.versiones_agente where id=p_version_id;
  if v_version_code is null then raise exception 'SCREEN_CANONICAL_GRAPH_AGENT_VERSION_NOT_FOUND:%',p_version_id; end if;

  select f.contract into v_contract from lf_ops.fn_b2b_backoffice_login_contract(v_shell_code,v_module_code,v_screen_code) f limit 1;
  if v_contract is null then raise exception 'SCREEN_CANONICAL_CONTRACT_UNRESOLVED:%',p_pantalla_id; end if;
  v_contract:=v_contract-'metadata';

  select coalesce(jsonb_agg(jsonb_build_object(
    'analytics_screen',to_jsonb(ap),'event',to_jsonb(ae),
    'parameters',coalesce((select jsonb_agg(to_jsonb(prm) order by prm.analytics_parameter_id) from lf_ops.analytics_eventos_parametros prm where prm.analytics_event_id=ae.analytics_event_id),'[]'::jsonb)
  ) order by ap.analytics_screen_id),'[]'::jsonb) into v_analytics
  from lf_ops.analytics_pantallas ap join lf_ops.analytics_eventos_definicion ae on ae.analytics_event_id=ap.analytics_event_id
  where ap.pantalla_id=p_pantalla_id;
  v_contract:=jsonb_set(v_contract,'{analytics}',v_analytics,true);

  select coalesce(jsonb_agg(jsonb_build_object('link',to_jsonb(pp),'permission',to_jsonb(pm)) order by pp.permission_id),'[]'::jsonb) into v_permissions
  from lf_ops.pantallas_permisos pp join lf_ops.permisos pm on pm.permission_id=pp.permission_id where pp.pantalla_id=p_pantalla_id;

  with direct_permissions as (
    select pp.permission_id from lf_ops.pantallas_permisos pp where pp.pantalla_id=p_pantalla_id and pp.permission_id is not null
  ), rule_permissions as (
    select distinct e.value::bigint permission_id
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    where rp.pantalla_id=p_pantalla_id and (e.key='permission_id' or e.key like '%_permission_id') and e.value~'^[0-9]+$'
  ), relevant_permissions as (
    select permission_id from direct_permissions union select permission_id from rule_permissions
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'screen_profile',to_jsonb(sp),'profile_permission',to_jsonb(pp),'permission',to_jsonb(pm),'authority','SCREEN_OR_RULE_SCOPED'
  ) order by sp.profile_id,pp.permission_id),'[]'::jsonb) into v_profile_permissions
  from lf_ops.pantallas_perfiles sp join lf_ops.perfiles_permisos pp on pp.profile_id=sp.profile_id join lf_ops.permisos pm on pm.permission_id=pp.permission_id
  where sp.pantalla_id=p_pantalla_id and pp.permission_id in (select permission_id from relevant_permissions);

  with field_ids as (
    select cp.campo_id,cp.message_id from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id
  ), timeout_policy_ids as (
    select distinct e.value::bigint timeout_policy_id
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    where rp.pantalla_id=p_pantalla_id and (e.key='timeout_policy_id' or e.key like '%_timeout_policy_id') and e.value~'^[0-9]+$'
  ), rule_message_ids as (
    select distinct e.value::bigint message_id
    from lf_ops.reglas_pantallas rp join lf_ops.reglas r on r.id=rp.regla_id cross join lateral jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    where rp.pantalla_id=p_pantalla_id and (e.key='message_id' or e.key like '%_message_id') and e.value~'^[0-9]+$'
  ), message_ids as (
    select message_id from field_ids where message_id is not null
    union select cv.message_id from lf_ops.campos_validaciones cv join field_ids f on f.campo_id=cv.campo_id where cv.message_id is not null
    union select tp.message_id from lf_ops.politicas_timeout tp where tp.timeout_policy_id in (select timeout_policy_id from timeout_policy_ids) and tp.message_id is not null
    union select message_id from rule_message_ids
  )
  select coalesce(jsonb_agg(to_jsonb(mu) order by mu.message_id),'[]'::jsonb) into v_messages
  from lf_ops.mensajes_ui mu where mu.message_id in (select message_id from message_ids);

  if v_version_code like 'v0.3-input-readiness-semantic-bindings%' then
    v_contract:=jsonb_set(v_contract,'{visual,design_bindings}',programacion.fn_input_design_binding_graph(p_pantalla_id),true);
    v_graph_contract:='SCREEN_CANONICAL_GRAPH_V5_0';
  end if;

  return jsonb_build_object(
    'graph_contract',v_graph_contract,'screen_code',v_screen_code,'module_code',v_module_code,'app_shell_code',v_shell_code,
    'canonical_contract',v_contract,'screen_permissions',v_permissions,'profile_permissions',v_profile_permissions,'messages',v_messages,
    'agent_contract_version_id',p_version_id
  );
end;
$$;

create or replace function programacion.fn_input_assertion_is_relevant(p_family_code text, p_source_ref jsonb, p_path jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_kind text:=coalesce(p_source_ref->>'kind','');
  v_path text;
begin
  if jsonb_typeof(p_path)<>'array' then return false; end if;
  select string_agg(x.value,'/' order by x.ord) into v_path from jsonb_array_elements_text(p_path) with ordinality x(value,ord);
  case p_family_code
    when 'SCREEN_IDENTITY' then return (v_kind='SCREEN' and v_path like 'observed/%') or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path in ('observed/screen_code','observed/module_code','observed/app_shell_code') or v_path like 'observed/canonical_contract/context/screen%'));
    when 'OBJECTIVE_OUTCOMES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/context/screen/objective%';
    when 'FIELDS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/fields%';
    when 'VALIDATIONS' then return (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/fields%') or (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%');
    when 'ACTIONS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'STATES' then return v_kind='SCREEN_STATE_SET' and v_path like 'observed%';
    when 'TRANSITIONS' then return (v_kind='TRANSITION_SET' and v_path like 'observed%') or (v_kind='SCREEN_STATE_SET' and v_path like 'observed%');
    when 'ROUTING_NAVIGATION' then return (v_kind='ROUTE_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%');
    when 'PROFILES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/profiles%';
    when 'PERMISSIONS' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/screen_permissions%' or v_path like 'observed/profile_permissions%');
    when 'ERRORS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/errors%';
    when 'UI_MESSAGES' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/messages%' or v_path like 'observed/canonical_contract/fields%');
    when 'SESSION' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/session%' or v_path like 'observed/canonical_contract/rules%');
    when 'RATE_LIMIT' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/rate_limit%' or v_path like 'observed/canonical_contract/rules%');
    when 'TIMEOUT_RETRY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/policies/timeout%' or v_path like 'observed/canonical_contract/rules%');
    when 'SECURITY' then return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/policies/security%');
    when 'MFA_OTP_SSO' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%');
    when 'PRIVACY_PII' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/fields%' or v_path like 'observed/canonical_contract/rules%');
    when 'AUDIT' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'ANALYTICS' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/analytics%';
    when 'OBSERVABILITY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/analytics%');
    when 'PERFORMANCE' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'RESPONSIVE' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/visual/variants%';
    when 'THEME_LIGHT_DARK_SYSTEM' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual%' or v_path like 'observed/canonical_contract/rules%');
    when 'FORCED_COLORS_CONTRAST','REDUCED_MOTION','ACCESSIBILITY' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/visual%');
    when 'DESIGN_SYSTEM' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual/design_system%' or v_path like 'observed/canonical_contract/visual/design_bindings%');
    when 'ASSETS_ICONS' then return v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/visual/components%' or v_path like 'observed/canonical_contract/evidence%' or v_path like 'observed/canonical_contract/rules%');
    when 'API_DATA_CONTRACT','LOADING_EMPTY_ERROR_STATES','IDEMPOTENCY_CONCURRENCY','TESTING_OBLIGATIONS','BROWSER_PLATFORM','ROLLOUT_PRODUCTION_GATES','CONTEXT_BUDGET_RETRIEVAL_POLICY' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/rules%';
    when 'FEATURE_FLAGS' then return v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='FEATURE_FLAGS' and v_path like 'observed/%';
    when 'I18N_FORMATS' then return v_kind='CAPABILITY_ABSENCE' and p_source_ref->>'capability'='I18N_FORMATS' and v_path like 'observed/%';
    when 'DEPENDENCIES' then return v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/context/screen/dependencies%';
    when 'VISUAL_EVIDENCE' then return (v_kind='CURRENT_VISUAL_ARTIFACT' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and v_path like 'observed/canonical_contract/evidence%');
    when 'EKB' then return v_kind in ('EKB_ERROR_SET','EKB_PREVENTION_SET','EKB_DECISION_SET') and v_path like 'observed%';
    when 'RUNTIME_CONFIG' then return (v_kind='SECURITY_POLICY_SET' and v_path like 'observed%') or (v_kind='SCREEN_CANONICAL_GRAPH' and (v_path like 'observed/canonical_contract/rules%' or v_path like 'observed/canonical_contract/policies/security%'));
    when 'SOURCE_AUTHORITY_PROVENANCE','FRESHNESS_INVALIDATION','NEGATIVE_REQUIREMENTS','CONFLICT_PRECEDENCE','APPLICABILITY_READINESS' then return v_kind='CONTRACT' and v_path like 'observed/especificacion/%';
    else return false;
  end case;
end;
$$;