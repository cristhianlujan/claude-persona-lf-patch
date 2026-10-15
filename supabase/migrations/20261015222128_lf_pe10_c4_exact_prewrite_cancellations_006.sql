-- PE10_C4 exactly seven independently inventoried abandoned PRE-WRITE attempts.
-- Disposition CANCELLED (NOT completed, PASSED or SUPERSEDED).
-- Historical scopes and original manifests/steps preserved; no declaration the work was done.
-- No automatic/inferred mass close: exact source+step+inactivity preimages for EACH row.
-- Tested inside rollback before durable mutation; no profile/registry/runtime changes.
BEGIN;
DO $pe10_c4$
DECLARE
  v_actor constant text := 'EXEC-PE10-C4-EXACT-INACTIVE-PREWRITE-CANCEL-20261015-006';
  v_code_prefix constant text := 'PE10_C4.PREWRITE_INCOMPLETE_CANCELLED.';
  v_row record;
  v_exec text;
  v_man jsonb;
  v_payload jsonb;
  v_ref text;
  v_asset_pre jsonb;
  v_event bigint;
BEGIN
  IF (SELECT COUNT(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>16
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u USING(work_item_id)
      WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
        AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
    OR (SELECT COUNT(*) FROM public.lf_operation_registry
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1'
        AND status='PRODUCCION_CONTROLADA')<>1
  THEN RAISE EXCEPTION 'PE10_C4_006_INITIAL_STATE_DRIFT'; END IF;
  IF (SELECT COUNT(*) FROM private.lf_event_type_contracts_v2
      WHERE event_type='ARTIFACT_RECONCILED' AND active
        AND contract_mode='OPERATIONAL'
        AND 'operational-event/v2'=ANY(allowed_evidence_schemas))<>1
  THEN RAISE EXCEPTION 'PE10_C4_006_EVENT_AUTHORITY_MISSING'; END IF;
  SELECT to_jsonb(a) INTO v_asset_pre FROM public.lf_activos a
    WHERE a.tipo_activo='PERFIL'
      AND a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      AND a.archived_at IS NULL;
  IF v_asset_pre IS NULL THEN RAISE EXCEPTION 'PE10_C4_006_PROFILE_PREIMAGE_MISSING'; END IF;

  -- Fixed individually investigated executions and exact observed step counts.
  FOR v_row IN SELECT * FROM (VALUES
      ('EXEC-LF-SRCR-PROFILE-RUNTIME-BOUNDED-20260919-001',6,1),
      ('EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',6,1),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-001',0,5),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-3e36ab10-5001-464f-9a90-74b515e637e2',1,0),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-V03-BASELINE-20260921-001',6,1),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-BASELINE-20260921-014',6,0),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-SEMANTIC-JUDGE-WIRING-20260922-001',1,0)
    ) AS x(exec_id,passes,nonpasses)
  LOOP
    v_exec:=v_row.exec_id;
    v_ref:=v_code_prefix||v_exec;
    SELECT e.manifest INTO v_man FROM public.lf_operation_execution e
    WHERE e.execution_id=v_exec
      AND e.operation_code='ACTUALIZACION_PERFIL_LF'
      AND e.status='IN_PROGRESS' AND e.completed_at IS NULL
      AND e.target_type='PERFIL'
      AND e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      AND e.target_repo IN ('cristhianlujan/claude-persona-lf-patch','github://cristhianlujan/claude-persona-lf-patch')
      AND e.updated_at < clock_timestamp()-interval '14 days'
      AND (e.lease_expires_at IS NULL OR e.lease_expires_at<clock_timestamp())
    FOR UPDATE;
    IF v_man IS NULL THEN RAISE EXCEPTION 'PE10_C4_006_EXACT_EXECUTION_ACTIVE_OR_NOT_FOUND:%',v_exec; END IF;
    IF (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
         WHERE s.execution_id=v_exec AND s.status='STEP_PASS_WITH_EVIDENCE')<>v_row.passes
       OR (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
         WHERE s.execution_id=v_exec AND s.status<>'STEP_PASS_WITH_EVIDENCE')<>v_row.nonpasses
       OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
         WHERE s.execution_id=v_exec AND s.step_id IN
           ('github_write','github_readback','deterministic_validation',
            'semantic_judge','regression_after','post_merge_reconcile','close','report_output'))
       OR EXISTS (SELECT 1 FROM public.lf_operation_execution n
         WHERE n.manifest->>'supersedes_execution'=v_exec
           AND n.operation_code='ACTUALIZACION_PERFIL_LF')
    THEN RAISE EXCEPTION 'PE10_C4_006_PREWRITE_OR_SUCCESSOR_DRIFT:%',v_exec; END IF;
    IF EXISTS (SELECT 1 FROM public.lf_eventos ev
      WHERE ev.evento_tipo='ARTIFACT_RECONCILED' AND ev.entidad_codigo=v_ref)
    THEN RAISE EXCEPTION 'PE10_C4_006_ALREADY_DISPOSED:%',v_exec; END IF;
  END LOOP;

  -------------------------------------------------------------------------
  -- TEST FIRST: exact cancellation plus event for each manually selected row.
  -------------------------------------------------------------------------
  BEGIN
    FOR v_row IN SELECT * FROM (VALUES ('EXEC-LF-SRCR-PROFILE-RUNTIME-BOUNDED-20260919-001',6,1),
      ('EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',6,1),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-001',0,5),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-3e36ab10-5001-464f-9a90-74b515e637e2',1,0),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-V03-BASELINE-20260921-001',6,1),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-BASELINE-20260921-014',6,0),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-SEMANTIC-JUDGE-WIRING-20260922-001',1,0)) AS x(exec_id,passes,nonpasses)
    LOOP
      v_exec:=v_row.exec_id; v_ref:=v_code_prefix||v_exec;
      SELECT e.manifest INTO v_man FROM public.lf_operation_execution e WHERE e.execution_id=v_exec;
      v_payload:=jsonb_build_object(
        'evidence_schema_version','operational-event/v2',
        'execution_id',v_actor,'producer','PE10_C4_HISTORICAL_NONWRITTEN_DISPOSITION_V1',
        'purpose','Cancel an inactive historical updater attempt without treating its unfinished work as delivered',
        'acceptance_declared',false,'occurred_at',clock_timestamp(),
        'operation_code','ACTUALIZACION_PERFIL_LF','checkpoint','PE10_C4',
        'historical_execution_id',v_exec,
        'prior_status','IN_PROGRESS',
        'disposition','CANCELLED',
        'reason','ABANDONED_HISTORICAL_PREWRITE_NO_GIT_EVIDENCE',
        'historical_passed_steps',v_row.passes,
        'historical_nonpass_steps',v_row.nonpasses,
        'retained_original_scope',v_man->'scope',
        'retained_manifest_sha256',encode(extensions.digest(convert_to(v_man::text,'UTF8'),'sha256'),'hex'),
        'work_delivered',false,
        'unfinished_work_preserved_for_future_triage',true,
        'github_write_evidenced',false,
        'current_profile_changed',false,
        'v02_activated',false
      );
      INSERT INTO public.lf_eventos(
        evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload
      ) VALUES ('ARTIFACT_RECONCILED','EXECUTION',v_ref,
       'Inactive historic pre-write execution cancelled without asserting delivered work',
       'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload) RETURNING id INTO v_event;
      UPDATE public.lf_operation_execution e
        SET status='CANCELLED',completed_at=clock_timestamp(),updated_by_execution_id=v_actor
        WHERE e.execution_id=v_exec AND e.status='IN_PROGRESS' AND e.manifest=v_man;
      IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_006_DRY_CANCELLATION_REJECTED:%',v_exec; END IF;
    END LOOP;
    IF (SELECT count(*) FROM public.lf_operation_execution
        WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>9
      OR (SELECT count(*) FROM public.lf_eventos
        WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo LIKE v_code_prefix||'%')<>7
    THEN RAISE EXCEPTION 'PE10_C4_006_DRY_READBACK_FAILED'; END IF;
    RAISE EXCEPTION 'PE10_C4_006_DELIBERATE_ROLLBACK_SENTINEL';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'PE10_C4_006_DELIBERATE_ROLLBACK_SENTINEL' THEN RAISE; END IF;
  END;
  -- NEGATIVE: test side effects must be absent.
  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>16
    OR EXISTS(SELECT 1 FROM public.lf_eventos
      WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo LIKE v_code_prefix||'%')
  THEN RAISE EXCEPTION 'PE10_C4_006_ROLLBACK_RESIDUAL_EFFECTS'; END IF;

  -------------------------------------------------------------------------
  -- DURABLE replay: original exact case keys and payload contract.
  -------------------------------------------------------------------------
  FOR v_row IN SELECT * FROM (VALUES ('EXEC-LF-SRCR-PROFILE-RUNTIME-BOUNDED-20260919-001',6,1),
      ('EXEC-LF-SRCR-PROFILE-PARTITION-V1-20260919-001',6,1),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-CLOSURE-20260919-001',0,5),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-3e36ab10-5001-464f-9a90-74b515e637e2',1,0),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-V03-BASELINE-20260921-001',6,1),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-BASELINE-20260921-014',6,0),
      ('EXEC-ACTUALIZACION-PERFIL-SRCR-SEMANTIC-JUDGE-WIRING-20260922-001',1,0)) AS x(exec_id,passes,nonpasses)
  LOOP
    v_exec:=v_row.exec_id; v_ref:=v_code_prefix||v_exec;
    SELECT e.manifest INTO v_man FROM public.lf_operation_execution e WHERE e.execution_id=v_exec;
    v_payload:=jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'execution_id',v_actor,'producer','PE10_C4_HISTORICAL_NONWRITTEN_DISPOSITION_V1',
      'purpose','Cancel an inactive historical updater attempt without treating its unfinished work as delivered',
      'acceptance_declared',false,'occurred_at',clock_timestamp(),
      'operation_code','ACTUALIZACION_PERFIL_LF','checkpoint','PE10_C4',
      'historical_execution_id',v_exec,
      'prior_status','IN_PROGRESS',
      'disposition','CANCELLED',
      'reason','ABANDONED_HISTORICAL_PREWRITE_NO_GIT_EVIDENCE',
      'historical_passed_steps',v_row.passes,
      'historical_nonpass_steps',v_row.nonpasses,
      'retained_original_scope',v_man->'scope',
      'retained_manifest_sha256',encode(extensions.digest(convert_to(v_man::text,'UTF8'),'sha256'),'hex'),
      'work_delivered',false,
      'unfinished_work_preserved_for_future_triage',true,
      'github_write_evidenced',false,
      'current_profile_changed',false,
      'v02_activated',false
    );
    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload
    ) VALUES ('ARTIFACT_RECONCILED','EXECUTION',v_ref,
     'Inactive historic pre-write execution cancelled without asserting delivered work',
     'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload) RETURNING id INTO v_event;
    UPDATE public.lf_operation_execution e
      SET status='CANCELLED',completed_at=clock_timestamp(),updated_by_execution_id=v_actor
      WHERE e.execution_id=v_exec AND e.status='IN_PROGRESS' AND e.manifest=v_man;
    IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_006_FINAL_CANCELLATION_REJECTED:%',v_exec; END IF;
    IF (SELECT count(*) FROM public.lf_operation_execution e
      WHERE e.execution_id=v_exec AND e.status='CANCELLED'
        AND e.manifest=v_man AND e.updated_by_execution_id=v_actor
        AND e.completed_at IS NOT NULL)<>1
     OR (SELECT count(*) FROM public.lf_eventos ev
      WHERE ev.id=v_event AND ev.entidad_codigo=v_ref
        AND ev.payload->>'disposition'='CANCELLED'
        AND ev.payload->>'historical_execution_id'=v_exec
        AND ev.payload->>'work_delivered'='false')<>1
    THEN RAISE EXCEPTION 'PE10_C4_006_FINAL_CASE_READBACK_FAILED:%',v_exec; END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.lf_operation_execution
     WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>9
    OR (SELECT to_jsonb(a) FROM public.lf_activos a
      WHERE a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
        AND a.tipo_activo='PERFIL' AND a.archived_at IS NULL) IS DISTINCT FROM v_asset_pre
    OR (SELECT count(*) FROM public.lf_operation_registry
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1')<>1
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u USING(work_item_id)
      WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
        AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
  THEN RAISE EXCEPTION 'PE10_C4_006_FINAL_GLOBAL_READBACK_FAILED'; END IF;
END
$pe10_c4$;
COMMIT;