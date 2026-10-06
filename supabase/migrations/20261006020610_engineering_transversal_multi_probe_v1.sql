
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{transversal_execution_v1,SHADOW_RUN,capabilities}',
  '["CURRENTNESS_AUTHORITY","CONTROL_EQUIVALENCE_JUDGE"]'::jsonb,
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M3.9';
