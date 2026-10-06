
update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{transversal_execution_v1,SHADOW_RUN,capabilities}',
  '[
    {"capability_code":"CURRENTNESS_AUTHORITY","handler":"CAPABILITY_CURRENT_READBACK"},
    {"capability_code":"TYPED_EVIDENCE_REGISTRY","handler":"CAPABILITY_CURRENT_READBACK"},
    {"capability_code":"CONTROL_EQUIVALENCE_JUDGE","handler":"T_EQUIV_SHADOW"}
  ]'::jsonb,
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M3.9';
