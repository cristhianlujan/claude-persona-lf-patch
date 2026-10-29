-- Exactly four abandoned ACTUALIZACION_PERFIL_LF attempts on PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF.
-- Disposition CANCELLED (NOT completed, PASSED or SUPERSEDED). Owner instruction: close what was left pending.
-- The delivered updates of this profile were recorded by other, completed executions
-- (EXEC-...-6862980c text guard, EXEC-...-b62a195e gap-resolution cascade); these four never closed.
-- Original manifests and steps are preserved. No profile, registry or runtime change.
-- Exact id + status + step-set preimages for EACH row; any drift aborts the whole migration.
BEGIN;
DO $lf_cancel$
DECLARE
  v_actor constant text := 'EXEC-LF-PROFILE-UPDATE-ABANDONED-SYSTEMIC-CANCEL-20261029-001';
  v_code_prefix constant text := 'PROFILE_UPDATE.ABANDONED_CANCELLED.';
  v_target constant text := 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF';
  v_row record;
  v_exec text;
  v_ref text;
  v_man jsonb;
  v_event bigint;
  v_before bigint;
  v_asset_pre jsonb;
BEGIN
  SELECT COUNT(*) INTO v_before FROM public.lf_operation_execution
    WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS';
  SELECT to_jsonb(a) INTO v_asset_pre FROM public.lf_activos a
    WHERE a.tipo_activo='PERFIL' AND a.codigo_activo=v_target AND a.archived_at IS NULL;
  IF v_asset_pre IS NULL THEN RAISE EXCEPTION 'CANCEL_SYSTEMIC_PROFILE_PREIMAGE_MISSING'; END IF;
  IF (SELECT COUNT(*) FROM private.lf_event_type_contracts_v2
      WHERE event_type='ARTIFACT_RECONCILED' AND active AND contract_mode='OPERATIONAL'
        AND 'operational-event/v2'=ANY(allowed_evidence_schemas))<>1
  THEN RAISE EXCEPTION 'CANCEL_SYSTEMIC_EVENT_AUTHORITY_MISSING'; END IF;

  FOR v_row IN SELECT * FROM (VALUES
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-f8d54f58-6c41-4746-8b70-9bc0908751c6', 1, false),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-f3fe5acc-7764-433a-ba64-45963675762f', 4, false),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-7adf0d72-c192-4966-b038-fb88886523ff', 11, true),
      ('EXEC-ACTUALIZACION-PERFIL-LF-OIDC-042f8a04-0566-4e1a-9c31-5cee52c39610', 11, true)
    ) AS x(exec_id, passes, wrote_branch)
  LOOP
    v_exec := v_row.exec_id;
    v_ref := v_code_prefix || v_exec;
    SELECT e.manifest INTO v_man FROM public.lf_operation_execution e
      WHERE e.execution_id=v_exec
        AND e.operation_code='ACTUALIZACION_PERFIL_LF'
        AND e.status='IN_PROGRESS' AND e.completed_at IS NULL
        AND e.target_type='PERFIL' AND e.target_code=v_target
        AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
        AND (e.lease_expires_at IS NULL OR e.lease_expires_at < clock_timestamp())
      FOR UPDATE;
    IF v_man IS NULL THEN RAISE EXCEPTION 'CANCEL_SYSTEMIC_EXECUTION_NOT_FOUND_OR_NOT_ABANDONED:%', v_exec; END IF;
    IF (SELECT COUNT(*) FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=v_exec AND s.status='STEP_PASS_WITH_EVIDENCE') <> v_row.passes
       OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=v_exec AND s.status<>'STEP_PASS_WITH_EVIDENCE')
       OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=v_exec AND s.step_id IN
            ('deterministic_validation','semantic_judge','regression_after','post_merge_reconcile','close','report_output'))
       OR (v_row.wrote_branch <> EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=v_exec AND s.step_id='github_write'))
    THEN RAISE EXCEPTION 'CANCEL_SYSTEMIC_STEP_SET_DRIFT:%', v_exec; END IF;
    IF EXISTS (SELECT 1 FROM public.lf_eventos ev
        WHERE ev.evento_tipo='ARTIFACT_RECONCILED' AND ev.entidad_codigo=v_ref)
    THEN RAISE EXCEPTION 'CANCEL_SYSTEMIC_ALREADY_DISPOSED:%', v_exec; END IF;

    INSERT INTO public.lf_eventos(
      evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad, origen, created_by_execution_id, payload
    ) VALUES ('ARTIFACT_RECONCILED', 'EXECUTION', v_ref,
      'Abandoned profile update attempt cancelled without asserting delivered work',
      'INFO', 'DERIVE_FROM_EXECUTION_ID', v_actor,
      jsonb_build_object(
        'evidence_schema_version', 'operational-event/v2',
        'execution_id', v_actor,
        'producer', 'PROFILE_UPDATE_ABANDONED_DISPOSITION_V1',
        'purpose', 'Cancel an abandoned updater attempt that never closed, so it cannot be resumed by mistake',
        'acceptance_declared', false,
        'occurred_at', clock_timestamp(),
        'operation_code', 'ACTUALIZACION_PERFIL_LF',
        'historical_execution_id', v_exec,
        'prior_status', 'IN_PROGRESS',
        'disposition', 'CANCELLED',
        'reason', 'ABANDONED_SUPERSEDED_BY_COMPLETED_EXECUTIONS_OWNER_INSTRUCTED_CLOSE',
        'historical_passed_steps', v_row.passes,
        'retained_manifest_sha256', encode(extensions.digest(convert_to(v_man::text, 'UTF8'), 'sha256'), 'hex'),
        'work_delivered', false,
        'github_write_evidenced', v_row.wrote_branch,
        'current_profile_changed', false,
        'runtime_changed', false
      )) RETURNING id INTO v_event;

    UPDATE public.lf_operation_execution e
      SET status='CANCELLED', completed_at=clock_timestamp(), updated_by_execution_id=v_actor
      WHERE e.execution_id=v_exec AND e.status='IN_PROGRESS' AND e.manifest=v_man;
    IF NOT FOUND THEN RAISE EXCEPTION 'CANCEL_SYSTEMIC_CANCELLATION_REJECTED:%', v_exec; END IF;

    IF (SELECT COUNT(*) FROM public.lf_operation_execution e
          WHERE e.execution_id=v_exec AND e.status='CANCELLED' AND e.manifest=v_man
            AND e.updated_by_execution_id=v_actor AND e.completed_at IS NOT NULL) <> 1
       OR (SELECT COUNT(*) FROM public.lf_eventos ev
          WHERE ev.id=v_event AND ev.entidad_codigo=v_ref
            AND ev.payload->>'disposition'='CANCELLED'
            AND ev.payload->>'work_delivered'='false') <> 1
    THEN RAISE EXCEPTION 'CANCEL_SYSTEMIC_ROW_READBACK_FAILED:%', v_exec; END IF;
  END LOOP;

  IF (SELECT COUNT(*) FROM public.lf_operation_execution
        WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS') <> v_before - 4
     OR (SELECT COUNT(*) FROM public.lf_eventos
        WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo LIKE v_code_prefix || '%') <> 4
     OR (SELECT to_jsonb(a) FROM public.lf_activos a
        WHERE a.tipo_activo='PERFIL' AND a.codigo_activo=v_target AND a.archived_at IS NULL) IS DISTINCT FROM v_asset_pre
  THEN RAISE EXCEPTION 'CANCEL_SYSTEMIC_FINAL_READBACK_FAILED'; END IF;
END
$lf_cancel$;
COMMIT;
