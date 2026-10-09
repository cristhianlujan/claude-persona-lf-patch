
insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
  created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref
)
select
  'ENGINEERING-TRANSVERSAL-EXPLICIT-ROUTING-001',
  'ENGINEERING_GOVERNANCE',
  'Transversal execution must be declared structurally by the plan, not inferred from checkpoint title',
  'A checkpoint that requires a transversal capability must expose that requirement in unit metadata so bootstrap/action-spec compilation can route deterministically without semantic title search.',
  'Special execution routing was inferred from checkpoint_code plus mutable title text, causing T-EQUIV to disappear when the title no longer contained t-equiv.',
  'checkpoint title changes -> special capability branch no longer matches -> generic material/readback handler compiled',
  'Prefer unit_metadata.transversal_execution_v1[checkpoint]. mode=EXPLICIT when the plan knows the capability; mode=SELECT only when dynamic selection is truly required. Explicit declaration has precedence over title heuristics. Resolve dependencies from capability manifests and fail closed on unsupported handlers.',
  'PASS when M3.9/SHADOW_RUN title contains no T-EQUIV text, yet action_spec_v3 returns STRUCTURAL_TRANSVERSAL_EXPLICIT + CONTROL_EQUIVALENCE_JUDGE and execution_packet returns READY with CAPABILITY_BIND_RECEIPT -> RUN_TEST -> CHECKPOINT_TRANSITION; a non-transversal checkpoint remains byte-equivalent to legacy action_spec.',
  'HIGH',
  1,
  now(),
  now(),
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M3.9',
  'ACTIVO',
  '2026-10-05 pilot: M3.9 SHADOW_RUN plan field mode=EXPLICIT capabilities=[CONTROL_EQUIVALENCE_JUDGE]. Live compile PASS despite title="Ejecutar muestra fresca de 3 pantallas del proceso; comparación legacy no decisional". execution_packet READY with seq1 bind, seq2 RUN_TEST, seq3 transition. M4.2 NEG_PASS_WITHOUT_ORACLE legacy_unchanged=true.',
  now(),
  now(),
  'EXECUTION',
  array['IG','ENGINEERING_AGENT'],
  'R5_EROSION_PROCESO',
  'PROCESS_DEPENDENT',
  'Engineering bootstrap transversal routing',
  'supabase://programacion.engineering_plan_units+programacion.fn_engineering_checkpoint_action_spec_v3'
where not exists (
  select 1 from public.lf_error_knowledge
  where codigo='ENGINEERING-TRANSVERSAL-EXPLICIT-ROUTING-001'
);

update public.lf_error_knowledge
set
  ultima_vez=now(),
  updated_at=now(),
  evidencia='2026-10-05 pilot: M3.9 SHADOW_RUN plan field mode=EXPLICIT capabilities=[CONTROL_EQUIVALENCE_JUDGE]. Live compile PASS despite title="Ejecutar muestra fresca de 3 pantallas del proceso; comparación legacy no decisional". execution_packet READY with seq1 bind, seq2 RUN_TEST, seq3 transition. M4.2 NEG_PASS_WITHOUT_ORACLE legacy_unchanged=true.'
where codigo='ENGINEERING-TRANSVERSAL-EXPLICIT-ROUTING-001';
