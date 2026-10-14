-- IG M10.7 CP1 only: align the unit's inherited SOAK criterion with M9.11's
-- verified historical-as-of policy and persist one OBSERVE_ONCE checkpoint.
-- Governed route: ACTUALIZACION_DB_LF -> Migration Train. No runtime/production.
-- Preflight was read-only: receipt 38 VERIFIED 13/13 screens, 47/47 families,
-- zero below-2, zero known false PASS and zero unresolved D4.
-- Negative read-only SQL projections rejected screen-gap, false-pass and D4.
-- The migration rehearses exact changes in a rollback subtransaction.
DO $m107cp1$
DECLARE
  v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit constant text := 'M10.7';
  v_actor constant text := 'IG_M107_CP1_CANONICAL_20261014';
  v_old_exit constant text := 'Soak post-cutover con umbrales en datos: ≥N ejecuciones, 13/13 pantallas, 47/47 familias críticas observadas, 0 falso PASS, 0 timeout >150 s; umbrales tomados del contrato de M9.11';
  v_new_exit constant text := 'Soak por suficiencia de observación conforme M9.11 / SOAK_OBSERVATION_HISTORY_V2: cohorte documentada de 13 pantallas y 47 familias críticas; cada pantalla y familia crítica con >=2 observaciones históricas elegibles as-of en ventanas compatibles; 0 falsos PASS conocidos, 0 divergencias D4 materiales sin resolver y 0 timeouts >150 s en la ventana operativa M10.7. Reusar historia; ejecutar nuevos runs solo ante gaps focales. No exigir dos sucesores simultáneamente CURRENT ni autorización de producción.';
  v_work bigint;
  v_old_actual text;
  v_receipt jsonb;
  v_receipt_hash text;
  v_spec jsonb;
  v_state jsonb;
  v_attempt integer;
  v_evidence text;
BEGIN
  SELECT work_item_id,exit_criterion INTO STRICT v_work,v_old_actual
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND disposition='ASSIGNED';
  IF v_work<>478 OR v_old_actual IS DISTINCT FROM v_old_exit THEN
    RAISE EXCEPTION 'M107_CP1_SOURCE_CRITERION_DRIFT';
  END IF;
  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)
     IS DISTINCT FROM 'BACKLOG'
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND status='PENDING')<>5
  OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code='SOAK_CRITERIA_ASIS'
        AND status='PENDING' AND sequence_no=1)
  THEN RAISE EXCEPTION 'M107_CP1_EXPECTED_0_PERCENT_DRIFT'; END IF;
  IF NOT EXISTS(SELECT 1 FROM programacion.engineering_plan_units p
       JOIN programacion.engineering_work_items w ON w.id=p.work_item_id
       WHERE p.plan_code=v_plan AND p.unit_code='M9.11' AND w.status='DONE')
  OR NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
       JOIN programacion.engineering_plan_units p ON p.work_item_id=c.work_item_id
       WHERE p.plan_code=v_plan AND p.unit_code='M9.11'
         AND c.checkpoint_code='SOAK_READBACK' AND c.status='DONE')
  THEN RAISE EXCEPTION 'M107_CP1_M911_NOT_CERTIFIED'; END IF;
  IF programacion.fn_engineering_effective_open_blocker_count_v1(v_work)<>0
  OR EXISTS(SELECT 1 FROM programacion.fn_engineering_effective_dependencies_v1(v_work) d
            WHERE d.is_unmet)
  THEN RAISE EXCEPTION 'M107_CP1_UNMET_DEPENDENCY'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.lf_router_action_registry
      WHERE operation_code='ACTUALIZACION_DB_LF' AND asset_type='MIGRATION'
        AND action_code='UPDATE' AND status='ACTIVE' AND write_allowed)
  THEN RAISE EXCEPTION 'M107_CP1_TRAIN_ROUTE_NOT_ACTIVE'; END IF;
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
      v_plan,v_unit,'SOAK_CRITERIA_ASIS');
  IF v_spec->>'action_kind' IS DISTINCT FROM 'OBSERVE_ONCE'
     OR (v_spec->>'requires_material_execution')::boolean IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'M107_CP1_NATURE_DRIFT'; END IF;
  SELECT payload,receipt_sha256 INTO STRICT v_receipt,v_receipt_hash
  FROM programacion.provenance_receipts
  WHERE id=38 AND receipt_kind='EVIDENCE_VERIFICATION'
    AND subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.11/SOAK_OBSERVATION_HISTORY_V2';
  IF v_receipt_hash !~ '^[0-9a-f]{64}$'
     OR v_receipt->>'schema_version' IS DISTINCT FROM 'SOAK_OBSERVATION_HISTORY_V2'
     OR v_receipt->>'verification_status' IS DISTINCT FROM 'VERIFIED'
     OR v_receipt->>'pass' IS DISTINCT FROM 'true'
     OR (v_receipt->>'screens_total')::integer<>13
     OR (v_receipt->>'families_total')::integer<>47
     OR (v_receipt->>'screens_below_2')::integer<>0
     OR (v_receipt->>'families_below_2')::integer<>0
     OR (v_receipt->>'known_false_pass_signals')::integer<>0
     OR (v_receipt->>'unresolved_d4')::integer<>0
  THEN RAISE EXCEPTION 'M107_CP1_M911_RECEIPT_INVALID'; END IF;
  v_evidence:='supabase://programacion.provenance_receipts/38#sha256='||v_receipt_hash||
      ';policy=SOAK_OBSERVATION_HISTORY_V2;screen=13/13;family=47/47;min_observations=2;false_pass=0;d4=0';
  FOR v_attempt IN 1..2 LOOP
    BEGIN
      UPDATE programacion.engineering_plan_units
      SET exit_criterion=v_new_exit,
          unit_metadata=jsonb_set(
            jsonb_set(unit_metadata,
              '{source_pack_v1,checkpoint_inputs,SOAK_CRITERIA_ASIS,missing}',
              '[]'::jsonb,true),
            '{source_pack_v1,checkpoint_inputs,SOAK_CRITERIA_ASIS,missing_typed}',
            '[]'::jsonb,true)
      WHERE plan_code=v_plan AND unit_code=v_unit
        AND work_item_id=v_work AND exit_criterion=v_old_exit;
      IF NOT FOUND THEN RAISE EXCEPTION 'M107_CP1_CRITERION_UPDATE_DID_NOT_MATCH'; END IF;
      v_state:=programacion.fn_engineering_checkpoint_transition_snapshot_v1(
         v_plan,v_unit,'SOAK_CRITERIA_ASIS','DONE',v_evidence,v_actor,
         'Readback M9.11 receipt 38 VERIFIED; criteria inherited as-of, no new runs.');
      IF v_state#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN
        RAISE EXCEPTION 'M107_CP1_TRANSITION_NOT_APPLIED'; END IF;
      IF v_attempt=1 THEN
        RAISE EXCEPTION 'M107_CP1_ROLLBACK_SENTINEL' USING ERRCODE='PZ107';
      END IF;
    EXCEPTION WHEN SQLSTATE 'PZ107' THEN
      IF v_attempt<>1 THEN RAISE; END IF;
    END;
    IF v_attempt=1 AND (
       (SELECT exit_criterion FROM programacion.engineering_plan_units
        WHERE plan_code=v_plan AND unit_code=v_unit) IS DISTINCT FROM v_old_exit
       OR (SELECT status FROM programacion.engineering_work_checkpoints
           WHERE work_item_id=v_work AND checkpoint_code='SOAK_CRITERIA_ASIS')<>'PENDING'
       OR (SELECT status FROM programacion.engineering_work_items
           WHERE id=v_work)<>'BACKLOG')
    THEN RAISE EXCEPTION 'M107_CP1_ROLLBACK_LEFT_RESIDUE'; END IF;
  END LOOP;
  IF (SELECT status FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work AND checkpoint_code='SOAK_CRITERIA_ASIS')<>'DONE'
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_work AND status='PENDING')<>4
  OR (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)<>'IN_PROGRESS'
  OR (SELECT exit_criterion FROM programacion.engineering_plan_units
       WHERE plan_code=v_plan AND unit_code=v_unit) IS DISTINCT FROM v_new_exit
  THEN RAISE EXCEPTION 'M107_CP1_POST_READBACK_FAILED'; END IF;

  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
      WHERE codigo='IG-M107-SOAK-CRITERION-DRIFT-001')
  THEN RAISE EXCEPTION 'M107_CP1_EKB_ALREADY_PRESENT'; END IF;
  INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,detectability,
    source_context,source_ref)
  VALUES (
    gen_random_uuid(),'IG-M107-SOAK-CRITERION-DRIFT-001','GOVERNANCE',
    'M10.7 heredó umbrales de soak sin semántica histórica as-of',
    'El criterio de M10.7 mencionaba 13/13 y 47/47 pero omitía >=2 observaciones elegibles por pantalla y familia, la ausencia de divergencias D4, y la distinción entre CURRENT y evidencia histórica de M9.11.',
    'Desalineación de proyección textual del contrato M10.7 frente a la autoridad SOAK_OBSERVATION_HISTORY_V2 de M9.11.',
    'SOAK_TEXTUAL_UMBRAL_LEGADO_VS_ASOF_CANONICAL',
    'Antes de CP1 leer M9.11 DONE y el recibo VERIFIED; heredar >=2 as-of, 0 falsos PASS y 0 D4. Reusar historia. No convertir 13/47 en obligación de nuevas corridas ni confundir latest CURRENT con validez histórica. Confirmar los checkpoints posteriores por su naturaleza.',
    'Read-only 2026-10-14: receipt 38 13/13 screens,47/47 families, zero below-2, false_pass=0,D4=0; tres negativos sintéticos rechazados. Migración prueba rollback y comprueba CP1 DONE/CP2 PENDING, sin activar producción.',
    'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
    'VALIDATED_TESTED',v_evidence,now(),now(),'PREFLIGHT',
    'CONTRACT_SEMANTIC_DRIFT','READBACK',
    'Supabase M9.11 receipt 38 and canonical action_spec M10.7 CP1',
    'supabase://programacion.provenance_receipts/38'
  );
END
$m107cp1$;
