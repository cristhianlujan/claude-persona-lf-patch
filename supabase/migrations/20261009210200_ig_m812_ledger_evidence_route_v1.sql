-- PAULO-146 / M8.12 checkpoint 3: remove stale transversal FINAL_EVIDENCE route.
-- The declared evidence contract is ledger-derived and forbids disabled POST_PASE FINAL_EVIDENCE.
UPDATE programacion.engineering_plan_units
SET unit_metadata=jsonb_set(
 unit_metadata,'{transversal_execution_v1}',
 (unit_metadata->'transversal_execution_v1')-'M8_EVIDENCE_BUNDLE',true)
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND unit_code='M8.12' AND disposition='ASSIGNED'
 AND unit_metadata #>> '{transversal_execution_v1,M8_EVIDENCE_BUNDLE,capabilities,0,capability_code}'
 = 'FINAL_EVIDENCE';

DO $guard$
BEGIN
 IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M8.12'
       AND unit_metadata->'transversal_execution_v1' ? 'M8_EVIDENCE_BUNDLE')<>0 THEN
   RAISE EXCEPTION 'M812_STALE_FINAL_EVIDENCE_ROUTE_REMAINS';
 END IF;
 IF (programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M8.12')
       ->'execution_readiness'->>'status')<>'READY' THEN
   RAISE EXCEPTION 'M812_LEDGER_READBACK_NOT_READY';
 END IF;
END;
$guard$;