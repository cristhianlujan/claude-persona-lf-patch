-- Train-managed failure, stale abandonment, and exact-apply resume support.
-- The Train will assign the final migration version before applying this file.

ALTER TABLE public.lf_operation_effect_guard
  DROP CONSTRAINT lf_operation_effect_guard_check,
  DROP CONSTRAINT lf_operation_effect_guard_state_check;

ALTER TABLE public.lf_operation_effect_guard
  ADD CONSTRAINT lf_operation_effect_guard_state_check
    CHECK (state = ANY (ARRAY['RESERVED'::text, 'SUCCEEDED'::text, 'ABANDONED'::text])),
  ADD CONSTRAINT lf_operation_effect_guard_check
    CHECK (
      (state = 'RESERVED'::text AND resolved_at IS NULL AND receipt IS NULL)
      OR
      (state IN ('SUCCEEDED'::text, 'ABANDONED'::text)
       AND resolved_at IS NOT NULL
       AND receipt IS NOT NULL
       AND jsonb_typeof(receipt) = 'object')
    );

CREATE OR REPLACE FUNCTION public.lf_fail_db_operation_execution_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_failure_evidence jsonb,
  p_actor text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_exec public.lf_operation_execution%rowtype;
  v_effect public.lf_operation_effect_guard%rowtype;
  v_version text;
  v_receipt jsonb;
BEGIN
  IF p_failure_evidence IS NULL OR jsonb_typeof(p_failure_evidence) <> 'object' THEN
    RAISE EXCEPTION 'DB_FAIL_EVIDENCE_INVALID';
  END IF;
  IF btrim(coalesce(p_actor, '')) = '' THEN
    RAISE EXCEPTION 'DB_FAIL_ACTOR_MISSING';
  END IF;

  SELECT * INTO v_exec
  FROM public.lf_operation_execution
  WHERE execution_id = p_execution_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EXECUTION_NOT_FOUND'; END IF;

  SELECT * INTO v_effect
  FROM public.lf_operation_effect_guard
  WHERE execution_id = p_execution_id
  ORDER BY effect_scope
  LIMIT 1
  FOR UPDATE;

  IF v_exec.status = 'BLOCKED'
     AND v_exec.manifest ? 'failure_evidence'
     AND v_exec.manifest ? 'failure_effect_receipt'
     AND v_effect.state = 'ABANDONED' THEN
    RETURN jsonb_build_object('result', 'REPLAY_ALREADY_FAILED', 'execution_id', p_execution_id);
  END IF;

  IF v_exec.operation_code <> 'ACTUALIZACION_DB_LF'
     OR v_exec.status <> 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'DB_FAIL_EXECUTION_NOT_IN_PROGRESS';
  END IF;
  IF v_exec.lease_owner IS DISTINCT FROM p_lease_owner
     OR v_exec.lease_fence IS DISTINCT FROM p_lease_fence
     OR v_exec.lease_expires_at IS NULL
     OR v_exec.lease_expires_at <= v_now THEN
    RAISE EXCEPTION 'STALE_OR_MISSING_LEASE_FENCE';
  END IF;

  v_version := substring(v_exec.target_code FROM '^([0-9]{14})_');
  IF v_version IS NULL THEN RAISE EXCEPTION 'DB_FAIL_TARGET_VERSION_INVALID'; END IF;
  IF EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations m WHERE m.version = v_version
  ) THEN
    RAISE EXCEPTION 'DB_FAIL_TARGET_VERSION_ALREADY_IN_LEDGER:%', v_version;
  END IF;

  IF v_effect.execution_id IS NULL
     OR v_effect.state <> 'RESERVED'
     OR v_effect.effect_scope <> 'MIGRATION:' || v_version THEN
    RAISE EXCEPTION 'DB_FAIL_RESERVED_MIGRATION_EFFECT_REQUIRED';
  END IF;

  v_receipt := jsonb_build_object(
    'schema_version', 'lf-operation-effect-abandoned/v1',
    'reason', 'APPLY_FAILED_BEFORE_LEDGER_EFFECT',
    'execution_id', p_execution_id,
    'effect_scope', v_effect.effect_scope,
    'target_version', v_version,
    'failure_evidence', p_failure_evidence,
    'actor', p_actor,
    'resolved_at', v_now
  );

  UPDATE public.lf_operation_effect_guard
  SET state = 'ABANDONED',
      receipt = v_receipt,
      resolved_at = v_now,
      updated_by_execution_id = p_actor,
      updated_at = v_now
  WHERE execution_id = p_execution_id AND effect_scope = v_effect.effect_scope;

  UPDATE public.lf_operation_execution
  SET status = 'BLOCKED',
      lease_owner = NULL,
      lease_expires_at = NULL,
      manifest = coalesce(manifest, '{}'::jsonb)
        || jsonb_build_object(
          'failure_evidence', p_failure_evidence,
          'failure_reason', 'APPLY_FAILED_BEFORE_LEDGER_EFFECT',
          'failure_effect_receipt', v_receipt,
          'failure_actor', p_actor,
          'failure_recorded_at', v_now
        ),
      updated_by_execution_id = p_actor,
      updated_at = v_now
  WHERE execution_id = p_execution_id;

  RETURN jsonb_build_object(
    'result', 'EXECUTION_BLOCKED_NO_LEDGER_EFFECT',
    'execution_id', p_execution_id,
    'target_version', v_version,
    'effect_state', 'ABANDONED'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.lf_abandon_stale_db_operation_execution_v1(
  p_execution_id text,
  p_evidence jsonb,
  p_actor text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_exec public.lf_operation_execution%rowtype;
  v_effect public.lf_operation_effect_guard%rowtype;
  v_version text;
  v_ledger_name text;
  v_successor_id text;
  v_reason text;
  v_receipt jsonb;
  v_evidence jsonb;
BEGIN
  IF p_evidence IS NULL OR jsonb_typeof(p_evidence) <> 'object' THEN
    RAISE EXCEPTION 'DB_ABANDON_EVIDENCE_INVALID';
  END IF;
  IF btrim(coalesce(p_actor, '')) = '' THEN
    RAISE EXCEPTION 'DB_ABANDON_ACTOR_MISSING';
  END IF;

  SELECT * INTO v_exec
  FROM public.lf_operation_execution
  WHERE execution_id = p_execution_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EXECUTION_NOT_FOUND'; END IF;

  SELECT * INTO v_effect
  FROM public.lf_operation_effect_guard
  WHERE execution_id = p_execution_id
  ORDER BY effect_scope
  LIMIT 1
  FOR UPDATE;

  IF v_exec.status = 'BLOCKED'
     AND v_exec.manifest ? 'stale_abandonment'
     AND v_exec.manifest ? 'failure_effect_receipt'
     AND v_effect.state = 'ABANDONED' THEN
    RETURN jsonb_build_object(
      'result', 'REPLAY_ALREADY_ABANDONED',
      'execution_id', p_execution_id,
      'reason', v_exec.manifest #>> '{stale_abandonment,reason}'
    );
  END IF;

  IF v_exec.operation_code <> 'ACTUALIZACION_DB_LF'
     OR v_exec.execution_id NOT LIKE 'EXEC-DB-TRAIN-%'
     OR v_exec.status <> 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'DB_ABANDON_EXECUTION_NOT_ELIGIBLE';
  END IF;
  IF v_exec.lease_expires_at IS NULL OR v_exec.lease_expires_at > v_now THEN
    RAISE EXCEPTION 'DB_ABANDON_LEASE_NOT_EXPIRED';
  END IF;

  v_version := substring(v_exec.target_code FROM '^([0-9]{14})_');
  IF v_version IS NULL THEN RAISE EXCEPTION 'DB_ABANDON_TARGET_VERSION_INVALID'; END IF;

  SELECT m.name INTO v_ledger_name
  FROM supabase_migrations.schema_migrations m
  WHERE m.version = v_version
  LIMIT 1;

  IF v_ledger_name IS NULL THEN
    v_reason := 'TARGET_VERSION_ABSENT_FROM_LEDGER';
  ELSE
    SELECT e.execution_id INTO v_successor_id
    FROM public.lf_operation_execution e
    WHERE e.operation_code = 'ACTUALIZACION_DB_LF'
      AND e.target_code = v_exec.target_code
      AND e.status = 'COMPLETED'
      AND e.execution_id <> p_execution_id
    ORDER BY e.completed_at DESC NULLS LAST, e.created_at DESC
    LIMIT 1;
    IF v_successor_id IS NULL THEN
      RAISE EXCEPTION 'DB_ABANDON_LEDGER_TARGET_WITHOUT_COMPLETED_SUCCESSOR';
    END IF;
    v_reason := 'LEDGER_TARGET_REPLACED_BY_COMPLETED_EXECUTION';
  END IF;

  IF v_effect.execution_id IS NULL
     OR v_effect.state = 'SUCCEEDED'
     OR v_effect.effect_scope <> 'MIGRATION:' || v_version THEN
    RAISE EXCEPTION 'DB_ABANDON_NON_SUCCEEDED_MIGRATION_EFFECT_REQUIRED';
  END IF;

  v_evidence := p_evidence || jsonb_build_object(
    'reason', v_reason,
    'target_version', v_version,
    'ledger_name', v_ledger_name,
    'completed_successor_execution_id', v_successor_id,
    'observed_at', v_now
  );
  v_receipt := jsonb_build_object(
    'schema_version', 'lf-operation-effect-abandoned/v1',
    'reason', v_reason,
    'execution_id', p_execution_id,
    'effect_scope', v_effect.effect_scope,
    'target_version', v_version,
    'ledger_name', v_ledger_name,
    'completed_successor_execution_id', v_successor_id,
    'evidence', v_evidence,
    'actor', p_actor,
    'resolved_at', v_now
  );

  UPDATE public.lf_operation_effect_guard
  SET state = 'ABANDONED',
      receipt = v_receipt,
      resolved_at = v_now,
      updated_by_execution_id = p_actor,
      updated_at = v_now
  WHERE execution_id = p_execution_id AND effect_scope = v_effect.effect_scope;

  UPDATE public.lf_operation_execution
  SET status = 'BLOCKED',
      lease_owner = NULL,
      lease_expires_at = NULL,
      manifest = coalesce(manifest, '{}'::jsonb)
        || jsonb_build_object(
          'failure_evidence', v_evidence,
          'stale_abandonment', v_evidence,
          'failure_reason', v_reason,
          'failure_effect_receipt', v_receipt,
          'failure_actor', p_actor,
          'failure_recorded_at', v_now
        ),
      updated_by_execution_id = p_actor,
      updated_at = v_now
  WHERE execution_id = p_execution_id;

  RETURN jsonb_build_object(
    'result', 'STALE_EXECUTION_BLOCKED',
    'execution_id', p_execution_id,
    'reason', v_reason,
    'target_version', v_version,
    'completed_successor_execution_id', v_successor_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.lf_fail_db_operation_execution_v1(text, text, bigint, jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_fail_db_operation_execution_v1(text, text, bigint, jsonb, text)
  TO service_role;

REVOKE ALL ON FUNCTION public.lf_abandon_stale_db_operation_execution_v1(text, jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_abandon_stale_db_operation_execution_v1(text, jsonb, text)
  TO service_role;

DO $cleanup$
DECLARE
  v_candidate record;
  v_result jsonb;
  v_processed jsonb := '[]'::jsonb;
  v_remaining bigint;
BEGIN
  FOR v_candidate IN
    SELECT
      e.execution_id,
      CASE
        WHEN NOT EXISTS (
          SELECT 1 FROM supabase_migrations.schema_migrations m
          WHERE m.version = substring(e.target_code FROM '^([0-9]{14})_')
        ) THEN 'TARGET_VERSION_ABSENT_FROM_LEDGER'
        ELSE 'LEDGER_TARGET_REPLACED_BY_COMPLETED_EXECUTION'
      END AS reason,
      (
        SELECT x.execution_id
        FROM public.lf_operation_execution x
        WHERE x.operation_code = 'ACTUALIZACION_DB_LF'
          AND x.target_code = e.target_code
          AND x.status = 'COMPLETED'
          AND x.execution_id <> e.execution_id
        ORDER BY x.completed_at DESC NULLS LAST, x.created_at DESC
        LIMIT 1
      ) AS completed_successor_execution_id,
      substring(e.target_code FROM '^([0-9]{14})_') AS target_version
    FROM public.lf_operation_execution e
    JOIN public.lf_operation_effect_guard g ON g.execution_id = e.execution_id
    WHERE e.execution_id LIKE 'EXEC-DB-TRAIN-%'
      AND e.operation_code = 'ACTUALIZACION_DB_LF'
      AND e.status = 'IN_PROGRESS'
      AND e.lease_expires_at IS NOT NULL
      AND e.lease_expires_at <= clock_timestamp()
      AND e.target_code ~ '^[0-9]{14}_'
      AND g.effect_scope = 'MIGRATION:' || substring(e.target_code FROM '^([0-9]{14})_')
      AND g.state <> 'SUCCEEDED'
      AND (
        NOT EXISTS (
          SELECT 1 FROM supabase_migrations.schema_migrations m
          WHERE m.version = substring(e.target_code FROM '^([0-9]{14})_')
        )
        OR EXISTS (
          SELECT 1 FROM supabase_migrations.schema_migrations m
          WHERE m.version = substring(e.target_code FROM '^([0-9]{14})_')
        ) AND EXISTS (
          SELECT 1 FROM public.lf_operation_execution x
          WHERE x.operation_code = 'ACTUALIZACION_DB_LF'
            AND x.target_code = e.target_code
            AND x.status = 'COMPLETED'
            AND x.execution_id <> e.execution_id
        )
      )
    ORDER BY e.execution_id
    FOR UPDATE OF e, g
  LOOP
    v_result := public.lf_abandon_stale_db_operation_execution_v1(
      v_candidate.execution_id,
      jsonb_build_object(
        'source', 'migration_cleanup',
        'reason', v_candidate.reason,
        'target_version', v_candidate.target_version,
        'completed_successor_execution_id', v_candidate.completed_successor_execution_id
      ),
      'LF-MIGRATION-TRAIN-CLEANUP'
    );
    v_processed := v_processed || jsonb_build_array(v_result);
  END LOOP;

  RAISE LOG 'LF_TRAIN_STALE_EXECUTION_CLEANUP %', v_processed::text;

  SELECT count(*) INTO v_remaining
  FROM public.lf_operation_execution e
  JOIN public.lf_operation_effect_guard g ON g.execution_id = e.execution_id
  WHERE e.execution_id LIKE 'EXEC-DB-TRAIN-%'
    AND e.operation_code = 'ACTUALIZACION_DB_LF'
    AND e.status = 'IN_PROGRESS'
    AND e.lease_expires_at IS NOT NULL
    AND e.lease_expires_at <= clock_timestamp()
    AND e.target_code ~ '^[0-9]{14}_'
    AND g.effect_scope = 'MIGRATION:' || substring(e.target_code FROM '^([0-9]{14})_')
    AND g.state <> 'SUCCEEDED'
    AND (
      NOT EXISTS (
        SELECT 1 FROM supabase_migrations.schema_migrations m
        WHERE m.version = substring(e.target_code FROM '^([0-9]{14})_')
      )
      OR EXISTS (
        SELECT 1 FROM supabase_migrations.schema_migrations m
        WHERE m.version = substring(e.target_code FROM '^([0-9]{14})_')
      ) AND EXISTS (
        SELECT 1 FROM public.lf_operation_execution x
        WHERE x.operation_code = 'ACTUALIZACION_DB_LF'
          AND x.target_code = e.target_code
          AND x.status = 'COMPLETED'
          AND x.execution_id <> e.execution_id
      )
    );

  IF v_remaining <> 0 THEN
    RAISE EXCEPTION 'LF_TRAIN_STALE_EXECUTION_POSTCHECK_FAILED:%', v_remaining;
  END IF;

  IF to_regrole('supabase_read_only_user') IS NULL THEN
    RAISE EXCEPTION 'LF_TRAIN_READ_ONLY_ROLE_MISSING';
  END IF;
  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_fail_db_operation_execution_v1(text,text,bigint,jsonb,text)'::regprocedure,
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_abandon_stale_db_operation_execution_v1(text,jsonb,text)'::regprocedure,
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'LF_TRAIN_READ_ONLY_EXECUTE_PRIVILEGE_REMAINS';
  END IF;
END;
$cleanup$;
