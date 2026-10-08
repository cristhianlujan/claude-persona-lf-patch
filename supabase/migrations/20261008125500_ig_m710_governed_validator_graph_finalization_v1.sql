-- M7.10: use the actual signed Curator handoff as durable producer transport.
-- Every completed Validator run creates its own operational ORCHESTRATION and
-- EVIDENCE_LEDGER executions; never reuse historical actors or hardcoded runs.
-- Existing operation, provenance and evidence ledger stores only.
CREATE OR REPLACE FUNCTION programacion.fn_ig_graph_receipt_on_validator_completed_v1(
  p_run_id bigint,p_validator_identity text,p_handoff_receipt_id bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,programacion,public,private
AS $finish$
DECLARE
  v_run record;
  v_handoff jsonb;
  v_graph text;
  v_head text;
  v_digest text;
  v_context jsonb;
  v_orch text;
  v_ledger text;
  v_orch_manifest jsonb;
  v_ledger_manifest jsonb;
  v_operation jsonb;
  v_dispatch jsonb;
  v_receipt jsonb;
  v_readback jsonb;
  v_scope jsonb;
  v_count integer;
BEGIN
  IF p_run_id IS NULL OR p_run_id<1 OR
     nullif(btrim(p_validator_identity),'') IS NULL THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_INPUT_INVALID';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('IG_GRAPH_RUN:'||p_run_id::text,0));
  SELECT id,pantalla_id,version_id,status,source_snapshot_sha256,
         source_manifest,validator_identity,family_count,curator_identity
    INTO v_run FROM programacion.input_readiness_runs WHERE id=p_run_id;
  IF v_run.id IS NULL OR v_run.status<>'COMPLETED' OR
     v_run.validator_identity IS DISTINCT FROM p_validator_identity OR
     coalesce(v_run.source_snapshot_sha256,'') !~ '^[0-9a-f]{64}$' OR
     jsonb_typeof(v_run.source_manifest)<>'array' THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_RUN_NOT_ELIGIBLE';
  END IF;
  SELECT count(*) INTO v_count FROM programacion.input_family_assessments
    WHERE run_id=p_run_id AND validator_outcome='PASS'
      AND validator_identity=p_validator_identity;
  IF v_count IS DISTINCT FROM v_run.family_count OR v_count<>47 THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_VALIDATOR_NOT_COMPLETE:%',v_count;
  END IF;
  v_handoff:=programacion.fn_input_governance_validator_handoff_assert_v1(
    p_run_id,p_handoff_receipt_id);
  IF v_handoff->>'status'<>'VERIFIED' THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_HANDOFF_NOT_VERIFIED';
  END IF;
  v_graph:=v_handoff->>'graph_sha256';
  v_head:=v_handoff->>'head_sha';
  IF coalesce(v_graph,'') !~ '^[0-9a-f]{64}$' OR
     coalesce(v_head,'') !~ '^[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_SIGNED_PRODUCER_HASH_MISSING';
  END IF;
  -- Handoff source_head is from the persisted, verified producer receipt.
  -- Bind it to this run rather than trusting a new caller-supplied SHA.
  IF nullif(current_setting('lf.input_request_context_v1',true),'') IS NOT NULL THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_EPHEMERAL_CONTEXT_FORBIDDEN';
  END IF;
  v_context:=jsonb_build_object(
    'schema_version','IG_GRAPH_RUN_BOUND_ORCHESTRATION_V1',
    'run_id',p_run_id,'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,'curator_identity',v_run.curator_identity,
    'validator_identity',p_validator_identity,
    'handoff_receipt_id',(v_handoff->>'receipt_id')::bigint,
    'handoff_receipt_sha256',v_handoff->>'receipt_sha256',
    'consumed_graph_sha256',v_graph,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'source_head_sha',v_head);
  v_digest:=programacion.fn_v09_sha256_jsonb(v_context);
  v_orch:='EXEC-IG-GRAPH-ORCH-RUN-'||p_run_id::text||'-'||substr(v_digest,1,12);
  v_ledger:='EXEC-IG-GRAPH-LEDGER-RUN-'||p_run_id::text||'-'||substr(v_digest,1,12);
  v_orch_manifest:=v_context||jsonb_build_object(
    'capability_code','EVIDENCE_LEDGER','plan_digest',v_digest,
    'producer_execution_id',v_orch);
  v_operation:=public.fn_lf_operation_reserve_execution_v1(
    v_orch,'ORQUESTACION_PIPELINE_LF','IG_RUN',p_run_id::text,
    'ig:graph:orch:'||p_run_id::text,v_digest,v_orch,
    null,null,v_orch_manifest);
  IF v_operation->>'execution_id' IS DISTINCT FROM v_orch THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_ORCHESTRATOR_IDEMPOTENCY_MISMATCH';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
    JOIN public.lf_operation_registry op ON op.operation_code=e.operation_code
    WHERE e.execution_id=v_orch AND e.manifest=v_orch_manifest
      AND e.status='IN_PROGRESS' AND op.operation_family='ORCHESTRATION'
      AND op.lifecycle_state_code='OP_OPERATIONAL') THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_ORCHESTRATOR_NOT_GOVERNED';
  END IF;
  v_ledger_manifest:=jsonb_build_object(
    'schema_version','IG_GRAPH_PER_RUN_ISSUER_V1',
    'run_id',p_run_id,'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'consumed_graph_sha256',v_graph,'source_head_sha',v_head,
    'producer_execution_id',v_orch,
    'orchestrator_execution_id',v_orch,
    'plan_digest',v_digest,'capability_code','EVIDENCE_LEDGER');
  v_operation:=public.fn_lf_operation_reserve_execution_v1(
    v_ledger,'ORQUESTACION_PIPELINE_LF','IG_RUN',p_run_id::text,
    'ig:graph:ledger:'||p_run_id::text,
    programacion.fn_v09_sha256_jsonb(v_ledger_manifest),v_ledger,
    null,null,v_ledger_manifest);
  IF v_operation->>'execution_id' IS DISTINCT FROM v_ledger OR
     NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
       WHERE e.execution_id=v_ledger AND e.manifest=v_ledger_manifest
         AND e.status='IN_PROGRESS') THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_LEDGER_ACTOR_REPLAY_MISMATCH';
  END IF;
  v_scope:=jsonb_build_object(
    'schema_version','IG_GRAPH_PER_RUN_DISPATCH_V1',
    'run_id',p_run_id,'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'producer_execution_id',v_orch,'source_head_sha',v_head,
    'consumed_graph_sha256',v_graph);
  v_dispatch:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch,v_ledger,'EVIDENCE_LEDGER',v_digest,v_scope,v_orch);
  IF NOT coalesce((v_dispatch->>'ready')::boolean,false) THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_DISPATCH_DENIED:%',v_dispatch->>'decision';
  END IF;
  v_receipt:=programacion.fn_ig_graph_receipt_emit_per_run_v1(
    p_run_id,v_orch,v_ledger,v_head,v_graph);
  IF v_receipt->>'status'<>'PASS' OR
     (v_receipt->>'consumer_readback_count')::int<>2 THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_EMISSION_FAILED';
  END IF;
  v_readback:=programacion.fn_ig_graph_receipt_consumer_readback_v1(
    p_run_id,v_graph,v_head,v_orch,v_ledger,v_orch);
  IF v_readback->>'status'<>'PASS' OR
     (v_readback->>'matched_receipts')::int<>2 THEN
    RAISE EXCEPTION 'IG_GRAPH_FINISH_INDEPENDENT_CONSUMER_FAILED:%',
      v_readback->>'reason';
  END IF;
  RETURN jsonb_build_object('status','PASS','run_id',p_run_id,
    'orchestrator_execution_id',v_orch,'ledger_execution_id',v_ledger,
    'dispatch_receipt',v_dispatch,'graph_receipt',v_receipt,
    'consumer_readback',v_readback);
END $finish$;

REVOKE ALL ON FUNCTION programacion.fn_ig_graph_receipt_on_validator_completed_v1(bigint,text,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_graph_receipt_on_validator_completed_v1(bigint,text,bigint)
  TO service_role;

-- The existing real Validator handoff entrypoint is the only owner of finalization.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_validate_handoff_v1(
 p_run_id bigint,p_validator_identity text,p_receipt_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,programacion,public
AS $handoff$
DECLARE v_handoff jsonb; v_result jsonb; v_graph_receipts jsonb;
BEGIN
 v_handoff:=programacion.fn_input_governance_validator_handoff_assert_v1(p_run_id,p_receipt_id);
 v_result:=programacion.fn_input_governance_validator_validate_v1(p_run_id,p_validator_identity);
 IF v_result->>'status' IN ('COMPLETED','NOOP_COMPLETED') THEN
   v_graph_receipts:=programacion.fn_ig_graph_receipt_on_validator_completed_v1(
     p_run_id,p_validator_identity,(v_handoff->>'receipt_id')::bigint);
 END IF;
 RETURN coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
   'handoff_receipt',v_handoff,'graph_receipts',v_graph_receipts);
END $handoff$;
