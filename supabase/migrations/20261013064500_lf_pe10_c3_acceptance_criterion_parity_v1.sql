-- PE10 C3: reconcile work-item acceptance text with canonical review-v3 contract.
-- Exact scope: PE10 engineering acceptance metadata only. No REVIEW verdict, activation or checkpoint transition.
BEGIN;
DO $fix$
DECLARE
 v_w bigint; v_old jsonb; v_new jsonb; v_meta jsonb;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT v_w,v_meta
 FROM programacion.engineering_plan_units
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
   AND unit_code='PE10' FOR UPDATE;
 SELECT acceptance_criteria INTO STRICT v_old
 FROM programacion.engineering_work_items WHERE id=v_w FOR UPDATE;
 IF v_meta#>>'{action_specs_v1,PE10_C3,canonical_receipt_kind}' IS DISTINCT FROM 'INDEPENDENT_REVIEW_RECEIPT'
 OR v_meta#>>'{source_pack_v2,checkpoint_inputs,PE10_C3,canonical_receipt_kind}' IS DISTINCT FROM 'INDEPENDENT_REVIEW_RECEIPT'
 OR v_meta#>>'{phase_separation_v1,independent_cutover_assurance,canonical_receipt_kind}' IS DISTINCT FROM 'INDEPENDENT_REVIEW_RECEIPT'
 OR (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_w AND checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 OR (SELECT count(*) FROM jsonb_array_elements_text(v_old) AS x(criteria)
     WHERE x.criteria LIKE 'PE10_C3:%AUDIT_VERDICT%')<>1
 THEN RAISE EXCEPTION 'PE10_C3_ACCEPTANCE_V1_PRESTATE_DRIFT'; END IF;
 SELECT jsonb_agg(
  CASE WHEN x.criteria LIKE 'PE10_C3:%' THEN
  to_jsonb('PE10_C3: require completed six-step canonical INDEPENDENT_ASSURANCE review-v3, VERIFIED REVIEW_DECISION and INDEPENDENT_REVIEW_RECEIPT for exact frozen PE10 subject, current bound capability, distinct producer/reviewer, real semantic PASS and dependency/data/author independence. Historical AUDIT_VERDICT from unrelated subjects is insufficient; no v0.2 activation.'::text)
  ELSE to_jsonb(x.criteria) END ORDER BY x.ordinality)
 INTO v_new FROM jsonb_array_elements_text(v_old) WITH ORDINALITY AS x(criteria,ordinality);
 IF v_new IS NULL OR v_new=v_old THEN RAISE EXCEPTION 'PE10_C3_ACCEPTANCE_V1_NO_CHANGE'; END IF;
 UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new WHERE id=v_w;
 IF (SELECT count(*) FROM jsonb_array_elements_text(v_new) AS x(criteria)
  WHERE x.criteria LIKE 'PE10_C3:%INDEPENDENT_REVIEW_RECEIPT%')<>1
  OR (SELECT status FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=v_w AND checkpoint_code='PE10_C3') IS DISTINCT FROM 'IN_PROGRESS'
 THEN RAISE EXCEPTION 'PE10_C3_ACCEPTANCE_V1_READBACK_FAIL'; END IF;
END $fix$;
COMMIT;
