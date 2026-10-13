
-- PE10_C4 drain lot 002:
-- Close two UI Architect historical executions whose immutable PASS-policy snapshot
-- requires exactly 14 steps and does NOT contain post_merge_reconcile.
-- No current profile authority/source mutation and no v0.2 activation.
DO $pe10$
DECLARE
  v_actor constant text := 'EXEC-SUPERADMIN-PE10-C4-UI-TERMINAL-DRAIN-20261013-001';
  v_pr constant integer := 602;
  v_pr_head constant text := 'bc04f694334cdfeaa6eb31993849cf3b22ed164f';
  v_merge_sha constant text := '256f9f2e3669eeda83391500b6612e8cc18cb36e';
  v_ids constant text[] := ARRAY[
    'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-N08C-REPAIR-20260908-001',
    'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-UPSTREAM-BINDING-20260908-002'
  ];
  v_write_shas constant jsonb := jsonb_build_object(
    'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-N08C-REPAIR-20260908-001',
      '2e0acfc6da67dfd42abd0f315b0d6928f9c6390d',
    'EXEC-ACTUALIZACION-PERFIL-UI-ARCHITECT-S26-UPSTREAM-BINDING-20260908-002',
      '8466d967102aa921752020736f1d34870782de56'
  );
  v_exec text;
  v_write text;
  v_r jsonb;
  v_close jsonb;
  v_report jsonb;
  v_q text;
  v_v01 integer;
  v_unclassified integer;
  v_open integer;
  v_checkpoint_status text;
  v_asset_runtime text;
  v_asset_operational text;
  v_asset_impact text;
  v_asset_doc text;
  v_asset_pr text;
  v_asset_merge text;
  v_asset_entry text;
  v_asset_manifest text;
  v_asset_pack text;
BEGIN
  -- Exact execution-step preflight.
  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE execution_id=ANY(v_ids)
        AND operation_code='ACTUALIZACION_PERFIL_LF'
        AND target_type='PERFIL'
        AND target_code='PERFIL-UI-ARCHITECT'
        AND status='IN_PROGRESS')<>2 THEN
    RAISE EXCEPTION 'PE10_C4_UI_DRAIN_EXECUTION_PREFLIGHT_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_execution e
    WHERE e.execution_id=ANY(v_ids)
      AND (
        jsonb_array_length(
          coalesce(e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}','[]'::jsonb)
        )<>14
        OR e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}'
           @> '["post_merge_reconcile"]'::jsonb
      )
  ) THEN
    RAISE EXCEPTION 'PE10_C4_UI_DRAIN_SNAPSHOT_STEPSET_DRIFT';
  END IF;

  IF EXISTS (
    WITH req AS (
      SELECT e.execution_id,x.step_id,x.ord
      FROM public.lf_operation_execution e
      CROSS JOIN LATERAL jsonb_array_elements_text(
        e.manifest#>'{operation_policy_snapshots,PASS_POLICY,policy_payload,required_steps}'
      ) WITH ORDINALITY x(step_id,ord)
      WHERE e.execution_id=ANY(v_ids)
    ), agg AS (
      SELECT r.execution_id,
             count(*)::int required_count,
             count(s.step_id) FILTER (WHERE s.status='STEP_PASS_WITH_EVIDENCE')::int passed,
             count(s.step_id) FILTER (WHERE s.step_id IS NOT NULL AND s.status<>'STEP_PASS_WITH_EVIDENCE')::int nonpass,
             coalesce(array_agg(r.step_id ORDER BY r.ord) FILTER (WHERE s.step_id IS NULL),array[]::text[]) missing
      FROM req r
      LEFT JOIN public.lf_operation_execution_steps s
        ON s.execution_id=r.execution_id AND s.step_id=r.step_id
      GROUP BY r.execution_id
    )
    SELECT 1 FROM agg
    WHERE required_count<>14 OR passed<>12 OR nonpass<>0
       OR missing<>ARRAY['close','report_output']::text[]
  ) THEN
    RAISE EXCEPTION 'PE10_C4_UI_DRAIN_REQUIRED_STEP_READBACK_FAILED';
  END IF;

  -- Bind the two historical writes to the exact evidence already stored in the
  -- immutable execution ledger. External GitHub ancestry was independently
  -- verified before this migration: each write is ancestor of merged PR #602.
  FOREACH v_exec IN ARRAY v_ids LOOP
    v_write := v_write_shas->>v_exec;

    IF NOT EXISTS (
      SELECT 1
      FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_exec
        AND s.step_id='github_write'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
        AND s.evidence_payload->>'commit_sha'=v_write
    ) OR NOT EXISTS (
      SELECT 1
      FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_exec
        AND s.step_id='github_readback'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
        AND s.evidence_payload->>'exact_head'=v_write
        AND coalesce((s.evidence_payload->>'sha_match')::boolean,false)
    ) THEN
      RAISE EXCEPTION 'PE10_C4_UI_DRAIN_GIT_LEDGER_MISMATCH:%',v_exec;
    END IF;
  END LOOP;

  -- Capture current profile authority/state. This terminal-only lot is forbidden
  -- to alter any of these fields.
  SELECT
    a.runtime_estado,a.estado_operativo,a.impacto_automatico,a.estado_documental,
    a.metadata->>'last_governed_pr',
    a.metadata->>'last_governed_merge_sha',
    a.metadata->>'entrypoint_sha',
    a.metadata->>'manifest_sha',
    coalesce(a.metadata->>'profile_pack_id',a.raw_payload->>'profile_pack_id')
  INTO
    v_asset_runtime,v_asset_operational,v_asset_impact,v_asset_doc,
    v_asset_pr,v_asset_merge,v_asset_entry,v_asset_manifest,v_asset_pack
  FROM public.lf_activos a
  WHERE a.codigo_activo='PERFIL-UI-ARCHITECT'
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PE10_C4_UI_DRAIN_CURRENT_ASSET_MISSING';
  END IF;

  SELECT c.status INTO v_checkpoint_status
  FROM programacion.engineering_work_checkpoints c
  JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
  WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND u.unit_code='PE10'
    AND c.checkpoint_code='PE10_C4';

  IF v_checkpoint_status NOT IN ('PENDING','IN_PROGRESS') THEN
    RAISE EXCEPTION 'PE10_C4_UI_DRAIN_CHECKPOINT_STATE_UNEXPECTED:%',v_checkpoint_status;
  END IF;

  SELECT unit_metadata#>>'{action_specs_v1,PE10_C4,verification_queries,0}'
  INTO v_q
  FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
    AND unit_code='PE10';

  IF nullif(v_q,'') IS NULL THEN
    RAISE EXCEPTION 'PE10_C4_UI_DRAIN_VERIFICATION_QUERY_MISSING';
  END IF;

  ---------------------------------------------------------------------------
  -- TEST FIRST: exact close -> report sequence for both executions, then rollback.
  ---------------------------------------------------------------------------
  BEGIN
    FOREACH v_exec IN ARRAY v_ids LOOP
      v_write := v_write_shas->>v_exec;

      v_close := jsonb_build_object(
        'all_required_steps_clean',true,
        'open_blockers','[]'::jsonb,
        'runtime_unchanged',true,
        'no_auto_promotion',true,
        'snapshot_required_step_count',14,
        'post_merge_reconcile_required_by_snapshot',false,
        'current_asset_mutation',false,
        'blocking_codes','[]'::jsonb
      );

      v_r := public.lf_record_profile_operation_step_v1(
        v_exec,
        'close',
        'supabase://public/lf_operation_execution/'||v_exec||'#snapshot-close',
        v_close,
        v_actor
      );
      IF v_r->>'outcome'<>'STEP_RECORDED' THEN
        RAISE EXCEPTION 'PE10_C4_UI_DRY_CLOSE_FAILED:%:%',v_exec,v_r;
      END IF;

      v_report := jsonb_build_object(
        'result','HISTORICAL_EXECUTION_COMPLETED_FROM_IMMUTABLE_SNAPSHOT_STEPSET',
        'exact_head',v_merge_sha,
        'evidence_refs',jsonb_build_array(
          'github://cristhianlujan/claude-persona-lf-patch/pull/602',
          'github://cristhianlujan/claude-persona-lf-patch@'||v_write,
          'github://cristhianlujan/claude-persona-lf-patch@'||v_pr_head,
          'github://cristhianlujan/claude-persona-lf-patch@'||v_merge_sha,
          'supabase://public/lf_operation_execution/'||v_exec
        ),
        'open_blockers','[]'::jsonb,
        'next_gate','NONE_LEGACY_EXECUTION_CLOSED',
        'snapshot_required_step_count',14,
        'post_merge_reconcile_required_by_snapshot',false,
        'github_pr_number',v_pr,
        'github_pr_head',v_pr_head,
        'historical_write_sha',v_write,
        'current_asset_mutation',false,
        'blocking_codes','[]'::jsonb
      );

      v_r := public.lf_record_profile_operation_step_v1(
        v_exec,
        'report_output',
        'github://cristhianlujan/claude-persona-lf-patch/pull/602;supabase://public/lf_operation_execution/'||v_exec,
        v_report,
        v_actor
      );
      IF v_r->>'outcome'<>'STEP_RECORDED' THEN
        RAISE EXCEPTION 'PE10_C4_UI_DRY_REPORT_FAILED:%:%',v_exec,v_r;
      END IF;

      IF (SELECT status FROM public.lf_operation_execution WHERE execution_id=v_exec)<>'COMPLETED' THEN
        RAISE EXCEPTION 'PE10_C4_UI_DRY_COMPLETION_NOT_REACHED:%',v_exec;
      END IF;
    END LOOP;

    EXECUTE v_q INTO v_v01,v_unclassified,v_open;
    IF v_v01<>22 OR v_unclassified<>0 OR v_open<>22 THEN
      RAISE EXCEPTION 'PE10_C4_UI_DRY_C4_READBACK_FAILED v01=% unclassified=% total=%',
        v_v01,v_unclassified,v_open;
    END IF;

    -- Checkpoint transition is not part of historical execution cleanup.

    RAISE EXCEPTION 'PE10_C4_UI_DRY_RUN_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM<>'PE10_C4_UI_DRY_RUN_ROLLBACK_SENTINEL' THEN
        RAISE;
      END IF;
  END;

  -- Rollback readback.
  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE execution_id=ANY(v_ids) AND status='IN_PROGRESS')<>2
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=ANY(v_ids)
           AND step_id IN ('close','report_output'))<>0 THEN
    RAISE EXCEPTION 'PE10_C4_UI_DRY_ROLLBACK_FAILED';
  END IF;

  IF v_checkpoint_status='PENDING' AND EXISTS (
    SELECT 1
    FROM programacion.engineering_work_checkpoints c
    JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
    WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
      AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4'
      AND c.status<>'PENDING'
  ) THEN
    RAISE EXCEPTION 'PE10_C4_UI_DRY_CHECKPOINT_ROLLBACK_FAILED';
  END IF;

  ---------------------------------------------------------------------------
  -- DURABLE REPLAY.
  ---------------------------------------------------------------------------
  FOREACH v_exec IN ARRAY v_ids LOOP
    v_write := v_write_shas->>v_exec;

    v_close := jsonb_build_object(
      'all_required_steps_clean',true,
      'open_blockers','[]'::jsonb,
      'runtime_unchanged',true,
      'no_auto_promotion',true,
      'snapshot_required_step_count',14,
      'post_merge_reconcile_required_by_snapshot',false,
      'current_asset_mutation',false,
      'blocking_codes','[]'::jsonb
    );

    v_r := public.lf_record_profile_operation_step_v1(
      v_exec,
      'close',
      'supabase://public/lf_operation_execution/'||v_exec||'#snapshot-close',
      v_close,
      v_actor
    );
    IF v_r->>'outcome'<>'STEP_RECORDED' THEN
      RAISE EXCEPTION 'PE10_C4_UI_CLOSE_PERSIST_FAILED:%:%',v_exec,v_r;
    END IF;

    v_report := jsonb_build_object(
      'result','HISTORICAL_EXECUTION_COMPLETED_FROM_IMMUTABLE_SNAPSHOT_STEPSET',
      'exact_head',v_merge_sha,
      'evidence_refs',jsonb_build_array(
        'github://cristhianlujan/claude-persona-lf-patch/pull/602',
        'github://cristhianlujan/claude-persona-lf-patch@'||v_write,
        'github://cristhianlujan/claude-persona-lf-patch@'||v_pr_head,
        'github://cristhianlujan/claude-persona-lf-patch@'||v_merge_sha,
        'supabase://public/lf_operation_execution/'||v_exec
      ),
      'open_blockers','[]'::jsonb,
      'next_gate','NONE_LEGACY_EXECUTION_CLOSED',
      'snapshot_required_step_count',14,
      'post_merge_reconcile_required_by_snapshot',false,
      'github_pr_number',v_pr,
      'github_pr_head',v_pr_head,
      'historical_write_sha',v_write,
      'current_asset_mutation',false,
      'blocking_codes','[]'::jsonb
    );

    v_r := public.lf_record_profile_operation_step_v1(
      v_exec,
      'report_output',
      'github://cristhianlujan/claude-persona-lf-patch/pull/602;supabase://public/lf_operation_execution/'||v_exec,
      v_report,
      v_actor
    );
    IF v_r->>'outcome'<>'STEP_RECORDED' THEN
      RAISE EXCEPTION 'PE10_C4_UI_REPORT_PERSIST_FAILED:%:%',v_exec,v_r;
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE execution_id=ANY(v_ids) AND status='COMPLETED')<>2
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=ANY(v_ids)
           AND step_id IN ('close','report_output')
           AND status='STEP_PASS_WITH_EVIDENCE')<>4 THEN
    RAISE EXCEPTION 'PE10_C4_UI_FINAL_EXECUTION_READBACK_FAILED';
  END IF;

  EXECUTE v_q INTO v_v01,v_unclassified,v_open;
  IF v_v01<>22 OR v_unclassified<>0 OR v_open<>22 THEN
    RAISE EXCEPTION 'PE10_C4_UI_FINAL_C4_READBACK_FAILED v01=% unclassified=% total=%',
      v_v01,v_unclassified,v_open;
  END IF;

  -- C3 is still the current checkpoint: no C4 transition or unit_metadata mutation.
  IF EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints c
    JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
    WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
      AND u.unit_code='PE10' AND c.checkpoint_code='PE10_C4'
      AND c.status IS DISTINCT FROM v_checkpoint_status
  ) THEN RAISE EXCEPTION 'PE10_C4_UI_CHECKPOINT_DRIFT'; END IF;

  -- Negative assertion: terminal-only historical closure must not mutate the
  -- current UI Architect authority/currentness/runtime state.
  IF EXISTS (
    SELECT 1
    FROM public.lf_activos a
    WHERE a.codigo_activo='PERFIL-UI-ARCHITECT'
      AND a.tipo_activo='PERFIL'
      AND a.archived_at IS NULL
      AND (
        a.runtime_estado IS DISTINCT FROM v_asset_runtime OR
        a.estado_operativo IS DISTINCT FROM v_asset_operational OR
        a.impacto_automatico IS DISTINCT FROM v_asset_impact OR
        a.estado_documental IS DISTINCT FROM v_asset_doc OR
        a.metadata->>'last_governed_pr' IS DISTINCT FROM v_asset_pr OR
        a.metadata->>'last_governed_merge_sha' IS DISTINCT FROM v_asset_merge OR
        a.metadata->>'entrypoint_sha' IS DISTINCT FROM v_asset_entry OR
        a.metadata->>'manifest_sha' IS DISTINCT FROM v_asset_manifest OR
        coalesce(a.metadata->>'profile_pack_id',a.raw_payload->>'profile_pack_id')
          IS DISTINCT FROM v_asset_pack
      )
  ) THEN
    RAISE EXCEPTION 'PE10_C4_UI_CURRENT_ASSET_DRIFT';
  END IF;
END;
$pe10$;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT
 'LF-PE10-C4-SNAPSHOT-STEPSET-NO-RETROACTIVE-POSTMERGE-20261013-001',
 'PROFILE_EVOLUTION',
 'Historical updater closure must honor immutable required-step snapshot',
 'Two UI Architect executions were clean through regression and lacked only close/report_output. Their immutable PASS-policy snapshot has 14 required steps and does not contain post_merge_reconcile, although the current operation lifecycle now includes that later step.',
 'Evaluating old executions against the current step catalog can introduce retrospective obligations that did not exist in their frozen execution contract.',
 'Legacy execution appears incomplete only because current lifecycle has additional later steps',
 'Resolve required steps from each execution policy snapshot. Do not retroactively require a step absent from that snapshot. Close only when every snapshotted prior step is PASS, no snapshotted step is non-pass, and terminal recorder rehearsal succeeds under rollback.',
 'PR 602 merged; both historical write SHAs are Git ancestors of merge 256f9f2e; each execution is 12/14 PASS with only close/report missing; rollback rehearsal must complete both then restore them; durable replay must reduce C4 open count 24->22 while current UI Architect asset is unchanged.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'PE10_C4_UI_TERMINAL_DRAIN_002','ACTIVO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/602;supabase://public/lf_operation_execution'
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='LF-PE10-C4-SNAPSHOT-STEPSET-NO-RETROACTIVE-POSTMERGE-20261013-001'
);

