-- LF B2B - one source for installment monetary precision.
-- Existing rule ID 422 governs 2 decimals and zero tolerance.
-- Plan rule ID 617 becomes a consumer; no new tables and no production activation.
-- Validation ID 88 remains CANDIDATO/PENDING_DECISION because plan grouping is
-- not yet physically resolved. Do NOT claim the installment validator E2E passed.
BEGIN;
DO $preflight$
BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas
     WHERE id=422 AND codigo='B2B-RULE-INSTALLMENT-001'
       AND estado='CANDIDATO'
       AND valor_config->>'currency_precision_decimals'='2'
       AND valor_config->>'allowed_difference'='0.00'
       AND valor_config->>'tolerance_policy'='EXACT_AFTER_2_DECIMAL_NORMALIZATION'
       AND valor_config->>'validation'='B2B_IMP_VAL_INSTALLMENT_SUM')<>1
 THEN RAISE EXCEPTION 'B2B_INSTALLMENT_CANONICAL_PRECISION_GUARD_FAILED'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas
     WHERE id=617 AND codigo='B2B-RULE-INSTALLMENT-PLAN-001'
       AND estado='CANDIDATO'
       AND valor_config->>'currency_precision_decimals'='2'
       AND NOT(valor_config ? 'currency_precision_source_rule_id'))<>1
 THEN RAISE EXCEPTION 'B2B_INSTALLMENT_PRECISION_CONSUMER_GUARD_FAILED'; END IF;
 IF (SELECT count(*) FROM lf_ops.campos_validaciones
     WHERE id=88 AND codigo='B2B_IMP_VAL_INSTALLMENT_SUM'
       AND estado='CANDIDATO'
       AND valor_config->>'tolerance_policy'='PENDING_DECISION')<>1
 THEN RAISE EXCEPTION 'B2B_INSTALLMENT_UNRESOLVED_VALIDATOR_GUARD_FAILED'; END IF;
END $preflight$;

UPDATE lf_ops.reglas
SET valor_config=(valor_config-'currency_precision_decimals')
                 ||jsonb_build_object('currency_precision_source_rule_id',422),
    updated_at=clock_timestamp()
WHERE id=617 AND codigo='B2B-RULE-INSTALLMENT-PLAN-001'
  AND estado='CANDIDATO';

DO $readback$
BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas WHERE id=617
     AND estado='CANDIDATO'
     AND valor_config->>'currency_precision_source_rule_id'='422'
     AND NOT (valor_config ? 'currency_precision_decimals'))<>1
 OR (SELECT count(*) FROM lf_ops.reglas WHERE id=422
     AND valor_config->>'currency_precision_decimals'='2'
     AND valor_config->>'tolerance_policy'='EXACT_AFTER_2_DECIMAL_NORMALIZATION')<>1
 OR (SELECT count(*) FROM lf_ops.campos_validaciones WHERE id=88
     AND estado='CANDIDATO'
     AND valor_config->>'tolerance_policy'='PENDING_DECISION')<>1
 THEN RAISE EXCEPTION 'B2B_INSTALLMENT_PRECISION_READBACK_FAILED'; END IF;
END $readback$;
COMMIT;
