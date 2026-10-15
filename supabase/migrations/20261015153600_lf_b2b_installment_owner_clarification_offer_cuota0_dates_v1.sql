-- LF B2B candidate business-rule clarification; no new physical plan model or runtime changes.
-- EKB checked: PRV-GOV-010, PRV-ARC-013, PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001,
-- PRV-INPUT-GOV-DECISION-RULE-PROVENANCE-PARITY-001 and IG-M96-MIGRATION-VERSION-COLLISION-001.
-- Front Cliente (REG_CLIENT_*) is read-only contract evidence, not a write target.
BEGIN;

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM lf_ops.reglas
    WHERE id=617 AND codigo='B2B-RULE-INSTALLMENT-PLAN-001' AND estado='CANDIDATO'
      AND valor_config->>'offer_amount_semantic'='TOTAL_ECONOMIC_AMOUNT_OF_PLAN'
      AND valor_config->>'offer_may_have_multiple_plans'='true'
      AND valor_config->'initial_payment_excel_policy'->>'required_per_plan'='true'
      AND valor_config->'initial_payment_excel_policy'->>'explicit_zero_allowed'='true'
      AND valor_config->'initial_payment_excel_policy'->>'source'='CRONOGRAMA'
      AND valor_config->'first_installment_date_policy'->>'prepay_schedule'='SERVER_PROPOSED'
      AND NOT (valor_config->'initial_payment_excel_policy' ? 'activation_amount_min_exclusive')
  )<>1 THEN RAISE EXCEPTION 'LF_B2B_CUOTA0_ORIGINAL_CONTRACT_MISMATCH'; END IF;

  IF (SELECT count(*) FROM lf_ops.campos_validaciones
    WHERE codigo='B2B_IMP_VAL_INITIAL_PAYMENT' AND estado='CANDIDATO'
      AND valor_config->>'min'='0'
  )<>1 THEN RAISE EXCEPTION 'LF_B2B_INITIAL_AMOUNT_VALIDATION_MISMATCH'; END IF;

  IF (SELECT count(*) FROM lf_ops.reglas
    WHERE id=422 AND codigo='B2B-RULE-INSTALLMENT-001' AND estado='CANDIDATO'
      AND valor_config->>'allowed_difference'='0.00'
  )<>1 THEN RAISE EXCEPTION 'LF_B2B_INSTALLMENT_TOTAL_POLICY_MISSING'; END IF;
END $preflight$;

-- The numeric threshold belongs to this governed B2B candidate business rule:
-- it MUST be read from configuration by future backend, not hardcoded in the screen.
-- A validated amount is not necessarily an active cuota 0.
UPDATE lf_ops.reglas
SET valor_config = jsonb_set(
    jsonb_set(valor_config,'{initial_payment_excel_policy}',
      (valor_config->'initial_payment_excel_policy') ||
        jsonb_build_object(
          'required_per_plan', false,
          'activation_amount_min_exclusive', 1,
          'activation_evaluation_authority', 'SERVER_CONFIG_DRIVEN',
          'zero_amount_behavior', 'NOT_CONSIDERED_AS_ACTIVE_CUOTA_0',
          'below_or_equal_threshold_behavior', 'NOT_ACTIVE_INITIAL_PAYMENT',
          'without_active_initial_payment_plan_activation', 'PENDING_FUNCTIONAL_DEFINITION'
        ),false),
    '{first_installment_date_policy}',
      (valor_config->'first_installment_date_policy') ||
        jsonb_build_object(
          'physical_date_model_status','PENDING_FUNCTIONAL_DEFINITION',
          'predevelopment_due_dates_status','SUGGESTED_NOT_FINAL',
          'dependency_reconciliation_required','PLAN_OFFER_PAYMENT_LEDGER_AND_COMPANY_CALENDAR'
        ),false),
    descripcion=descripcion ||
      ' Aclaración del propietario 2026-10-15: cada alternativa de plan tiene su propia oferta económica y su monto específico. La referencia contenedora o su identificador de oferta vigente NO autoriza agregar los importes de planes alternativos; para descuentos conjuntos solamente se consideran las ofertas económicas seleccionadas y validadas server-side. La identidad física oferta-versión-plan y su cardinalidad final quedan pendientes del modelado y de reconciliar el contrato Cliente sin alterar sus reglas vigentes. Cuota 0 puede venir en el cronograma durante la carga, pero no es obligatoria; solo constituye un pago inicial activo si su monto supera el umbral parametrizado (hoy mayor que 1 en la moneda del plan). Cero no se considera pago inicial activo; para valores iguales o menores al umbral no se inicia cobro de cuota 0. La activación de planes sin cuota 0 activa queda PENDING_FUNCTIONAL_DEFINITION y nunca se presume automática. Fechas y ventanas actuales son sugerencias de diseño; faltan el modelo físico y sus relaciones con oferta, plan, cobro, calendario, ledger y snapshot; no fijar fechas definitivas ni constantes de frontend.',
    updated_at=clock_timestamp()
WHERE id=617 AND codigo='B2B-RULE-INSTALLMENT-PLAN-001' AND estado='CANDIDATO';

DO $readback$
DECLARE v_cfg jsonb;
BEGIN
  SELECT valor_config INTO v_cfg FROM lf_ops.reglas
    WHERE id=617 AND codigo='B2B-RULE-INSTALLMENT-PLAN-001' AND estado='CANDIDATO';

  IF v_cfg->'initial_payment_excel_policy'->>'required_per_plan'<>'false'
    OR v_cfg->'initial_payment_excel_policy'->>'activation_amount_min_exclusive'<>'1'
    OR v_cfg->'initial_payment_excel_policy'->>'zero_amount_behavior'<>'NOT_CONSIDERED_AS_ACTIVE_CUOTA_0'
    OR v_cfg->'initial_payment_excel_policy'->>'without_active_initial_payment_plan_activation'<>'PENDING_FUNCTIONAL_DEFINITION'
    OR v_cfg->'first_installment_date_policy'->>'physical_date_model_status'<>'PENDING_FUNCTIONAL_DEFINITION'
    OR v_cfg->'first_installment_date_policy'->>'predevelopment_due_dates_status'<>'SUGGESTED_NOT_FINAL'
    OR v_cfg->>'offer_amount_semantic'<>'TOTAL_ECONOMIC_AMOUNT_OF_PLAN'
    OR NOT(0::numeric <= (v_cfg->'initial_payment_excel_policy'->>'activation_amount_min_exclusive')::numeric)
    OR NOT(1::numeric <= (v_cfg->'initial_payment_excel_policy'->>'activation_amount_min_exclusive')::numeric)
    OR NOT(1.01::numeric > (v_cfg->'initial_payment_excel_policy'->>'activation_amount_min_exclusive')::numeric)
    OR (SELECT count(*) FROM lf_ops.campos_validaciones WHERE codigo='B2B_IMP_VAL_INITIAL_PAYMENT'
        AND valor_config->>'min'='0')<>1
  THEN RAISE EXCEPTION 'LF_B2B_CUOTA0_DATE_OWNER_CLARIFICATION_READBACK_FAILED'; END IF;
END $readback$;
COMMIT;
