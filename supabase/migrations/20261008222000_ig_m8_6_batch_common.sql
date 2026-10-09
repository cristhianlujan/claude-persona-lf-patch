-- IG M8.6 BATCH_COMMON: single run-scoped eager assessment snapshot; no new objects.
CREATE OR REPLACE FUNCTION programacion.fn_input_context_manifest(p_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'lf_ops'
AS $function$
declare
  v_run programacion.input_readiness_runs%rowtype; v_screen record; v_story_rule jsonb;
  v_family_statuses jsonb:='[]'::jsonb; v_open_families jsonb:='[]'::jsonb; v_unresolved jsonb:='[]'::jsonb;
  v_negative jsonb:='[]'::jsonb; v_tests jsonb:='[]'::jsonb; v_source_pins jsonb:='[]'::jsonb; v_handles jsonb:='[]'::jsonb;
  v_design_summary jsonb; v_api_summary jsonb; v_counts jsonb; v_payload jsonb; v_stage jsonb;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_CONTEXT_MANIFEST_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status<>'COMPLETED' then raise exception 'INPUT_CONTEXT_MANIFEST_REQUIRES_COMPLETED_RUN:%:%',p_run_id,v_run.status; end if;
  if not programacion.fn_input_readiness_run_is_current(p_run_id) then raise exception 'INPUT_CONTEXT_MANIFEST_REQUIRES_CURRENT_RUN:%',p_run_id; end if;

  select p.id,p.codigo,p.nombre,p.version,p.module_code,p.objective into v_screen from lf_ops.pantallas p where p.id=v_run.pantalla_id;
  if not found then raise exception 'INPUT_CONTEXT_MANIFEST_SCREEN_NOT_FOUND:%',v_run.pantalla_id; end if;

  select jsonb_build_object('rule_id',r.id,'rule_code',r.codigo,'story_ready_rule',r.valor_config->>'story_ready_rule','family_count',r.valor_config->'family_count','allowed_statuses',r.valor_config->'allowed_statuses','severity_model',r.valor_config->'severity_model','source_precedence',r.valor_config->'source_precedence','no_invention',r.valor_config->'no_invention','no_silent_omission',r.valor_config->'no_silent_omission','readback_required',r.valor_config->'readback_required') into v_story_rule from lf_ops.reglas r where r.id=v_run.universe_rule_id;

  -- M8.6 BATCH_COMMON: read the same governed family facts once for this run.
  -- PostgreSQL materializes the snapshot once, preserving the old independent
  -- aggregations, JSON order and sha256 semantics in each downstream view.
  with assessments as materialized (
    select * from programacion.input_family_assessments a where a.run_id=p_run_id
  ), common as (
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'family_code',a.family_code,'severity',a.severity,'applicability',a.applicability,
        'coverage',a.coverage_status,'well_defined',a.well_defined_status,
        'story',a.story_ready_status,'implementation',a.implementation_ready_status,
        'qa',a.qa_ready_status,'production',a.production_ready_status,
        'validator_outcome',a.validator_outcome) order by a.family_code),'[]'::jsonb)
          as family_statuses,
      coalesce(jsonb_agg(jsonb_build_object(
        'family_code',a.family_code,'severity',a.severity,'applicability',a.applicability,
        'story',a.story_ready_status,'implementation',a.implementation_ready_status,
        'qa',a.qa_ready_status,'production',a.production_ready_status,'blockers',a.blockers)
        order by case a.severity when 'P0' then 0 when 'P1' then 1
          when 'P2' then 2 when 'P3' then 3 when 'P4' then 4 else 5 end,
          a.family_code)
        filter (where a.applicability='UNRESOLVED'
          or (a.applicability='APPLICABLE'
            and (a.story_ready_status<>'READY'
              or a.implementation_ready_status not in ('READY','NOT_APPLICABLE')
              or a.qa_ready_status not in ('READY','NOT_APPLICABLE')
              or a.production_ready_status not in ('READY','NOT_APPLICABLE')
              or coalesce(jsonb_array_length(a.blockers),0)>0))),'[]'::jsonb)
          as open_families,
      coalesce(jsonb_agg(jsonb_build_object(
        'family_code',a.family_code,'severity',a.severity,
        'rationale',a.rationale,'blockers',a.blockers)
        order by a.family_code)
        filter (where a.applicability='UNRESOLVED'),'[]'::jsonb) as unresolved,
      jsonb_build_object(
        'families_total',count(*),
        'applicable',count(*) filter(where a.applicability='APPLICABLE'),
        'not_applicable',count(*) filter(where a.applicability='NOT_APPLICABLE'),
        'unresolved',count(*) filter(where a.applicability='UNRESOLVED'),
        'story_open_applicable',count(*) filter(where a.applicability='APPLICABLE' and a.story_ready_status<>'READY'),
        'implementation_open_applicable',count(*) filter(where a.applicability='APPLICABLE' and a.implementation_ready_status not in ('READY','NOT_APPLICABLE')),
        'qa_open_applicable',count(*) filter(where a.applicability='APPLICABLE' and a.qa_ready_status not in ('READY','NOT_APPLICABLE')),
        'production_open_applicable',count(*) filter(where a.applicability='APPLICABLE' and a.production_ready_status not in ('READY','NOT_APPLICABLE')),
        'validator_pass',count(*) filter(where a.validator_outcome='PASS')) as counts
    from assessments a
  ), negative_facts as (
    select coalesce(jsonb_agg(z.value order by z.value::text),'[]'::jsonb) as negative_requirements
    from (select distinct e.value from assessments a
      cross join lateral jsonb_array_elements(coalesce(a.negative_requirements,'[]'::jsonb)) e(value)) z
  ), test_facts as (
    select coalesce(jsonb_agg(z.value order by z.value::text),'[]'::jsonb) as test_obligations
    from (select distinct e.value from assessments a
      cross join lateral jsonb_array_elements(coalesce(a.test_obligations,'[]'::jsonb)) e(value)) z
  ), refs as (
    select distinct e.value ref from assessments a
    cross join lateral jsonb_array_elements(coalesce(a.source_refs,'[]'::jsonb)) e(value)
  ), handles as (
    select jsonb_build_object('kind','SOURCE_REF','ref',ref) h from refs
    union all select jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_run.pantalla_id,'version_id',v_run.version_id)
    union all select jsonb_build_object('kind','DESIGN_BINDING_GRAPH_V3','pantalla_id',v_run.pantalla_id)
    union all select jsonb_build_object('kind','API_CONTRACT_RESOLUTION_V1','pantalla_id',v_run.pantalla_id)
    union all select jsonb_build_object('kind','INPUT_FRESHNESS_DELTA_V1','run_id',v_run.id)
  ), handle_facts as (
    select coalesce(jsonb_agg(h order by h::text),'[]'::jsonb) retrieval_handles
    from handles
  )
  select c.family_statuses,c.open_families,c.unresolved,
    n.negative_requirements,t.test_obligations,h.retrieval_handles,c.counts
    into v_family_statuses,v_open_families,v_unresolved,
      v_negative,v_tests,v_handles,v_counts
  from common c cross join negative_facts n cross join test_facts t cross join handle_facts h;

  select coalesce(jsonb_agg(jsonb_build_object(
    'ref',e.value->'ref','observed_sha256',e.value->>'observed_sha256','authority',e.value->'authority')
    order by (e.value->'ref')::text),'[]'::jsonb)
    into v_source_pins from jsonb_array_elements(v_run.source_manifest) e(value);

  v_design_summary:=programacion.fn_input_design_binding_graph_v2(v_run.pantalla_id)->'summary';
  select jsonb_build_object('resolution_contract',a->>'resolution_contract','behavioral_contract_rule_count',a->'behavioral_contract_rule_count','materialized_contract_ref_count',a->'materialized_contract_ref_count','broken_contract_ref_count',a->'broken_contract_ref_count','has_behavioral_contract',a->'has_behavioral_contract','has_resolvable_operation_schema_authority',a->'has_resolvable_operation_schema_authority','implementation_gate',a->'implementation_gate') into v_api_summary from (select programacion.fn_input_api_contract_resolution(v_run.pantalla_id) a) q;

  v_stage:=programacion.fn_input_stage_gate_summary(p_run_id);
  v_payload:=jsonb_build_object(
    'manifest_contract','INPUT_CONTEXT_MANIFEST_V2',
    'run',jsonb_build_object('run_id',v_run.id,'version_id',v_run.version_id,'contract_version',v_run.contract_version,'contract_revision',v_run.contract_revision,'contract_snapshot_sha256',v_run.contract_snapshot_sha256,'source_snapshot_sha256',v_run.source_snapshot_sha256,'source_observed_at',v_run.source_observed_at,'validator_identity',v_run.validator_identity,'validator_completed_at',v_run.validator_completed_at),
    'screen',jsonb_build_object('pantalla_id',v_screen.id,'screen_code',v_screen.codigo,'name',v_screen.nombre,'screen_version',v_screen.version,'module_code',v_screen.module_code,'objective',v_screen.objective),
    'story_gate',jsonb_build_object('canonical_rule',v_story_rule,'canonical_story_gate_pass',v_stage->'canonical_story_gate_pass','story_stage_open_count',v_stage#>'{summary,story_stage_open}','note','Canonical story gate is NO_STORY_STAGE_OPEN; validator PASS is evidence integrity, not readiness.'),
    'counts',v_counts,'stage_gate_summary',v_stage,'family_statuses',v_family_statuses,'open_families',v_open_families,'unresolved_applicability',v_unresolved,'negative_requirements',v_negative,'test_obligations',v_tests,'design_binding_summary',v_design_summary,'api_contract_summary',v_api_summary,'source_pins',v_source_pins,'retrieval_handles',v_handles,
    'materialization_policy',jsonb_build_object('canonical_source_payloads_embedded',false,'primitive_token_values_embedded',false,'runtime_secrets_embedded',false,'real_pii_embedded',false,'retrieval_mode','REFERENCE_PLUS_JIT'));
  return v_payload||jsonb_build_object('manifest_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;
