create or replace function programacion.fn_input_freshness_delta(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_receipt jsonb;
  v_ref jsonb;
  v_current_receipt jsonb;
  v_current_observed jsonb;
  v_stored_sha text;
  v_current_sha text;
  v_state text;
  v_error text;
  v_changes jsonb := '[]'::jsonb;
  v_family_impacts jsonb := '[]'::jsonb;
  v_nodes jsonb := '[]'::jsonb;
  v_edges jsonb := '[]'::jsonb;
  v_changed_sources integer := 0;
  v_affected_families integer := 0;
  v_payload jsonb;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_FRESHNESS_DELTA_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status not in ('COMPLETED','BLOCKED') then
    raise exception 'INPUT_FRESHNESS_DELTA_REQUIRES_TERMINAL_RUN:%:%',p_run_id,v_run.status;
  end if;
  if jsonb_typeof(v_run.source_manifest)<>'array' or jsonb_array_length(v_run.source_manifest)=0 then
    raise exception 'INPUT_FRESHNESS_DELTA_REQUIRES_PINNED_SOURCE_MANIFEST:%',p_run_id;
  end if;

  for v_receipt in select value from jsonb_array_elements(v_run.source_manifest)
  loop
    v_ref:=v_receipt->'ref';
    v_stored_sha:=v_receipt->>'observed_sha256';
    v_current_sha:=null; v_error:=null; v_state:='CURRENT';
    begin
      if v_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
        v_current_observed:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
        v_current_sha:=programacion.fn_v09_sha256_jsonb(v_current_observed);
      else
        v_current_receipt:=programacion.fn_input_resolve_source_ref(v_ref,v_run.pantalla_id,v_run.version_id);
        v_current_sha:=coalesce(v_current_receipt->>'observed_sha256',programacion.fn_v09_sha256_jsonb(v_current_receipt->'observed'));
      end if;
      if v_current_sha is distinct from v_stored_sha then v_state:='STALE'; end if;
    exception when others then
      v_state:='RESOLUTION_ERROR';
      v_error:=sqlerrm;
    end;
    if v_state<>'CURRENT' then v_changed_sources:=v_changed_sources+1; end if;
    v_changes:=v_changes || jsonb_build_array(jsonb_build_object(
      'ref',v_ref,
      'stored_sha256',v_stored_sha,
      'current_sha256',v_current_sha,
      'state',v_state,
      'resolution_error',v_error
    ));
  end loop;

  with impacts as (
    select a.family_code,a.severity,a.applicability,
           count(*) filter(where c.value->>'state'<>'CURRENT') changed_ref_count,
           coalesce(jsonb_agg(jsonb_build_object(
             'ref',c.value->'ref',
             'state',c.value->>'state',
             'stored_sha256',c.value->>'stored_sha256',
             'current_sha256',c.value->>'current_sha256',
             'resolution_error',c.value->>'resolution_error'
           ) order by (c.value->'ref')::text) filter(where c.value->>'state'<>'CURRENT'),'[]'::jsonb) changed_refs
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(coalesce(a.source_refs,'[]'::jsonb)) sr(value)
    left join lateral (
      select x.value from jsonb_array_elements(v_changes) x(value)
      where x.value->'ref'=sr.value
    ) c on true
    where a.run_id=p_run_id
    group by a.family_code,a.severity,a.applicability
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'family_code',family_code,
      'severity',severity,
      'applicability',applicability,
      'state',case when changed_ref_count>0 then 'REVALIDATE' else 'CURRENT' end,
      'changed_source_ref_count',changed_ref_count,
      'changed_source_refs',changed_refs
    ) order by family_code),'[]'::jsonb),
    count(*) filter(where changed_ref_count>0)
  into v_family_impacts,v_affected_families
  from impacts;

  with source_nodes as (
    select jsonb_build_object(
      'id','source:'||substr(programacion.fn_v09_sha256_jsonb(value->'ref'),1,16),
      'type','SOURCE',
      'state',value->>'state',
      'ref',value->'ref',
      'stored_sha256',value->>'stored_sha256',
      'current_sha256',value->>'current_sha256'
    ) node
    from jsonb_array_elements(v_changes)
  ), family_nodes as (
    select jsonb_build_object(
      'id','family:'||(value->>'family_code'),
      'type','FAMILY',
      'state',value->>'state',
      'family_code',value->>'family_code',
      'severity',value->>'severity',
      'applicability',value->>'applicability'
    ) node
    from jsonb_array_elements(v_family_impacts)
  ), fixed_nodes as (
    select jsonb_build_object('id','run:'||p_run_id::text,'type','INPUT_READINESS_RUN','state',case when v_changed_sources>0 then 'STALE' else 'CURRENT' end,'run_id',p_run_id) node
    union all
    select jsonb_build_object('id','context_manifest:'||p_run_id::text,'type','INPUT_CONTEXT_MANIFEST','state',case when v_changed_sources>0 then 'REGENERATE' else 'CURRENT' end,'run_id',p_run_id)
  ), all_nodes as (
    select node from source_nodes union all select node from family_nodes union all select node from fixed_nodes
  )
  select coalesce(jsonb_agg(node order by node->>'id'),'[]'::jsonb) into v_nodes from all_nodes;

  with source_family as (
    select jsonb_build_object(
      'from','source:'||substr(programacion.fn_v09_sha256_jsonb(sr.value),1,16),
      'to','family:'||a.family_code,
      'relation','GOVERNS'
    ) edge
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(coalesce(a.source_refs,'[]'::jsonb)) sr(value)
    where a.run_id=p_run_id
  ), family_run as (
    select jsonb_build_object('from','family:'||a.family_code,'to','run:'||p_run_id::text,'relation','ASSESSED_IN') edge
    from programacion.input_family_assessments a where a.run_id=p_run_id
  ), run_manifest as (
    select jsonb_build_object('from','run:'||p_run_id::text,'to','context_manifest:'||p_run_id::text,'relation','PROJECTS_TO') edge
  ), all_edges as (
    select edge from source_family union all select edge from family_run union all select edge from run_manifest
  )
  select coalesce(jsonb_agg(edge order by edge->>'from',edge->>'to'),'[]'::jsonb) into v_edges from all_edges;

  v_payload:=jsonb_build_object(
    'graph_contract','INPUT_DEPENDENCY_GRAPH_V1',
    'shape_compatibility','programacion.traceability_graphs.nodes_edges',
    'run_id',p_run_id,
    'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,
    'stored_source_snapshot_sha256',v_run.source_snapshot_sha256,
    'run_state',case when v_changed_sources>0 then 'STALE' else 'CURRENT' end,
    'summary',jsonb_build_object(
      'source_count',jsonb_array_length(v_changes),
      'changed_source_count',v_changed_sources,
      'family_count',jsonb_array_length(v_family_impacts),
      'affected_family_count',v_affected_families,
      'selective_revalidation_required',v_affected_families>0
    ),
    'source_changes',v_changes,
    'family_impacts',v_family_impacts,
    'nodes',v_nodes,
    'edges',v_edges,
    'persistence_policy','ON_DEMAND_PROJECTION_NOT_PARALLEL_SOURCE_OF_TRUTH'
  );
  return v_payload || jsonb_build_object('graph_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;

revoke all on function programacion.fn_input_freshness_delta(bigint) from public;

insert into programacion.contratos(
  version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,
  especificacion,fail_closed,estado
)
select 18,
       'INPUT_FRESHNESS_DELTA_CONTRACT',
       'TRACEABILITY_PROJECTION',
       'Input selective freshness delta',
       'Proyección on-demand source→family para detectar qué familias requieren revalidación cuando cambia una fuente pinneada. Reutiliza source_refs/source_manifest y el shape nodes+edges sin persistir otro grafo.',
       45,
       null,
       jsonb_build_object(
         'schema_version',1,
         'contract_revision','1.0',
         'graph_contract','INPUT_DEPENDENCY_GRAPH_V1',
         'generation','ON_DEMAND_PROJECTION',
         'input_authority',jsonb_build_array('programacion.input_readiness_runs.source_manifest','programacion.input_family_assessments.source_refs'),
         'states',jsonb_build_array('CURRENT','STALE','RESOLUTION_ERROR','REVALIDATE','REGENERATE'),
         'fail_closed_on_unpinned_run',true,
         'no_parallel_graph_store',true,
         'compatible_shape','programacion.traceability_graphs.nodes_edges',
         'selective_revalidation',true
       ),
       true,
       'defined'
where not exists(
  select 1 from programacion.contratos
  where version_id=18 and contrato_codigo='INPUT_FRESHNESS_DELTA_CONTRACT'
);