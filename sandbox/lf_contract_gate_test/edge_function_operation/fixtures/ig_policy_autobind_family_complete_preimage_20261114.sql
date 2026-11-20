CREATE OR REPLACE FUNCTION programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id integer, p_family_code text, p_version_id bigint DEFAULT 19, p_graph jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_criteria jsonb;
  v_kind text;
  v_graph jsonb;
  v_probe jsonb:='{}'::jsonb;
  v_sem jsonb;
  v_rules jsonb;
  v_evidence jsonb;
  v_count integer:=0;
  v_vigente integer:=0;
  v_candidate integer:=0;
  v_pending integer:=0;
  v_pending_marker integer:=0;
  v_errors integer:=0;
  v_complete boolean:=false;
begin
  select c.especificacion->'families'->p_family_code->'complete_criteria_v1'
    into v_criteria
  from programacion.contratos c
  where c.version_id=p_version_id
    and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    and c.fail_closed
  limit 1;

  if jsonb_typeof(v_criteria)<>'object'
     or v_criteria->>'schema_version' is distinct from 'input-family-complete-criteria/v1'
     or coalesce((v_criteria->>'fail_closed')::boolean,false) is not true then
    return jsonb_build_object('handled',false,'family_code',p_family_code,'reason','COMPLETE_CRITERIA_UNAVAILABLE');
  end if;

  v_kind:=v_criteria->>'probe_kind';
  if v_kind='EXISTING_RESOLVER' then
    return jsonb_build_object('handled',false,'family_code',p_family_code,'reason','EXISTING_RESOLVER_RETAINS_AUTHORITY');
  end if;

  v_graph:=coalesce(p_graph,programacion.fn_input_screen_canonical_graph(p_pantalla_id,p_version_id));
  if jsonb_typeof(v_graph)<>'object' then
    return jsonb_build_object('handled',false,'family_code',p_family_code,'reason','CANONICAL_GRAPH_UNAVAILABLE');
  end if;

  if v_kind='RULES_REGEX_V1' then
    v_rules:=coalesce(v_graph->'canonical_contract'->'rules','[]'::jsonb);
    v_probe:=programacion.fn_input_bootstrap_rule_probe_v1(v_rules,null,v_criteria->>'rule_regex');
    v_count:=coalesce((v_probe->>'count')::integer,0);
    v_vigente:=coalesce((v_probe->>'vigente_count')::integer,0);
    v_candidate:=coalesce((v_probe->>'candidate_count')::integer,0);
    v_pending:=coalesce((v_probe->>'pending_decision_count')::integer,0);
    v_pending_marker:=coalesce((v_probe->>'pending_marker_count')::integer,0);
    v_complete:=v_count>0 and v_vigente=v_count and v_candidate=0 and v_pending=0 and v_pending_marker=0;

  elsif v_kind='SEMANTIC_PROBE_V1_RULESET' then
    if p_graph is null then
      v_sem:=programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id,p_family_code,p_version_id);
    else
      v_sem:=programacion.fn_input_governance_semantic_probe_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,v_graph);
    end if;
    v_probe:=coalesce(v_sem->'probe','{}'::jsonb);
    v_count:=coalesce((v_probe->>'count')::integer,0);
    v_vigente:=coalesce((v_probe->>'vigente_count')::integer,0);
    v_candidate:=coalesce((v_probe->>'candidate_count')::integer,0);
    v_pending:=coalesce((v_probe->>'pending_decision_count')::integer,0);
    v_pending_marker:=coalesce((v_probe->>'pending_marker_count')::integer,0);
    v_errors:=coalesce((v_probe->>'error_count')::integer,0);
    v_complete:=v_count>0 and v_vigente=v_count and v_candidate=0 and v_pending=0 and v_pending_marker=0;
    if v_criteria#>>'{complete_if,error_count_gt}' is not null then
      v_complete:=v_complete and v_errors>(v_criteria#>>'{complete_if,error_count_gt}')::integer;
    end if;

  elsif v_kind='SEMANTIC_PROBE_V1_ASSET_BINDINGS' then
    if p_graph is null then
      v_sem:=programacion.fn_input_governance_semantic_probe_v1(p_pantalla_id,p_family_code,p_version_id);
    else
      v_sem:=programacion.fn_input_governance_semantic_probe_v1_cached_v1(p_pantalla_id,p_family_code,p_version_id,v_graph);
    end if;
    v_probe:=coalesce(v_sem->'probe','{}'::jsonb);
    v_complete:=coalesce((v_probe->>'component_count')::integer,0)>0
      and coalesce((v_probe->>'required_semantic_pending_count')::integer,0)=0
      and coalesce((v_probe->>'required_missing_component_count')::integer,0)=0
      and coalesce((v_probe->>'referential_integrity_failure_count')::integer,0)=0
      and coalesce((v_probe->>'required_semantic_resolved_count')::integer,0)
          +coalesce((v_probe->>'required_semantic_not_applicable_count')::integer,0)
          =coalesce((v_probe->>'required_element_count')::integer,0);

  elsif v_kind='CANONICAL_VISUAL_EVIDENCE' then
    v_evidence:=coalesce(v_graph->'canonical_contract'->'evidence','[]'::jsonb);
    v_count:=jsonb_array_length(v_evidence);
    select count(*) into v_vigente
    from jsonb_array_elements(v_evidence) e
    where coalesce((e->>'is_current')::boolean,false);
    v_probe:=jsonb_build_object('artifact_count',v_count,'current_count',v_vigente);
    v_complete:=v_count>0 and v_vigente=v_count;

  else
    return jsonb_build_object('handled',false,'family_code',p_family_code,'reason','UNKNOWN_PROBE_KIND_FAIL_CLOSED');
  end if;

  if not v_complete then
    return jsonb_build_object('handled',false,'family_code',p_family_code,'reason','COMPLETE_CRITERIA_NOT_MET','probe',v_probe,'criteria_ref','INPUT_FAMILY_POLICY_REGISTRY@N5.1');
  end if;

  return jsonb_build_object(
    'handled',true,'family_code',p_family_code,'level','COMPLETE','severity','P4','blocker_code',null,
    'probe',v_probe||jsonb_build_object('resolution_contract','INPUT_FAMILY_COMPLETE_CRITERIA_V1','criteria_ref','INPUT_FAMILY_POLICY_REGISTRY@N5.1','probe_kind',v_kind)
  );
end;
$function$

