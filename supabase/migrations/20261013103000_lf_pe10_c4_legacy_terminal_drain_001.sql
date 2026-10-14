BEGIN;

-- PE10_C4 legacy terminal drain lot 001.
-- Scope: exactly one historical ACTUALIZACION_PERFIL_LF execution with independently
-- verified merged provenance (PR #966). No v0.2 activation, no runtime change, no
-- current lf_activos source/currentness mutation.
DO $pe10$
DECLARE
  v_execution constant text := 'EXEC-ACTUALIZACION-PERFIL-LF-OIDC-d184fa03-cd43-4e45-ab4e-29e31e9ba262';
  v_actor constant text := 'EXEC-SUPERADMIN-PE10-C4-LEGACY-DRAIN-20261013-001';
  v_write_sha constant text := '56c158fbbda3ee894f4e68d8d560bb28d3343332';
  v_pr_head constant text := 'd300fdf0403a0437ce80e0ae893935cfa8acce65';
  v_merge_sha constant text := 'ba472e65681d0ac059eeecf0397ddd3711ded154';
  v_entrypoint_sha constant text := '7e76aea2226db9c6dc578035d70044bbe0f9313e';
  v_manifest_sha constant text := '43e5913ce35b181d2fc72f732b0d9bb6aae48447';
  v_pack constant text := 'SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2';
  v_pr constant integer := 966;
  v_asset_entry_before text;
  v_asset_manifest_before text;
  v_asset_pack_before text;
  v_asset_pr_before text;
  v_asset_merge_before text;
  v_runtime_before text;
  v_operational_before text;
  v_impact_before text;
  v_doc_before text;
  v_pass integer;
  v_bad integer;
  v_terminal integer;
  v_r jsonb;
  v_post jsonb;
  v_close jsonb;
  v_report jsonb;
BEGIN
  -- Fail closed if the historical execution or its already-recorded evidence drifted.
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution e
    WHERE e.execution_id=v_execution
      AND e.operation_code='ACTUALIZACION_PERFIL_LF'
      AND e.target_type='PERFIL'
      AND e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
      AND e.status='IN_PROGRESS'
  ) THEN
    RAISE EXCEPTION 'PE10_C4_DRAIN_EXECUTION_PREFLIGHT_FAILED';
  END IF;

  SELECT
    count(*) FILTER (WHERE s.status='STEP_PASS_WITH_EVIDENCE'),
    count(*) FILTER (WHERE s.status<>'STEP_PASS_WITH_EVIDENCE'),
    count(*) FILTER (WHERE s.step_id IN ('post_merge_reconcile','close','report_output'))
  INTO v_pass,v_bad,v_terminal
  FROM public.lf_operation_execution_steps s
  WHERE s.execution_id=v_execution;

  IF v_pass<>12 OR v_bad<>0 OR v_terminal<>0 THEN
    RAISE EXCEPTION 'PE10_C4_DRAIN_STEP_PREFLIGHT_FAILED pass=% bad=% terminal=%',
      v_pass,v_bad,v_terminal;
  END IF;

  -- The current asset is materially newer than this historical execution.
  -- Capture currentness and prove this drain never rewinds it.
  SELECT
    a.metadata->>'entrypoint_sha',
    a.metadata->>'manifest_sha',
    coalesce(a.metadata->>'profile_pack_id',a.raw_payload->>'profile_pack_id'),
    a.metadata->>'last_governed_pr',
    a.metadata->>'last_governed_merge_sha',
    a.runtime_estado,a.estado_operativo,a.impacto_automatico,a.estado_documental
  INTO
    v_asset_entry_before,v_asset_manifest_before,v_asset_pack_before,
    v_asset_pr_before,v_asset_merge_before,
    v_runtime_before,v_operational_before,v_impact_before,v_doc_before
  FROM public.lf_activos a
  WHERE a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL;

  IF v_asset_pr_before IS NULL
     OR v_asset_pr_before::integer<=v_pr
     OR v_asset_merge_before IS NULL
     OR v_asset_merge_before=v_merge_sha THEN
    RAISE EXCEPTION 'PE10_C4_DRAIN_CURRENT_ASSET_NOT_NEWER';
  END IF;

  -- Exact payloads are reused byte-for-byte for rollback rehearsal and durable pass.
  v_post := jsonb_build_object(
    'reconciliation_disposition','HISTORICAL_SOURCE_RECONCILED_NO_CURRENTNESS_MUTATION',
    'merge_sha',v_merge_sha,
    'entrypoint_sha',v_entrypoint_sha,
    'manifest_sha',v_manifest_sha,
    'profile_pack_id',v_pack,
    'runtime_state_before',v_runtime_before,
    'runtime_state_after',v_runtime_before,
    'operational_state_preserved',true,
    'automatic_impact_preserved',true,
    'next_gate','LEGACY_TERMINAL_DRAIN_ONLY',
    'historical_pr_number',v_pr,
    'historical_pr_head',v_pr_head,
    'historical_write_sha',v_write_sha,
    'current_asset_mutation',false,
    'blocking_codes','[]'::jsonb
  );

  v_close := jsonb_build_object(
    'all_required_steps_clean',true,
    'open_blockers','[]'::jsonb,
    'runtime_unchanged',true,
    'no_auto_promotion',true,
    'historical_reconciliation',true,
    'current_asset_mutation',false,
    'blocking_codes','[]'::jsonb
  );

  v_report := jsonb_build_object(
    'result','HISTORICAL_SOURCE_RECONCILED_EXECUTION_COMPLETED_NO_CURRENT_ASSET_MUTATION',
    'exact_head',v_merge_sha,
    'evidence_refs',jsonb_build_array(
      'github://cristhianlujan/claude-persona-lf-patch/pull/966',
      'github://cristhianlujan/claude-persona-lf-patch@56c158fbbda3ee894f4e68d8d560bb28d3343332',
      'github://cristhianlujan/claude-persona-lf-patch@d300fdf0403a0437ce80e0ae893935cfa8acce65',
      'github://cristhianlujan/claude-persona-lf-patch@ba472e65681d0ac059eeecf0397ddd3711ded154/profiles/systemic_root_cause_repair_lf',
      'supabase://public/lf_operation_execution/'||v_execution
    ),
    'open_blockers','[]'::jsonb,
    'next_gate','NONE_LEGACY_EXECUTION_CLOSED',
    'current_asset_mutation',false,
    'blocking_codes','[]'::jsonb
  );

  -- Required live rule: execute the exact terminal sequence first inside a nested
  -- transaction and deliberately roll it back. Any unexpected error propagates.
  BEGIN
    v_r := public.lf_record_profile_operation_step_v1(
      v_execution,'post_merge_reconcile',
      'github://cristhianlujan/claude-persona-lf-patch/pull/966#historical-post-merge',
      v_post,v_actor
    );
    IF v_r->>'outcome'<>'STEP_RECORDED' THEN
      RAISE EXCEPTION 'PE10_C4_DRY_POSTMERGE_FAILED:%',v_r;
    END IF;

    v_r := public.lf_record_profile_operation_step_v1(
      v_execution,'close',
      'supabase://public/lf_operation_execution/'||v_execution||'#historical-close',
      v_close,v_actor
    );
    IF v_r->>'outcome'<>'STEP_RECORDED' THEN
      RAISE EXCEPTION 'PE10_C4_DRY_CLOSE_FAILED:%',v_r;
    END IF;

    v_r := public.lf_record_profile_operation_step_v1(
      v_execution,'report_output',
      'github://cristhianlujan/claude-persona-lf-patch/pull/966;supabase://public/lf_operation_execution/'||v_execution,
      v_report,v_actor
    );
    IF v_r->>'outcome'<>'STEP_RECORDED' THEN
      RAISE EXCEPTION 'PE10_C4_DRY_REPORT_FAILED:%',v_r;
    END IF;

    IF (SELECT status FROM public.lf_operation_execution WHERE execution_id=v_execution)<>'COMPLETED' THEN
      RAISE EXCEPTION 'PE10_C4_DRY_COMPLETION_NOT_REACHED';
    END IF;

    RAISE EXCEPTION 'PE10_C4_DRY_RUN_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM<>'PE10_C4_DRY_RUN_ROLLBACK_SENTINEL' THEN
        RAISE;
      END IF;
  END;

  -- Readback proves the rehearsal really rolled back.
  IF (SELECT status FROM public.lf_operation_execution WHERE execution_id=v_execution)<>'IN_PROGRESS'
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_execution
           AND step_id IN ('post_merge_reconcile','close','report_output'))<>0 THEN
    RAISE EXCEPTION 'PE10_C4_DRY_RUN_ROLLBACK_FAILED';
  END IF;

  -- Durable execution: exact same payloads and same canonical recorder.
  v_r := public.lf_record_profile_operation_step_v1(
    v_execution,'post_merge_reconcile',
    'github://cristhianlujan/claude-persona-lf-patch/pull/966#historical-post-merge',
    v_post,v_actor
  );
  IF v_r->>'outcome'<>'STEP_RECORDED' THEN
    RAISE EXCEPTION 'PE10_C4_POSTMERGE_PERSIST_FAILED:%',v_r;
  END IF;

  v_r := public.lf_record_profile_operation_step_v1(
    v_execution,'close',
    'supabase://public/lf_operation_execution/'||v_execution||'#historical-close',
    v_close,v_actor
  );
  IF v_r->>'outcome'<>'STEP_RECORDED' THEN
    RAISE EXCEPTION 'PE10_C4_CLOSE_PERSIST_FAILED:%',v_r;
  END IF;

  v_r := public.lf_record_profile_operation_step_v1(
    v_execution,'report_output',
    'github://cristhianlujan/claude-persona-lf-patch/pull/966;supabase://public/lf_operation_execution/'||v_execution,
    v_report,v_actor
  );
  IF v_r->>'outcome'<>'STEP_RECORDED' THEN
    RAISE EXCEPTION 'PE10_C4_REPORT_PERSIST_FAILED:%',v_r;
  END IF;

  -- Final execution readback.
  IF (SELECT status FROM public.lf_operation_execution WHERE execution_id=v_execution)<>'COMPLETED'
     OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_execution
           AND step_id IN ('post_merge_reconcile','close','report_output')
           AND status='STEP_PASS_WITH_EVIDENCE')<>3 THEN
    RAISE EXCEPTION 'PE10_C4_DRAIN_FINAL_READBACK_FAILED';
  END IF;

  -- Critical negative assertion: current profile authority/currentness did not move.
  IF EXISTS (
    SELECT 1
    FROM public.lf_activos a
    WHERE a.codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
      AND a.tipo_activo='PERFIL'
      AND a.archived_at IS NULL
      AND (
        a.metadata->>'entrypoint_sha' IS DISTINCT FROM v_asset_entry_before OR
        a.metadata->>'manifest_sha' IS DISTINCT FROM v_asset_manifest_before OR
        coalesce(a.metadata->>'profile_pack_id',a.raw_payload->>'profile_pack_id') IS DISTINCT FROM v_asset_pack_before OR
        a.metadata->>'last_governed_pr' IS DISTINCT FROM v_asset_pr_before OR
        a.metadata->>'last_governed_merge_sha' IS DISTINCT FROM v_asset_merge_before OR
        a.runtime_estado IS DISTINCT FROM v_runtime_before OR
        a.estado_operativo IS DISTINCT FROM v_operational_before OR
        a.impacto_automatico IS DISTINCT FROM v_impact_before OR
        a.estado_documental IS DISTINCT FROM v_doc_before
      )
  ) THEN
    RAISE EXCEPTION 'PE10_C4_DRAIN_CURRENT_ASSET_DRIFT';
  END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution
      WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND status='IN_PROGRESS')<>24 THEN
    RAISE EXCEPTION 'PE10_C4_DRAIN_OPEN_COUNT_UNEXPECTED';
  END IF;
END
$pe10$;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT
 'LF-PE10-C4-HISTORICAL-POSTMERGE-CURRENTNESS-REWIND-20261013-001',
 'PROFILE_EVOLUTION',
 'Historical updater reconciliation can rewind the current profile asset',
 'A legacy execution can have valid merged Git provenance while public.lf_activos already points to a much newer governed profile revision. Calling lf_profile_update_post_merge_reconcile_v1 late would overwrite current asset source metadata with the old PR/merge.',
 'The original post-merge reconciler assumes reconciliation occurs immediately after its own merge and has no late-history/currentness guard.',
 'Historical execution drained after newer profile authority exists',
 'For late legacy closure, verify exact PR/head/merge and profile blobs, preserve current lf_activos metadata and state, rehearse the canonical terminal recorder inside rollback, then persist only execution terminal evidence. Never invoke the source-mutating reconciler on an older merge.',
 'PR 966 merged; write SHA 56c158f is ancestor of PR head d300fdf; head is ancestor of merge ba472e6; SKILL blob 7e76aea and manifest blob 43e5913 are read from that merge; durable close must reduce updater IN_PROGRESS 25->24 while current asset remains byte-for-byte equivalent on governed currentness/state fields.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'PE10_C4_LEGACY_DRAIN_001','ACTIVO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/966;supabase://public/lf_operation_execution/EXEC-ACTUALIZACION-PERFIL-LF-OIDC-d184fa03-cd43-4e45-ab4e-29e31e9ba262'
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='LF-PE10-C4-HISTORICAL-POSTMERGE-CURRENTNESS-REWIND-20261013-001'
);

COMMIT;
