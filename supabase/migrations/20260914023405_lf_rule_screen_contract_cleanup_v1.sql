-- Canonicalize active contract set for VINCULACION_REGLA_PANTALLA_LF.
-- Historical typo contract remains durable but is superseded; v1.1.0 is the sole active contract.

DO $pre$
DECLARE
  c integer;
BEGIN
  IF (SELECT status FROM public.lf_operation_registry WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF')<>'PRODUCCION_CONTROLADA' THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_CONTRACT_CLEANUP_OPERATION_NOT_PROD';
  END IF;

  SELECT count(*) INTO c
  FROM public.lf_operation_contracts
  WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
    AND status='ACTIVE_ENFORCEMENT';
  IF c<>2 THEN RAISE EXCEPTION 'LF_RULE_SCREEN_CONTRACT_CLEANUP_EXPECTED_TWO_ACTIVE:%',c; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
      AND contract_code='CONTRACT-VINCULACION-REGLA-PANTALLA_LF-v1.1.0'
      AND status='ACTIVE_ENFORCEMENT'
  ) THEN RAISE EXCEPTION 'LF_RULE_SCREEN_CONTRACT_CLEANUP_V11_MISSING'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
      AND contract_code='CONTRACT-VINCULACION-REGLA-PANTALLA_LF-v1.0.0'
      AND status='ACTIVE_ENFORCEMENT'
  ) THEN RAISE EXCEPTION 'LF_RULE_SCREEN_CONTRACT_CLEANUP_LEGACY_MISSING'; END IF;
END
$pre$;

UPDATE public.lf_operation_contracts
SET status='SUPERSEDED_INTEGRATION',
    updated_by_execution_id='EXEC-VINCULACION-REGLA-PANTALLA-CONTRACT-CLEANUP-20260914-001',
    updated_at=now()
WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
  AND contract_code='CONTRACT-VINCULACION-REGLA-PANTALLA_LF-v1.0.0'
  AND status='ACTIVE_ENFORCEMENT';

DO $post$
DECLARE
  c integer;
  v jsonb;
BEGIN
  SELECT count(*) INTO c
  FROM public.lf_operation_contracts
  WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
    AND status='ACTIVE_ENFORCEMENT';
  IF c<>1 THEN RAISE EXCEPTION 'LF_RULE_SCREEN_CONTRACT_CLEANUP_ACTIVE_COUNT:%',c; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
      AND contract_code='CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0'
      AND status='ACTIVE_ENFORCEMENT'
  ) THEN RAISE EXCEPTION 'LF_RULE_SCREEN_CONTRACT_CLEANUP_CANONICAL_NOT_ACTIVE'; END IF;

  v:=public.lf_router_resolve_v1('vincular regla con pantalla',null,null,null,'ROUTER');
  IF v->>'status'<>'READY_TO_EXECUTE'
     OR v->>'operation_code'<>'VINCULACION_REGLA_PANTALLA_LF'
     OR (v->>'contract_count')::integer<>1 THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_CONTRACT_CLEANUP_ROUTE_FAIL:%',v;
  END IF;
END
$post$;

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=now(),
    manifest=manifest||jsonb_build_object(
      'result','RULE_SCREEN_CONTRACT_CANONICALIZED',
      'active_contract','CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0',
      'legacy_contract_status','SUPERSEDED_INTEGRATION'
    ),
    updated_by_execution_id='EXEC-VINCULACION-REGLA-PANTALLA-CONTRACT-CLEANUP-20260914-001',
    updated_at=now()
WHERE execution_id='EXEC-VINCULACION-REGLA-PANTALLA-CONTRACT-CLEANUP-20260914-001';

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=now(),
    manifest=manifest||jsonb_build_object(
      'result','RULE_SCREEN_CONTRACT_CLEANUP_MIGRATION_APPLIED',
      'active_contract_count',1
    ),
    updated_by_execution_id='EXEC-ACTUALIZACION-DB-RULE-SCREEN-CONTRACT-CLEANUP-20260914-001',
    updated_at=now()
WHERE execution_id='EXEC-ACTUALIZACION-DB-RULE-SCREEN-CONTRACT-CLEANUP-20260914-001';
