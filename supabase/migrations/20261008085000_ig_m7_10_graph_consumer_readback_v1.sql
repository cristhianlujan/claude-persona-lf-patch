-- IG M7.10: independent consumer readback for already-issued per-run graph receipts.
-- Never issues a receipt. No run IDs, actors, SHAs, or store are hard-coded.
CREATE OR REPLACE FUNCTION programacion.fn_ig_graph_receipt_consumer_readback_v1(
  p_run_id bigint,
  p_graph_sha256 text,
  p_source_head_sha text,
  p_producer_execution_id text,
  p_ledger_execution_id text,
  p_orchestrator_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,programacion,public,private
AS $readback$
DECLARE
  v_run record;
  v_receipts integer:=0;
  v_ordinal_count integer:=0;
  v_dispatch_count integer:=0;
BEGIN
  IF p_run_id IS NULL OR p_run_id<1
     OR coalesce(p_graph_sha256,'') !~ '^[0-9a-f]{64}$'
     OR coalesce(p_source_head_sha,'') !~ '^[0-9a-f]{40}$'
     OR nullif(btrim(p_producer_execution_id),'') IS NULL
     OR nullif(btrim(p_ledger_execution_id),'') IS NULL
     OR nullif(btrim(p_orchestrator_execution_id),'') IS NULL THEN
    RAISE EXCEPTION 'IG_GRAPH_CONSUMER_INPUT_INVALID';
  END IF;
  SELECT id,pantalla_id,version_id,status,source_snapshot_sha256
    INTO v_run
    FROM programacion.input_readiness_runs WHERE id=p_run_id;
  IF v_run.id IS NULL OR v_run.status<>'COMPLETED'
     OR v_run.source_snapshot_sha256 !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('status','FAIL','reason','RUN_NOT_COMPLETED_OR_SOURCE_UNBOUND',
      'run_id',p_run_id,'matched_receipts',0);
  END IF;
  SELECT count(*) INTO v_dispatch_count
    FROM private.lf_orchestrator_dispatch_receipts_v1 d
    JOIN public.lf_operation_execution e
      ON e.execution_id=d.consumer_execution_id
    WHERE d.consumer_execution_id=p_ledger_execution_id
      AND d.orchestrator_execution_id=p_orchestrator_execution_id
      AND d.issued_by_execution_id=p_orchestrator_execution_id
      AND d.capability_code='EVIDENCE_LEDGER'
      AND d.plan_digest=e.manifest->>'plan_digest'
      AND d.dispatch_scope->>'schema_version'='IG_GRAPH_PER_RUN_DISPATCH_V1'
      AND d.dispatch_scope->>'run_id'=p_run_id::text
      AND d.dispatch_scope->>'pantalla_id'=v_run.pantalla_id::text
      AND d.dispatch_scope->>'version_id'=v_run.version_id::text
      AND d.dispatch_scope->>'source_snapshot_sha256'=v_run.source_snapshot_sha256
      AND d.dispatch_scope->>'source_head_sha'=p_source_head_sha
      AND d.dispatch_scope->>'consumed_graph_sha256'=p_graph_sha256
      AND d.dispatch_scope->>'producer_execution_id'=p_producer_execution_id
      AND e.manifest->>'orchestrator_execution_id'=p_orchestrator_execution_id
      AND e.manifest->>'capability_code'='EVIDENCE_LEDGER';
  IF v_dispatch_count<>1 THEN
    RETURN jsonb_build_object('status','FAIL','reason','GOVERNED_DISPATCH_MISSING',
      'run_id',p_run_id,'matched_dispatches',v_dispatch_count);
  END IF;
  SELECT count(*),count(DISTINCT (l.receipt_payload->>'recalculation_ordinal')::int)
    INTO v_receipts,v_ordinal_count
  FROM private.lf_evidence_ledger_v1 l
  WHERE l.receipt_kind='GRAPH_RECEIPT'
    AND l.subject_type='IG_SCREEN_GRAPH'
    AND l.execution_id=p_producer_execution_id
    AND l.created_by_execution_id=p_ledger_execution_id
    AND l.subject_sha256=p_graph_sha256
    AND l.source_head_sha=p_source_head_sha
    AND l.verification_state='VERIFIED'
    AND l.receipt_payload->>'schema_version'='IG_SCREEN_GRAPH_RECEIPT_PER_RUN_V1'
    AND l.receipt_payload->>'run_id'=p_run_id::text
    AND l.receipt_payload->>'pantalla_id'=v_run.pantalla_id::text
    AND l.receipt_payload->>'version_id'=v_run.version_id::text
    AND l.receipt_payload->>'producer_execution_id'=p_producer_execution_id
    AND l.receipt_payload->>'orchestrator_execution_id'=p_orchestrator_execution_id
    AND l.verification_payload->>'source_snapshot_sha256'=v_run.source_snapshot_sha256
    AND l.verification_payload->>'graph_sha256'=p_graph_sha256
    AND l.receipt_payload->>'recalculation_ordinal' IN ('1','2')
    AND l.subject_ref='supabase://programacion.input_readiness_runs/'||
      p_run_id::text||'#canonical_graph/recalc-'||
      (l.receipt_payload->>'recalculation_ordinal');
  RETURN jsonb_build_object('status',CASE WHEN v_receipts=2 AND v_ordinal_count=2
                                   THEN 'PASS' ELSE 'FAIL' END,
    'reason',CASE WHEN v_receipts=2 AND v_ordinal_count=2
                  THEN 'RUN_BOUND_GRAPH_RECEIPTS_VERIFIED'
                  ELSE 'GRAPH_RECEIPTS_INCOMPLETE_OR_MISMATCH' END,
    'run_id',p_run_id,'matched_receipts',v_receipts,
    'distinct_ordinals',v_ordinal_count,'matched_dispatches',v_dispatch_count,
    'consumer_graph_sha256',p_graph_sha256);
END $readback$;

REVOKE ALL ON FUNCTION programacion.fn_ig_graph_receipt_consumer_readback_v1(bigint,text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_graph_receipt_consumer_readback_v1(bigint,text,text,text,text,text) TO service_role;
