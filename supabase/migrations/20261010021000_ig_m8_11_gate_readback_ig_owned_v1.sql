-- M8.11 correction: IG GATE_READBACK must consume IG-owned ledger, not disabled POST_PASE.
-- No new control, no runtime/deploy changes.
DO $m811$
DECLARE v_query text := $ig_query$select pu.unit_code,
       pu.unit_metadata#>>'{performance_regression_defer_v1,obligation_status}' as relative_p95_obligation,
       pu.unit_metadata#>>'{performance_regression_defer_v1,owner}' as authority_owner,
       slo.status as absolute_slo_negative_status,
       slo.assertion_receipt->>'passed' as absolute_slo_negative_asserted,
       deferred.status as relative_checkpoint_disposition,
       (select count(*) from programacion.provenance_receipts where subject_type='IG_PERFORMANCE_TIMING') as timing_receipt_count
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints slo
    on slo.work_item_id=254 and slo.checkpoint_code='SLO_OVER_LIMIT_NEGATIVE'
  join programacion.engineering_work_checkpoints deferred
    on deferred.work_item_id=255 and deferred.checkpoint_code='REGRESSION_GATE_NEGATIVE'
 where pu.id=67 and pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and pu.unit_code='M8.11'$ig_query$;
        v_inputs jsonb;
BEGIN
 IF NOT EXISTS(
  SELECT 1 FROM programacion.engineering_plan_units pu
  JOIN programacion.engineering_work_checkpoints cp ON cp.work_item_id=pu.work_item_id
  WHERE pu.id=67 AND pu.unit_code='M8.11'
    AND cp.checkpoint_code='GATE_READBACK' AND cp.status='PENDING'
    AND pu.unit_metadata#>>'{performance_regression_defer_v1,obligation_status}'='OPEN_DEFERRED_NOT_PASSED'
 ) THEN RAISE EXCEPTION 'IG_M811_GATE_READBACK_PREFLIGHT_FAIL'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM programacion.engineering_plan_units pu
  WHERE pu.id=67 AND pu.unit_metadata#>>'{source_pack_v1,checkpoint_inputs,GATE_READBACK,inputs,events,0}'='19652'
 ) THEN RAISE EXCEPTION 'IG_M811_SOURCE_PACK_DRIFT'; END IF;
 v_inputs:=jsonb_build_object('assets','[]'::jsonb,'events','[]'::jsonb,
   'queries',jsonb_build_array(v_query),'artifacts','[]'::jsonb,
   'db_objects',jsonb_build_array('programacion.engineering_plan_units',
    'programacion.engineering_work_checkpoints','programacion.provenance_receipts'));
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,
   '{source_pack_v1,checkpoint_inputs,GATE_READBACK,inputs}',v_inputs,true)
 WHERE id=67 AND unit_code='M8.11';
 IF EXISTS(
  SELECT 1 FROM programacion.engineering_plan_units
  WHERE id=67 AND (
    unit_metadata#>>'{source_pack_v1,checkpoint_inputs,GATE_READBACK,inputs,events,0}' IS NOT NULL
    OR unit_metadata#>>'{source_pack_v1,checkpoint_inputs,GATE_READBACK,inputs,queries,0}' IS DISTINCT FROM v_query
    OR unit_metadata#>>'{performance_regression_defer_v1,obligation_status}' IS DISTINCT FROM 'OPEN_DEFERRED_NOT_PASSED'
  )
 ) THEN RAISE EXCEPTION 'IG_M811_READBACK_SOURCE_RECONCILE_FAIL'; END IF;
END;
$m811$;
