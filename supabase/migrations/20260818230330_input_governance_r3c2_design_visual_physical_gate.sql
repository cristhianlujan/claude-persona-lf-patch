create or replace function programacion.fn_input_design_readiness_v2(p_pantalla_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops','lf_design'
as $$
declare
  v_graph jsonb; v_summary jsonb; v_design_system_id bigint; v_design_status text;
  v_missing_fields integer; v_semantic_pending integer; v_missing_layouts integer; v_ref_failures integer; v_nonprod_components integer; v_missing_supabase_visual integer;
  v_coverage text:='COMPLETE'; v_well text:='COMPLETE'; v_story text:='READY'; v_impl text:='READY'; v_qa text:='READY'; v_prod text:='READY'; v_blockers jsonb:='[]'::jsonb;
begin
  begin
    v_graph:=programacion.fn_input_design_binding_graph_v2(p_pantalla_id);
  exception when others then
    return jsonb_build_object('coverage_status','MISSING','well_defined_status','BLOCKED','story_ready_status','BLOCKED','implementation_ready_status','BLOCKED','qa_ready_status','BLOCKED','production_ready_status','BLOCKED','blockers',jsonb_build_array(jsonb_build_object('code','DESIGN_AUTHORITY_UNRESOLVED','detail',sqlerrm)),'binding_graph',null);
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
  if v_missing_fields>0 then v_well:='PARTIAL'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SCREEN_FIELD_COMPONENT_BINDING_MISSING','count',v_missing_fields)); end if;
  if v_semantic_pending>0 then v_well:='PARTIAL'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SCREEN_FIELD_SEMANTIC_COMPONENT_PENDING','count',v_semantic_pending)); end if;
  if v_missing_layouts>0 then v_well:='PARTIAL'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','SCREEN_VARIANT_LAYOUT_BINDING_MISSING','count',v_missing_layouts)); end if;
  if v_ref_failures>0 then v_well:='BLOCKED'; v_impl:='BLOCKED'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DESIGN_REFERENCE_INTEGRITY_FAILURE','count',v_ref_failures)); end if;

  select count(*) into v_nonprod_components
  from (
    select distinct (f#>>'{component_receipt,component,component_token_id}')::bigint component_token_id
    from jsonb_array_elements(v_graph->'fields') f where f#>>'{component_receipt,component,component_token_id}' is not null
    union
    select distinct (v#>>'{layout_component_receipt,component,component_token_id}')::bigint
    from jsonb_array_elements(v_graph->'variants') v where v#>>'{layout_component_receipt,component,component_token_id}' is not null
  ) q join lf_design.component_tokens ct using(component_token_id)
  where ct.status<>'VIGENTE';
  if v_design_status<>'VIGENTE' or v_nonprod_components>0 then
    if v_prod='READY' then v_prod:='NOT_READY'; end if;
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','DESIGN_SOURCE_NOT_PRODUCTION_STATUS','design_system_status',v_design_status,'non_vigente_component_count',v_nonprod_components));
  end if;

  select count(*) into v_missing_supabase_visual
  from lf_ops.pantalla_artefactos a
  where a.pantalla_id=p_pantalla_id and a.is_current=true and a.storage_provider='SUPABASE_STORAGE'
    and (a.storage_bucket is null or a.storage_object_path is null or not exists(select 1 from storage.objects o where o.bucket_id=a.storage_bucket and o.name=a.storage_object_path));
  if v_missing_supabase_visual>0 then
    v_qa:='BLOCKED'; v_prod:='BLOCKED';
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object('code','CURRENT_SUPABASE_VISUAL_ARTIFACT_NOT_PHYSICALLY_RESOLVABLE','count',v_missing_supabase_visual));
  end if;

  return jsonb_build_object('coverage_status',v_coverage,'well_defined_status',v_well,'story_ready_status',v_story,'implementation_ready_status',v_impl,'qa_ready_status',v_qa,'production_ready_status',v_prod,
    'blockers',v_blockers,'binding_graph',v_graph,
    'policy',jsonb_build_object('generic_design_rule_alone_is_implementation_ready',false,'component_id_alone_is_semantic_binding_sufficient',false,'explicit_pending_visual_component_blocks_implementation',true,'candidate_visual_may_guide_candidate_implementation',true,'candidate_visual_is_production_ready',false,'declared_supabase_visual_must_exist_for_qa',true));
end;
$$;