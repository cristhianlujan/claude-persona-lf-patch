-- Remove foreign POST_PASE/SADM closure requirements from IG macrolot exit criteria.
-- The checkpoint code is retained for traceability, but its title explicitly records
-- that it is NOT_APPLICABLE while the owning POST_PASE workstream is disabled.

do $preflight$
declare
  v_units int;
  v_checkpoints int;
begin
  select count(*) into v_units
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and unit_code in ('M5.10','M6.13');

  select count(*) into v_checkpoints
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code in ('M5.10','M6.13')
    and c.checkpoint_code='FINAL_EVIDENCE_SADM';

  if v_units<>2 or v_checkpoints<>2 then
    raise exception 'IG_POST_PASE_EXIT_GATE_PREFLIGHT_FAILED units=% checkpoints=%',v_units,v_checkpoints;
  end if;
end
$preflight$;

update programacion.engineering_plan_units
set exit_criterion = case unit_code
  when 'M5.10' then
    'Las 10 unidades M5 (M5.0–M5.9) DONE; evidencia de cierre IG derivada del ledger/checkpoints; evento HANDOFF de cierre M5 persistido; readback independiente del Curator. POST_PASE/SADM queda fuera de alcance mientras su workstream permanezca desactivado.'
  when 'M6.13' then
    'Unidades M6 (M6.0–M6.12 y T-CURR/T-INVAL/T-EVID que absorben M6.8/M6.11) DONE; evidencia de cierre IG derivada del ledger/checkpoints; evento HANDOFF de cierre M6; readback independiente de receipts IG. POST_PASE/SADM queda fuera de alcance mientras su workstream permanezca desactivado.'
  else exit_criterion
end
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code in ('M5.10','M6.13');

update programacion.engineering_work_checkpoints c
set title='Control externo POST_PASE/SADM — NOT_APPLICABLE mientras el workstream permanezca desactivado',
    updated_at=now(),
    updated_by_execution_id='IG_POST_PASE_SCOPE_CORRECTION_V1'
from programacion.engineering_plan_units pu
where pu.work_item_id=c.work_item_id
  and pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and pu.unit_code in ('M5.10','M6.13')
  and c.checkpoint_code='FINAL_EVIDENCE_SADM';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-CROSS-WORKSTREAM-POST-PASE-BLEED-001',
  'PLAN_SCOPE',
  'IG closure must not execute disabled POST_PASE/SADM workstream controls',
  'M5.10 and M6.13 inherited POST_PASE_ROUTER/POST_PASE_ORCHESTRATOR and FINAL_EVIDENCE/CLOSURE_GATE requirements from a separate Super Admin workstream.',
  'CROSS_WORKSTREAM_REQUIREMENT_COPIED_INTO_IG_CLOSURE',
  'IG_MACROLOT_CLOSURE_REQUIRES_POST_PASE_WHILE_POST_PASE_IS_DISABLED',
  'Keep POST_PASE references DECLARED_ONLY for traceability. Do not include FINAL_EVIDENCE/CLOSURE_GATE from the disabled external workstream in IG exit criteria. The retained checkpoint is NOT_APPLICABLE while that workstream remains disabled.',
  'PASS when M5.10 and M6.13 POST_PASE transversal activation is DECLARED_ONLY, their exit criteria contain no active FINAL_EVIDENCE/CLOSURE_GATE requirement, and FINAL_EVIDENCE_SADM is treated as NOT_APPLICABLE rather than executed.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.engineering_plan_units/M5.10,M6.13',
  'DESIGN',
  array['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'IG closure scope boundary',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

do $selftest$
declare
  v_bad_exit int;
  v_bad_activation int;
begin
  select count(*) into v_bad_exit
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and unit_code in ('M5.10','M6.13')
    and (
      exit_criterion ilike '%evidencia final%FINAL_EVIDENCE%'
      or exit_criterion ilike '%evidencia final vía FINAL_EVIDENCE/CLOSURE_GATE%'
    );

  select count(*) into v_bad_activation
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and unit_code in ('M5.10','M6.13')
    and unit_metadata#>>'{transversal_execution_v1,FINAL_EVIDENCE_SADM,activation}'<>'DECLARED_ONLY';

  if v_bad_exit<>0 or v_bad_activation<>0 then
    raise exception 'IG_POST_PASE_EXIT_GATE_SELFTEST_FAILED bad_exit=% bad_activation=%',v_bad_exit,v_bad_activation;
  end if;
end
$selftest$;
