-- Issue #352: reconcile Supabase runtime metadata with canonical Git-first Card procedure.
-- Source authority: gobernanza/procedimientos/creacion_card_lf_steps_validation.yaml
-- Main source blob: 29e147df8640831f205df8ee69c84da9649ba5ff
-- Scope: sandbox governance metadata only. No runtime enablement, no production promotion.

DO $$
DECLARE
  v_steps integer;
  v_contracts integer;
BEGIN
  SELECT count(*) INTO v_steps
  FROM public.lf_operation_steps
  WHERE operation_code = 'CREACION_CARD_LF'
    AND (step_id, step_order) IN (
      ('partial_scope_guard', 23),
      ('pre_write_execution_binding_gate', 24),
      ('github_write', 25),
      ('github_readback', 26),
      ('evidence_log', 27)
    );

  IF v_steps <> 5 THEN
    RAISE EXCEPTION 'CARD_PREWRITE_RECONCILE_SOURCE_DRIFT: expected 5 canonical steps at orders 23..27, observed %', v_steps;
  END IF;

  SELECT count(*) INTO v_contracts
  FROM public.lf_operation_step_contracts
  WHERE operation_code = 'CREACION_CARD_LF'
    AND step_id IN (
      'partial_scope_guard',
      'pre_write_execution_binding_gate',
      'github_write',
      'github_readback',
      'evidence_log'
    );

  IF v_contracts <> 5 THEN
    RAISE EXCEPTION 'CARD_PREWRITE_RECONCILE_CONTRACT_DRIFT: expected 5 step contracts, observed %', v_contracts;
  END IF;
END $$;

UPDATE public.lf_operation_steps
SET execution_order = CASE step_id
      WHEN 'partial_scope_guard' THEN 23
      WHEN 'pre_write_execution_binding_gate' THEN 24
      WHEN 'github_write' THEN 25
      WHEN 'github_readback' THEN 26
      WHEN 'evidence_log' THEN 27
    END,
    source_path = 'gobernanza/procedimientos/creacion_card_lf_steps_validation.yaml',
    source_sha = '29e147df8640831f205df8ee69c84da9649ba5ff',
    updated_at = now()
WHERE operation_code = 'CREACION_CARD_LF'
  AND step_id IN (
    'partial_scope_guard',
    'pre_write_execution_binding_gate',
    'github_write',
    'github_readback',
    'evidence_log'
  );

UPDATE public.lf_operation_step_contracts
SET step_order = CASE step_id
      WHEN 'partial_scope_guard' THEN 23
      WHEN 'pre_write_execution_binding_gate' THEN 24
      WHEN 'github_write' THEN 25
      WHEN 'github_readback' THEN 26
      WHEN 'evidence_log' THEN 27
    END,
    execution_order = CASE step_id
      WHEN 'partial_scope_guard' THEN 23
      WHEN 'pre_write_execution_binding_gate' THEN 24
      WHEN 'github_write' THEN 25
      WHEN 'github_readback' THEN 26
      WHEN 'evidence_log' THEN 27
    END,
    updated_at = now()
WHERE operation_code = 'CREACION_CARD_LF'
  AND step_id IN (
    'partial_scope_guard',
    'pre_write_execution_binding_gate',
    'github_write',
    'github_readback',
    'evidence_log'
  );

DO $$
DECLARE
  v_bad integer;
  v_pre integer;
  v_write integer;
BEGIN
  SELECT count(*) INTO v_bad
  FROM public.lf_operation_steps s
  JOIN public.lf_operation_step_contracts c
    ON c.operation_code = s.operation_code
   AND c.step_id = s.step_id
  WHERE s.operation_code = 'CREACION_CARD_LF'
    AND s.step_id IN (
      'partial_scope_guard',
      'pre_write_execution_binding_gate',
      'github_write',
      'github_readback',
      'evidence_log'
    )
    AND (
      s.step_order IS DISTINCT FROM c.step_order
      OR s.execution_order IS DISTINCT FROM c.execution_order
      OR s.step_order IS DISTINCT FROM s.execution_order
    );

  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'CARD_PREWRITE_RECONCILE_POSTCHECK_FAILED: % step/contract order mismatches remain', v_bad;
  END IF;

  SELECT execution_order INTO v_pre
  FROM public.lf_operation_steps
  WHERE operation_code = 'CREACION_CARD_LF'
    AND step_id = 'pre_write_execution_binding_gate';

  SELECT execution_order INTO v_write
  FROM public.lf_operation_steps
  WHERE operation_code = 'CREACION_CARD_LF'
    AND step_id = 'github_write';

  IF v_pre IS NULL OR v_write IS NULL OR v_pre >= v_write THEN
    RAISE EXCEPTION 'CARD_PREWRITE_TEMPORAL_GUARD_FAILED: pre_write=% github_write=%', v_pre, v_write;
  END IF;
END $$;
