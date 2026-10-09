-- IG scope correction (recurrence of IG-CROSS-WORKSTREAM-POST-PASE-BLEED-001), pending units M9.8 / M9.12 / M8.11 / M10.13.
-- Their exit criteria and checkpoint titles still require CLOSURE_GATE / FINAL_EVIDENCE of the disabled POST_PASE/SADM workstream.
-- No execution is routed to those controls (transversal activation checked); the defect is the canonical text, which the test-authoring
-- checkpoints use as semantic authority. Checkpoint codes are kept for traceability; the mechanism becomes IG-owned and ledger-derived.
do $preflight$
declare v_u int; v_c int;
begin
  select count(*) into v_u from programacion.engineering_plan_units
   where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code in ('M9.8','M9.12','M8.11','M10.13');
  select count(*) into v_c from programacion.engineering_plan_units pu
   join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
   where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     and (pu.unit_code,c.checkpoint_code) in (('M9.8','CLOSURE_GATE_ASIS'),('M9.12','PROMOTION_ASIS'),('M9.12','CLOSURE_GATE_CONSUME'),('M8.11','GATE_READBACK'),('M10.13','CLOSURE_GATE_REUSE'));
  if v_u<>4 or v_c<>5 then raise exception 'IG_POST_PASE_TEXT_BLEED_PREFLIGHT_FAILED units=% checkpoints=%',v_u,v_c; end if;
  if exists (select 1 from programacion.engineering_plan_units pu
              join programacion.engineering_work_items w on w.id=pu.work_item_id
              cross join lateral jsonb_each(coalesce(pu.unit_metadata->'transversal_execution_v1','{}'::jsonb)) e
             where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code in ('M9.8','M9.12','M8.11','M10.13')
               and e.value->>'activation'='ACTIVE' and e.value::text ~ '(CLOSURE_GATE|FINAL_EVIDENCE|POST_PASE)') then
    raise exception 'IG_POST_PASE_TEXT_BLEED_ACTIVE_ROUTING_FOUND';
  end if;
end
$preflight$;

do $apply$
begin
  update programacion.engineering_plan_units
  set exit_criterion = case unit_code
    when 'M9.8' then
      'Shadow Gate evaluado de forma determinista sobre el manifest de evidencia derivado del ledger de IG, con controles: 0 errores, 0 D4 sin explicar, 0 UNRESOLVED, 0 falso PASS, 47/47, M7 PASS; veredicto PASS persistido. El workstream POST_PASE/SADM queda fuera de alcance mientras permanezca desactivado.'
    when 'M9.12' then
      'Cutover Readiness Receipt CUTOVER_READY derivado del manifest del ledger de IG (M9.8 PASS, M9.10 drill PASS, M9.11 soak) y ligado al SHA del bundle M9.0; nunca PRODUCTION_ACTIVE. El workstream POST_PASE/SADM queda fuera de alcance mientras permanezca desactivado.'
    when 'M10.13' then
      replace(exit_criterion,
        'y consumo de CLOSURE_GATE/ARCHITECTURE_CLOSURE de Super Admin (no gate propio)',
        'y cierre evaluado de forma determinista sobre el ledger de IG (sin gate propio; el workstream POST_PASE/SADM queda fuera de alcance mientras permanezca desactivado)')
    else exit_criterion
  end
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code in ('M9.8','M9.12','M10.13');

  update programacion.engineering_work_checkpoints c
  set title = case pu.unit_code||'/'||c.checkpoint_code
    when 'M9.8/CLOSURE_GATE_ASIS' then 'Readback AS-IS del ledger de IG y de los receipts de controles reutilizables (sin depender del workstream POST_PASE/SADM)'
    when 'M9.12/PROMOTION_ASIS' then 'Readback AS-IS: programacion.promotions vacío y capacidades de cierre disponibles'
    when 'M9.12/CLOSURE_GATE_CONSUME' then 'Receipt CUTOVER_READY derivado del manifest del ledger de IG (sin gate propio ni workstream POST_PASE)'
    when 'M8.11/GATE_READBACK' then 'Readback terminal: gate de regresión registrado como control del ledger de IG'
    when 'M10.13/CLOSURE_GATE_REUSE' then 'Cierre evaluado de forma determinista sobre el ledger de IG (sin gate propio)'
    else c.title end,
      updated_at=now(), updated_by_execution_id='IG_POST_PASE_SCOPE_CORRECTION_V3'
  from programacion.engineering_plan_units pu
  where pu.work_item_id=c.work_item_id and pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and (pu.unit_code,c.checkpoint_code) in (('M9.8','CLOSURE_GATE_ASIS'),('M9.12','PROMOTION_ASIS'),('M9.12','CLOSURE_GATE_CONSUME'),('M8.11','GATE_READBACK'),('M10.13','CLOSURE_GATE_REUSE'));
end
$apply$;

do $selftest$
declare v_bad int;
begin
  select count(*) into v_bad from programacion.engineering_plan_units pu
   where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code in ('M9.8','M9.12','M10.13')
     and pu.exit_criterion ~ '(CLOSURE_GATE|FINAL_EVIDENCE)';
  if v_bad<>0 then raise exception 'IG_POST_PASE_TEXT_BLEED_SELFTEST_EXIT:%',v_bad; end if;
  select count(*) into v_bad from programacion.engineering_plan_units pu
   join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
   where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     and (pu.unit_code,c.checkpoint_code) in (('M9.8','CLOSURE_GATE_ASIS'),('M9.12','PROMOTION_ASIS'),('M9.12','CLOSURE_GATE_CONSUME'),('M8.11','GATE_READBACK'),('M10.13','CLOSURE_GATE_REUSE'))
     and c.title ~ '(CLOSURE_GATE|FINAL_EVIDENCE)';
  if v_bad<>0 then raise exception 'IG_POST_PASE_TEXT_BLEED_SELFTEST_TITLE:%',v_bad; end if;
end
$selftest$;
