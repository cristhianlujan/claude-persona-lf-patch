
with decl(unit_code,checkpoint_code,capabilities) as (
  values
    ('M4.4','INDEPENDENCE_FROM_TINDEP',
      '[{"capability_code":"INDEPENDENT_ASSURANCE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M4.5','REGISTRY_SOURCE_RESOLUTION',
      '[{"capability_code":"SOURCE_RESOLUTION_POLICY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M4.7','REUSE_EVIDENCE_LEDGER',
      '[{"capability_code":"EVIDENCE_LEDGER","handler":"DECLARED_HANDLER_PENDING"},{"capability_code":"TYPED_EVIDENCE_REGISTRY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M4.10','SHADOW_BY_MODULE',
      '[{"capability_code":"CONTROL_EQUIVALENCE_JUDGE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M8.8','BUDGET_FROM_TPERF',
      '[{"capability_code":"TIMEOUT_PHASE_BUDGET_POLICY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M8.10','BENCH_VIA_TPERF',
      '[{"capability_code":"PERFORMANCE_EXACT_SOURCE_BENCHMARK","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M8.10','PHASE_BUDGET',
      '[{"capability_code":"TIMEOUT_PHASE_BUDGET_POLICY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M8.11','RECEIPT_MODEL_REUSE',
      '[{"capability_code":"EVIDENCE_LEDGER","handler":"DECLARED_HANDLER_PENDING"},{"capability_code":"TYPED_EVIDENCE_REGISTRY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M9.3','TEQUIV_CONSUMPTION',
      '[{"capability_code":"CONTROL_EQUIVALENCE_JUDGE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M9.5','TEQUIV_ENGINE_BINDING',
      '[{"capability_code":"CONTROL_EQUIVALENCE_JUDGE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M9.7','TYPED_SCHEMA',
      '[{"capability_code":"TYPED_EVIDENCE_REGISTRY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M10.11','REUSE_RETIREMENT_GOV',
      '[{"capability_code":"ASSET_RETIREMENT_GOVERNANCE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('M10.13','GIT_RUNTIME_PARITY',
      '[{"capability_code":"MIGRATION_SOURCE_PARITY","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb),
    ('N-6','INDEPENDENT_JUDGE',
      '[{"capability_code":"INDEPENDENT_ASSURANCE","handler":"DECLARED_HANDLER_PENDING"}]'::jsonb)
)
update programacion.engineering_plan_units pu
set unit_metadata =
  pu.unit_metadata ||
  jsonb_build_object(
    'transversal_execution_v1',
    coalesce(pu.unit_metadata->'transversal_execution_v1','{}'::jsonb)
    || jsonb_build_object(
      d.checkpoint_code,
      jsonb_build_object(
        'mode','EXPLICIT',
        'activation','DECLARED_ONLY',
        'capabilities',d.capabilities,
        'dependency_resolution','MANIFEST_GRAPH',
        'execution_order','PLAN_ORDER_ONE_BY_ONE',
        'admission_required',false
      )
    )
  )
from decl d
where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code=d.unit_code;
