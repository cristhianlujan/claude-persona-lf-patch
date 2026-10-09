-- M8.11 contract + governed owner deferral, same lot.
-- Scope only M8.11 contract metadata and current checkpoint labels.
-- No test receipt may be forged; checkpoint state transitions remain canonical.
DO $m811$
DECLARE
  v_owner_refs integer; v_abs_ok boolean; v_unit integer; v_checkpoints integer;
  v_policy text := 'github://cristhianlujan/claude-persona-lf-patch/docs/ig_refactor/m8_11_relative_regression_defer_v1.json#blob=364f5a2ba9c355850f23267156fcb525bd7e4a85';
  v_deferred jsonb;
BEGIN
  SELECT count(*) INTO v_owner_refs
  FROM programacion.engineering_work_checkpoints c
  WHERE c.work_item_id=254 AND c.checkpoint_code IN ('BENCH_VIA_TPERF','PHASE_BUDGET','SLO_READBACK')
    AND c.status='NOT_APPLICABLE' AND c.evidence_ref LIKE 'owner-decision://2026-10-09%';
  IF v_owner_refs<>3 THEN RAISE EXCEPTION 'M811_OWNER_DEFER_PROOF_MISSING:%',v_owner_refs; END IF;

  SELECT EXISTS(
    SELECT 1 FROM programacion.engineering_work_checkpoints c
    WHERE c.work_item_id=254 AND c.checkpoint_code='SLO_OVER_LIMIT_NEGATIVE'
      AND c.status='DONE' AND c.assertion_receipt->>'passed'='true'
  ) INTO v_abs_ok;
  IF NOT v_abs_ok THEN RAISE EXCEPTION 'M811_M810_NEGATIVE_GATE_NOT_PROVEN'; END IF;

  SELECT count(*) INTO v_unit
  FROM programacion.engineering_plan_units pu
  WHERE pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND pu.unit_code='M8.11'
    AND pu.id=67 AND pu.work_item_id=255 AND pu.disposition='ASSIGNED'
    AND pu.exit_criterion LIKE '%gate de regresión%';
  SELECT count(*) INTO v_checkpoints FROM programacion.engineering_work_checkpoints c
  WHERE c.work_item_id=255 AND
    ((c.checkpoint_code='REGRESSION_GATE_NEGATIVE' AND c.status='IN_PROGRESS') OR
     (c.checkpoint_code='GATE_READBACK' AND c.status='PENDING'));
  IF v_unit<>1 OR v_checkpoints<>2 THEN
     RAISE EXCEPTION 'M811_CONTRACT_PREFLIGHT_DRIFT:unit=% checkpoints=%',v_unit,v_checkpoints;
  END IF;

  v_deferred:=jsonb_build_object(
    'schema_version','IG_M8_11_RELATIVE_REGRESSION_DEFERRAL_V1',
    'policy_ref',v_policy,
    'owner','SUPER_ADMIN',
    'decision','DEFER_RELATIVE_P95_TO_POST_DEPLOY_BASELINE',
    'owner_evidence_ref','supabase://programacion.engineering_work_checkpoints/M8.10/BENCH_VIA_TPERF',
    'obligation_code','IG_M8_11_RELATIVE_P95_REGRESSION_GATE',
    'obligation_status','OPEN_DEFERRED_NOT_PASSED',
    'trigger','AFTER_INITIAL_PRODUCTION_DEPLOYMENT_AND_AUTHORIZED_COMPARABLE_BASELINE',
    'baseline_required',true,'relative_tolerance_authorized',false,
    'active_absolute_slo_negative_ref','M8.10/SLO_OVER_LIMIT_NEGATIVE',
    'current_negative_test','FAILED_EXPECTED_DIAGNOSTIC_NOT_PASS',
    'test_evidence_ref','github://cristhianlujan/claude-persona-lf-patch/pull/2128',
    'required_closure_evidence',jsonb_build_array(
      'COMPARABLE_EXACT_RELEASE_AND_COHORT_P95','OWNER_APPROVED_NUMERIC_TOLERANCE',
      'INJECTED_REGRESSION_REJECTED','POSITIVE_NON_REGRESSION_ACCEPTED','LEDGER_GIT_DB_PARITY'),
    'no_production_activation',true,'no_synthetic_pass',true);

  UPDATE programacion.engineering_plan_units pu
  SET exit_criterion=
    'IG performance receipts por run publicados y trazados al release; reutilizacion de capacidades evidenciada. '||
    'SLO absoluto M8.10 negativo conservado con asercion real. '||
    'Regresion p95 relativa frente a baseline M8.10: OBLIGACION DIFERIDA ABIERTA, no PASS, '||
    'hasta primera puesta en produccion y baseline comparable con tolerancia numerica autorizada. '||
    'La unidad solo cierra su alcance predeploy al registrar NOT_APPLICABLE_WITH_OWNER_AUTHORITY y readback de la obligacion abierta.',
  unit_metadata=jsonb_set(coalesce(pu.unit_metadata,'{}'::jsonb),
    '{performance_regression_defer_v1}',v_deferred,true)
  WHERE pu.id=67;

  UPDATE programacion.engineering_work_checkpoints c
  SET title=CASE c.checkpoint_code
    WHEN 'REGRESSION_GATE_NEGATIVE' THEN
     'Disposition gobernada: negativo p95 relativo diferido (sin falso PASS; SLO absoluto M8.10 vigente)'
    WHEN 'GATE_READBACK' THEN
     'Readback terminal IG: SLO M8.10 vigente y deuda postdeploy p95 relativa OPEN_DEFERRED'
  END, updated_at=clock_timestamp(),
  updated_by_execution_id='IG_M8_11_CONTRACT_GOVERNANCE_DEFER_20261009'
  WHERE c.work_item_id=255 AND c.checkpoint_code IN ('REGRESSION_GATE_NEGATIVE','GATE_READBACK');

  IF NOT EXISTS(
    SELECT 1 FROM programacion.engineering_plan_units pu
    WHERE pu.id=67
      AND pu.unit_metadata#>>'{performance_regression_defer_v1,obligation_status}'='OPEN_DEFERRED_NOT_PASSED'
      AND pu.unit_metadata#>>'{performance_regression_defer_v1,policy_ref}'=v_policy
      AND pu.exit_criterion LIKE '%OBLIGACION DIFERIDA ABIERTA%'
  ) THEN RAISE EXCEPTION 'M811_CONTRACT_GOVERNANCE_READBACK_FAILED'; END IF;
END;
$m811$;
