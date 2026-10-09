
update programacion.engineering_plan_units
set unit_metadata =
  unit_metadata ||
  jsonb_build_object(
    'transversal_execution_v1',
    coalesce(unit_metadata->'transversal_execution_v1','{}'::jsonb)
    || jsonb_build_object(
      'BENCH_VIA_TPERF',
      jsonb_build_object(
        'mode','EXPLICIT',
        'activation','DECLARED_ONLY',
        'capabilities','[{"capability_code":"PERFORMANCE_EXACT_SOURCE_BENCHMARK","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb,
        'dependency_resolution','MANIFEST_GRAPH',
        'execution_order','PLAN_ORDER_ONE_BY_ONE',
        'admission_required',false
      ),
      'PHASE_BUDGET',
      jsonb_build_object(
        'mode','EXPLICIT',
        'activation','DECLARED_ONLY',
        'capabilities','[{"capability_code":"TIMEOUT_PHASE_BUDGET_POLICY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb,
        'dependency_resolution','MANIFEST_GRAPH',
        'execution_order','PLAN_ORDER_ONE_BY_ONE',
        'admission_required',false
      )
    )
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M8.10';
