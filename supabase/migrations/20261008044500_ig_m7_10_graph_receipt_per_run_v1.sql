-- IG M7.10 / UPSTREAM_E2E_REPAIR: typed, per-run EVIDENCE_LEDGER issuer.
-- No historical run or operation actor is embedded. Invocation must originate from
-- the governed producer/orchestrator with a fresh, run-bound EVIDENCE_LEDGER actor.
CREATE OR REPLACE FUNCTION programacion.fn_ig_graph_receipt_emit_per_run_v1(
  p_run_id bigint,
  p_producer_execution_id text,
  p_ledger_execution_id text,
  p_source_head_sha text,
  p_consumed_graph_sha256 text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, programacion, public, private, extensions
AS $issuer$
DECLARE
  v_run record;
  v_actor record;
  v_producer record;
  v_graph_a jsonb;
  v_graph_b jsonb;
  v_sha_a text;
  v_sha_b text;
  v_source_ref text;
  v_a jsonb;
  v_b jsonb;
  v_count integer;
  v_resolver_id text;
  v_payload jsonb;
  v_verification jsonb;
  v_ord integer;
  v_result jsonb;
BEGIN
  IF p_run_id IS NULL OR p_run_id <= 0
     OR nullif(btrim(p_producer_execution_id),'') IS NULL
     OR nullif(btrim(p_ledger_execution_id),'') IS NULL
     OR p_source_head_sha !~ '^[0-9a-f]{40}$'
     OR p_consumed_graph_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'IG_GRAPH_RECEIPT_INPUT_INVALID';
  END IF;

  SELECT r.id,r.pantalla_id,r.version_id,r.status,
         r.source_snapshot_sha256,r.source_manifest
    INTO v_run
  FROM programacion.input_readiness_runs r
  WHERE r.id=p_run_id;
  IF v_run.id IS NULL OR v_run.status <> 'COMPLETED'
     OR v_run.pantalla_id IS NULL OR v_run.version_id IS NULL
     OR v_run.source_snapshot_sha256 !~ '^[0-9a-f]{64}$'
     OR jsonb_typeof(v_run.source_manifest) <> 'array' THEN
    RAISE EXCEPTION 'IG_GRAPH_RECEIPT_RUN_NOT_ELIGIBLE';
  END IF;

  SELECT e.execution_id,e.status,e.manifest INTO v_actor
  FROM public.lf_operation_execution e
  WHERE e.execution_id=p_ledger_execution_id;
  IF v_actor.execution_id IS NULL
     OR v_actor.status <> 'IN_PROGRESS'
     OR v_actor.manifest->>'capability_code' <> 'EVIDENCE_LEDGER'
     OR v_actor.manifest->>'schema_version' <> 'IG_GRAPH_PER_RUN_ISSUER_V1'
     OR v_actor.manifest->>'run_id' IS DISTINCT FROM p_run_id::text
     OR v_actor.manifest->>'pantalla_id' IS DISTINCT FROM v_run.pantalla_id::text
     OR v_actor.manifest->>'version_id' IS DISTINCT FROM v_run.version_id::text
     OR v_actor.manifest->>'source_snapshot_sha256'
        IS DISTINCT FROM v_run.source_snapshot_sha256
     OR v_actor.manifest->>'producer_execution_id'
        IS DISTINCT FROM p_producer_execution_id
     OR v_actor.manifest->>'source_head_sha'
        IS DISTINCT FROM p_source_head_sha
     OR v_actor.manifest->>'consumed_graph_sha256'
        IS DISTINCT FROM p_consumed_graph_sha256
     OR nullif(v_actor.manifest->>'orchestrator_execution_id','') IS NULL
     OR coalesce(v_actor.manifest->>'plan_digest','') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'IG_GRAPH_RECEIPT_LEDGER_ACTOR_SCOPE_MISMATCH';
  END IF;

  SELECT e.execution_id,e.status,e.manifest INTO v_producer
  FROM public.lf_operation_execution e
  WHERE e.execution_id=p_producer_execution_id;
  IF v_producer.execution_id IS NULL OR v_producer.status NOT IN ('IN_PROGRESS','DONE')
     OR v_producer.manifest->>'run_id' IS DISTINCT FROM p_run_id::text
     OR v_producer.manifest->>'source_head_sha' IS DISTINCT FROM p_source_head_sha THEN
    RAISE EXCEPTION 'IG_GRAPH_RECEIPT_PRODUCER_RUN_BINDING_MISSING';
  END IF;

  SELECT count(*),min(rr.resolver_id) INTO v_count,v_resolver_id
  FROM private.lf_evidence_resolver_registry_v1 rr
  WHERE rr.provider='SUPABASE'
    AND rr.verification_method='SUPABASE_SQL_READBACK_PLUS_DB_DIGEST'
    AND rr.trust_level='TRUSTED_PROVIDER_BOUND' AND rr.active;
  IF v_count<>1 OR v_resolver_id IS NULL THEN
    RAISE EXCEPTION 'IG_GRAPH_RECEIPT_TRUSTED_RESOLVER_INVALID';
  END IF;

  -- Recompute from actual canonical authority, not caller-provided graph JSON.
  -- A session-level cached request graph would make both calls replay the same input.
  IF nullif(current_setting('lf.input_request_context_v1',true),'') IS NOT NULL THEN
    RAISE EXCEPTION 'IG_GRAPH_RECEIPT_CACHED_REQUEST_CONTEXT_FORBIDDEN';
  END IF;
  v_graph_a:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
  v_graph_b:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
  v_sha_a:=programacion.fn_v09_sha256_jsonb(v_graph_a);
  v_sha_b:=programacion.fn_v09_sha256_jsonb(v_graph_b);
  IF v_graph_a IS NULL OR v_graph_b IS NULL
     OR v_graph_a IS DISTINCT FROM v_graph_b
     OR v_sha_a IS DISTINCT FROM v_sha_b
     OR v_sha_a IS DISTINCT FROM p_consumed_graph_sha256 THEN
    RAISE EXCEPTION 'IG_GRAPH_RECEIPT_CANONICAL_CONSUMER_SHA_MISMATCH';
  END IF;

  v_verification:=jsonb_build_object(
    'provider_readback_verified',true,'digest_recomputed',true,
    'stable_pair',true,'run_id',v_run.id,'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'graph_sha256',v_sha_a,
    'producer_execution_id',p_producer_execution_id,
    'ledger_execution_id',p_ledger_execution_id,
    'orchestrator_execution_id',v_actor.manifest->>'orchestrator_execution_id');
  v_payload:=jsonb_build_object(
    'schema_version','IG_SCREEN_GRAPH_RECEIPT_PER_RUN_V1',
    'run_id',v_run.id,'pantalla_id',v_run.pantalla_id,
    'version_id',v_run.version_id,'graph_sha256',v_sha_a,
    'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'producer_execution_id',p_producer_execution_id,
    'stable_pair',true);
  FOR v_ord IN 1..2 LOOP
    v_source_ref:='supabase://programacion.input_readiness_runs/'
                  ||p_run_id::text||'#canonical_graph/recalc-'||v_ord::text;
    v_result:=public.fn_lf_evidence_ledger_anchor_v1(
      p_producer_execution_id,'EVIDENCE_LEDGER','IG_GRAPH_SHA_RECEIPT',
      'GRAPH_RECEIPT','IG_SCREEN_GRAPH',v_source_ref,v_sha_a,
      p_source_head_sha,
      'supabase://programacion.fn_input_screen_canonical_graph(integer,bigint)',
      v_resolver_id,'SUPABASE',
      'supabase://programacion.fn_input_screen_canonical_graph(integer,bigint)',
      'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST','VERIFIED',
      v_verification||jsonb_build_object('recalculation_ordinal',v_ord),
      v_payload||jsonb_build_object('recalculation_ordinal',v_ord),
      p_ledger_execution_id);
    IF coalesce(v_result->>'receipt_id','')='' THEN
      RAISE EXCEPTION 'IG_GRAPH_RECEIPT_ANCHOR_MISSING:%',v_ord;
    END IF;
    IF v_ord=1 THEN v_a:=v_result; ELSE v_b:=v_result; END IF;
  END LOOP;

  SELECT count(*) INTO v_count
  FROM private.lf_evidence_ledger_v1 l
  WHERE l.receipt_id IN ((v_a->>'receipt_id')::uuid,(v_b->>'receipt_id')::uuid)
    AND l.receipt_kind='GRAPH_RECEIPT'
    AND l.subject_type='IG_SCREEN_GRAPH'
    AND l.subject_sha256=v_sha_a
    AND l.source_head_sha=p_source_head_sha
    AND l.created_by_execution_id=p_ledger_execution_id
    AND l.verification_state='VERIFIED'
    AND l.receipt_payload->>'run_id'=p_run_id::text
    AND l.receipt_payload->>'producer_execution_id'=p_producer_execution_id
    AND l.receipt_payload->>'orchestrator_execution_id'
        =v_actor.manifest->>'orchestrator_execution_id';
  IF v_count<>2 OR (v_a->>'receipt_id')=(v_b->>'receipt_id') THEN
    RAISE EXCEPTION 'IG_GRAPH_RECEIPT_CONSUMER_READBACK_MISMATCH';
  END IF;

  RETURN jsonb_build_object(
    'status','PASS','schema_version','IG_GRAPH_RECEIPT_PER_RUN_V1',
    'run_id',p_run_id,'graph_sha256',v_sha_a,
    'source_head_sha',p_source_head_sha,
    'producer_execution_id',p_producer_execution_id,
    'ledger_execution_id',p_ledger_execution_id,
    'receipt_ids',jsonb_build_array(v_a->>'receipt_id',v_b->>'receipt_id'),
    'consumer_readback_count',v_count);
END;
$issuer$;

REVOKE ALL ON FUNCTION programacion.fn_ig_graph_receipt_emit_per_run_v1(bigint,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_graph_receipt_emit_per_run_v1(bigint,text,text,text,text) TO service_role;

COMMENT ON FUNCTION programacion.fn_ig_graph_receipt_emit_per_run_v1(bigint,text,text,text,text)
IS 'Generic per-new-COMPLETED-run GRAPH_RECEIPT issuer for IG M7.10; reuse governed EVIDENCE_LEDGER actor scoped to exact run, producer, head, source snapshot, and consumed graph SHA; two independently recomputed canonical digests and ledger readback. Called by the existing run orchestrator, never by old one-off M6.2 actor. No runtime activation implied.';
