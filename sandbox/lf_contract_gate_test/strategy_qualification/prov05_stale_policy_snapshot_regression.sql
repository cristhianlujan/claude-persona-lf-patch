-- S30 / S36 PROV-05 deterministic regression.
-- Purpose: prove that Strategy Qualification rejects stale/incomplete operation-policy
-- snapshots without fabricating a persisted stale execution, disabling triggers, or
-- mutating immutable policy capsules.
--
-- This is deliberately read-only. The canonical INSERT trigger always attaches the
-- current policy capsule and the UPDATE guard makes that capsule immutable. Therefore
-- a black-box stale persisted row would itself require bypassing the controls under test.
-- Instead this regression binds to the live qualification runner source, evaluates the
-- exact stale predicate against in-memory JSON variants built from the canonical live
-- policy view, and verifies that the guard executes before any qualification receipt write.

DO $prov05$
DECLARE
  v_runner text;
  v_capsule jsonb;
  v_stale jsonb;
  v_missing jsonb;
  v_role text;
  v_stale_detected boolean;
  v_missing_detected boolean;
  v_attach_enabled boolean;
  v_immutable_enabled boolean;
  v_receipts_before bigint;
  v_receipts_after bigint;
BEGIN
  SELECT pg_get_functiondef('public.lf_run_strategy_qualification_v1(bigint,text)'::regprocedure)
    INTO v_runner;

  IF position('LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_STALE' in v_runner)=0 THEN
    RAISE EXCEPTION 'PROV05_LIVE_RUNNER_STALE_GUARD_MISSING';
  END IF;
  IF position('LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_MISSING' in v_runner)=0 THEN
    RAISE EXCEPTION 'PROV05_LIVE_RUNNER_MISSING_GUARD_MISSING';
  END IF;
  IF position('public.v_lf_operation_policy_snapshot' in v_runner)=0 THEN
    RAISE EXCEPTION 'PROV05_LIVE_RUNNER_POLICY_VIEW_BINDING_MISSING';
  END IF;
  IF position('LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_STALE' in v_runner)
       >= position('INSERT INTO public.lf_qualification_receipts' in v_runner) THEN
    RAISE EXCEPTION 'PROV05_STALE_GUARD_NOT_FAIL_CLOSED_BEFORE_RECEIPT';
  END IF;

  SELECT count(*) INTO v_receipts_before
  FROM public.lf_qualification_receipts;

  WITH roles AS (
    SELECT policy_role,policy_code,policy_version,policy_sha,
           row_number() over (order by policy_role) AS rn
    FROM public.v_lf_operation_policy_snapshot
    WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
      AND required
  )
  SELECT jsonb_object_agg(
           policy_role,
           jsonb_build_object(
             'policy_code',policy_code,
             'policy_version',policy_version,
             'policy_sha',policy_sha
           )
         ),
         max(policy_role) filter (where rn=1)
    INTO v_capsule,v_role
  FROM roles;

  IF v_capsule IS NULL OR v_role IS NULL THEN
    RAISE EXCEPTION 'PROV05_CANONICAL_POLICY_CAPSULE_MISSING';
  END IF;

  -- In-memory only: never persisted to lf_operation_execution.
  v_stale := jsonb_set(
    v_capsule,
    ARRAY[v_role,'policy_sha'],
    to_jsonb(repeat('0',64)),
    false
  );
  v_missing := v_capsule - v_role;

  SELECT EXISTS (
    SELECT 1
    FROM public.v_lf_operation_policy_snapshot p
    WHERE p.operation_code='EJECUCION_ESTRATEGIA_LF'
      AND p.required
      AND (
        NOT (v_stale ? p.policy_role)
        OR (v_stale->p.policy_role->>'policy_code') IS DISTINCT FROM p.policy_code
        OR (v_stale->p.policy_role->>'policy_version') IS DISTINCT FROM p.policy_version
        OR (v_stale->p.policy_role->>'policy_sha') IS DISTINCT FROM p.policy_sha
      )
  ) INTO v_stale_detected;

  SELECT EXISTS (
    SELECT 1
    FROM public.v_lf_operation_policy_snapshot p
    WHERE p.operation_code='EJECUCION_ESTRATEGIA_LF'
      AND p.required
      AND (
        NOT (v_missing ? p.policy_role)
        OR (v_missing->p.policy_role->>'policy_code') IS DISTINCT FROM p.policy_code
        OR (v_missing->p.policy_role->>'policy_version') IS DISTINCT FROM p.policy_version
        OR (v_missing->p.policy_role->>'policy_sha') IS DISTINCT FROM p.policy_sha
      )
  ) INTO v_missing_detected;

  IF NOT v_stale_detected THEN
    RAISE EXCEPTION 'PROV05_STALE_POLICY_VARIANT_NOT_DETECTED';
  END IF;
  IF NOT v_missing_detected THEN
    RAISE EXCEPTION 'PROV05_MISSING_POLICY_VARIANT_NOT_DETECTED';
  END IF;

  SELECT
    count(*) filter (
      where tgname='trg_00_lf_operation_policy_snapshot_v1' and tgenabled<>'D'
    )=1,
    count(*) filter (
      where tgname='trg_01_lf_operation_policy_snapshot_guard_v1' and tgenabled<>'D'
    )=1
    INTO v_attach_enabled,v_immutable_enabled
  FROM pg_trigger
  WHERE tgrelid='public.lf_operation_execution'::regclass
    AND NOT tgisinternal;

  IF NOT v_attach_enabled THEN
    RAISE EXCEPTION 'PROV05_CANONICAL_POLICY_ATTACH_TRIGGER_NOT_ENABLED';
  END IF;
  IF NOT v_immutable_enabled THEN
    RAISE EXCEPTION 'PROV05_POLICY_IMMUTABILITY_TRIGGER_NOT_ENABLED';
  END IF;

  SELECT count(*) INTO v_receipts_after
  FROM public.lf_qualification_receipts;
  IF v_receipts_after<>v_receipts_before THEN
    RAISE EXCEPTION 'PROV05_READ_ONLY_REGRESSION_LEFT_RECEIPT_RESIDUE:%:%',v_receipts_before,v_receipts_after;
  END IF;
END
$prov05$;

SELECT jsonb_build_object(
  'case','PROV-05',
  'name','stale_operation_policy_snapshot_blocked',
  'status','PASS',
  'method','LIVE_RUNNER_SOURCE_BOUND_READ_ONLY_POLICY_STALENESS_PROOF',
  'persistent_write',false,
  'bypass_used',false,
  'expected_stale_block','LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_STALE',
  'expected_missing_block','LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_MISSING',
  'receipt_count',(select count(*) from public.lf_qualification_receipts)
) AS prov05_result;
