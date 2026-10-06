
update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  unit_metadata,
  '{transversal_execution_v1,SHADOW_RUN,capabilities}',
  '["CONTROL_EQUIVALENCE_JUDGE"]'::jsonb,
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M3.9';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
  created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref
)
select
  'ENGINEERING-TRANSVERSAL-MULTI-CAPABILITY-001',
  'ENGINEERING_GOVERNANCE',
  'Transversal execution must preserve multiple selected capabilities end-to-end',
  'Explicit transversal routing may select more than one capability; action spec, binder and execution packet must preserve the ordered set instead of collapsing to a single capability_execution object.',
  'The first structural pilot supported exactly one capability and the existing binder/packet contract also reads one capability_execution object.',
  'capabilities array length > 1 -> structural router cannot compile handler -> BLOCK_TRANSVERSAL_CAPABILITY_HANDLER_MISSING',
  'Represent multi-capability execution as an ordered capability_executions array, expand manifest dependencies, deduplicate, topologically order, and bind/execute each capability with its own identity and receipt. Preserve the existing READ|WRITE_DB|WRITE_GIT|RUN_TEST router surface; do not invent a fifth execution capability.',
  'PASS only when an explicit plan with at least two capabilities compiles both in deterministic order, produces separate binding identities/receipts, executes only supported handlers, and a single-capability plan remains backward compatible.',
  'HIGH',1,now(),now(),
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M3.9',
  'ACTIVO',
  '2026-10-05 negative probe: M3.9 SHADOW_RUN capabilities=[CURRENTNESS_AUTHORITY,CONTROL_EQUIVALENCE_JUDGE] returned BLOCK_TRANSVERSAL_CAPABILITY_HANDLER_MISSING. Binder core and execution_packet each consume one capability_execution object. Probe restored to CONTROL_EQUIVALENCE_JUDGE only.',
  now(),now(),'EXECUTION',array['IG','ENGINEERING_AGENT'],
  'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
  'Engineering bootstrap transversal multi-capability routing',
  'supabase://programacion.fn_engineering_checkpoint_action_spec_v3+programacion.fn_engineering_capability_bind_receipt_core_v1+programacion.fn_engineering_execution_packet_from_spec_v1'
where not exists (
  select 1 from public.lf_error_knowledge
  where codigo='ENGINEERING-TRANSVERSAL-MULTI-CAPABILITY-001'
);
