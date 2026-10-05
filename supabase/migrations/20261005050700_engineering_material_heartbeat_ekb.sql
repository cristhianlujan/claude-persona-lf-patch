update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{material_heartbeat_v1}',
  jsonb_build_object(
    'contract','ENGINEERING_MATERIAL_HEARTBEAT_V1',
    'entrypoint','programacion.fn_engineering_checkpoint_heartbeat_v1',
    'ledger','programacion.engineering_work_updates',
    'progress_authority','programacion.engineering_work_checkpoints',
    'required_for','MATERIAL_ACTIONS_ONLY',
    'phases',jsonb_build_array('ACTION_STARTED','STEP_STARTED','STEP_DONE','CONNECTOR_BLOCKED','RETRYING','ACTION_DONE','ACTION_FAILED'),
    'effective_at',now()
  ),true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';

insert into public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
  created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref
)
select
  gen_random_uuid(),
  'ENGINEERING-MATERIAL-HEARTBEAT-001',
  'ENGINEERING_GOVERNANCE',
  'Material execution can be healthy while chat UI appears stalled',
  'Long material steps and connector retries were invisible between action-spec selection and checkpoint persistence, making active work indistinguishable from a hang.',
  'Progress was persisted only at checkpoint boundaries, not at material action-step boundaries.',
  'bootstrap PASS -> material execution -> no visible durable stage -> apparent hang',
  'For material ACTION_SPEC steps, persist heartbeat stages in engineering_work_updates before and after each declared action. Record CONNECTOR_BLOCKED explicitly on connector rejection. Heartbeats never alter checkpoint progress percentage.',
  'PASS when Bootstrap V3 exposes latest material heartbeat and age; material actions can persist STARTED/DONE/BLOCKED states; terminal units preserve STOP_TERMINAL_DONE; checkpoint progress remains ledger-derived.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2',null,'ACTIVO',
  'supabase://programacion.fn_engineering_checkpoint_heartbeat_v1',now(),now(),
  'EXECUTION','{IG,ENGINEERING_AGENT}'::text[],'R5_EROSION_PROCESO',
  'PROCESS_DEPENDENT','IG material action visibility and connector-block diagnosis',
  'supabase://programacion.fn_engineering_checkpoint_heartbeat_v1'
where not exists (
  select 1 from public.lf_error_knowledge where codigo='ENGINEERING-MATERIAL-HEARTBEAT-001'
);
