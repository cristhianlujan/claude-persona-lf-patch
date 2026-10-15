-- PE10 C4: one exact historical execution, after Git commit, explicitly superseded.
-- Different from no-write cancellations and from COMPL E T E D late-merge reconciliations.
-- Source Git commit preserved; no claims that old commit was merged or deployed.
-- Correct disposition = SUPERSEDED, not COMPLETED; no profile/currentness mutation.
-- Routed through LF Migration Merge Train. Exact transaction rehearsal and rollback.
BEGIN;
DO $pe10_c4$
DECLARE
  v_old constant text := 'EXEC-LF-SRCR-SEMANTIC-CONDITIONALITY-20260919-001';
  v_next constant text := 'EXEC-LF-SRCR-SEMANTIC-CONDITIONALITY-20260919-002';
  v_sha constant text := '72c57bf9584d9a0a873966c847e676c184036a49';
  v_actor constant text := 'EXEC-PE10-C4-WRITTEN-SUPERSESSION-20261015-005';
  v_event_code constant text := 'PE10_C4.HISTORICAL_WRITTEN_SUPERSEDED.EXEC-LF-SRCR-SEMANTIC-CONDITIONALITY-20260919-001';
  v_payload jsonb;
  v_old_manifest jsonb;
  v_asset_before jsonb;
  v_rid bigint;
BEGIN
  SELECT e.manifest INTO v_old_manifest FROM public.lf_operation_execution e
  WHERE e.execution_id=v_old AND e.operation_code='ACTUALIZACION_PERFIL_LF'
    AND e.status='IN_PROGRESS' AND e.completed_at IS NULL
    AND e.target_type='PERFIL' AND e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.target_path='profiles/systemic_root_cause_repair_lf/schemas/output.schema.json'
    AND e.manifest->>'scope'='SRCR_STATUS_CONDITIONAL_SEMANTICS_V1'
    AND e.manifest->>'runtime_activation'='false'
  FOR UPDATE;
  IF v_old_manifest IS NULL THEN
    RAISE EXCEPTION 'PE10_C4_005_OLD_EXECUTION_PREIMAGE_CHANGED'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution newer
      JOIN public.lf_operation_execution old ON old.execution_id=v_old
    WHERE newer.execution_id=v_next AND newer.operation_code=old.operation_code
      AND newer.target_type=old.target_type AND newer.target_code=old.target_code
      AND newer.target_repo=old.target_repo
      AND newer.status='COMPLETED' AND newer.created_at>old.created_at
      AND newer.manifest->>'supersedes_execution'=v_old
  ) THEN RAISE EXCEPTION 'PE10_C4_005_COMPLETED_EXPLICIT_SUCCESSOR_MISSING'; END IF;
  IF (SELECT count(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_old AND s.status='STEP_PASS_WITH_EVIDENCE')<>12
    OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_old AND s.status<>'STEP_PASS_WITH_EVIDENCE')
    OR (SELECT count(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_old AND s.step_id='github_write'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
        AND s.evidence_payload->>'commit_sha'=v_sha)<>1
    OR (SELECT count(*) FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_old AND s.step_id='github_readback'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
        AND s.evidence_payload->>'exact_head'=v_sha
        AND s.evidence_payload->>'sha_match'='true')<>1
    OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_old AND s.step_id IN ('post_merge_reconcile','close','report_output'))
  THEN RAISE EXCEPTION 'PE10_C4_005_EXACT_GIT_PROVENANCE_OR_STEPS_CHANGED'; END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>17
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u USING(work_item_id)
      WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
        AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
    OR (SELECT count(*) FROM public.lf_operation_registry
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1'
        AND status='PRODUCCION_CONTROLADA')<>1
  THEN RAISE EXCEPTION 'PE10_C4_005_GLOBAL_PREIMAGE_CHANGED'; END IF;
  IF (SELECT count(*) FROM private.lf_event_type_contracts_v2
      WHERE event_type='ARTIFACT_RECONCILED' AND active
        AND contract_mode='OPERATIONAL'
        AND 'operational-event/v2'=ANY(allowed_evidence_schemas))<>1
  THEN RAISE EXCEPTION 'PE10_C4_005_EVENT_CONTRACT_CHANGED'; END IF;
  IF EXISTS (SELECT 1 FROM public.lf_eventos
    WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo=v_event_code)
  THEN RAISE EXCEPTION 'PE10_C4_005_ALREADY_DISPOSED'; END IF;
  SELECT to_jsonb(a) INTO v_asset_before FROM public.lf_activos a
    WHERE a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      AND a.tipo_activo='PERFIL' AND a.archived_at IS NULL;
  IF v_asset_before IS NULL THEN RAISE EXCEPTION 'PE10_C4_005_PROFILE_MISSING'; END IF;

  v_payload:=jsonb_build_object(
    'evidence_schema_version','operational-event/v2',
    'execution_id',v_actor,'producer','PE10_C4_EXACT_GIT_WRITTEN_SUPERSESSION_V1',
    'purpose','Close one explicitly superseded candidate while preserving old Git write evidence',
    'acceptance_declared',false,'occurred_at',clock_timestamp(),
    'operation_code','ACTUALIZACION_PERFIL_LF',
    'checkpoint','PE10_C4',
    'historical_execution_id',v_old,'successor_execution_id',v_next,
    'historical_source_commit_sha',v_sha,
    'historical_github_write_existed',true,
    'historical_github_readback_existed',true,
    'historical_merge_verified',false,
    'historical_deploy_verified',false,
    'successor_status_at_preflight','COMPLETED',
    'disposition','SUPERSEDED',
    'independent_assurance_pass',false,
    'profile_source_not_rewound',true,
    'source_manifest_preserved',true,
    'cutover_admitted',false
  );
  IF private.fn_lf_event_acceptance_signal_v2('ARTIFACT_RECONCILED',
    v_event_code,'Historical Git write superseded, not admitted or deployed',v_payload) IS NOT NULL
  THEN RAISE EXCEPTION 'PE10_C4_005_FALSE_EVENT_ACCEPTANCE_SIGNAL'; END IF;

  -- True rollback rehearsal of the exact eventual insert and status transition.
  BEGIN
    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
      created_by_execution_id,payload)
    VALUES('ARTIFACT_RECONCILED','EXECUTION',v_event_code,
      'Historical Git write superseded, not admitted or deployed',
      'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload)
    RETURNING id INTO v_rid;
    UPDATE public.lf_operation_execution
      SET status='SUPERSEDED',completed_at=clock_timestamp(),
          updated_by_execution_id=v_actor
      WHERE execution_id=v_old AND status='IN_PROGRESS' AND manifest=v_old_manifest;
    IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_005_DRY_UPDATE_REJECTED'; END IF;
    IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>16
      OR (SELECT count(*) FROM public.lf_eventos
        WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo=v_event_code)<>1
    THEN RAISE EXCEPTION 'PE10_C4_005_DRY_READBACK_FAILED'; END IF;
    RAISE EXCEPTION 'PE10_C4_005_INTENTIONAL_TEST_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'PE10_C4_005_INTENTIONAL_TEST_ROLLBACK' THEN RAISE; END IF;
  END;
  IF (SELECT status FROM public.lf_operation_execution
      WHERE execution_id=v_old)<>'IN_PROGRESS'
    OR (SELECT manifest FROM public.lf_operation_execution
      WHERE execution_id=v_old) IS DISTINCT FROM v_old_manifest
    OR EXISTS(SELECT 1 FROM public.lf_eventos
      WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo=v_event_code)
  THEN RAISE EXCEPTION 'PE10_C4_005_TEST_ROLLBACK_RESIDUAL'; END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
    created_by_execution_id,payload)
  VALUES('ARTIFACT_RECONCILED','EXECUTION',v_event_code,
    'Historical Git write superseded, not admitted or deployed',
    'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload)
  RETURNING id INTO v_rid;
  UPDATE public.lf_operation_execution
    SET status='SUPERSEDED',completed_at=clock_timestamp(),
        updated_by_execution_id=v_actor
    WHERE execution_id=v_old AND status='IN_PROGRESS' AND manifest=v_old_manifest;
  IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_005_FINAL_UPDATE_REJECTED'; END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution
       WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>16
    OR (SELECT count(*) FROM public.lf_operation_execution
       WHERE execution_id=v_old AND status='SUPERSEDED'
         AND updated_by_execution_id=v_actor AND manifest=v_old_manifest)<>1
    OR (SELECT count(*) FROM public.lf_eventos
       WHERE id=v_rid AND evento_tipo='ARTIFACT_RECONCILED'
         AND entidad_codigo=v_event_code
         AND payload->>'historical_source_commit_sha'=v_sha
         AND payload->>'historical_github_write_existed'='true'
         AND payload->>'historical_merge_verified'='false'
         AND payload->>'disposition'='SUPERSEDED')<>1
    OR (SELECT to_jsonb(a) FROM public.lf_activos a
       WHERE a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
         AND a.tipo_activo='PERFIL' AND a.archived_at IS NULL) IS DISTINCT FROM v_asset_before
    OR (SELECT count(*) FROM public.lf_operation_registry
       WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1')<>1
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
       JOIN programacion.engineering_plan_units u USING(work_item_id)
       WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
         AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
  THEN RAISE EXCEPTION 'PE10_C4_005_FINAL_READBACK_FAILED'; END IF;
END
$pe10_c4$;
COMMIT;
