BEGIN;
DO $m96$
DECLARE j jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units
  WHERE id=279 AND unit_metadata#>>'{action_specs_v1,UNRESOLVED_NEGATIVE,contract_family}'='BOUNDED_CHECKPOINT_TEST')
 THEN RAISE EXCEPTION 'M96_NEGATIVE_FAMILY_PREIMAGE_DRIFT'; END IF;
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,UNRESOLVED_NEGATIVE,contract_family}',
  '"CURRENT_ADJUDICATION_NEGATIVE_SQL_READBACK"'::jsonb,true)
 WHERE id=279;
 j:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.6')::jsonb;
 IF j->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
 OR j#>>'{execution_packet,status}'<>'READY'
 OR j#>>'{action_spec,action_kind}'<>'READBACK_ONCE'
 THEN RAISE EXCEPTION 'M96_NEGATIVE_SQL_PACKET_NOT_READY:%',j#>'{execution_packet,status}'; END IF;
END $m96$;
COMMIT;
