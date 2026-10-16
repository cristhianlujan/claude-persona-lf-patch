-- LF B2B — owner clarification: one Plan can contain multiple offer alternatives.
-- Exclusive selection within each Plan; cross-Plan totals only for selected offers.
-- No physical DDL; Excel contract and CLIENT_APP_SHELL remain unchanged.
-- Route: ACT-0001 / MIGRATION UPDATE / ACTUALIZACION_DB_LF.
-- EKB: PRV-ARC-013, PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001,
-- PRV-INPUT-GOV-DECISION-RULE-PROVENANCE-PARITY-001.
BEGIN;

DO $preflight$
BEGIN
 IF (SELECT COUNT(*) FROM lf_ops.reglas
   WHERE id=617 AND codigo='B2B-RULE-INSTALLMENT-PLAN-001' AND estado='CANDIDATO'
     AND valor_config->>'offer_may_have_multiple_plans'='true'
     AND valor_config->>'offer_amount_semantic'='TOTAL_ECONOMIC_AMOUNT_OF_PLAN'
     AND valor_config->>'initial_payment_scope'='PER_PLAN'
     AND valor_config->'initial_payment_excel_policy'->>'activation_amount_min_exclusive'='1')<>1
 THEN RAISE EXCEPTION 'B2B_PLAN_OFFER_INVERTED_CARDINALITY_GUARD_FAILED'; END IF;

 IF (SELECT COUNT(*) FROM lf_ops.reglas
   WHERE id=654 AND codigo='B2B-RULE-LOAD-MULTI-OFFER-001' AND estado='CANDIDATO'
     AND valor_config->'file_relation_key'='["REFERENCIA_EMPRESA","PLAN"]'::jsonb
     AND valor_config->>'file_relation_key_role'='FILE_JOIN_ONLY_NOT_CANONICAL_IDENTITY')<>1
 THEN RAISE EXCEPTION 'B2B_EXCEL_JOIN_IDENTITY_GUARD_FAILED'; END IF;

 IF (SELECT COUNT(*) FROM lf_ops.reglas
   WHERE id=620 AND codigo='B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001'
     AND estado='CANDIDATO'
     AND valor_config->'contract_field_matrix_v4'->>'file_relation_semantic'
       ='REFERENCIA_EMPRESA_PLUS_PLAN_ONLY_RELATES_OFERTAS_PLANES_TO_CRONOGRAMA_WITHIN_THE_FILE; LF_GENERATES_CANONICAL_INTERNAL_IDS')<>1
 THEN RAISE EXCEPTION 'B2B_EXCEL_CONTRACT_OWNERSHIP_GUARD_FAILED'; END IF;

 IF (SELECT COUNT(*) FROM lf_ops.campos_validaciones
   WHERE id=88 AND codigo='B2B_IMP_VAL_INSTALLMENT_SUM' AND estado='CANDIDATO'
     AND valor_config->>'group_by'='external_offer_id'
     AND valor_config->>'tolerance_policy'='PENDING_DECISION')<>1
 THEN RAISE EXCEPTION 'B2B_INSTALLMENT_VALIDATION_LEGACY_GROUP_GUARD_FAILED'; END IF;
END $preflight$;

-- Replace the previously inverted definition; leave the physical foreign keys pending.
UPDATE lf_ops.reglas
SET valor_config = (valor_config - 'offer_may_have_multiple_plans')
 || jsonb_build_object(
    'plan_may_have_multiple_offers', true,
    'offer_selection_within_plan','AT_MOST_ONE_SELECTED_OFFER_PER_PLAN',
    'cross_plan_selection','ACCUMULATE_ONLY_EXPLICITLY_SELECTED_OFFERS',
    'offer_amount_semantic','TOTAL_ECONOMIC_AMOUNT_OF_SELECTED_OFFER',
    'initial_payment_scope','PER_SELECTED_OFFER',
    'physical_plan_offer_mapping_status','PENDING_FUNCTIONAL_DEFINITION'),
 descripcion = descripcion ||
   ' Owner 2026-10-15 supersedes the inverted offer-to-plan cardinality: a PLAN may present MULTIPLE economic offer alternatives (for example 3, 6 or 9 installments), each with its own economic amount and schedule; at most ONE is selected from that plan. Offers selected from DIFFERENT plans are included together in a validated checkout quote, never the unselected alternatives. The payment amount, discount and customer savings are evaluated only for selected offers server-side, with downstream CLIENT_APP_SHELL contract reconciliation pending. The physical plan-offer relationship and identifiers are pending; this rule does not authorize changes to the Client checkout.',
 updated_at=CURRENT_TIMESTAMP
WHERE id=617 AND codigo='B2B-RULE-INSTALLMENT-PLAN-001' AND estado='CANDIDATO';

-- Preserve currently-approved Excel schema, flag ambiguity rather than silently joining
-- two different alternative offers to the same schedule.
UPDATE lf_ops.reglas
SET descripcion = descripcion ||
  ' Owner 2026-10-15: within a plan there can be several independent offer alternatives, with exclusive selection; PLAN A and PLAN B can each contribute one selected offer to a combined quote. The current standard Excel join key REFERENCIA_EMPRESA+PLAN is insufficient to distinguish schedules for two alternative offers under the SAME PLAN. The physical and Excel identity mapping is PENDING_FUNCTIONAL_DEFINITION; no ambiguous rows may be accepted as a valid resolved schedule until the authoritative mapping is defined.',
 updated_at=CURRENT_TIMESTAMP
WHERE id=654 AND codigo='B2B-RULE-LOAD-MULTI-OFFER-001' AND estado='CANDIDATO';

UPDATE lf_ops.reglas
SET descripcion = descripcion ||
   ' Before implementation, reconcile the Excel Completo relation REFERENCIA_EMPRESA+PLAN against multiple alternative economic offers within a plan. Existing V4 Excel schema remains unchanged; same-plan multi-offer disambiguation is PENDING_FUNCTIONAL_DEFINITION. Do not silently associate one cronograma with more than one offer.',
 updated_at=CURRENT_TIMESTAMP
WHERE id=620 AND codigo='B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001'
 AND estado='CANDIDATO';

-- Legacy external_offer_id is not a column in the approved standard Excel.
-- This validator is CANDIDATO/PENDING_DECISION: never deploy it with stale grouping.
UPDATE lf_ops.campos_validaciones
SET valor_config=valor_config-'group_by',
    descripcion=descripcion ||
      ' The former group_by=external_offer_id is not authoritative in B2B Excel Completo. Future reconciliation must group by the LF-generated identity of the SELECTED economic offer, plus the plan and company scoping as established by the physical model. Until then the validator remains CANDIDATO/PENDING_DECISION, not runnable as a complete grouping validator.',
    updated_at=CURRENT_TIMESTAMP
WHERE id=88 AND codigo='B2B_IMP_VAL_INSTALLMENT_SUM' AND estado='CANDIDATO';

DO $readback$
BEGIN
 IF (SELECT COUNT(*) FROM lf_ops.reglas
     WHERE id=617 AND estado='CANDIDATO'
       AND valor_config->>'plan_may_have_multiple_offers'='true'
       AND valor_config->>'offer_selection_within_plan'='AT_MOST_ONE_SELECTED_OFFER_PER_PLAN'
       AND valor_config->>'cross_plan_selection'='ACCUMULATE_ONLY_EXPLICITLY_SELECTED_OFFERS'
       AND valor_config->>'offer_amount_semantic'='TOTAL_ECONOMIC_AMOUNT_OF_SELECTED_OFFER'
       AND valor_config->>'initial_payment_scope'='PER_SELECTED_OFFER'
       AND NOT (valor_config ? 'offer_may_have_multiple_plans'))<>1
 OR (SELECT COUNT(*) FROM lf_ops.reglas
     WHERE id=654 AND estado='CANDIDATO'
       AND valor_config->'file_relation_key'='["REFERENCIA_EMPRESA","PLAN"]'::jsonb
       AND descripcion LIKE '%insufficient to distinguish schedules%')<>1
 OR (SELECT COUNT(*) FROM lf_ops.reglas
     WHERE id=620 AND estado='CANDIDATO'
       AND descripcion LIKE '%same-plan multi-offer disambiguation is PENDING_FUNCTIONAL_DEFINITION%')<>1
 OR (SELECT COUNT(*) FROM lf_ops.campos_validaciones
     WHERE id=88 AND estado='CANDIDATO'
       AND NOT (valor_config ? 'group_by')
       AND valor_config->>'tolerance_policy'='PENDING_DECISION')<>1
 THEN RAISE EXCEPTION 'B2B_PLAN_OFFER_EXCLUSIVE_SELECTION_READBACK_FAILED'; END IF;
END $readback$;

COMMIT;
