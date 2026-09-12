-- LF Input Governance Design System resolution v1
-- Resolve DS authority via screen -> module -> app shell -> design system, with rule conflict detection.

create or replace function programacion.fn_input_design_system_resolution_v1(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion,lf_ops,lf_design
as $$
declare
  v_screen lf_ops.pantallas%rowtype;
  v_module lf_ops.modulos%rowtype;
  v_shell lf_ops.app_shells%rowtype;
  v_ds lf_design.design_systems%rowtype;
  v_rule_count integer:=0;
  v_rule_ds_count integer:=0;
  v_rule_ds_id bigint;
  v_rule_codes jsonb:='[]'::jsonb;
  v_payload jsonb;
begin
  select * into v_screen from lf_ops.pantallas where id=p_pantalla_id;
  if not found then raise exception 'DESIGN_SYSTEM_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  select * into v_module
  from lf_ops.modulos
  where module_id=v_screen.module_id
     or (v_screen.module_id is null and module_code=v_screen.module_code)
  order by case when module_id=v_screen.module_id then 0 else 1 end
  limit 1;
  if v_module.module_id is null then raise exception 'DESIGN_SYSTEM_MODULE_UNRESOLVED:%',p_pantalla_id; end if;

  select * into v_shell
  from lf_ops.app_shells
  where app_shell_id=v_module.app_shell_id
     or app_shell_code=v_module.app_shell_code
  order by case when app_shell_id=v_module.app_shell_id then 0 else 1 end
  limit 1;
  if v_shell.app_shell_id is null then raise exception 'DESIGN_SYSTEM_SHELL_UNRESOLVED:%',p_pantalla_id; end if;

  select * into v_ds
  from lf_design.design_systems
  where design_system_id=v_shell.design_system_id
     or design_system_code=v_shell.design_system_code
  order by case when design_system_id=v_shell.design_system_id then 0 else 1 end
  limit 1;
  if v_ds.design_system_id is null then raise exception 'DESIGN_SYSTEM_CANONICAL_ID_UNRESOLVED:%',p_pantalla_id; end if;
  if v_shell.design_system_id is distinct from v_ds.design_system_id
     or v_shell.design_system_code is distinct from v_ds.design_system_code then
    raise exception 'DESIGN_SYSTEM_SHELL_REGISTRY_CONFLICT:% shell_id=% registry_id=% shell_code=% registry_code=%',
      p_pantalla_id,v_shell.design_system_id,v_ds.design_system_id,v_shell.design_system_code,v_ds.design_system_code;
  end if;

  select count(*),
         count(distinct (r.valor_config->>'design_system_id')),
         max((r.valor_config->>'design_system_id')::bigint),
         coalesce(jsonb_agg(distinct r.codigo),'[]'::jsonb)
  into v_rule_count,v_rule_ds_count,v_rule_ds_id,v_rule_codes
  from lf_ops.reglas_pantallas rp
  join lf_ops.reglas r on r.id=rp.regla_id
  where rp.pantalla_id=p_pantalla_id
    and r.codigo='B2B-RULE-DESIGN-001'
    and coalesce(r.valor_config->>'design_system_id','')~'^[0-9]+$';

  if v_rule_ds_count>1 then
    raise exception 'DESIGN_SYSTEM_RULE_CONFLICT:%',p_pantalla_id;
  end if;
  if v_rule_ds_count=1 and v_rule_ds_id is distinct from v_ds.design_system_id then
    raise exception 'DESIGN_SYSTEM_RULE_SHELL_CONFLICT:% rule=% shell=%',
      p_pantalla_id,v_rule_ds_id,v_ds.design_system_id;
  end if;

  v_payload:=jsonb_build_object(
    'resolution_contract','DESIGN_SYSTEM_RESOLUTION_V1',
    'pantalla_id',p_pantalla_id,
    'screen_code',v_screen.codigo,
    'module_id',v_module.module_id,
    'module_code',v_module.module_code,
    'app_shell_id',v_shell.app_shell_id,
    'app_shell_code',v_shell.app_shell_code,
    'design_system_id',v_ds.design_system_id,
    'design_system_code',v_ds.design_system_code,
    'design_system_status',v_ds.status,
    'authority','APP_SHELL_DESIGN_SYSTEM',
    'reinforcing_rule_count',v_rule_count,
    'reinforcing_rule_codes',v_rule_codes,
    'conflict_detected',false
  );
  return v_payload||jsonb_build_object('resolution_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;

create or replace function programacion.fn_input_design_binding_graph_v2(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion,lf_ops,lf_design
as $$
declare
  v_design_resolution jsonb;
  v_design_system_id bigint;
  v_screen jsonb; v_fields jsonb; v_variants jsonb; v_elements jsonb;
  v_field_count integer; v_field_bound integer; v_field_semantic_pending integer; v_variant_count integer; v_variant_bound integer;
  v_element_count integer; v_element_required integer; v_element_bound integer; v_element_semantic_pending integer; v_integrity_failures integer;
begin
  select to_jsonb(p) into v_screen from lf_ops.pantallas p where p.id=p_pantalla_id;
  if v_screen is null then raise exception 'DESIGN_BINDING_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;

  v_design_resolution:=programacion.fn_input_design_system_resolution_v1(p_pantalla_id);
  v_design_system_id:=(v_design_resolution->>'design_system_id')::bigint;

  select count(*),count(*) filter(where cp.component_token_id is not null),count(*) filter(where coalesce(cp.nota,'')~*'PENDING_VISUAL_COMPONENT'),
         coalesce(jsonb_agg(jsonb_build_object(
           'screen_field_link_id',cp.id,'field_id',c.id,'field_code',c.codigo,'context_key',cp.context_key,
           'component_token_id',cp.component_token_id,'component_token_code',cp.component_token_code,'source_note',cp.nota,
           'semantic_binding_pending',coalesce(cp.nota,'')~*'PENDING_VISUAL_COMPONENT',
           'binding_status',case when cp.component_token_id is null then 'MISSING' when coalesce(cp.nota,'')~*'PENDING_VISUAL_COMPONENT' then 'PENDING_SEMANTIC_COMPONENT' else 'RESOLVED_ID' end,
           'component_receipt',case when cp.component_token_id is null then null else programacion.fn_input_component_binding_receipt(cp.component_token_id,v_design_system_id) end
         ) order by cp.orden_visual,cp.id),'[]'::jsonb)
    into v_field_count,v_field_bound,v_field_semantic_pending,v_fields
  from lf_ops.campos_pantallas cp join lf_ops.campos c on c.id=cp.campo_id where cp.pantalla_id=p_pantalla_id;

  select count(*),count(*) filter(where pv.layout_component_token_id is not null),
         coalesce(jsonb_agg(jsonb_build_object(
           'variant_id',pv.variant_id,'variant_code',pv.variant_code,'responsive_token_id',pv.responsive_token_id,'theme_binding_id',pv.theme_binding_id,
           'layout_component_token_id',pv.layout_component_token_id,'layout_component_token_code',pv.layout_component_token_code,'source_decision_id',pv.source_decision_id,
           'binding_status',case when pv.layout_component_token_id is null then 'MISSING' else 'RESOLVED_ID' end,
           'layout_component_receipt',case when pv.layout_component_token_id is null then null else programacion.fn_input_component_binding_receipt(pv.layout_component_token_id,v_design_system_id) end
         ) order by pv.variant_id),'[]'::jsonb)
    into v_variant_count,v_variant_bound,v_variants
  from lf_ops.pantalla_variantes pv where pv.pantalla_id=p_pantalla_id;

  select count(*),count(*) filter(where pe.required_for_implementation),count(*) filter(where pe.component_token_id is not null),
         count(*) filter(where pe.semantic_binding_status='PENDING_SEMANTIC_COMPONENT'),
         coalesce(jsonb_agg(jsonb_build_object(
           'element_id',pe.element_id,'element_code',pe.element_code,'element_role',pe.element_role,'context_key',pe.context_key,
           'required_for_implementation',pe.required_for_implementation,'semantic_binding_status',pe.semantic_binding_status,'component_token_id',pe.component_token_id,
           'status',pe.status,'source_refs',pe.source_refs,
           'component_receipt',case when pe.component_token_id is null then null else programacion.fn_input_component_binding_receipt(pe.component_token_id,v_design_system_id) end
         ) order by pe.element_id),'[]'::jsonb)
    into v_element_count,v_element_required,v_element_bound,v_element_semantic_pending,v_elements
  from lf_ops.pantalla_elementos pe where pe.pantalla_id=p_pantalla_id and pe.status<>'DEPRECATED';

  select coalesce(sum(x.failures),0)::integer into v_integrity_failures
  from (
    select case when cp.component_token_id is null then 0 else ((programacion.fn_input_component_binding_receipt(cp.component_token_id,v_design_system_id)->>'unresolved_expected_ref_count')::integer+(programacion.fn_input_component_binding_receipt(cp.component_token_id,v_design_system_id)->>'ambiguous_expected_ref_count')::integer) end failures
      from lf_ops.campos_pantallas cp where cp.pantalla_id=p_pantalla_id
    union all
    select case when pv.layout_component_token_id is null then 0 else ((programacion.fn_input_component_binding_receipt(pv.layout_component_token_id,v_design_system_id)->>'unresolved_expected_ref_count')::integer+(programacion.fn_input_component_binding_receipt(pv.layout_component_token_id,v_design_system_id)->>'ambiguous_expected_ref_count')::integer) end
      from lf_ops.pantalla_variantes pv where pv.pantalla_id=p_pantalla_id
    union all
    select case when pe.component_token_id is null then 0 else ((programacion.fn_input_component_binding_receipt(pe.component_token_id,v_design_system_id)->>'unresolved_expected_ref_count')::integer+(programacion.fn_input_component_binding_receipt(pe.component_token_id,v_design_system_id)->>'ambiguous_expected_ref_count')::integer) end
      from lf_ops.pantalla_elementos pe where pe.pantalla_id=p_pantalla_id and pe.status<>'DEPRECATED'
  ) x;

  return jsonb_build_object(
    'graph_contract','DESIGN_BINDING_GRAPH_V4',
    'pantalla_id',p_pantalla_id,
    'screen_code',v_screen->>'codigo',
    'design_system_id',v_design_system_id,
    'design_system_resolution',v_design_resolution,
    'fields',v_fields,'variants',v_variants,'elements',v_elements,
    'summary',jsonb_build_object(
      'field_count',v_field_count,'field_component_binding_count',v_field_bound,'field_component_missing_count',v_field_count-v_field_bound,'field_semantic_component_pending_count',v_field_semantic_pending,
      'variant_count',v_variant_count,'variant_layout_binding_count',v_variant_bound,'variant_layout_missing_count',v_variant_count-v_variant_bound,
      'element_inventory_count',v_element_count,'element_required_count',v_element_required,'element_component_binding_count',v_element_bound,
      'element_required_missing_component_count',(select count(*) from lf_ops.pantalla_elementos pe where pe.pantalla_id=p_pantalla_id and pe.status<>'DEPRECATED' and pe.required_for_implementation and (pe.component_token_id is null or pe.semantic_binding_status<>'RESOLVED_ID')),
      'element_semantic_component_pending_count',v_element_semantic_pending,'referential_integrity_failure_count',v_integrity_failures
    )
  );
end;
$$;


revoke all on function programacion.fn_input_design_system_resolution_v1(integer) from public,anon,authenticated;
grant execute on function programacion.fn_input_design_system_resolution_v1(integer) to service_role;
