
-- Original semantic gate restored and still blocks unauthorized new executions.
DO $original_intake$
BEGIN
 IF (SELECT hash FROM intake_guard_baseline) <>
    md5(pg_get_functiondef('saly.creative_intake_semantic_gate_v1()'::regprocedure))
 THEN RAISE EXCEPTION 'ORIGINAL_INTAKE_GATE_NOT_RESTORED'; END IF;
 BEGIN
   UPDATE saly.creative_orders SET scope_json=scope_json||'{"render_authorized":true}'::jsonb
   WHERE code='SALY_ADELANTO_V015_SINGLE_20261123';
   RAISE EXCEPTION 'INTAKE_GATE_OTHER_ORDER_BYPASSED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='INTAKE_GATE_OTHER_ORDER_BYPASSED'
     OR position('CREATIVE_INTAKE_ORIGINAL_VISUAL_LITERAL_MISSING' in SQLERRM)=0
  THEN RAISE; END IF;
 END;
END $original_intake$;
SELECT 'PASS_INTAKE_GATE_RESTORED_AND_OTHER_ORDER_BLOCKED';
