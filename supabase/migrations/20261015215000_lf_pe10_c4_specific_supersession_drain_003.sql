-- PE10_C4 / targeted historical disposition #003
-- Router -> ACTUALIZACION_DB_LF -> LF Migration Merge Train.
-- Only specific historical execution ending -002, explicitly superseded by -003.
-- No auto/bulk closure, no synthetic PASS, no profile or authority mutation.
-- Historical execution is SUPERSEDED, NOT COMPLETED, with source evidence preserved.
-- Transactional positive, deliberate rollback, negative, then exact replay/readback.
BEGIN;
DO $pe10_c4$
DECLARE
  v_old constant text := 'EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-002';
  v_new constant text := 'EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-003';
  v_actor constant text := 'EXEC-PE10-C4-SPECIFIC-SUPERSESSION-20261015-003';
  v_eventcode constant text := 'PE10_C4.HISTORICAL_EXECUTION_SUPERSEDED.EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-002';
  v_payload jsonb;
  v_event_id bigint;
  v_old_manifest jsonb;
  v_asset_before jsonb;
  v_count integer;
BEGIN
  -- No closed execution, source-asset mutation or unproved successor allowed.
  SELECT e.manifest INTO v_old_manifest
  FROM public.lf_operation_execution e
  WHERE e.execution_id=v_old
    AND e.operation_code='ACTUALIZACION_PERFIL_LF'
    AND e.status='IN_PROGRESS' AND e.target_type='PERFIL'
    AND e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.target_path='profiles/systemic_root_cause_repair_lf'
    AND e.completed_at IS NULL
  FOR UPDATE;
  IF NOT FOUND OR v_old_manifest IS NULL
  THEN RAISE EXCEPTION 'PE10_C4_003_LEGACY_PREIMAGE_NOT_CURRENT'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution e
    JOIN public.lf_operation_execution old ON old.execution_id=v_old
    WHERE e.execution_id=v_new
      AND e.operation_code=old.operation_code
      AND e.target_type=old.target_type
      AND e.target_code=old.target_code
      AND e.target_repo=old.target_repo
      AND e.status IN ('IN_PROGRESS','COMPLETED')
      AND e.created_at>old.created_at
      AND e.manifest->>'supersedes_execution'=v_old
  ) THEN RAISE EXCEPTION 'PE10_C4_003_EXPLICIT_SUCCESSOR_NOT_VERIFIED'; END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_old AND s.status='STEP_PASS_WITH_EVIDENCE')<>6
     OR (SELECT count(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_old AND s.step_id='pre_write_execution_binding_gate'
        AND s.status='RETURN_TO_ROUTER')<>1
     OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=v_old
        AND s.step_id IN ('github_write','github_readback','deterministic_validation',
                          'semantic_judge','regression_after','post_merge_reconcile',
                          'close','report_output'))
  THEN RAISE EXCEPTION 'PE10_C4_003_OLD_HAD_UNEXPECTED_WRITE_OR_STEPS'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
    WHERE s.execution_id=v_new AND s.step_id='github_write'
      AND s.status='STEP_PASS_WITH_EVIDENCE'
      AND nullif(s.evidence_payload->>'commit_sha','') IS NOT NULL)
  THEN RAISE EXCEPTION 'PE10_C4_003_SUCCESSOR_WRITE_NOT_RECORDED'; END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>22
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u USING(work_item_id)
        WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
          AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C3')<>'DONE'
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u USING(work_item_id)
        WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
          AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
    OR (SELECT count(*) FROM public.lf_operation_registry r
        WHERE r.operation_code='ACTUALIZACION_PERFIL_LF'
          AND r.version='v0.1' AND r.status='PRODUCCION_CONTROLADA')<>1
  THEN RAISE EXCEPTION 'PE10_C4_003_PLAN_OR_VERSION_DRIFT'; END IF;

  IF (SELECT count(*) FROM private.lf_event_type_contracts_v2 e
      WHERE e.event_type='ARTIFACT_RECONCILED' AND e.active
        AND e.contract_mode='OPERATIONAL'
        AND 'operational-event/v2'=ANY(e.allowed_evidence_schemas))<>1
  THEN RAISE EXCEPTION 'PE10_C4_003_EVENT_CONTRACT_NOT_ACTIVE'; END IF;

  IF EXISTS (SELECT 1 FROM public.lf_eventos
      WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo=v_eventcode)
  THEN RAISE EXCEPTION 'PE10_C4_003_ALREADY_DISPOSED'; END IF;

  SELECT to_jsonb(a) INTO v_asset_before FROM public.lf_activos a
  WHERE a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    AND a.tipo_activo='PERFIL' AND a.archived_at IS NULL;
  IF v_asset_before IS NULL
  THEN RAISE EXCEPTION 'PE10_C4_003_PROFILE_ASSET_MISSING'; END IF;

  v_payload := jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',v_actor,
    'producer','PE10_C4_EVIDENCE_BOUND_TERMINAL_DISPOSITION_V1',
    'purpose','Record exact historical supersession after old pre-write RETURN, not a completed update',
    'acceptance_declared',false,
    'occurred_at',clock_timestamp(),
    'operation_code','ACTUALIZACION_PERFIL_LF',
    'checkpoint','PE10_C4',
    'historical_execution_id',v_old,
    'successor_execution_id',v_new,
    'disposition','SUPERSEDED',
    'prior_execution_status','IN_PROGRESS',
    'supersession_basis','EXPLICIT_SUCCESSOR_MANIFEST_SUPERSEDES_EXECUTION',
    'pre_write_gate_status','RETURN_TO_ROUTER',
    'historical_write_recorded',false,
    'successor_write_receipt_present',true,
    'independent_assurance_pass',false,
    'cutover_admission',false,
    'source_manifest_immutable',true,
    'profile_asset_mutated',false,
    'runtime_activation',false
  );
  IF private.fn_lf_event_acceptance_signal_v2('ARTIFACT_RECONCILED',
    v_eventcode,'Historical execution superseded by exact declared successor; no approval',v_payload) IS NOT NULL
  THEN RAISE EXCEPTION 'PE10_C4_003_EVENT_FALSE_ACCEPTANCE_SIGNAL'; END IF;

  ---------------------------------------------------------------------------
  -- Test first, mandatory deliberate subtransaction rollback.
  ---------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
      created_by_execution_id,payload
    ) VALUES (
      'ARTIFACT_RECONCILED','EXECUTION',v_eventcode,
      'Historical execution superseded by exact declared successor; no approval',
      'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload
    ) RETURNING id INTO v_event_id;

    UPDATE public.lf_operation_execution
      SET status='SUPERSEDED',completed_at=clock_timestamp(),
          updated_by_execution_id=v_actor
      WHERE execution_id=v_old AND status='IN_PROGRESS' AND manifest=v_old_manifest;
    IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_003_TEST_UPDATE_CAS_FAILED'; END IF;
    IF (SELECT status FROM public.lf_operation_execution
          WHERE execution_id=v_old) <> 'SUPERSEDED'
      OR (SELECT count(*) FROM public.lf_eventos
          WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo=v_eventcode)<>1
      OR (SELECT count(*) FROM public.lf_operation_execution
          WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>21
    THEN RAISE EXCEPTION 'PE10_C4_003_POSITIVE_TEST_READBACK_FAILED'; END IF;

    RAISE EXCEPTION 'PE10_C4_003_MANDATORY_ROLLBACK_SENTINEL';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'PE10_C4_003_MANDATORY_ROLLBACK_SENTINEL' THEN RAISE; END IF;
  END;

  IF (SELECT status FROM public.lf_operation_execution
       WHERE execution_id=v_old) IS DISTINCT FROM 'IN_PROGRESS'
    OR (SELECT manifest FROM public.lf_operation_execution
       WHERE execution_id=v_old) IS DISTINCT FROM v_old_manifest
    OR EXISTS(SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo=v_eventcode)
    OR (SELECT count(*) FROM public.lf_operation_execution
       WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>22
  THEN RAISE EXCEPTION 'PE10_C4_003_NEGATIVE_ROLLBACK_CHECK_FAILED'; END IF;

  ---------------------------------------------------------------------------
  -- Durable exact replay; no raw data, reviewer or current profile changes.
  ---------------------------------------------------------------------------
  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
    created_by_execution_id,payload
  ) VALUES (
    'ARTIFACT_RECONCILED','EXECUTION',v_eventcode,
    'Historical execution superseded by exact declared successor; no approval',
    'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload
  ) RETURNING id INTO v_event_id;

  UPDATE public.lf_operation_execution
    SET status='SUPERSEDED',completed_at=clock_timestamp(),
        updated_by_execution_id=v_actor
    WHERE execution_id=v_old AND status='IN_PROGRESS' AND manifest=v_old_manifest;
  IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_003_FINAL_UPDATE_CAS_FAILED'; END IF;

  IF (SELECT count(*) FROM public.lf_eventos e
      WHERE e.id=v_event_id AND e.evento_tipo='ARTIFACT_RECONCILED'
        AND e.entidad_codigo=v_eventcode
        AND e.payload->>'historical_execution_id'=v_old
        AND e.payload->>'successor_execution_id'=v_new
        AND e.payload->>'disposition'='SUPERSEDED'
        AND e.payload->>'acceptance_declared'='false'
        AND e.payload->>'source_manifest_immutable'='true')<>1
    OR (SELECT count(*) FROM public.lf_operation_execution e
      WHERE e.execution_id=v_old AND e.status='SUPERSEDED'
        AND e.completed_at IS NOT NULL AND e.updated_by_execution_id=v_actor
        AND e.manifest=v_old_manifest)<>1
    OR (SELECT count(*) FROM public.lf_operation_execution e
      WHERE e.operation_code='ACTUALIZACION_PERFIL_LF' AND e.status='IN_PROGRESS')<>21
    OR (SELECT to_jsonb(a) FROM public.lf_activos a
      WHERE a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
        AND a.tipo_activo='PERFIL' AND a.archived_at IS NULL) IS DISTINCT FROM v_asset_before
    OR (SELECT count(*) FROM public.lf_operation_registry r
      WHERE r.operation_code='ACTUALIZACION_PERFIL_LF' AND r.version='v0.1')<>1
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u USING(work_item_id)
        WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
          AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
  THEN RAISE EXCEPTION 'PE10_C4_003_FINAL_READBACK_INVARIANT_FAILED'; END IF;
END
$pe10_c4$;
COMMIT;
