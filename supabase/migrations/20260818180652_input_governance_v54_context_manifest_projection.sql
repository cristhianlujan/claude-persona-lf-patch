create or replace function programacion.fn_input_context_manifest(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_screen record;
  v_story_rule jsonb;
  v_family_statuses jsonb := '[]'::jsonb;
  v_open_families jsonb := '[]'::jsonb;
  v_unresolved jsonb := '[]'::jsonb;
  v_negative jsonb := '[]'::jsonb;
  v_tests jsonb := '[]'::jsonb;
  v_source_pins jsonb := '[]'::jsonb;
  v_handles jsonb := '[]'::jsonb;
  v_design_summary jsonb;
  v_api_summary jsonb;
  v_counts jsonb;
  v_payload jsonb;
  v_applicable_p0_story_open integer := 0;
  v_story_stage_open integer := 0;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then
    raise exception 'INPUT_CONTEXT_MANIFEST_RUN_NOT_FOUND:%',p_run_id;
  end if;
  if v_run.status <> 'COMPLETED' then
    raise exception 'INPUT_CONTEXT_MANIFEST_REQUIRES_COMPLETED_RUN:%:%',p_run_id,v_run.status;
  end if;
  if not programacion.fn_input_readiness_run_is_current(p_run_id) then
    raise exception 'INPUT_CONTEXT_MANIFEST_REQUIRES_CURRENT_RUN:%',p_run_id;
  end if;

  select p.id,p.codigo,p.nombre,p.version,p.module_code,p.objective
    into v_screen
  from lf_ops.pantallas p
  where p.id=v_run.pantalla_id;
  if not found then raise exception 'INPUT_CONTEXT_MANIFEST_SCREEN_NOT_FOUND:%',v_run.pantalla_id; end if;

  select jsonb_build_object(
    'rule_id',r.id,
    'rule_code',r.codigo,
    'story_ready_rule',r.valor_config->>'story_ready_rule',
    'readiness_levels',r.valor_config->'readiness_levels',
    'applicability_statuses',r.valor_config->'applicability_statuses',
    'source_authority_required',r.valor_config->'source_authority_required',
    'freshness_recompute_required',r.valor_config->'freshness_recompute_required'
  ) into v_story_rule
  from lf_ops.reglas r where r.id=v_run.universe_rule_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'family_code',a.family_code,
      'severity',a.severity,
      'applicability',a.applicability,
      'coverage',a.coverage_status,
      'well_defined',a.well_defined_status,
      'story',a.story_ready_status,
      'implementation',a.implementation_ready_status,
      'qa',a.qa_ready_status,
      'production',a.production_ready_status,
      'validator_outcome',a.validator_outcome
    ) order by a.family_code),'[]'::jsonb)
  into v_family_statuses
  from programacion.input_family_assessments a
  where a.run_id=p_run_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'family_code',a.family_code,
      'severity',a.severity,
      'applicability',a.applicability,
      'story',a.story_ready_status,
      'implementation',a.implementation_ready_status,
      'qa',a.qa_ready_status,
      'production',a.production_ready_status,
      'blockers',a.blockers
    ) order by
      case a.severity when 'P0' then 0 when 'P1' then 1 when 'P2' then 2 when 'P3' then 3 when 'P4' then 4 else 5 end,
      a.family_code),'[]'::jsonb)
  into v_open_families
  from programacion.input_family_assessments a
  where a.run_id=p_run_id
    and (
      a.applicability='UNRESOLVED'
      or (a.applicability='APPLICABLE' and (
        a.story_ready_status<>'READY'
        or a.implementation_ready_status not in ('READY','NOT_APPLICABLE')
        or a.qa_ready_status not in ('READY','NOT_APPLICABLE')
        or a.production_ready_status not in ('READY','NOT_APPLICABLE')
        or coalesce(jsonb_array_length(a.blockers),0)>0
      ))
    );

  select coalesce(jsonb_agg(jsonb_build_object(
      'family_code',a.family_code,
      'severity',a.severity,
      'rationale',a.rationale,
      'blockers',a.blockers
    ) order by a.family_code),'[]'::jsonb)
  into v_unresolved
  from programacion.input_family_assessments a
  where a.run_id=p_run_id and a.applicability='UNRESOLVED';

  select coalesce(jsonb_agg(x.value order by x.value::text),'[]'::jsonb)
  into v_negative
  from (
    select distinct e.value
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(coalesce(a.negative_requirements,'[]'::jsonb)) e(value)
    where a.run_id=p_run_id
  ) x;

  select coalesce(jsonb_agg(x.value order by x.value::text),'[]'::jsonb)
  into v_tests
  from (
    select distinct e.value
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(coalesce(a.test_obligations,'[]'::jsonb)) e(value)
    where a.run_id=p_run_id
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
      'ref',e.value->'ref',
      'observed_sha256',e.value->>'observed_sha256',
      'authority',e.value->'authority'
    ) order by (e.value->'ref')::text),'[]'::jsonb)
  into v_source_pins
  from jsonb_array_elements(v_run.source_manifest) e(value);

  with refs as (
    select distinct e.value ref
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(coalesce(a.source_refs,'[]'::jsonb)) e(value)
    where a.run_id=p_run_id
  ), handles as (
    select jsonb_build_object('kind','SOURCE_REF','ref',ref) h from refs
    union all
    select jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_run.pantalla_id,'version_id',v_run.version_id)
    union all
    select jsonb_build_object('kind','DESIGN_BINDING_GRAPH_V2','pantalla_id',v_run.pantalla_id)
    union all
    select jsonb_build_object('kind','API_CONTRACT_RESOLUTION_V1','pantalla_id',v_run.pantalla_id)
  )
  select coalesce(jsonb_agg(h order by h::text),'[]'::jsonb) into v_handles from handles;

  v_design_summary := programacion.fn_input_design_binding_graph_v2(v_run.pantalla_id)->'summary';
  select jsonb_build_object(
    'resolution_contract',a->>'resolution_contract',
    'behavioral_contract_rule_count',a->'behavioral_contract_rule_count',
    'materialized_contract_ref_count',a->'materialized_contract_ref_count',
    'broken_contract_ref_count',a->'broken_contract_ref_count',
    'has_behavioral_contract',a->'has_behavioral_contract',
    'has_resolvable_operation_schema_authority',a->'has_resolvable_operation_schema_authority',
    'implementation_gate',a->'implementation_gate'
  ) into v_api_summary
  from (select programacion.fn_input_api_contract_resolution(v_run.pantalla_id) a) q;

  select
    count(*) filter(where applicability='APPLICABLE' and severity='P0' and story_ready_status<>'READY'),
    count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and story_ready_status<>'READY')),
    jsonb_build_object(
      'families_total',count(*),
      'applicable',count(*) filter(where applicability='APPLICABLE'),
      'not_applicable',count(*) filter(where applicability='NOT_APPLICABLE'),
      'unresolved',count(*) filter(where applicability='UNRESOLVED'),
      'story_open_applicable',count(*) filter(where applicability='APPLICABLE' and story_ready_status<>'READY'),
      'implementation_open_applicable',count(*) filter(where applicability='APPLICABLE' and implementation_ready_status not in ('READY','NOT_APPLICABLE')),
      'qa_open_applicable',count(*) filter(where applicability='APPLICABLE' and qa_ready_status not in ('READY','NOT_APPLICABLE')),
      'production_open_applicable',count(*) filter(where applicability='APPLICABLE' and production_ready_status not in ('READY','NOT_APPLICABLE')),
      'validator_pass',count(*) filter(where validator_outcome='PASS')
    )
  into v_applicable_p0_story_open,v_story_stage_open,v_counts
  from programacion.input_family_assessments
  where run_id=p_run_id;

  v_payload:=jsonb_build_object(
    'manifest_contract','INPUT_CONTEXT_MANIFEST_V1',
    'run',jsonb_build_object(
      'run_id',v_run.id,
      'version_id',v_run.version_id,
      'contract_version',v_run.contract_version,
      'source_snapshot_sha256',v_run.source_snapshot_sha256,
      'source_observed_at',v_run.source_observed_at,
      'validator_identity',v_run.validator_identity,
      'validator_completed_at',v_run.validator_completed_at
    ),
    'screen',jsonb_build_object(
      'pantalla_id',v_screen.id,
      'screen_code',v_screen.codigo,
      'name',v_screen.nombre,
      'screen_version',v_screen.version,
      'module_code',v_screen.module_code,
      'objective',v_screen.objective
    ),
    'story_gate',jsonb_build_object(
      'canonical_rule',v_story_rule,
      'applicable_p0_story_open_count',v_applicable_p0_story_open,
      'canonical_no_applicable_p0_open_pass',v_applicable_p0_story_open=0,
      'story_stage_open_count',v_story_stage_open,
      'note','Canonical P0 gate and full story-stage openness are reported separately.'
    ),
    'counts',v_counts,
    'family_statuses',v_family_statuses,
    'open_families',v_open_families,
    'unresolved_applicability',v_unresolved,
    'negative_requirements',v_negative,
    'test_obligations',v_tests,
    'design_binding_summary',v_design_summary,
    'api_contract_summary',v_api_summary,
    'source_pins',v_source_pins,
    'retrieval_handles',v_handles,
    'materialization_policy',jsonb_build_object(
      'canonical_source_payloads_embedded',false,
      'primitive_token_values_embedded',false,
      'runtime_secrets_embedded',false,
      'real_pii_embedded',false,
      'retrieval_mode','REFERENCE_PLUS_JIT'
    )
  );

  return v_payload || jsonb_build_object('manifest_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;

revoke all on function programacion.fn_input_context_manifest(bigint) from public;

insert into programacion.contratos(
  version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,
  especificacion,fail_closed,estado
)
select 18,
       'INPUT_CONTEXT_MANIFEST_CONTRACT',
       'CONTEXT_MANIFEST',
       'Input Context Manifest on-demand',
       'Proyección mínima y reproducible de un input-readiness run validado/current para Story Creator y Context Pack. No duplica fuentes canónicas.',
       45,
       null,
       jsonb_build_object(
         'schema_version',1,
         'contract_revision','1.0',
         'manifest_contract','INPUT_CONTEXT_MANIFEST_V1',
         'generation','ON_DEMAND_PROJECTION',
         'requires',jsonb_build_array('RUN_COMPLETED','RUN_CURRENT','47_FAMILY_ASSESSMENTS','VALIDATOR_PASS'),
         'includes',jsonb_build_array('SCREEN_IDENTITY','READINESS_STATUSES','OPEN_BLOCKERS','UNRESOLVED_APPLICABILITY','NEGATIVE_REQUIREMENTS','TEST_OBLIGATIONS','SOURCE_PINS','RETRIEVAL_HANDLES','DESIGN_BINDING_SUMMARY','API_CONTRACT_SUMMARY','MANIFEST_SHA256'),
         'forbids',jsonb_build_array('RAW_CANONICAL_SOURCE_DUMPS','PRIMITIVE_TOKEN_VALUES','RUNTIME_SECRETS','REAL_PII','UNPINNED_SOURCE_CLAIMS'),
         'source_of_truth','REFERENCES_ONLY',
         'retrieval_mode','REFERENCE_PLUS_JIT',
         'story_gate_reporting',jsonb_build_object(
           'canonical_rule','NO_APPLICABLE_P0_OPEN',
           'also_report_full_story_stage_open_count',true,
           'do_not_conflate_validator_pass_with_ready',true
         ),
         'fail_closed',true
       ),
       true,
       'defined'
where not exists(
  select 1 from programacion.contratos
  where version_id=18 and contrato_codigo='INPUT_CONTEXT_MANIFEST_CONTRACT'
);