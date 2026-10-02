-- N-5 / PAULO-170 — declarative COMPLETE criteria for zero-COMPLETE families.
-- Source-first. Reuses INPUT_FAMILY_POLICY_REGISTRY and the existing semantic classification chain.
-- Family-to-criterion mapping is data; resolver logic is generic by probe kind.

begin;

do $pre$
declare
  v_count integer;
  v_spec_md5 text;
begin
  select count(*), min(md5(especificacion::text))
    into v_count,v_spec_md5
  from programacion.contratos
  where id=46
    and version_id=19
    and contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    and fail_closed;

  if v_count <> 1 then
    raise exception 'N5_FAMILY_POLICY_REGISTRY_CARDINALITY:%',v_count;
  end if;
  if v_spec_md5 is distinct from '60f17665df3453a5b0bd9a72bdc8c2cf' then
    raise exception 'N5_FAMILY_POLICY_REGISTRY_PREIMAGE_DRIFT:%',v_spec_md5;
  end if;

  if md5(pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure))
       <> 'aa4e57b3fe9f1a3cd0041d8c86d96b1e' then
    raise exception 'N5_SEMANTIC_PROBE_V3_PREIMAGE_DRIFT';
  end if;
  if md5(pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure))
       <> '9d472c47da26eb6367a8de57b97aa1d6' then
    raise exception 'N5_SEMANTIC_PROBE_V3_CACHED_PREIMAGE_DRIFT';
  end if;
end
$pre$;

do $criteria$
declare
  v_spec jsonb;
  v_row record;
  v_count integer:=0;
begin
  select especificacion into v_spec
  from programacion.contratos
  where id=46
  for update;

  for v_row in
    select * from (values
      ('ASSETS_ICONS', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','SEMANTIC_PROBE_V1_ASSET_BINDINGS',
        'source_authority','ASSET_ICON_SEMANTIC_RESOLUTION_V1',
        'complete_if',jsonb_build_object('component_count_gt',0,'required_semantic_pending_count_eq',0,'required_missing_component_count_eq',0,'referential_integrity_failure_count_eq',0,'required_resolved_plus_na_eq_required',true),
        'partial_if','POSITIVE_SOURCE_AND_COMPLETE_FALSE','missing_if','NO_COMPONENT_SOURCE','fail_closed',true
      )),
      ('BROWSER_PLATFORM', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','RULES_REGEX_V1','rule_regex','(BROWSER|NAVEGADOR|COMPAT|PLATFORM)',
        'source_authority','SCREEN_CANONICAL_GRAPH.rules',
        'complete_if',jsonb_build_object('rule_count_gt',0,'all_matched_rules_vigente',true,'candidate_count_eq',0,'pending_decision_count_eq',0,'pending_marker_count_eq',0),
        'partial_if','MATCHED_RULES_PRESENT_AND_COMPLETE_FALSE','missing_if','NO_MATCHED_RULES','fail_closed',true
      )),
      ('DESIGN_SYSTEM', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','EXISTING_RESOLVER','source_authority','DESIGN_ELEMENT_BINDING_SEMANTICS_V1',
        'complete_if',jsonb_build_object('design_system_status_eq','VIGENTE','referential_integrity_failure_count_eq',0,'field_component_missing_count_eq',0,'variant_layout_missing_count_eq',0,'element_required_missing_component_count_eq',0),
        'fail_closed',true
      )),
      ('FEATURE_FLAGS', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','RULES_REGEX_V1','rule_regex','(FEATURE|FLAG|EXPERIMENT|ABT)',
        'source_authority','SCREEN_CANONICAL_GRAPH.rules',
        'complete_if',jsonb_build_object('rule_count_gt',0,'all_matched_rules_vigente',true,'candidate_count_eq',0,'pending_decision_count_eq',0,'pending_marker_count_eq',0),
        'partial_if','MATCHED_RULES_PRESENT_AND_COMPLETE_FALSE','missing_if','NO_MATCHED_RULES','fail_closed',true
      )),
      ('I18N_FORMATS', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','SEMANTIC_PROBE_V1_RULESET','source_authority','SCREEN_CANONICAL_GRAPH.rules','resolution_contract','I18N_FORMATS_RULESET_COMPLETION_V1',
        'complete_if',jsonb_build_object('rule_count_gt',0,'all_matched_rules_vigente',true,'candidate_count_eq',0,'pending_decision_count_eq',0,'pending_marker_count_eq',0),
        'partial_if','MATCHED_RULES_PRESENT_AND_COMPLETE_FALSE','missing_if','NO_MATCHED_RULES','fail_closed',true
      )),
      ('IDEMPOTENCY_CONCURRENCY', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','RULES_REGEX_V1','rule_regex','(IDEMP|CONCURRENC|SINGLE.?FLIGHT|X-IDEMPOTENCY)',
        'source_authority','SCREEN_CANONICAL_GRAPH.rules',
        'complete_if',jsonb_build_object('rule_count_gt',0,'all_matched_rules_vigente',true,'candidate_count_eq',0,'pending_decision_count_eq',0,'pending_marker_count_eq',0),
        'partial_if','MATCHED_RULES_PRESENT_AND_COMPLETE_FALSE','missing_if','NO_MATCHED_RULES','fail_closed',true
      )),
      ('LOADING_EMPTY_ERROR_STATES', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','SEMANTIC_PROBE_V1_RULESET','source_authority','SCREEN_CANONICAL_GRAPH.rules+canonical_contract.errors','resolution_contract','LOADING_EMPTY_ERROR_STATES_COMPLETION_V1',
        'complete_if',jsonb_build_object('rule_count_gt',0,'error_count_gt',0,'all_matched_rules_vigente',true,'candidate_count_eq',0,'pending_decision_count_eq',0,'pending_marker_count_eq',0),
        'partial_if','POSITIVE_SOURCE_AND_COMPLETE_FALSE','missing_if','RULES_OR_ERRORS_ABSENT','fail_closed',true
      )),
      ('OBSERVABILITY', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','EXISTING_RESOLVER','source_authority','OBSERVABILITY_SEMANTIC_RESOLUTION_V1',
        'complete_if',jsonb_build_object('semantic_rule_count_gt',0,'candidate_rule_count_eq',0,'dimensions_contract_count_gt',0,'activation_gate_contract_count_gt',0,'runtime_ready_provider_count_gt',0),
        'fail_closed',true
      )),
      ('PERFORMANCE', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','RULES_REGEX_V1','rule_regex','(LCP|PERFORMANCE|CORE WEB|OBS_004|ALR_005)',
        'source_authority','SCREEN_CANONICAL_GRAPH.rules',
        'complete_if',jsonb_build_object('rule_count_gt',0,'all_matched_rules_vigente',true,'candidate_count_eq',0,'pending_decision_count_eq',0,'pending_marker_count_eq',0),
        'partial_if','MATCHED_RULES_PRESENT_AND_COMPLETE_FALSE','missing_if','NO_MATCHED_RULES','fail_closed',true
      )),
      ('PRIVACY_PII', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','RULES_REGEX_V1','rule_regex','(PII|MASK|PRIVACY|PRIVACIDAD|RETEN|DATO)',
        'source_authority','SCREEN_CANONICAL_GRAPH.rules',
        'complete_if',jsonb_build_object('rule_count_gt',0,'all_matched_rules_vigente',true,'candidate_count_eq',0,'pending_decision_count_eq',0,'pending_marker_count_eq',0),
        'partial_if','MATCHED_RULES_PRESENT_AND_COMPLETE_FALSE','missing_if','NO_MATCHED_RULES','fail_closed',true
      )),
      ('TESTING_OBLIGATIONS', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','RULES_REGEX_V1','rule_regex','(TEST|PRUEBA|QA)',
        'source_authority','SCREEN_CANONICAL_GRAPH.rules',
        'complete_if',jsonb_build_object('rule_count_gt',0,'all_matched_rules_vigente',true,'candidate_count_eq',0,'pending_decision_count_eq',0,'pending_marker_count_eq',0),
        'partial_if','MATCHED_RULES_PRESENT_AND_COMPLETE_FALSE','missing_if','NO_MATCHED_RULES','fail_closed',true
      )),
      ('VISUAL_EVIDENCE', jsonb_build_object(
        'schema_version','input-family-complete-criteria/v1','probe_kind','CANONICAL_VISUAL_EVIDENCE','source_authority','SCREEN_CANONICAL_GRAPH.canonical_contract.evidence',
        'complete_if',jsonb_build_object('artifact_count_gt',0,'current_count_eq_artifact_count',true),
        'partial_if','ARTIFACTS_PRESENT_AND_NOT_ALL_CURRENT','missing_if','NO_ARTIFACTS','fail_closed',true
      ))
    ) as x(family_code,criteria)
  loop
    if not (v_spec->'families' ? v_row.family_code) then
      raise exception 'N5_FAMILY_NOT_IN_REGISTRY:%',v_row.family_code;
    end if;
    v_spec:=jsonb_set(v_spec,array['families',v_row.family_code,'complete_criteria_v1'],v_row.criteria,true);
    v_count:=v_count+1;
  end loop;

  if v_count<>12 then raise exception 'N5_CRITERIA_COUNT:%',v_count; end if;
  v_spec:=jsonb_set(v_spec,'{complete_criteria_contract_version}','"N5.1"'::jsonb,true);
  v_spec:=jsonb_set(v_spec,'{complete_criteria_family_count}','12'::jsonb,true);
  update programacion.contratos set especificacion=v_spec where id=46;
end
$criteria$;

create or replace function programacion.fn_input_governance_family_complete_probe_v1(
  p_pantalla_id integer,
  p_family_code text,
  p_version_id bigint default 19,
  p_graph jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $function$
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
$function$;

do $patch$
declare
  v_def text;
  v_new text;
begin
  v_def:=pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure);
  if md5(v_def)<>'aa4e57b3fe9f1a3cd0041d8c86d96b1e' then raise exception 'N5_V3_PATCH_PREIMAGE_DRIFT:%',md5(v_def); end if;
  v_new:=replace(v_def,
    '  v_implementation_pending boolean:=false;'||chr(10)||'begin',
    '  v_implementation_pending boolean:=false;'||chr(10)||'  v_family_complete jsonb;'||chr(10)||'begin'
  );
  v_new:=replace(v_new,
    '  v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);',
    '  v_base:=programacion.fn_input_governance_semantic_probe_v2(p_pantalla_id,p_family_code,p_version_id);'||chr(10)||
    '  v_family_complete:=programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,null);'||chr(10)||
    '  if coalesce((v_family_complete->>''handled'')::boolean,false) then return v_family_complete; end if;'
  );
  if v_new=v_def then raise exception 'N5_V3_PATCH_NOOP'; end if;
  execute v_new;

  v_def:=pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)'::regprocedure);
  if md5(v_def)<>'9d472c47da26eb6367a8de57b97aa1d6' then raise exception 'N5_V3_CACHED_PATCH_PREIMAGE_DRIFT:%',md5(v_def); end if;
  v_new:=replace(v_def,
    '  v_implementation_pending boolean:=false;'||chr(10)||'begin',
    '  v_implementation_pending boolean:=false;'||chr(10)||'  v_family_complete jsonb;'||chr(10)||'begin'
  );
  v_new:=replace(v_new,
    '  v_base:=programacion.fn_input_governance_semantic_probe_v2_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);',
    '  v_base:=programacion.fn_input_governance_semantic_probe_v2_cached_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);'||chr(10)||
    '  v_family_complete:=programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,p_family_code,p_version_id,p_graph);'||chr(10)||
    '  if coalesce((v_family_complete->>''handled'')::boolean,false) then return v_family_complete; end if;'
  );
  if v_new=v_def then raise exception 'N5_V3_CACHED_PATCH_NOOP'; end if;
  execute v_new;
end
$patch$;

do $tests$
declare
  v_json jsonb;
  v_graph jsonb;
  v_n integer;
begin
  select count(*) into v_n
  from jsonb_each((select especificacion->'families' from programacion.contratos where id=46)) f(key,value)
  where f.value ? 'complete_criteria_v1';
  if v_n<>12 then raise exception 'N5_CRITERIA_READBACK_COUNT:%',v_n; end if;

  v_graph:=jsonb_build_object('canonical_contract',jsonb_build_object(
    'rules',jsonb_build_array(jsonb_build_object('rule_code','PERFORMANCE_TEST','title','performance','description','LCP','status','VIGENTE','pending_decision',false,'config','{}'::jsonb)),
    'evidence','[]'::jsonb
  ));
  v_json:=programacion.fn_input_governance_family_complete_probe_v1(1,'PERFORMANCE',19,v_graph);
  if coalesce((v_json->>'handled')::boolean,false) is not true or v_json->>'level'<>'COMPLETE' then raise exception 'N5_GENERIC_POSITIVE_FAILED:%',v_json; end if;
  v_graph:=jsonb_set(v_graph,'{canonical_contract,rules,0,status}','"CANDIDATO"'::jsonb,false);
  v_json:=programacion.fn_input_governance_family_complete_probe_v1(1,'PERFORMANCE',19,v_graph);
  if coalesce((v_json->>'handled')::boolean,false) is true then raise exception 'N5_CANDIDATE_NEGATIVE_FAILED:%',v_json; end if;

  v_graph:=jsonb_build_object('canonical_contract',jsonb_build_object('rules','[]'::jsonb,'evidence',jsonb_build_array(jsonb_build_object('is_current',true),jsonb_build_object('is_current',true))));
  v_json:=programacion.fn_input_governance_family_complete_probe_v1(1,'VISUAL_EVIDENCE',19,v_graph);
  if coalesce((v_json->>'handled')::boolean,false) is not true then raise exception 'N5_VISUAL_POSITIVE_FAILED:%',v_json; end if;
  v_graph:=jsonb_set(v_graph,'{canonical_contract,evidence,1,is_current}','false'::jsonb,false);
  v_json:=programacion.fn_input_governance_family_complete_probe_v1(1,'VISUAL_EVIDENCE',19,v_graph);
  if coalesce((v_json->>'handled')::boolean,false) is true then raise exception 'N5_VISUAL_STALE_NEGATIVE_FAILED:%',v_json; end if;

  v_json:=programacion.fn_input_governance_family_complete_probe_v1(1,'DESIGN_SYSTEM',19,v_graph);
  if coalesce((v_json->>'handled')::boolean,false) is true then raise exception 'N5_EXISTING_RESOLVER_SHADOWED:%',v_json; end if;

  if position('like ''B2B-%''' in lower(pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure)))>0 then
    raise exception 'N5_V3_B2B_PREFIX_REGRESSION';
  end if;
end
$tests$;

comment on function programacion.fn_input_governance_family_complete_probe_v1(integer,text,bigint,jsonb) is
'N-5 generic COMPLETE promotion seam. Family criterion/source mapping is governed in INPUT_FAMILY_POLICY_REGISTRY; false/unresolved criteria remain fail-closed and delegate to existing classifier behavior.';

commit;
