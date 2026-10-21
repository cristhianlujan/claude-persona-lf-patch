-- IG M10.8 terminal FIX_FORWARD readback.
-- Closes GATE_READBACK only after exact canonical readback.
-- No production activation. No operational rollback to M9.0.

BEGIN;

DO $m108_close$
DECLARE
  v_progress numeric;
  v_work_status text;
  v_done_count integer;
  v_cp4 record;
  v_cp5 record;
  v_spec jsonb;
  v_packet jsonb;
  v_transition jsonb;
BEGIN
  SELECT progress_pct,status
    INTO v_progress,v_work_status
  FROM programacion.v_engineering_work_progress
  WHERE id=479;

  IF v_progress IS DISTINCT FROM 80.00
     OR v_work_status IS DISTINCT FROM 'IN_PROGRESS'
  THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_PRESTATE_FAIL:progress=% status=%',
      v_progress,v_work_status;
  END IF;

  SELECT status,evidence_ref INTO v_cp4
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=479 AND checkpoint_code='EXPIRY_DECISION';

  SELECT status,evidence_ref INTO v_cp5
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=479 AND checkpoint_code='GATE_READBACK'
  FOR UPDATE;

  IF v_cp4.status IS DISTINCT FROM 'DONE'
     OR v_cp4.evidence_ref IS DISTINCT FROM
       'supabase://transversal.decision_log#DEC-IG-M10.8-FIX-FORWARD-20261021'
     OR v_cp5.status IS DISTINCT FROM 'PENDING'
     OR v_cp5.evidence_ref IS NOT NULL
  THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_CP_FAIL:cp4=% cp5=%',
      row_to_json(v_cp4),row_to_json(v_cp5);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM transversal.decision_log
    WHERE adr='DEC-IG-M10.8-FIX-FORWARD-20261021'
      AND upper(estado)='VIGENTE'
      AND decision LIKE 'ADOPT_FIX_FORWARD.%'
  ) THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_OWNER_DECISION_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units
    WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND unit_code='M10.8'
      AND unit_metadata#>>'{recovery_policy_v2,operational_recovery_mode}'='FIX_FORWARD'
      AND unit_metadata#>>'{recovery_policy_v2,operational_rollback_to_m9_0}'='FORBIDDEN'
      AND unit_metadata#>>'{recovery_policy_v2,archived_m9_0_role}'='EVIDENCE_HISTORY_ONLY'
      AND unit_metadata#>>'{recovery_policy_v2,production_authorized}'='false'
      AND unit_metadata#>>'{operational_maturity_policy_v1,state}'='SUPERSEDED_BY_FIX_FORWARD'
  ) THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_POLICY_FAIL';
  END IF;

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.8','GATE_READBACK'
  );

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_spec->>'contract_family' IS DISTINCT FROM 'FIX_FORWARD_TERMINAL_READBACK'
     OR v_spec->>'mutation_policy' IS DISTINCT FROM 'NO_DOMAIN_MUTATION'
  THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_SPEC_FAIL:%',v_spec;
  END IF;

  v_packet := programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.8',
    'GATE_READBACK',
    v_spec,
    '{}'::jsonb
  );

  IF v_packet->>'status' IS DISTINCT FROM 'READY'
     OR v_packet->>'execution_capability' IS DISTINCT FROM 'READ'
  THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_PACKET_FAIL:%',v_packet;
  END IF;

  v_transition := programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.8',
    'GATE_READBACK',
    'DONE',
    'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.8#recovery_policy_v2=FIX_FORWARD;operational_rollback_to_m9_0=FORBIDDEN;archived_m9_0_role=EVIDENCE_HISTORY_ONLY',
    'GPT_NATIVE:M10.8:GATE_READBACK',
    'Exact ENGINEERING_READ_BUNDLE_V1 PASS: progress=80 before transition; EXPIRY_DECISION DONE with owner ADR; GATE_READBACK PENDING; recovery_mode=FIX_FORWARD; rollback_to_m9=FORBIDDEN; archive_role=EVIDENCE_HISTORY_ONLY; production_authorized=false.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_transition#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
  THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_TRANSITION_FAIL:%',v_transition;
  END IF;

  SELECT progress_pct,status
    INTO v_progress,v_work_status
  FROM programacion.v_engineering_work_progress
  WHERE id=479;

  SELECT count(*) INTO v_done_count
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=479
    AND status='DONE';

  IF v_progress IS DISTINCT FROM 100.00
     OR v_work_status IS DISTINCT FROM 'DONE'
     OR v_done_count <> 5
  THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_TERMINAL_FAIL:progress=% status=% done=%',
      v_progress,v_work_status,v_done_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units
    WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND unit_code='M10.8'
      AND unit_metadata#>>'{recovery_policy_v2,operational_recovery_mode}'='FIX_FORWARD'
      AND unit_metadata#>>'{recovery_policy_v2,operational_rollback_to_m9_0}'='FORBIDDEN'
      AND unit_metadata#>>'{recovery_policy_v2,archived_m9_0_role}'='EVIDENCE_HISTORY_ONLY'
      AND unit_metadata#>>'{recovery_policy_v2,production_authorized}'='false'
  ) THEN
    RAISE EXCEPTION 'M108_GATE_READBACK_POST_POLICY_DRIFT';
  END IF;
END
$m108_close$;

INSERT INTO public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
)
VALUES(
  'IG-M108-FIX-FORWARD-TERMINAL-CLOSE-053',
  'GOVERNANCE',
  'M10.8 cierra con FIX_FORWARD sin rollback operativo a M9.0',
  'El readback terminal confirma que la estrategia operativa es FIX_FORWARD y que el bundle archivado M9.0 ya no forma parte del camino de recuperación operativo.',
  'Corrección de la conflación previa entre rollback operativo de release y reversibilidad técnica de pruebas/transacciones.',
  'FIX_FORWARD_TERMINAL_RECOVERY_POLICY',
  'Mantener recovery_policy_v2 como autoridad: FIX_FORWARD, operational_rollback_to_m9_0=FORBIDDEN, archived_m9_0_role=EVIDENCE_HISTORY_ONLY. Preservar rollback transaccional, Migration Train y reversibilidad de pruebas.',
  'PASS si M10.8 queda DONE 100% con 5/5 checkpoints DONE, decisión ADR vigente, production_authorized=false y GATE_READBACK evidencia el readback exacto.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','VERIFICADO',
  'ENGINEERING_READ_BUNDLE_V1: prestate 80%; decision DONE; recovery FIX_FORWARD; rollback M9.0 FORBIDDEN; archive EVIDENCE_HISTORY_ONLY; production_authorized=false.',
  'GOVERNANCE',
  array['INPUT_GOVERNANCE','ENGINEERING_EXECUTOR']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'M10.8 terminal recovery strategy',
  'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.8'
)
ON CONFLICT (codigo) DO UPDATE SET
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();

COMMIT;
