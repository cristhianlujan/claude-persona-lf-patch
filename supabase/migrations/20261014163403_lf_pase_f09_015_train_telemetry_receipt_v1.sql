-- LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1 — F09-015 telemetry receipt extension.
-- Adds the existing step envelopes to the existing typed Train receipt.
-- No new table, event type, workflow credential, or write route is introduced.
DO $guard$
BEGIN
  IF to_regprocedure('public.lf_record_migration_train_receipt_v1(text,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'F09_015_TRAIN_RECEIPT_FUNCTION_MISSING';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.lf_record_migration_train_receipt_v1(
  p_execution_id text,
  p_provenance jsonb,
  p_actor text
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $fn$
DECLARE
  c_event_type constant text := 'MIGRATION_TRAIN_RECEIPT_RECORDED';
  c_sha40 constant text := '^[0-9a-f]{40}$';
  m text[];
  v_version text;
  e public.lf_operation_execution%rowtype;
  g public.lf_operation_effect_guard%rowtype;
  v_has_guard boolean;
  s_pre jsonb;
  s_patch jsonb;
  s_verify jsonb;
  v_ledger jsonb;
  v_apply jsonb;
  v_class text;
  v_receipt jsonb;
  v_sha text;
  v_payload jsonb;
  v_desc text;
  v_signal text;
  v_existing record;
  v_event_id bigint;
  c_ts constant text := 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"';
BEGIN
  m := regexp_match(coalesce(p_execution_id, ''), '^EXEC-DB-TRAIN-PR([0-9]+)-([0-9]{14})-R([0-9]+)$');
  IF m IS NULL THEN RAISE EXCEPTION 'TRAIN_RECEIPT_EXECUTION_ID_INVALID:%', p_execution_id; END IF;
  v_version := m[2];
  IF coalesce(p_actor, '') !~ '^LF-MIGRATION-TRAIN-RUN-[0-9]+$' THEN
    RAISE EXCEPTION 'TRAIN_RECEIPT_ACTOR_INVALID:%', p_actor;
  END IF;

  SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id = p_execution_id;
  IF NOT FOUND OR e.operation_code <> 'ACTUALIZACION_DB_LF' OR e.target_type <> 'MIGRATION' THEN
    RAISE EXCEPTION 'TRAIN_RECEIPT_EXECUTION_NOT_FOUND:%', p_execution_id;
  END IF;
  IF e.status NOT IN ('COMPLETED', 'BLOCKED') THEN
    RAISE EXCEPTION 'TRAIN_RECEIPT_EXECUTION_NOT_TERMINAL:%', e.status;
  END IF;
  -- Only the Train run that terminated the execution may emit its receipt.
  IF e.updated_by_execution_id IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'TRAIN_RECEIPT_ACTOR_NOT_TERMINATOR:%', p_actor;
  END IF;

  -- Provenance observed by the Train (shape only; facts come from the run).
  IF jsonb_typeof(p_provenance) IS DISTINCT FROM 'object'
     OR p_provenance->>'label' IS DISTINCT FROM 'ready-to-merge'
     OR length(btrim(coalesce(p_provenance->>'authorized_by', ''))) < 1
     OR coalesce(p_provenance->>'authorized_head', '') !~ c_sha40
     OR coalesce(p_provenance->>'final_head', '') !~ c_sha40
     OR (p_provenance->>'main_before' IS NOT NULL AND p_provenance->>'main_before' !~ c_sha40)
     OR p_provenance->>'diff_class' IS NULL
     OR p_provenance->>'diff_class' NOT IN ('NO_CHANGE', 'SYNC_AND_RETIMESTAMP_ONLY', 'UNEXPECTED_CHANGES', 'NOT_EVALUATED')
     OR jsonb_typeof(coalesce(p_provenance->'diff_unexpected_paths', '[]'::jsonb)) <> 'array'
  THEN
    RAISE EXCEPTION 'TRAIN_RECEIPT_PROVENANCE_INVALID';
  END IF;
  IF e.status = 'COMPLETED' AND p_provenance->>'main_before' IS NULL THEN
    RAISE EXCEPTION 'TRAIN_RECEIPT_MAIN_BEFORE_REQUIRED';
  END IF;
  v_class := p_provenance->>'diff_class';

  SELECT * INTO g FROM public.lf_operation_effect_guard WHERE execution_id = p_execution_id;
  v_has_guard := FOUND;
  SELECT evidence_payload INTO s_pre FROM public.lf_operation_execution_steps
   WHERE execution_id = p_execution_id AND step_id = 'preflight' ORDER BY step_order LIMIT 1;
  SELECT evidence_payload INTO s_patch FROM public.lf_operation_execution_steps
   WHERE execution_id = p_execution_id AND step_id = 'patch' ORDER BY step_order LIMIT 1;
  SELECT evidence_payload INTO s_verify FROM public.lf_operation_execution_steps
   WHERE execution_id = p_execution_id AND step_id = 'verify' ORDER BY step_order LIMIT 1;
  SELECT jsonb_build_object('version', version, 'name', name) INTO v_ledger
    FROM supabase_migrations.schema_migrations WHERE version = v_version;
  v_apply := CASE WHEN v_has_guard THEN g.receipt->'apply_receipt' END;

  -- Neutral key names: lf_eventos rejects acceptance values under status-like keys.
  v_receipt := jsonb_strip_nulls(jsonb_build_object(
    'schema_version', 'LF_MIGRATION_TRAIN_RECEIPT_V1',
    'execution_id', e.execution_id,
    'train_run_id', e.manifest->>'train_run_id',
    'repository', e.target_repo,
    'pr', (e.manifest->>'pr')::bigint,
    'terminal_status', e.status,
    'started_at', to_char(e.started_at AT TIME ZONE 'UTC', c_ts),
    'completed_at', to_char(e.completed_at AT TIME ZONE 'UTC', c_ts),
    'terminated_by', p_actor,
    'human_authorization', jsonb_build_object(
      'label', p_provenance->>'label',
      'authorized_by', p_provenance->>'authorized_by',
      'github_actor', p_provenance->>'github_actor',
      'triggering_actor', p_provenance->>'triggering_actor',
      'run_attempt', p_provenance->>'run_attempt',
      'authorized_head', p_provenance->>'authorized_head'),
    'heads', jsonb_build_object(
      'main_before', p_provenance->>'main_before',
      'authorized_head', p_provenance->>'authorized_head',
      'final_head', p_provenance->>'final_head',
      'execution_head', e.manifest->>'head_sha',
      'final_head_is_execution_head', (p_provenance->>'final_head') = (e.manifest->>'head_sha'),
      'persisted_head', s_pre#>>'{schema_source_readback,persisted_head_sha}',
      'main_after', e.manifest#>>'{closure_evidence,merge_sha}'),
    'diff_check', jsonb_build_object(
      'rule', 'D1_ONLY_MAIN_SYNC_AND_VERSION_RETIMESTAMP',
      'class', v_class,
      'unexpected_paths', coalesce(p_provenance->'diff_unexpected_paths', '[]'::jsonb),
      'note', p_provenance->>'diff_note'),
    'migration', jsonb_build_object(
      'target_code', e.target_code,
      'path', e.target_path,
      'version', v_version,
      'name', s_pre#>>'{exact_target,migration_name}',
      'source_blob', s_pre#>>'{exact_target,source_blob}',
      'source_sha256', e.request_sha256),
    'write_ahead', CASE WHEN v_has_guard THEN jsonb_build_object(
      'effect_scope', g.effect_scope,
      'dispatch_key', g.dispatch_key,
      'request_sha256', g.effect_request_sha256,
      'reserved_at', to_char(g.reserved_at AT TIME ZONE 'UTC', c_ts)) END,
    'effect', CASE WHEN v_has_guard THEN jsonb_build_object(
      'scope', g.effect_scope,
      'phase', g.state,
      'resolved_at', to_char(g.resolved_at AT TIME ZONE 'UTC', c_ts)) END,
    'apply', CASE WHEN v_apply IS NOT NULL THEN jsonb_build_object(
      'code', v_apply->>'code',
      'executor', v_apply->>'executor',
      'ledger_version', v_apply->>'ledger_version',
      'ledger_name', v_apply->>'ledger_name',
      'fallback_used', v_apply->'fallback_used') END,
    'ledger_readback', CASE WHEN v_ledger IS NOT NULL THEN v_ledger || jsonb_build_object(
      'matches_target', (v_ledger->>'version') || '_' || (v_ledger->>'name') = e.target_code) END,
    'telemetry', jsonb_build_object(
      'schema_version', 'pase_f09_015_telemetry_receipt_v1',
      'preflight', coalesce(s_pre->'pase_f09_015_telemetry_v1', '"NOT_OBSERVED"'::jsonb),
      'patch', coalesce(s_patch->'pase_f09_015_telemetry_v1', '"NOT_OBSERVED"'::jsonb),
      'verify', coalesce(s_verify->'pase_f09_015_telemetry_v1', '"NOT_OBSERVED"'::jsonb)),
    'parity', CASE WHEN s_verify IS NOT NULL THEN jsonb_build_object(
      'migration_source_parity', s_verify#>>'{regression_or_parity,migration_source_parity}') END,
    'merge', CASE WHEN e.manifest ? 'closure_evidence' THEN jsonb_build_object(
      'merge_sha', e.manifest#>>'{closure_evidence,merge_sha}',
      'in_main', s_verify#>'{readback,in_main}') END,
    'failure', CASE WHEN e.manifest ? 'failure_reason' THEN jsonb_build_object(
      'reason', e.manifest->>'failure_reason',
      'failed_step', e.manifest#>>'{failure_evidence,failed_step}',
      'error_summary', e.manifest#>>'{failure_evidence,error_summary}',
      'recorded_at', e.manifest->>'failure_recorded_at') END
  ));
  v_sha := encode(extensions.digest(convert_to(v_receipt::text, 'UTF8'), 'sha256'), 'hex');

  SELECT id, payload->>'receipt_sha256' AS sha INTO v_existing
    FROM public.lf_eventos
   WHERE evento_tipo = c_event_type AND entidad_codigo = p_execution_id
   ORDER BY id LIMIT 1;
  IF FOUND THEN
    IF v_existing.sha IS DISTINCT FROM v_sha THEN
      RAISE EXCEPTION 'TRAIN_RECEIPT_CONFLICT:% existing=% new=%', p_execution_id, v_existing.sha, v_sha;
    END IF;
    RETURN jsonb_build_object('outcome', 'TRAIN_RECEIPT_REPLAY', 'event_id', v_existing.id,
                              'receipt_sha256', v_sha, 'execution_id', p_execution_id);
  END IF;

  v_desc := format('Migration Merge Train receipt for %s (%s, diff %s)', e.execution_id, e.status, v_class);
  v_payload := jsonb_build_object(
    'evidence_schema_version', 'operational-event/v2',
    'purpose', 'Typed terminal receipt of one Migration Merge Train execution (PASE-ATOM-F07-X01)',
    'producer', 'lf-migration-merge-train',
    'execution_id', p_actor,
    'receipt_schema', 'LF_MIGRATION_TRAIN_RECEIPT_V1',
    'receipt_sha256', v_sha,
    'receipt', v_receipt,
    'acceptance_declared', false,
    'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));

  v_signal := private.fn_lf_event_acceptance_signal_v2(c_event_type, p_execution_id, v_desc, v_payload);
  IF v_signal IS NOT NULL THEN
    RAISE EXCEPTION 'TRAIN_RECEIPT_ACCEPTANCE_SIGNAL:%', v_signal;
  END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    c_event_type, 'EXECUTION', p_execution_id, v_desc,
    CASE WHEN e.status = 'COMPLETED' AND v_class IN ('NO_CHANGE', 'SYNC_AND_RETIMESTAMP_ONLY')
         THEN 'INFO' ELSE 'WARN' END,
    v_payload, 'lf-migration-merge-train', p_actor
  ) RETURNING id INTO v_event_id;

  RETURN jsonb_build_object('outcome', 'TRAIN_RECEIPT_RECORDED', 'event_id', v_event_id,
                            'receipt_sha256', v_sha, 'execution_id', p_execution_id);
END
$fn$;
