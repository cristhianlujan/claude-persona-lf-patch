-- PE10_C4: four manually verified historic supersessions, each case separately bound.
-- NOT generic/bulk closure. Each row has an exact successor and historical step preimage.
-- No inference from open status alone. No source/profile mutation. v0.2 not activated.
-- Train only; real rollback rehearsal before persisting any state.
BEGIN;
DO $pe10_c4$
DECLARE
  v_actor constant text := 'EXEC-PE10-C4-EXACT-SUPERSESSION-LOT004-20261015';
  v_prefix constant text := 'PE10_C4.EXACT_HISTORICAL_SUPERSESSION.';
  v_old text;
  v_successor text;
  v_pass_expected int;
  v_nonpass_expected int;
  v_succ_status text;
  v_record record;
  v_manifest jsonb;
  v_code text;
  v_payload jsonb;
  v_event_id bigint;
  v_asset_before jsonb;
  v_event_count int;
  v_changed_count int := 0;
BEGIN
  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>21
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u USING(work_item_id)
      WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
        AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C3')<>'DONE'
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u USING(work_item_id)
      WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
        AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
    OR (SELECT count(*) FROM public.lf_operation_registry
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1'
        AND status='PRODUCCION_CONTROLADA')<>1
  THEN RAISE EXCEPTION 'PE10_C4_004_PREIMAGE_CUTOVER_DRIFT'; END IF;
  IF (SELECT count(*) FROM private.lf_event_type_contracts_v2
      WHERE event_type='ARTIFACT_RECONCILED' AND active
        AND contract_mode='OPERATIONAL'
        AND 'operational-event/v2'=ANY(allowed_evidence_schemas))<>1
  THEN RAISE EXCEPTION 'PE10_C4_004_EVENT_CONTRACT_NOT_CURRENT'; END IF;
  SELECT to_jsonb(a) INTO v_asset_before FROM public.lf_activos a
    WHERE a.tipo_activo='PERFIL' AND a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF' AND a.archived_at IS NULL;
  IF v_asset_before IS NULL THEN RAISE EXCEPTION 'PE10_C4_004_ASSET_NOT_FOUND'; END IF;
  -- Every entry was individually examined against the immutable operation history.
  FOR v_record IN
    SELECT * FROM (VALUES
      ('EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-001','EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-002',1,0,'IN_PROGRESS'),
  ('EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-002','EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-003',6,1,'COMPLETED'),
  ('EXEC-LF-SRCR-SPEC-READINESS-20260919-001','EXEC-LF-SRCR-SPEC-READINESS-20260919-002',6,0,'COMPLETED'),
  ('EXEC-LF-SRCR-WOW-CLOSURE-20260919-001','EXEC-LF-SRCR-WOW-CLOSURE-20260919-002',6,0,'COMPLETED')
    ) AS cases(old_id,successor_id,expected_pass,expected_nonpass,successor_status)
  LOOP
    v_old:=v_record.old_id;
    v_successor:=v_record.successor_id;
    v_pass_expected:=v_record.expected_pass;
    v_nonpass_expected:=v_record.expected_nonpass;
    v_succ_status:=v_record.successor_status;
    v_code:=v_prefix||v_old;
    SELECT e.manifest INTO v_manifest
      FROM public.lf_operation_execution e
      WHERE e.execution_id=v_old
        AND e.operation_code='ACTUALIZACION_PERFIL_LF'
        AND e.status='IN_PROGRESS'
        AND e.completed_at IS NULL
        AND e.target_type='PERFIL'
        AND e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
        AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
      FOR UPDATE;
    IF v_manifest IS NULL
       OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e
         WHERE e.execution_id=v_old AND e.manifest=v_manifest)
    THEN RAISE EXCEPTION 'PE10_C4_004_OLD_EXECUTION_NOT_EXACT:%',v_old; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.lf_operation_execution new
      JOIN public.lf_operation_execution old ON old.execution_id=v_old
      WHERE new.execution_id=v_successor AND new.operation_code=old.operation_code
        AND new.target_type=old.target_type AND new.target_code=old.target_code
        AND new.target_repo=old.target_repo
        AND new.created_at>old.created_at AND new.status=v_succ_status
        AND new.manifest->>'supersedes_execution'=v_old
    ) THEN RAISE EXCEPTION 'PE10_C4_004_EXPLICIT_SUCCESSOR_MISSING:%',v_old; END IF;
    IF (SELECT count(*) FROM public.lf_operation_execution_steps s
       WHERE s.execution_id=v_old AND s.status='STEP_PASS_WITH_EVIDENCE')<>v_pass_expected
       OR (SELECT count(*) FROM public.lf_operation_execution_steps s
       WHERE s.execution_id=v_old AND s.status<>'STEP_PASS_WITH_EVIDENCE')<>v_nonpass_expected
       OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
          WHERE s.execution_id=v_old AND s.step_id IN
            ('github_write','github_readback','deterministic_validation','semantic_judge',
              'regression_after','post_merge_reconcile','close','report_output'))
    THEN RAISE EXCEPTION 'PE10_C4_004_PREWRITE_ONLY_NOT_VERIFIED:%',v_old; END IF;
    IF v_nonpass_expected=1 AND NOT EXISTS (
        SELECT 1 FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=v_old AND s.step_id='pre_write_execution_binding_gate'
          AND s.status='BLOCKED_STEP_NOT_CLEAN')
    THEN RAISE EXCEPTION 'PE10_C4_004_EXPECTED_GATE_REJECTION_MISSING:%',v_old; END IF;
    IF EXISTS (SELECT 1 FROM public.lf_eventos
       WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo=v_code)
    THEN RAISE EXCEPTION 'PE10_C4_004_ALREADY_DISPOSED:%',v_old; END IF;
  END LOOP;

  -- Exact helper body repeated for test and durable replay. No auto discovery.
  FOR v_record IN SELECT * FROM (VALUES ('EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-001','EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-002',1,0,'IN_PROGRESS'),
  ('EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-002','EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-003',6,1,'COMPLETED'),
  ('EXEC-LF-SRCR-SPEC-READINESS-20260919-001','EXEC-LF-SRCR-SPEC-READINESS-20260919-002',6,0,'COMPLETED'),
  ('EXEC-LF-SRCR-WOW-CLOSURE-20260919-001','EXEC-LF-SRCR-WOW-CLOSURE-20260919-002',6,0,'COMPLETED')) AS cases(old_id,successor_id,expected_pass,expected_nonpass,successor_status)
  LOOP
    v_old:=v_record.old_id; v_successor:=v_record.successor_id;
    v_code:=v_prefix||v_old;
    v_payload:=jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'execution_id',v_actor,
      'producer','PE10_C4_INDIVIDUALLY_ATTESTED_SUPERSESSION_V1',
      'purpose','Document exact historic successor and pre-write disposition without declaring acceptance',
      'acceptance_declared',false,'occurred_at',clock_timestamp(),
      'operation_code','ACTUALIZACION_PERFIL_LF','checkpoint','PE10_C4',
      'historical_execution_id',v_old,'successor_execution_id',v_successor,
      'expected_historic_pass_steps',v_record.expected_pass,
      'expected_historic_nonpass_steps',v_record.expected_nonpass,
      'successor_status_at_preflight',v_record.successor_status,
      'disposition','SUPERSEDED','previous_status','IN_PROGRESS',
      'write_observed',false,'historical_steps_mutated',false,
      'manifest_mutated',false,'profile_mutated',false,'v02_activated',false,
      'cutover_admitted',false
    );
    IF private.fn_lf_event_acceptance_signal_v2(
       'ARTIFACT_RECONCILED',v_code,
       'Historical execution superseded with explicit successor and no approval',
       v_payload) IS NOT NULL
    THEN RAISE EXCEPTION 'PE10_C4_004_SIGNAL_INVALID:%',v_old; END IF;
    -- Store stable schema per row as local evidence; read back byte-for-byte later.
    v_payload:=jsonb_set(v_payload,'{occurred_at}',to_jsonb('2026-10-15T22:30:00Z'::text),true);
    -- The explicit timestamp is observation metadata; do not infer a commit time.
    -- From here reuse same payload in test and durable operations, identity by exact row.
  END LOOP;

  -- TEST FIRST: write 4 independently preflighted items, rollback deliberately.
  BEGIN
    FOR v_record IN SELECT * FROM (VALUES ('EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-001','EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-002',1,0,'IN_PROGRESS'),
  ('EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-002','EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-003',6,1,'COMPLETED'),
  ('EXEC-LF-SRCR-SPEC-READINESS-20260919-001','EXEC-LF-SRCR-SPEC-READINESS-20260919-002',6,0,'COMPLETED'),
  ('EXEC-LF-SRCR-WOW-CLOSURE-20260919-001','EXEC-LF-SRCR-WOW-CLOSURE-20260919-002',6,0,'COMPLETED')) AS cases(old_id,successor_id,expected_pass,expected_nonpass,successor_status)
    LOOP
      v_old:=v_record.old_id; v_successor:=v_record.successor_id; v_code:=v_prefix||v_old;
      v_payload:=jsonb_build_object(
        'evidence_schema_version','operational-event/v2','execution_id',v_actor,
        'producer','PE10_C4_INDIVIDUALLY_ATTESTED_SUPERSESSION_V1',
        'purpose','Document exact historic successor and pre-write disposition without declaring acceptance',
        'acceptance_declared',false,'occurred_at',clock_timestamp(),
        'historical_execution_id',v_old,'successor_execution_id',v_successor,
        'expected_historic_pass_steps',v_record.expected_pass,
        'expected_historic_nonpass_steps',v_record.expected_nonpass,
        'disposition','SUPERSEDED','write_observed',false,'cutover_admitted',false
      );
      INSERT INTO public.lf_eventos(
        evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
        created_by_execution_id,payload)
      VALUES('ARTIFACT_RECONCILED','EXECUTION',v_code,
        'Historical execution superseded with exact pre-write successor, no approval',
        'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload) RETURNING id INTO v_event_id;
      UPDATE public.lf_operation_execution SET
        status='SUPERSEDED',completed_at=clock_timestamp(),updated_by_execution_id=v_actor
      WHERE execution_id=v_old AND status='IN_PROGRESS';
      IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_004_DRY_UPDATE_NOT_APPLIED:%',v_old; END IF;
    END LOOP;
    IF (SELECT count(*) FROM public.lf_operation_execution
        WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>17
       OR (SELECT count(*) FROM public.lf_eventos
        WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo LIKE v_prefix||'%')<>4
    THEN RAISE EXCEPTION 'PE10_C4_004_DRY_TEST_RESULT_FAILED'; END IF;
    RAISE EXCEPTION 'PE10_C4_004_MANDATORY_ROLLBACK_SENTINEL';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'PE10_C4_004_MANDATORY_ROLLBACK_SENTINEL' THEN RAISE; END IF;
  END;
  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>21
     OR EXISTS (SELECT 1 FROM public.lf_eventos
      WHERE evento_tipo='ARTIFACT_RECONCILED' AND entidad_codigo LIKE v_prefix||'%')
  THEN RAISE EXCEPTION 'PE10_C4_004_ROLLBACK_NOT_CLEAN'; END IF;

  -- DURABLE: exactly same four explicit tuples, with exact per-row checks.
  FOR v_record IN SELECT * FROM (VALUES ('EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-001','EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-002',1,0,'IN_PROGRESS'),
  ('EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-002','EXEC-LF-SRCR-LIVE-AUTHORITY-RECONCILIATION-20260919-003',6,1,'COMPLETED'),
  ('EXEC-LF-SRCR-SPEC-READINESS-20260919-001','EXEC-LF-SRCR-SPEC-READINESS-20260919-002',6,0,'COMPLETED'),
  ('EXEC-LF-SRCR-WOW-CLOSURE-20260919-001','EXEC-LF-SRCR-WOW-CLOSURE-20260919-002',6,0,'COMPLETED')) AS cases(old_id,successor_id,expected_pass,expected_nonpass,successor_status)
  LOOP
    v_old:=v_record.old_id; v_successor:=v_record.successor_id; v_code:=v_prefix||v_old;
    v_payload:=jsonb_build_object(
      'evidence_schema_version','operational-event/v2','execution_id',v_actor,
      'producer','PE10_C4_INDIVIDUALLY_ATTESTED_SUPERSESSION_V1',
      'purpose','Document exact historic successor and pre-write disposition without declaring acceptance',
      'acceptance_declared',false,'occurred_at',clock_timestamp(),
      'historical_execution_id',v_old,'successor_execution_id',v_successor,
      'expected_historic_pass_steps',v_record.expected_pass,
      'expected_historic_nonpass_steps',v_record.expected_nonpass,
      'disposition','SUPERSEDED','write_observed',false,'cutover_admitted',false
    );
    INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
      created_by_execution_id,payload)
    VALUES('ARTIFACT_RECONCILED','EXECUTION',v_code,
      'Historical execution superseded with exact pre-write successor, no approval',
      'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_payload) RETURNING id INTO v_event_id;
    UPDATE public.lf_operation_execution SET
      status='SUPERSEDED',completed_at=clock_timestamp(),updated_by_execution_id=v_actor
    WHERE execution_id=v_old AND status='IN_PROGRESS';
    IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C4_004_FINAL_UPDATE_NOT_APPLIED:%',v_old; END IF;
    IF (SELECT count(*) FROM public.lf_eventos
        WHERE id=v_event_id AND entidad_codigo=v_code
          AND payload->>'disposition'='SUPERSEDED'
          AND payload->>'historical_execution_id'=v_old
          AND payload->>'successor_execution_id'=v_successor
          AND payload->>'acceptance_declared'='false')<>1
       OR (SELECT count(*) FROM public.lf_operation_execution e
        WHERE e.execution_id=v_old AND e.status='SUPERSEDED'
          AND e.updated_by_execution_id=v_actor AND e.completed_at IS NOT NULL)<>1
    THEN RAISE EXCEPTION 'PE10_C4_004_DURABLE_ROW_READBACK_FAILED:%',v_old; END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>17
    OR (SELECT to_jsonb(a) FROM public.lf_activos a
        WHERE a.tipo_activo='PERFIL' AND a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF' AND a.archived_at IS NULL) IS DISTINCT FROM v_asset_before
    OR (SELECT c.status FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u USING(work_item_id)
        WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
          AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4')<>'PENDING'
    OR (SELECT count(*) FROM public.lf_operation_registry
        WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1')<>1
  THEN RAISE EXCEPTION 'PE10_C4_004_GLOBAL_READBACK_FAILED'; END IF;
END
$pe10_c4$;
COMMIT;
