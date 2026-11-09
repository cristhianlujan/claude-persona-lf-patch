-- LF B2B-AUTH-001: reconcile the documentary pending note of AUTH-016 only.
-- Governed ACTUALIZACION_DB_LF migration; execute only through authorized Merge Train.
-- Do NOT use public.lf_regla_candidate_write_v1 (candidate-only) or change rule authority.
-- Intended effect: exactly one lf_ops.reglas.pendiente_detalle + its updated_at.
-- Rollback: transactional before COMMIT; after apply, a separately governed reverse
-- migration may restore the exact old note, guarded by the after-note hash.
BEGIN;

DO $preflight$
DECLARE
  v_rule lf_ops.reglas%ROWTYPE;
  v_exec_count integer;
BEGIN
  -- The Train may retimestamp the filename before apply. Bind to its
  -- actual authorized RUN + clean preflight, not a frozen 14-digit prefix.
  SELECT count(*) INTO v_exec_count
  FROM public.lf_operation_execution e
  JOIN public.lf_operation_execution_steps s
    ON s.execution_id=e.execution_id
   AND s.step_id='preflight'
   AND s.status='PASS_CLEAN'
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code ~ '^20[0-9]{12}_lf_auth016_vigente_document_only_reconcile_v1
  IF v_exec_count<>1 THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_DB_GOVERNED_EXECUTION_NOT_BOUND:%',v_exec_count;
  END IF;

  SELECT * INTO v_rule
  FROM lf_ops.reglas
  WHERE id=435 AND codigo='B2B-RULE-AUTH-016'
  FOR UPDATE;
  IF NOT FOUND
     OR v_rule.estado IS DISTINCT FROM 'VIGENTE'
     OR v_rule.pendiente_decision IS DISTINCT FROM false
     OR v_rule.valor_config->>'timeout_policy_id' IS DISTINCT FROM '10'
     OR v_rule.valor_config->>'implementation_status' IS DISTINCT FROM 'PENDING_IMPLEMENTATION_QA'
     OR md5(to_jsonb(v_rule)::text) IS DISTINCT FROM '686fe953d9b0f2f018046e8786c022d9'
     OR md5(v_rule.pendiente_detalle) IS DISTINCT FROM 'f34f1e6399ea1cb322b2e3666c75263c'
  THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_SOURCE_DRIFT_OR_STATE_CHANGE';
  END IF;

  IF (
    SELECT count(*)
    FROM lf_ops.politicas_timeout p
    WHERE p.timeout_policy_id=10
      AND p.policy_code='TIMEOUT-B2B-AUTH-LOGIN'
      AND p.status='VIGENTE'
      AND p.timeout_seconds=15
      AND p.retry_limit=0
  )<>1 THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_TIMEOUT_POLICY_DRIFT';
  END IF;
END
$preflight$;

DO $apply$
DECLARE v_affected integer;
BEGIN
  UPDATE lf_ops.reglas
  SET pendiente_detalle=
    'PENDING_IMPLEMENTATION_QA: La regla de Login ya referencia la política central VIGENTE TIMEOUT-B2B-AUTH-LOGIN (timeout_policy_id=10; 15 s; retry_limit=0). Permanecen pendientes las mediciones del proveedor y pruebas integrales en staging para acreditar la implementación y calibración. No declarar READY ni cambiar valores, reintentos o vigencia sin evidencia y operación gobernada.',
      updated_at=clock_timestamp()
  WHERE id=435
    AND codigo='B2B-RULE-AUTH-016'
    AND estado='VIGENTE'
    AND pendiente_decision=false
    AND md5(pendiente_detalle)='f34f1e6399ea1cb322b2e3666c75263c';
  GET DIAGNOSTICS v_affected=ROW_COUNT;
  IF v_affected<>1 THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_WRITE_CARDINALITY:%',v_affected;
  END IF;
END
$apply$;

DO $readback$
BEGIN
  IF (
    SELECT count(*)
    FROM lf_ops.reglas r
    WHERE r.id=435
      AND r.codigo='B2B-RULE-AUTH-016'
      AND r.estado='VIGENTE'
      AND r.pendiente_decision=false
      AND r.valor_config->>'timeout_policy_id'='10'
      AND r.valor_config->>'implementation_status'='PENDING_IMPLEMENTATION_QA'
      AND md5(r.valor_config::text)='4b0938369d21dcda859a1ff8a53002d8'
      AND md5(coalesce(r.descripcion,''))='5ca4bb2e32f719108490690ee62853bc'
      AND md5(coalesce(r.razon,''))='ca588a13e62e1a79d3e057665a6f3382'
      AND md5(coalesce(r.origen,''))='696f299967cd0b82dec86f473fae19c0'
      AND md5(coalesce(r.titulo,''))='6e3235baef5362a5a7b71063592f2191'
      AND r.pendiente_detalle =
       'PENDING_IMPLEMENTATION_QA: La regla de Login ya referencia la política central VIGENTE TIMEOUT-B2B-AUTH-LOGIN (timeout_policy_id=10; 15 s; retry_limit=0). Permanecen pendientes las mediciones del proveedor y pruebas integrales en staging para acreditar la implementación y calibración. No declarar READY ni cambiar valores, reintentos o vigencia sin evidencia y operación gobernada.'
  )<>1 THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_READBACK_INVARIANTS_FAILED';
  END IF;
END
$readback$;
COMMIT;

    AND e.target_path='supabase/migrations/' || e.target_code || '.sql'
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.execution_id LIKE 'EXEC-DB-TRAIN-PR3713-%'
    AND e.manifest->>'producer'='lf-migration-merge-train'
    AND e.manifest->>'pr'='3713'
    AND e.manifest#>>'{router_authority_receipt,schema_version}'='LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1'
    AND e.manifest#>>'{router_authority_receipt,target_code}'=e.target_code
    AND s.evidence_payload->>'producer'='lf-migration-merge-train'
    AND s.evidence_payload#>>'{exact_target,pr}'='3713'
    AND s.evidence_payload#>>'{exact_target,target_path}'=e.target_path
    AND s.evidence_payload#>>'{trust_validation,valid}'='true'
    AND e.status='IN_PROGRESS';
  IF v_exec_count<>1 THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_DB_GOVERNED_EXECUTION_NOT_BOUND:%',v_exec_count;
  END IF;

  SELECT * INTO v_rule
  FROM lf_ops.reglas
  WHERE id=435 AND codigo='B2B-RULE-AUTH-016'
  FOR UPDATE;
  IF NOT FOUND
     OR v_rule.estado IS DISTINCT FROM 'VIGENTE'
     OR v_rule.pendiente_decision IS DISTINCT FROM false
     OR v_rule.valor_config->>'timeout_policy_id' IS DISTINCT FROM '10'
     OR v_rule.valor_config->>'implementation_status' IS DISTINCT FROM 'PENDING_IMPLEMENTATION_QA'
     OR md5(to_jsonb(v_rule)::text) IS DISTINCT FROM '686fe953d9b0f2f018046e8786c022d9'
     OR md5(v_rule.pendiente_detalle) IS DISTINCT FROM 'f34f1e6399ea1cb322b2e3666c75263c'
  THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_SOURCE_DRIFT_OR_STATE_CHANGE';
  END IF;

  IF (
    SELECT count(*)
    FROM lf_ops.politicas_timeout p
    WHERE p.timeout_policy_id=10
      AND p.policy_code='TIMEOUT-B2B-AUTH-LOGIN'
      AND p.status='VIGENTE'
      AND p.timeout_seconds=15
      AND p.retry_limit=0
  )<>1 THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_TIMEOUT_POLICY_DRIFT';
  END IF;
END
$preflight$;

DO $apply$
DECLARE v_affected integer;
BEGIN
  UPDATE lf_ops.reglas
  SET pendiente_detalle=
    'PENDING_IMPLEMENTATION_QA: La regla de Login ya referencia la política central VIGENTE TIMEOUT-B2B-AUTH-LOGIN (timeout_policy_id=10; 15 s; retry_limit=0). Permanecen pendientes las mediciones del proveedor y pruebas integrales en staging para acreditar la implementación y calibración. No declarar READY ni cambiar valores, reintentos o vigencia sin evidencia y operación gobernada.',
      updated_at=clock_timestamp()
  WHERE id=435
    AND codigo='B2B-RULE-AUTH-016'
    AND estado='VIGENTE'
    AND pendiente_decision=false
    AND md5(pendiente_detalle)='f34f1e6399ea1cb322b2e3666c75263c';
  GET DIAGNOSTICS v_affected=ROW_COUNT;
  IF v_affected<>1 THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_WRITE_CARDINALITY:%',v_affected;
  END IF;
END
$apply$;

DO $readback$
BEGIN
  IF (
    SELECT count(*)
    FROM lf_ops.reglas r
    WHERE r.id=435
      AND r.codigo='B2B-RULE-AUTH-016'
      AND r.estado='VIGENTE'
      AND r.pendiente_decision=false
      AND r.valor_config->>'timeout_policy_id'='10'
      AND r.valor_config->>'implementation_status'='PENDING_IMPLEMENTATION_QA'
      AND md5(r.valor_config::text)='4b0938369d21dcda859a1ff8a53002d8'
      AND md5(coalesce(r.descripcion,''))='5ca4bb2e32f719108490690ee62853bc'
      AND md5(coalesce(r.razon,''))='ca588a13e62e1a79d3e057665a6f3382'
      AND md5(coalesce(r.origen,''))='696f299967cd0b82dec86f473fae19c0'
      AND md5(coalesce(r.titulo,''))='6e3235baef5362a5a7b71063592f2191'
      AND r.pendiente_detalle =
       'PENDING_IMPLEMENTATION_QA: La regla de Login ya referencia la política central VIGENTE TIMEOUT-B2B-AUTH-LOGIN (timeout_policy_id=10; 15 s; retry_limit=0). Permanecen pendientes las mediciones del proveedor y pruebas integrales en staging para acreditar la implementación y calibración. No declarar READY ni cambiar valores, reintentos o vigencia sin evidencia y operación gobernada.'
  )<>1 THEN
    RAISE EXCEPTION 'BLOCK_AUTH016_READBACK_INVARIANTS_FAILED';
  END IF;
END
$readback$;
COMMIT;
